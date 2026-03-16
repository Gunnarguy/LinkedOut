"""LinkedOut — Headless Career Engine API."""

from __future__ import annotations

import asyncio
import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

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
    JobNotesUpdate,
    JobPayload,
    JobStatusUpdate,
    LoginURLResponse,
    RawJobListing,
    ScoringResult,
    TokenExchangeRequest,
    UserPreferences,
)
from scoring_engine import score_batch, score_job, triage_and_score

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)

# ── In-memory log ring buffer for /api/dev/logs endpoint ─────────────────────
import collections

_LOG_RING: collections.deque[str] = collections.deque(maxlen=500)


class _RingHandler(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:
        _LOG_RING.append(self.format(record))


_ring_handler = _RingHandler()
_ring_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
logging.getLogger().addHandler(_ring_handler)

# ── Background ingest task ───────────────────────────────────────────────────

_ingest_task: asyncio.Task | None = None
_manual_ingest_task: asyncio.Task | None = None
_last_ingest_result: int | None = None  # Result of last manual ingest
_ingest_lock = asyncio.Lock()  # Serialize ingest cycles so manual + periodic don't race

# User preferences — updated via API, used in ingest cycles
_DATA_DIR = Path("/app/data") if Path("/app").exists() else Path("./data")
_PREFS_FILE = _DATA_DIR / "user_prefs.json"


def _load_prefs() -> UserPreferences:
    try:
        if _PREFS_FILE.exists():
            data = json.loads(_PREFS_FILE.read_text())
            prefs = UserPreferences(**data)
            # Re-save if the file was missing newly-added fields
            if set(data.keys()) != set(prefs.model_dump().keys()):
                _save_prefs(prefs)
            return prefs
    except Exception:
        pass
    return UserPreferences()


def _save_prefs(prefs: UserPreferences) -> None:
    try:
        _PREFS_FILE.parent.mkdir(parents=True, exist_ok=True)
        _PREFS_FILE.write_text(json.dumps(prefs.model_dump(), indent=2))
    except Exception:
        logger.warning("Could not persist preferences to disk")


_user_prefs = _load_prefs()


async def _run_ingest_cycle():
    """Fetch real jobs from APIs, score them through the LLM, add to pending.

    Pipeline: Fetch → Dedup (skip seen URLs) → Flash triage → Pro scoring → Queue
    """
    import time as _time
    cycle_start = _time.monotonic()
    logger.info("="*60)
    logger.info("INGEST CYCLE STARTING")
    logger.info("="*60)
    try:
        t0 = _time.monotonic()
        raw_listings = await fetch_all_sources()
        fetch_elapsed = _time.monotonic() - t0
        logger.info(f"[FETCH] Got {len(raw_listings)} total listings in {fetch_elapsed:.1f}s")
        if not raw_listings:
            logger.info("[FETCH] No listings fetched from any source")
            return 0

        # Dedup: skip URLs we've already scored OR already in store
        dedup_urls: set[str] = set()
        new_listings: list[RawJobListing] = []
        for r in raw_listings:
            if r.url in dedup_urls:
                continue
            if store.is_url_seen(r.url) or store.has_url(r.url):
                continue
            dedup_urls.add(r.url)
            new_listings.append(r)
        skipped = len(raw_listings) - len(new_listings)
        logger.info(f"[DEDUP] {len(new_listings)} new, {skipped} already-seen")

        if not new_listings:
            logger.info("[DEDUP] All listings already seen — nothing to score")
            return 0

        # Log a sample of new listings
        for i, nl in enumerate(new_listings[:5]):
            logger.info(f"[SAMPLE {i}] {nl.title} @ {nl.company} — {nl.url[:80]}")

        # Two-tier scoring: Flash triage → Pro full scoring → local fallback
        prefs = _user_prefs
        total_added = 0
        batch_size = 10
        min_builder_score = 0.30

        for i in range(0, len(new_listings), batch_size):
            batch = new_listings[i : i + batch_size]
            t1 = _time.monotonic()
            results = await triage_and_score(batch, prefs)
            score_elapsed = _time.monotonic() - t1

            for raw_listing, result in zip(batch, results):
                # Only mark as seen after we've processed it
                store.mark_url_seen(raw_listing.url)
                if result.passed_filter and result.job:
                    if result.job.builder_score >= min_builder_score:
                        store.add_pending(result.job)
                        total_added += 1
                        logger.info(
                            f"[QUEUED] {result.job.role_title} @ {result.job.company_name} "
                            f"score={result.job.builder_score:.2f}"
                        )
                    else:
                        logger.info(
                            f"[LOW SCORE] {result.job.role_title} @ {result.job.company_name} "
                            f"score={result.job.builder_score:.2f} < {min_builder_score}"
                        )
                elif not result.passed_filter:
                    logger.info(
                        f"[REJECTED] {raw_listing.title} @ {raw_listing.company} "
                        f"— {result.rejection_reason}"
                    )

            store.flush_seen()

            passed = sum(1 for r in results if r.passed_filter)
            logger.info(
                f"[BATCH {i // batch_size + 1}] "
                f"{passed}/{len(batch)} passed → {total_added} total queued "
                f"({score_elapsed:.1f}s)"
            )

        total_elapsed = _time.monotonic() - cycle_start
        logger.info("="*60)
        logger.info(
            f"INGEST COMPLETE: {total_added} new jobs queued "
            f"(from {len(new_listings)} new / {len(raw_listings)} total) "
            f"in {total_elapsed:.1f}s"
        )
        logger.info(f"STORE STATE: {store.stats}")
        logger.info("="*60)
        return total_added

    except Exception as e:
        total_elapsed = _time.monotonic() - cycle_start
        logger.exception(f"INGEST CYCLE FAILED after {total_elapsed:.1f}s: {e}")
        return 0


async def _periodic_ingest(interval_hours: int = 6):
    """Run ingest cycle on a schedule. Also expires stale jobs."""
    while True:
        async with _ingest_lock:
            store.expire_old_jobs(max_age_days=14)
            result = await _run_ingest_cycle()
        logger.info(f"Next ingest in {interval_hours} hours")
        await asyncio.sleep(interval_hours * 3600)


async def _keep_alive(interval_minutes: int = 10):
    """Self-ping to prevent Render free tier from sleeping."""
    import httpx

    url = f"http://localhost:{settings.port}/health"
    while True:
        await asyncio.sleep(interval_minutes * 60)
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                await client.get(url)
            logger.debug("Keep-alive ping OK")
        except Exception:
            pass


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: kick off initial job ingest + keep-alive. Shutdown: cancel tasks."""
    global _ingest_task
    logger.info("LinkedOut engine starting — scheduling initial job ingest...")
    _ingest_task = asyncio.create_task(_periodic_ingest())
    _keepalive_task = asyncio.create_task(_keep_alive())
    yield
    _keepalive_task.cancel()
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


@app.get("/api/jobs/rejected", response_model=list[JobPayload])
async def get_rejected_jobs():
    """Get all jobs the user passed on."""
    return store.get_rejected()


@app.post("/api/jobs/import")
async def import_jobs(jobs: list[JobPayload]):
    """Bulk-import pre-scored jobs (e.g. from another backend instance)."""
    added = 0
    for job in jobs:
        if not store.has_url(job.source_url):
            store.add_pending(job)
            added += 1
    return {
        "imported": added,
        "skipped": len(jobs) - added,
        "total_pending": len(store._pending),
    }


@app.get("/api/jobs/stats")
async def get_stats():
    """Pipeline statistics."""
    return store.stats


@app.post("/api/jobs/undo")
async def undo_last_action():
    """Undo the last swipe/action — restores the job to its previous bucket."""
    job = store.undo_last()
    if not job:
        raise HTTPException(status_code=404, detail="Nothing to undo")
    return {"success": True, "job_id": job.id, "message": "Action undone"}


# Dynamic path param MUST come after all static /api/jobs/* routes
@app.get("/api/jobs/{job_id}", response_model=JobPayload)
async def get_job(job_id: str):
    """Get a specific job by ID."""
    job = store.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@app.put("/api/jobs/{job_id}/notes", response_model=JobPayload)
async def update_job_notes(job_id: str, body: JobNotesUpdate):
    """Update user notes on a job."""
    if not store.update_job_notes(job_id, body.notes):
        raise HTTPException(status_code=404, detail="Job not found")
    job = store.get_job(job_id)
    return job


@app.put("/api/jobs/{job_id}/status", response_model=JobPayload)
async def update_job_status(job_id: str, body: JobStatusUpdate):
    """Update application status on a job."""
    if not store.update_job_status(job_id, body.status):
        raise HTTPException(status_code=404, detail="Job not found or invalid status")
    job = store.get_job(job_id)
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


# ── Re-score existing jobs ───────────────────────────────────────────────────

_rescore_task: asyncio.Task | None = None
_rescore_progress: dict = {"running": False, "done": 0, "total": 0, "errors": 0}


@app.post("/api/jobs/rescore")
async def rescore_jobs(buckets: list[str] = Query(default=["pending"])):
    """Re-run LLM scoring on existing jobs (non-blocking).

    Reconstructs RawJobListing from each stored job and re-scores with the
    current prompt. Preserves job ID, notes, application_status, notion_page_id.
    """
    global _rescore_task
    if _rescore_task is not None and not _rescore_task.done():
        return {"status": "already_running", **_rescore_progress}

    # Collect jobs from requested buckets
    bucket_map = {
        "pending": store._pending,
        "applied": store._applied,
        "saved": store._saved,
        "rejected": store._rejected,
    }
    jobs_to_rescore: list[JobPayload] = []
    for b in buckets:
        if b in bucket_map:
            jobs_to_rescore.extend(bucket_map[b].values())

    if not jobs_to_rescore:
        return {"status": "nothing_to_rescore", "total": 0}

    _rescore_progress.update(running=True, done=0, total=len(jobs_to_rescore), errors=0)

    async def _do_rescore():
        async with _ingest_lock:
            prefs = _user_prefs
            for job in jobs_to_rescore:
                try:
                    raw = RawJobListing(
                        title=job.role_title or "",
                        company=job.company_name or "",
                        description=job.description or "",
                        url=job.source_url or "",
                        salary_text=f"${job.salary_floor}" if job.salary_floor else "",
                        location=job.location or "",
                        is_remote=job.is_remote,
                    )
                    result = await score_job(raw, prefs)
                    if result.passed_filter and result.job:
                        # Preserve user-managed fields
                        result.job.id = job.id
                        result.job.notes = job.notes
                        result.job.application_status = job.application_status
                        result.job.notion_page_id = job.notion_page_id
                        result.job.posted_at = job.posted_at
                        store.update_job(job.id, result.job)
                        logger.info(
                            f"[RESCORE] Updated {job.role_title} @ {job.company_name} "
                            f"score={result.job.builder_score:.2f}"
                        )
                    else:
                        logger.info(
                            f"[RESCORE] {job.role_title} @ {job.company_name} "
                            f"— kept existing (LLM rejected on rescore)"
                        )
                except Exception as e:
                    _rescore_progress["errors"] += 1
                    logger.warning(f"[RESCORE] Error on {job.role_title}: {e}")
                _rescore_progress["done"] += 1
                await asyncio.sleep(1.5)  # Rate limit pacing
            _rescore_progress["running"] = False

    _rescore_task = asyncio.create_task(_do_rescore())
    return {
        "status": "started",
        "total": len(jobs_to_rescore),
        "buckets": buckets,
    }


@app.get("/api/jobs/rescore/status")
async def rescore_status():
    """Check re-score progress."""
    return _rescore_progress


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
    """Trigger a job ingest cycle in the background (non-blocking).

    Returns immediately so the client doesn't time out.
    Poll GET /api/ingest/status to check progress.

    If a periodic ingest is already mid-cycle (holding the lock), the manual
    task will wait for it instead of racing — so the client will see the
    periodic ingest's results once the lock releases.
    """
    global _manual_ingest_task, _last_ingest_result
    if _manual_ingest_task is not None and not _manual_ingest_task.done():
        return {
            "status": "already_running",
            "ingested": 0,
            "total_pending": store.pending_count,
            "store": store.stats,
        }

    _last_ingest_result = None

    async def _do_manual_ingest():
        global _last_ingest_result
        async with _ingest_lock:
            store.expire_old_jobs(max_age_days=14)
            _last_ingest_result = await _run_ingest_cycle()

    _manual_ingest_task = asyncio.create_task(_do_manual_ingest())
    return {
        "status": "started",
        "ingested": 0,
        "total_pending": store.pending_count,
        "store": store.stats,
    }


@app.get("/api/ingest/status")
async def ingest_status():
    """Check ingest status — both periodic and manual tasks."""
    manual_running = _manual_ingest_task is not None and not _manual_ingest_task.done()
    periodic_running = _ingest_task is not None and not _ingest_task.done()
    return {
        "task_running": manual_running or periodic_running,
        "manual_running": manual_running,
        "cycle_active": _ingest_lock.locked(),
        "last_ingest_result": _last_ingest_result,
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
    _save_prefs(prefs)
    return _user_prefs


# ── Notion Sync ──────────────────────────────────────────────────────────────

from notion_sync import notion_sync

_notion_sync_task: asyncio.Task | None = None
_notion_sync_result: dict | None = None


@app.post("/api/notion/configure")
async def notion_configure(body: dict):
    """Configure Notion integration at runtime (no Docker rebuild needed).

    Accepts: {"token": "ntn_...", "database_id": "..."}
    Validates the token by attempting to discover the database schema.
    """
    token = (body.get("token") or "").strip()
    database_id = (body.get("database_id") or "").strip()

    if not token:
        raise HTTPException(status_code=400, detail="token is required")
    if not database_id:
        raise HTTPException(status_code=400, detail="database_id is required")

    # Apply credentials
    notion_sync.reconfigure(token, database_id)

    # Validate by trying to discover the database
    try:
        schema = await notion_sync.discover_schema()
        return {
            "status": "connected",
            "database_id": database_id,
            "schema": schema,
            "data_source_id": notion_sync._data_source_id,
            "property_count": len(schema),
        }
    except Exception as e:
        # Revert on failure
        notion_sync.reconfigure("", "")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to connect: {e}. Check that the token is correct and the database is shared with the integration.",
        )


@app.get("/api/notion/status")
async def notion_status():
    """Check Notion integration status and configuration."""
    sync_running = _notion_sync_task is not None and not _notion_sync_task.done()

    status: dict = {
        "configured": notion_sync.configured,
        "sync_running": sync_running,
        "last_sync_result": _notion_sync_result,
        "database_id": settings.notion_database_id or None,
        "has_token": bool(settings.notion_token),
    }

    # If configured, try to discover schema
    if notion_sync.configured and not sync_running:
        try:
            schema = await notion_sync.discover_schema()
            status["schema"] = schema
            status["data_source_id"] = notion_sync._data_source_id
        except Exception as e:
            status["schema_error"] = str(e)

    return status


@app.post("/api/notion/sync")
async def notion_sync_trigger():
    """Trigger a full bidirectional Notion sync (non-blocking).

    Push all LinkedOut jobs → Notion, pull Notion changes → LinkedOut.
    """
    global _notion_sync_task, _notion_sync_result

    if not notion_sync.configured:
        raise HTTPException(
            status_code=400,
            detail="Notion not configured. Set NOTION_TOKEN and NOTION_DATABASE_ID.",
        )

    if _notion_sync_task is not None and not _notion_sync_task.done():
        return {"status": "already_running", "last_result": _notion_sync_result}

    _notion_sync_result = None

    async def _do_sync():
        global _notion_sync_result
        try:
            _notion_sync_result = await notion_sync.full_sync(store)
        except Exception as e:
            logger.exception(f"[NOTION] Sync failed: {e}")
            _notion_sync_result = {"error": str(e)}

    _notion_sync_task = asyncio.create_task(_do_sync())
    return {"status": "started", "store": store.stats}


@app.post("/api/notion/push")
async def notion_push():
    """Push all LinkedOut jobs to Notion (one-way, no pull)."""
    if not notion_sync.configured:
        raise HTTPException(
            status_code=400,
            detail="Notion not configured. Set NOTION_TOKEN and NOTION_DATABASE_ID.",
        )

    stats = {"pushed": 0, "updated": 0, "errors": 0}
    buckets = {
        "pending": store.get_pending(limit=9999),
        "applied": store.get_applied(),
        "saved": store.get_saved(),
        "rejected": store.get_rejected(),
    }

    for bucket_name, jobs in buckets.items():
        for job in jobs:
            try:
                page_id = await notion_sync.push_job(job, bucket_name)
                if not job.notion_page_id and page_id:
                    job.notion_page_id = page_id
                    store.update_notion_page_id(job.id, page_id)
                    stats["pushed"] += 1
                else:
                    stats["updated"] += 1
            except Exception as e:
                logger.error(f"[NOTION] Push failed for {job.id}: {e}")
                stats["errors"] += 1

    return {"status": "complete", "stats": stats}


@app.post("/api/notion/pull")
async def notion_pull():
    """Pull changes from Notion → LinkedOut (one-way, no push)."""
    if not notion_sync.configured:
        raise HTTPException(
            status_code=400,
            detail="Notion not configured. Set NOTION_TOKEN and NOTION_DATABASE_ID.",
        )

    try:
        notion_jobs = await notion_sync.pull_jobs()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")

    stats = {"total": len(notion_jobs), "updated": 0, "unmatched": 0}

    for nj in notion_jobs:
        linkedout_id = nj.get("linkedout_id")
        if not linkedout_id:
            stats["unmatched"] += 1
            continue

        existing = store.get_job(linkedout_id)
        if not existing:
            stats["unmatched"] += 1
            continue

        changed = False
        # Sync notes
        if nj.get("notes") and nj["notes"] != existing.notes:
            store.update_job_notes(linkedout_id, nj["notes"])
            changed = True

        # Sync bucket
        notion_status_str = (nj.get("status") or "").lower()
        current_bucket = store.get_job_bucket(linkedout_id)
        bucket_map = {
            "applied": "applied",
            "saved": "saved",
            "rejected": "rejected",
            "not started": "pending",
            "pending": "pending",
        }
        target = bucket_map.get(notion_status_str)
        if target and target != current_bucket:
            store.move_to_bucket(linkedout_id, target)
            changed = True

        if changed:
            stats["updated"] += 1

    return {"status": "complete", "stats": stats}


@app.get("/api/notion/jobs")
async def notion_list_jobs():
    """List all jobs in the Notion database (raw pull, no sync)."""
    if not notion_sync.configured:
        raise HTTPException(
            status_code=400,
            detail="Notion not configured. Set NOTION_TOKEN and NOTION_DATABASE_ID.",
        )

    try:
        return await notion_sync.pull_jobs()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")


@app.get("/api/notion/schema")
async def notion_schema():
    """Return the Notion database schema (property names and types)."""
    if not notion_sync.configured:
        raise HTTPException(status_code=400, detail="Notion not configured")
    try:
        schema = await notion_sync.discover_schema()
        return {"schema": schema}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")


@app.get("/api/notion/jobs/{page_id}")
async def notion_get_job(page_id: str):
    """Fetch a single Notion page by its page ID."""
    if not notion_sync.configured:
        raise HTTPException(status_code=400, detail="Notion not configured")
    try:
        return await notion_sync.get_page(page_id)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")


@app.patch("/api/notion/jobs/{page_id}")
async def notion_update_job(page_id: str, body: dict):
    """Update properties on a Notion page.

    Body is a dict mapping property names to new values.
    Example: {"Status": "Applied", "Notes": "Great fit", "Score": 85}
    """
    if not notion_sync.configured:
        raise HTTPException(status_code=400, detail="Notion not configured")
    try:
        return await notion_sync.update_page_properties(page_id, body)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")


@app.delete("/api/notion/jobs/{page_id}")
async def notion_delete_job(page_id: str):
    """Archive (soft-delete) a Notion page."""
    if not notion_sync.configured:
        raise HTTPException(status_code=400, detail="Notion not configured")
    try:
        await notion_sync.archive_page(page_id)
        return {"status": "archived", "page_id": page_id}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")


@app.post("/api/notion/jobs")
async def notion_create_job(body: dict):
    """Create a new Notion page from property name → value pairs.

    Body example: {"Name": "iOS Engineer @ Acme", "Status": "Not started", "Remote": true}
    """
    if not notion_sync.configured:
        raise HTTPException(status_code=400, detail="Notion not configured")
    try:
        return await notion_sync.create_page_from_properties(body)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion API error: {e}")


# ── Score Notion jobs with LLM ──────────────────────────────────────────────

_notion_score_task: asyncio.Task | None = None
_notion_score_progress: dict = {
    "running": False,
    "done": 0,
    "total": 0,
    "errors": 0,
    "scored": 0,
    "skipped": 0,
}


@app.post("/api/notion/score")
async def notion_score_jobs(
    rescore_all: bool = Query(default=False),
):
    """Score Notion database jobs with the LLM scoring engine (non-blocking).

    By default only scores jobs that don't already have a score.
    Set rescore_all=true to re-score everything.
    Writes scores and AI analysis back to Notion properties.
    """
    global _notion_score_task
    if not notion_sync.configured:
        raise HTTPException(status_code=400, detail="Notion not configured")

    if _notion_score_task is not None and not _notion_score_task.done():
        return {"status": "already_running", **_notion_score_progress}

    # Fetch all Notion jobs
    try:
        notion_jobs = await notion_sync.pull_jobs()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Notion fetch failed: {e}")

    # Filter to unscored (or all if rescore_all)
    to_score = []
    for nj in notion_jobs:
        if rescore_all or nj.get("score") is None:
            to_score.append(nj)

    if not to_score:
        return {"status": "nothing_to_score", "total": 0}

    _notion_score_progress.update(
        running=True, done=0, total=len(to_score), errors=0, scored=0, skipped=0
    )

    async def _do_notion_score():
        async with _ingest_lock:
            prefs = _user_prefs
            schema = await notion_sync.discover_schema()

            for nj in to_score:
                page_id = nj["notion_page_id"]
                company = nj.get("name") or nj.get("company") or ""
                role = nj.get("role") or ""
                location = nj.get("location") or ""
                salary = nj.get("salary") or ""
                source_url = nj.get("source_url") or ""
                tech_stack = nj.get("tech_stack") or []

                # Build a description from available data
                desc_parts = []
                if role:
                    desc_parts.append(f"Role: {role}")
                if company:
                    desc_parts.append(f"Company: {company}")
                if location:
                    desc_parts.append(f"Location: {location}")
                if salary:
                    desc_parts.append(f"Salary: {salary}")
                if tech_stack:
                    desc_parts.append(f"Tech Stack: {', '.join(tech_stack)}")
                if nj.get("notes"):
                    desc_parts.append(f"Notes: {nj['notes']}")

                description = (
                    "\n".join(desc_parts) if desc_parts else f"{role} at {company}"
                )

                try:
                    raw = RawJobListing(
                        title=role or company,
                        company=company,
                        description=description,
                        url=source_url,
                        salary_text=salary,
                        location=location,
                        is_remote=nj.get("remote", False),
                    )
                    result = await score_job(raw, prefs)

                    if result.passed_filter and result.job:
                        j = result.job
                        # Write score + AI analysis back to Notion
                        updates: dict = {}
                        if "Score" in schema:
                            updates["Score"] = round(j.builder_score * 100, 1)
                        if "AI Summary" in schema and j.ai_pitch_summary:
                            updates["AI Summary"] = j.ai_pitch_summary[:2000]
                        if "Tech Stack Summary" in schema and j.tech_stack:
                            updates["Tech Stack Summary"] = ", ".join(j.tech_stack)
                        if "Gaps" in schema and j.red_flags:
                            updates["Gaps"] = "; ".join(j.red_flags)
                        if "Gains" in schema and j.fit_reasons:
                            updates["Gains"] = "; ".join(j.fit_reasons)
                        if "Cover Letter" in schema and j.drafted_cover_letter:
                            updates["Cover Letter"] = j.drafted_cover_letter[:2000]

                        if updates:
                            await notion_sync.update_page_properties(page_id, updates)

                        _notion_score_progress["scored"] += 1
                        logger.info(
                            f"[NOTION-SCORE] {role} @ {company} → "
                            f"score={j.builder_score:.2f}"
                        )
                    else:
                        _notion_score_progress["skipped"] += 1
                        logger.info(
                            f"[NOTION-SCORE] {role} @ {company} — "
                            f"rejected: {result.rejection_reason}"
                        )
                except Exception as e:
                    _notion_score_progress["errors"] += 1
                    logger.warning(f"[NOTION-SCORE] Error on {role} @ {company}: {e}")

                _notion_score_progress["done"] += 1
                await asyncio.sleep(2.0)  # Rate limit (Notion + LLM)

            _notion_score_progress["running"] = False

    _notion_score_task = asyncio.create_task(_do_notion_score())
    return {
        "status": "started",
        "total": len(to_score),
        "rescore_all": rescore_all,
    }


@app.get("/api/notion/score/status")
async def notion_score_status():
    """Check Notion scoring progress."""
    return _notion_score_progress


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
            salary_max=220000,
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
            description=(
                "We're building Devin, the first AI software engineer. Our mission is to "
                "make software engineering accessible to everyone. We need product engineers "
                "who are obsessed with building great AI-native experiences. You'll own "
                "features end-to-end — from ideation to production — in a team of <30 people."
            ),
            company_description=(
                "Cognition is the company behind Devin, the world's first autonomous AI "
                "software engineer. Founded by a team of competitive programmers, they raised "
                "$175M Series B from Founders Fund. Building the future of autonomous coding."
            ),
            company_size="10-50",
            company_stage="Series B",
            company_url="https://cognition.ai",
            requirements=[
                "Strong product intuition",
                "Rapid prototyping ability",
                "Python or TypeScript",
            ],
            nice_to_haves=[
                "AI/ML experience",
                "iOS/mobile experience",
                "Startup background",
            ],
            tech_stack=["Python", "TypeScript", "React", "LLMs", "AWS"],
            why_interesting=(
                "This is ground zero for agentic AI — exactly the thesis you've been building "
                "around. Small team, insane trajectory, and they value shipping over pedigree. "
                "Your hobbyist builder DNA is literally the profile they're looking for."
            ),
            red_flags=[
                "Extremely fast-paced, potential for burnout",
                "Competitive programming culture (may feel intimidating)",
            ],
            apply_url="https://cognition.ai/careers",
            experience_level="Mid",
            job_type="Full-time",
            benefits=[
                "Equity",
                "Health/dental/vision",
                "Unlimited PTO",
                "Remote-first",
            ],
        ),
        JobPayload(
            company_name="Cursor",
            role_title="Product Engineer",
            salary_floor=200000,
            salary_max=250000,
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
            description=(
                "Cursor is building the next generation of code editors — powered by AI. "
                "We're looking for product engineers who care deeply about developer experience. "
                "You'll work on AI-assisted coding features used by hundreds of thousands of developers."
            ),
            company_description=(
                "Cursor is an AI-native code editor used by hundreds of thousands of developers. "
                "They raised over $400M at a $9B valuation. The team is ~60 people with an "
                "engineering-first culture. Building the IDE of the future."
            ),
            company_size="50-200",
            company_stage="Series B",
            company_url="https://cursor.com",
            requirements=[
                "Strong product sense",
                "Ship quickly",
                "Full-stack (frontend + backend)",
            ],
            nice_to_haves=[
                "AI/ML background",
                "Passion for dev tools",
                "Editor/IDE experience",
            ],
            tech_stack=[
                "TypeScript",
                "React",
                "Electron",
                "Python",
                "LLMs",
                "VS Code APIs",
            ],
            why_interesting=(
                "You use AI coding tools every day. Cursor is the one building what you already "
                "live in. Product engineer means taste + execution, not LeetCode. Your builder "
                "portfolio IS the interview."
            ),
            red_flags=[
                "High valuation means high expectations",
                "Rapid growth can be chaotic",
            ],
            apply_url="https://cursor.com/careers",
            experience_level="Mid",
            job_type="Full-time",
            benefits=[
                "Equity",
                "Health insurance",
                "Remote-friendly",
                "Hardware stipend",
            ],
        ),
        JobPayload(
            company_name="Replit",
            role_title="AI Product Engineer — Mobile",
            salary_floor=170000,
            salary_max=210000,
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
            description=(
                "Replit is building the world's most accessible development environment. "
                "We're expanding to mobile and need an AI product engineer to lead our "
                "iOS experience. You'll design how millions of non-traditional builders "
                "interact with AI-powered coding on their phones."
            ),
            company_description=(
                "Replit is a cloud-based IDE and development platform with 30M+ users. "
                "Known for democratizing coding — you can build and deploy full apps from "
                "a browser. Backed by a16z, they're pushing hard into AI-assisted development."
            ),
            company_size="200-500",
            company_stage="Series C+",
            company_url="https://replit.com",
            requirements=[
                "iOS/SwiftUI experience",
                "Product ownership",
                "AI/ML familiarity",
            ],
            nice_to_haves=[
                "Published apps on App Store",
                "Community building",
                "Teaching/content creation",
            ],
            tech_stack=["Swift", "SwiftUI", "Python", "React", "LLMs", "GCP"],
            why_interesting=(
                "You literally are their target user — a non-traditional builder who ships "
                "real apps. Their mobile push needs iOS native experience, and your SwiftUI "
                "portfolio speaks louder than any resume. Plus, their mission aligns with "
                "your belief that AI makes CS gatekeeping obsolete."
            ),
            red_flags=[
                "Larger company (200+), some startup scrappiness may be lost",
                "Mobile push is newer — could shift priorities",
            ],
            apply_url="https://replit.com/careers",
            experience_level="Mid",
            job_type="Full-time",
            benefits=[
                "Equity",
                "Health/dental/vision",
                "Remote-first",
                "Learning stipend",
                "Home office budget",
            ],
        ),
    ]

    for job in mock_jobs:
        store.add_pending(job)

    return {"seeded": len(mock_jobs), "total_pending": store.pending_count}


@app.post("/api/dev/reset-seen")
async def reset_seen_urls():
    """Clear all seen URLs so the next ingest fetches everything fresh."""
    count = store.seen_count
    store.clear_seen()
    return {"cleared": count, "message": "Seen URLs cleared — next ingest will fetch fresh"}


@app.post("/api/dev/clear-pending")
async def clear_pending_jobs():
    """Clear all pending jobs so re-ingest starts with a clean slate."""
    count = store.clear_pending()
    return {"cleared": count, "message": "Pending jobs cleared"}


@app.post("/api/dev/purge-keyword-scored")
async def purge_keyword_scored():
    """Remove jobs scored by local keyword matcher (bogus scores).
    Their source URLs are un-seen so they get re-fetched and LLM-scored on next ingest."""
    count = store.purge_keyword_scored()
    return {
        "purged": count,
        "remaining_pending": store.pending_count,
        "message": f"Removed {count} keyword-scored jobs — they'll be re-ingested with LLM scoring",
    }


@app.get("/api/dev/logs")
async def get_recent_logs(n: int = Query(100, ge=1, le=500)):
    """Return recent backend log lines (ring buffer, newest last)."""
    lines = list(_LOG_RING)[-n:]
    return {"count": len(lines), "logs": lines}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
