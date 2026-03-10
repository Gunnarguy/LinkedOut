"""LinkedOut — Headless Career Engine API."""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

from config import settings
from job_fetcher import fetch_all_sources
from job_store import store
from linkedin_api import share_to_linkedin
from linkedin_oauth import (
    create_session,
    generate_authorization_url,
    get_all_sessions,
    get_session,
    refresh_access_token,
    validate_state,
)
from models import (
    AuthStatusResponse,
    JobActionRequest,
    JobActionResponse,
    JobPayload,
    LoginURLResponse,
    RawJobListing,
    ScoringResult,
    TokenExchangeRequest,
    UserPreferences,
)
from scoring_engine import score_batch, score_job, triage_and_score

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Background ingest task ───────────────────────────────────────────────────

_ingest_task: asyncio.Task | None = None

# User preferences — updated via API, used in ingest cycles
_user_prefs = UserPreferences()


async def _run_ingest_cycle():
    """Fetch real jobs from APIs, score them through the LLM, add to pending.

    Pipeline: Fetch → Dedup (skip seen URLs) → Flash triage → Pro scoring → Queue
    """
    logger.info("Starting job ingest cycle...")
    try:
        raw_listings = await fetch_all_sources()
        if not raw_listings:
            logger.info("No listings fetched from any source")
            return 0

        # Dedup: skip URLs we've already scored
        new_listings = [r for r in raw_listings if not store.is_url_seen(r.url)]
        skipped = len(raw_listings) - len(new_listings)
        if skipped:
            logger.info(f"Skipped {skipped} already-seen URLs")

        if not new_listings:
            logger.info("All listings already seen — nothing to score")
            return 0

        # Mark all as seen now (even if scoring fails, don't re-try same URLs)
        for listing in new_listings:
            store.mark_url_seen(listing.url)
        store.flush_seen()

        # Two-tier scoring: Flash triage → Pro full scoring
        prefs = _user_prefs
        total_added = 0
        batch_size = 10
        min_builder_score = 0.3

        for i in range(0, len(new_listings), batch_size):
            batch = new_listings[i : i + batch_size]
            results = await triage_and_score(batch, prefs)

            for result in results:
                if result.passed_filter and result.job:
                    if result.job.builder_score >= min_builder_score:
                        store.add_pending(result.job)
                        total_added += 1

            passed = sum(1 for r in results if r.passed_filter)
            logger.info(
                f"Batch {i // batch_size + 1}: "
                f"{passed}/{len(batch)} passed → {total_added} total queued"
            )

        logger.info(
            f"Ingest complete: {total_added} new jobs queued "
            f"(from {len(new_listings)} new listings, "
            f"{len(raw_listings)} total fetched)"
        )
        return total_added

    except Exception as e:
        logger.exception(f"Ingest cycle failed: {e}")
        return 0


async def _periodic_ingest(interval_hours: int = 6):
    """Run ingest cycle on a schedule."""
    while True:
        await _run_ingest_cycle()
        logger.info(f"Next ingest in {interval_hours} hours")
        await asyncio.sleep(interval_hours * 3600)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: kick off initial job ingest. Shutdown: cancel background task."""
    global _ingest_task
    logger.info("LinkedOut engine starting — scheduling initial job ingest...")
    _ingest_task = asyncio.create_task(_periodic_ingest())
    yield
    if _ingest_task:
        _ingest_task.cancel()
        try:
            await _ingest_task
        except asyncio.CancelledError:
            pass
    logger.info("LinkedOut engine shut down")


app = FastAPI(
    title="LinkedOut Engine",
    description="AI-powered headless career screening engine",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health ───────────────────────────────────────────────────────────────────


@app.get("/health")
async def health():
    return {"status": "ok", "store": store.stats}


# ── Auth Routes ──────────────────────────────────────────────────────────────


@app.get("/auth/login", response_model=LoginURLResponse)
async def auth_login():
    """Generate LinkedIn OAuth authorization URL."""
    url, state = generate_authorization_url()
    return LoginURLResponse(authorization_url=url, state=state)


@app.get("/auth/callback")
async def auth_callback(code: str, state: str):
    """OAuth callback — exchanges code for token, fetches profile."""
    if not validate_state(state):
        raise HTTPException(status_code=400, detail="Invalid or expired state")

    try:
        session = await create_session(code)
    except Exception as e:
        logger.exception("OAuth callback failed")
        raise HTTPException(status_code=400, detail=f"Auth failed: {e}")

    # Redirect to the iOS app via deep link
    return RedirectResponse(
        url=f"linkedout://auth?person_id={session.profile.person_id}"
    )


@app.post("/auth/token", response_model=AuthStatusResponse)
async def auth_token_exchange(req: TokenExchangeRequest):
    """Mobile-friendly token exchange (code + state → session)."""
    if not validate_state(req.state):
        raise HTTPException(status_code=400, detail="Invalid or expired state")

    try:
        session = await create_session(req.code)
    except Exception as e:
        logger.exception("Token exchange failed")
        raise HTTPException(status_code=400, detail=f"Auth failed: {e}")

    return AuthStatusResponse(authenticated=True, profile=session.profile)


@app.get("/auth/status/{person_id}", response_model=AuthStatusResponse)
async def auth_status(person_id: str):
    """Check if a session exists and is valid."""
    session = get_session(person_id)
    if session:
        return AuthStatusResponse(authenticated=True, profile=session.profile)

    # Try refresh
    refreshed = await refresh_access_token(person_id)
    if refreshed:
        return AuthStatusResponse(authenticated=True, profile=refreshed.profile)

    return AuthStatusResponse(authenticated=False)


# ── Job Routes ───────────────────────────────────────────────────────────────


@app.get("/api/jobs/pending", response_model=list[JobPayload])
async def get_pending_jobs(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """Get pending (unreviewed) jobs, sorted by builder_score descending."""
    return store.get_pending(limit=limit, offset=offset)


@app.post("/api/jobs/action", response_model=JobActionResponse)
async def job_action(req: JobActionRequest):
    """Apply, reject, or save a job."""
    success = store.act_on_job(req.job_id, req.action)
    if not success:
        raise HTTPException(status_code=404, detail="Job not found")
    return JobActionResponse(
        job_id=req.job_id,
        action=req.action,
        success=True,
        message=f"Job {req.action.value}d successfully",
    )


@app.get("/api/jobs/applied", response_model=list[JobPayload])
async def get_applied_jobs():
    """Get all jobs the user swiped right on."""
    return store.get_applied()


@app.get("/api/jobs/saved", response_model=list[JobPayload])
async def get_saved_jobs():
    """Get all saved/bookmarked jobs."""
    return store.get_saved()


@app.get("/api/jobs/stats")
async def get_stats():
    """Pipeline statistics."""
    return store.stats


# Dynamic path param MUST come after all static /api/jobs/* routes
@app.get("/api/jobs/{job_id}", response_model=JobPayload)
async def get_job(job_id: str):
    """Get a specific job by ID."""
    job = store.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


# ── Scoring / Ingestion ─────────────────────────────────────────────────────


@app.post("/api/score", response_model=ScoringResult)
async def score_single_job(raw: RawJobListing, prefs: UserPreferences | None = None):
    """Score a single raw job listing through the AI bouncer."""
    result = await score_job(raw, prefs)
    if result.passed_filter and result.job:
        store.add_pending(result.job)
    return result


@app.post("/api/score/batch", response_model=list[ScoringResult])
async def score_job_batch(
    listings: list[RawJobListing],
    prefs: UserPreferences | None = None,
):
    """Score a batch of raw job listings."""
    results = await score_batch(listings, prefs)
    for r in results:
        if r.passed_filter and r.job:
            store.add_pending(r.job)
    return results


# ── LinkedIn Sharing ─────────────────────────────────────────────────────────


@app.post("/api/share")
async def share_job(person_id: str, job_id: str, custom_text: str = ""):
    """Share a job application to LinkedIn."""
    session = get_session(person_id)
    if not session:
        raise HTTPException(status_code=401, detail="Not authenticated")

    job = store.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    text = custom_text or (
        f"Excited about this opportunity: {job.role_title} at {job.company_name}! "
        f"#OpenToWork #LinkedOut"
    )

    result = await share_to_linkedin(
        access_token=session.linkedin_access_token,
        person_id=session.profile.person_id,
        text=text,
        article_url=job.source_url,
    )
    return result


# ── Job Ingest ───────────────────────────────────────────────────────────────


@app.post("/api/ingest/refresh")
async def ingest_refresh():
    """Manually trigger a job ingest cycle (fetch + score + queue)."""
    added = await _run_ingest_cycle()
    return {
        "ingested": added,
        "total_pending": store.pending_count,
        "store": store.stats,
    }


@app.get("/api/ingest/status")
async def ingest_status():
    """Check if the background ingest task is running."""
    return {
        "task_running": _ingest_task is not None and not _ingest_task.done(),
        "store": store.stats,
    }


# ── User Preferences ────────────────────────────────────────────────────────


@app.get("/api/preferences", response_model=UserPreferences)
async def get_preferences():
    """Get current scoring preferences."""
    return _user_prefs


@app.put("/api/preferences", response_model=UserPreferences)
async def update_preferences(prefs: UserPreferences):
    """Update scoring preferences (used in future ingest cycles)."""
    global _user_prefs
    _user_prefs = prefs
    return _user_prefs


# ── Dev/Debug: Seed with mock data ──────────────────────────────────────────


@app.post("/api/dev/seed")
async def seed_mock_data():
    """Seed the store with mock job data for development."""
    if not settings.debug:
        raise HTTPException(
            status_code=403, detail="Seed endpoint disabled in production"
        )
    mock_jobs = [
        JobPayload(
            company_name="Cognition (Devin)",
            role_title="AI Product Engineer",
            salary_floor=180000,
            is_remote=True,
            builder_score=0.96,
            ai_pitch_summary=(
                "• You build iOS apps for fun — Cognition wants people who "
                "ship products, not people who study for interviews\n"
                "• Devin is the poster child of agentic AI. You've been "
                "preaching this thesis — now go build it\n"
                "• Small team, massive ambition, product-obsessed — your "
                "exact vibe"
            ),
            drafted_cover_letter=(
                "I've been building AI-powered tools as a hobbyist while "
                "everyone else was arguing about whether AI would take their "
                "jobs. Spoiler: I'm the one it empowers. I ship iOS apps "
                "with on-device ML, built an entire Tinder-for-jobs app "
                "with agentic scoring, and I think Devin represents where "
                "software engineering is going. I don't have a CS degree "
                "— I have shipped products. Let me build with you."
            ),
            source_url="https://cognition.ai/careers",
            location="Remote / SF",
            tags=["AI", "Agents", "Product", "Startup"],
        ),
        JobPayload(
            company_name="Cursor",
            role_title="Product Engineer",
            salary_floor=200000,
            is_remote=True,
            builder_score=0.94,
            ai_pitch_summary=(
                "• Cursor is THE AI coding tool — you literally use AI tools to "
                "build things, making you the exact user-turned-builder they need\n"
                "• Product engineer role = taste + shipping > algorithms. "
                "Your hobbyist builder profile is the signal, not the noise\n"
                "• SwiftUI + LLM integration experience means you understand the "
                "UX challenges of AI-augmented dev tools firsthand"
            ),
            drafted_cover_letter=(
                "I build things with AI every day — not because it's my job, "
                "but because it's genuinely fun. I shipped an iOS app that uses "
                "LLMs to score job listings, and the whole thing was built with "
                "AI-assisted coding. I'm your power user who also builds. "
                "Cursor needs people who feel the product in their bones, not "
                "people who treat it like another B2B SaaS. I'm in."
            ),
            source_url="https://cursor.com/careers",
            location="Remote / SF",
            tags=["AI", "DevTools", "Product", "LLM"],
        ),
        JobPayload(
            company_name="Replit",
            role_title="AI Product Engineer — Mobile",
            salary_floor=170000,
            is_remote=True,
            builder_score=0.91,
            ai_pitch_summary=(
                "• Replit's mobile push needs someone who actually ships iOS "
                "apps — not a web dev who happens to know React Native\n"
                "• You're the demographic they're building for: non-traditional "
                "builders who use AI to create real software\n"
                "• Agentic coding + mobile UX = the exact intersection where "
                "your hobbyist energy meets their product roadmap"
            ),
            drafted_cover_letter=(
                "I'm the user Replit was made for — someone who isn't a "
                "'professional' engineer but ships real products anyway. "
                "I build iOS apps with SwiftUI, wire up LLM pipelines, and "
                "deploy Docker containers, all because AI tools unlocked it. "
                "Your mobile product needs someone who understands both the "
                "builder's frustration and the magic moment when it clicks. "
                "That's me."
            ),
            source_url="https://replit.com/careers",
            location="Remote",
            tags=["AI", "Mobile", "Product", "CreatorTools"],
        ),
    ]

    for job in mock_jobs:
        store.add_pending(job)

    return {"seeded": len(mock_jobs), "total_pending": store.pending_count}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
