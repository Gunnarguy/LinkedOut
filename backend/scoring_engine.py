"""LLM-powered job scoring engine — the AI bouncer.

Multi-provider with automatic fallback chain:
  Gemini Pro → Gemini Flash → OpenAI GPT-5.4 → Local keyword scorer

Set LLM_PROVIDER in .env to choose the primary provider.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time as _time_mod
from collections.abc import Callable
from datetime import datetime, timezone

from openai import AsyncOpenAI

from config import settings
from location_mapper import classify_location, TIER_LABELS
from models import JobPayload, RawJobListing, ScoringResult, UserPreferences

logger = logging.getLogger(__name__)

_openai_client: AsyncOpenAI | None = None
_gemini_client = None
_pro_cooldown_until: float = 0  # monotonic timestamp; skip Pro until this time


def _get_openai_client() -> AsyncOpenAI:
    global _openai_client
    if _openai_client is None:
        _openai_client = AsyncOpenAI(api_key=settings.openai_api_key)
    return _openai_client


def _get_gemini_client():
    global _gemini_client
    if _gemini_client is None:
        from google import genai

        _gemini_client = genai.Client(api_key=settings.gemini_api_key)
    return _gemini_client


async def _call_gemini(
    system: str, user_msg: str, use_flash: bool = False, timeout: int = 30
) -> str:
    """Call Google Gemini (Pro or Flash). Raises on failure."""
    client = _get_gemini_client()
    model = settings.gemini_flash_model if use_flash else settings.gemini_model
    resp = await asyncio.wait_for(
        client.aio.models.generate_content(
            model=model,
            contents=user_msg,
            config={
                "system_instruction": system,
                "temperature": 0.3,
                "response_mime_type": "application/json",
            },
        ),
        timeout=timeout,
    )
    return resp.text or ""


async def _call_openai(system: str, user_msg: str) -> str:
    """Call OpenAI GPT-5.4 with thinking enabled. Raises on failure."""
    client = _get_openai_client()
    resp = await asyncio.wait_for(
        client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_msg},
            ],
            temperature=0.3,
            response_format={"type": "json_object"},
        ),
        timeout=30,
    )
    return resp.choices[0].message.content or ""


async def _call_llm(
    system: str, user_msg: str, use_flash: bool = False, timeout: int = 30
) -> str:
    """Route LLM call with automatic fallback chain.

    Chain: Gemini Pro → Flash (on timeout/rate-limit) → OpenAI GPT-5.4
    On Pro timeout: skip retries, immediately try Flash (Pro is unresponsive).
    On rate limit: retry with backoff, then Flash → OpenAI.
    Pro cooldown: after a timeout, skip Pro for 5 minutes.
    """
    global _pro_cooldown_until
    provider = settings.llm_provider.lower()
    max_retries = 3

    # If Pro is in cooldown, go directly to Flash
    if (
        provider == "gemini"
        and not use_flash
        and _time_mod.monotonic() < _pro_cooldown_until
    ):
        logger.debug("[LLM] Pro in cooldown — using Flash directly")
        use_flash = True

    for attempt in range(max_retries):
        try:
            if provider == "openai":
                return await _call_openai(system, user_msg)
            elif provider == "gemini":
                return await _call_gemini(
                    system, user_msg, use_flash=use_flash, timeout=timeout
                )
            else:
                raise ValueError(f"Unknown LLM provider: {provider}")

        except Exception as e:
            error_str = str(e)
            error_type = type(e).__name__
            is_rate_limit = "429" in error_str or "RESOURCE_EXHAUSTED" in error_str
            is_timeout = isinstance(e, asyncio.TimeoutError) or error_str == ""
            is_auth_error = (
                "API_KEY_INVALID" in error_str
                or "API key expired" in error_str
                or "PERMISSION_DENIED" in error_str
            )
            is_transient = (
                is_rate_limit
                or is_timeout
                or "disconnected" in error_str.lower()
                or "server" in error_str.lower()
                or "connection" in error_str.lower()
            )

            # API key dead — skip retries, go straight to OpenAI
            if is_auth_error and provider != "openai" and settings.openai_api_key:
                logger.warning(
                    f"[LLM] Gemini auth error ({error_str[:80]}) → falling back to OpenAI"
                )
                return await _call_openai(system, user_msg)

            # On Pro timeout: don't waste retries, immediately fall through to Flash
            if is_timeout and provider == "gemini" and not use_flash:
                _pro_cooldown_until = _time_mod.monotonic() + 300  # 5-min cooldown
                logger.warning(
                    f"[LLM] Gemini Pro timed out ({timeout}s) → trying Flash "
                    f"(Pro cooldown for 5 min)..."
                )
                try:
                    return await _call_gemini(
                        system, user_msg, use_flash=True, timeout=timeout
                    )
                except Exception as flash_err:
                    logger.warning(f"Flash also failed: {flash_err}")
                if settings.openai_api_key:
                    logger.warning("Flash failed → falling back to OpenAI GPT-5.4")
                    try:
                        return await _call_openai(system, user_msg)
                    except Exception as oai_err:
                        logger.error(f"OpenAI fallback also failed: {oai_err}")
                        raise oai_err from e
                raise

            if is_transient and attempt < max_retries - 1:
                wait_time = 1 * (attempt + 1)
                logger.warning(
                    f"[LLM] {error_type} (attempt {attempt + 1}/{max_retries}): "
                    f"{error_str or '(empty)'} — retrying in {wait_time}s..."
                )
                await asyncio.sleep(wait_time)
                continue

            # Exhausted retries on any transient error — walk the fallback chain
            if is_transient:
                if provider == "gemini" and not use_flash:
                    logger.warning("Gemini Pro exhausted → trying Flash...")
                    try:
                        return await _call_gemini(
                            system, user_msg, use_flash=True, timeout=timeout
                        )
                    except Exception as flash_err:
                        logger.warning(f"Flash also failed: {flash_err}")

                if provider != "openai" and settings.openai_api_key:
                    logger.warning("Gemini exhausted → falling back to OpenAI GPT-5.4")
                    try:
                        return await _call_openai(system, user_msg)
                    except Exception as oai_err:
                        logger.error(f"OpenAI fallback also failed: {oai_err}")
                        raise oai_err from e

            logger.error(
                f"[LLM] Final failure ({error_type}): {error_str or '(empty)'}"
            )
            raise

    raise RuntimeError("LLM call failed after max retries")


SYSTEM_PROMPT = """\
You are a cold, analytical job-match evaluator. No cheerleading. No hype. Zero sycophancy.
Your job: evaluate whether a job listing is WORTH APPLYING TO given the candidate's profile, and produce a factual intelligence brief with structured scoring factors.
You are writing directly TO the candidate — always use second person ("you/your"). Every claim must trace to something in the listing or the profile below.

**LANGUAGE RULES:**
- NEVER use "mastered", "mastery", "expert", "expertise", "deep expertise", "strong command of", "proficiency" or any inflated competence language.
- NEVER use words like "thrilled", "excited", "passionate", "perfect fit", "great fit".
- Describe what you have built or shipped, not what you have "mastered".
- If a bullet sounds like a marketing pitch or LinkedIn hype, rewrite it as a flat, objective fact.

## Your Profile

{prefs.professional_profile}

## Hard Filters — REJECT only if CLEARLY impossible
- Pure non-tech role (sales, marketing, HR, legal, finance, design-only) where building software is not the job
- Salary band explicitly ENTIRELY below ${min_salary} with zero flexibility
- Role is exclusively about hand-writing low-level systems code with zero product/AI/application surface (e.g. pure kernel dev, embedded C firmware, FPGA)
- Hard geographic restriction outside the US with no remote option
- Requires a specific language you cannot learn (e.g. Mandarin-only customer-facing role)
- Non-software IT role (helpdesk, SysAdmin, network admin) with no development component

IMPORTANT: Do NOT hard-reject based on:
- Seniority in title alone — many "Senior" roles at startups are flexible, and the candidate can learn. Flag it as a caveat, not a reject.
- Years of experience — treat as friction, not a gate. "3+ years" is a caveat. "10+ years" is a strong caveat. Neither is an auto-reject.
- CS degree requirements — "or equivalent experience/projects" counts, and many companies are flexible even when the listing says "required". Flag as caveat.
- Stack mismatches — the candidate can learn new stacks. Flag what's unfamiliar as a caveat.
- Credential culture signals — penalize in scoring, don't reject.

## The Core Matching Question

You are scoring: "Is this role worth applying to?"

This means: Would the time invested in applying have a reasonable chance of leading somewhere — an interview, a conversation, a connection — given the candidate's unique profile? The candidate can learn anything technical. The question is whether the role aligns with their trajectory and whether the company is likely to engage.

## Structured Factor Extraction

For each job, extract these factors as scores from 0.0 to 1.0:

### domain_alignment (weight: 0.30)
How well does the company's domain match the candidate's strengths?
- 1.0: HealthTech/MedTech/Clinical AI — direct O.R. and clinical ops experience applies
- 0.9: AI tooling, LLM platforms, RAG systems — the candidate builds exactly these
- 0.8: iOS/mobile apps with AI components — candidate's primary workflow
- 0.7: Developer tools, AI-adjacent platforms
- 0.5: Generic SaaS or tech company — no special alignment
- 0.3: Enterprise infrastructure, legacy B2B — weak alignment
- 0.1: Non-tech adjacent (e-commerce platform dev, marketing tech)

### role_alignment (weight: 0.25)
How well does the role's daily work match what the candidate does?
- 1.0: Building AI-powered applications end-to-end, shipping product
- 0.9: iOS/mobile development with AI integration
- 0.8: Full-stack product engineering at a startup
- 0.7: AI/ML engineering with product focus
- 0.5: General software engineering — some alignment
- 0.3: Backend-only, infrastructure, or platform engineering
- 0.1: Pure ops, QA, or non-building role

### culture_fit (weight: 0.20)
Does the company value what the candidate brings?
- 1.0: "Show us what you've built", portfolio-first, non-traditional backgrounds welcome
- 0.9: Startup <50 people, ship-fast culture, AI-native workflow
- 0.7: Growth-stage company that values output and speed
- 0.5: Standard tech company — unclear signals
- 0.3: Enterprise with formal leveling, credential-heavy culture
- 0.1: FAANG-tier process, LeetCode culture, strict CS degree gate

### experience_friction (weight: 0.15)
How much friction will the candidate's experience gap create? (INVERTED — higher = less friction)
- 1.0: "No experience required", "portfolio over resume", entry-level
- 0.8: 0-2 years, or "equivalent projects accepted"
- 0.6: 2-3 years with "or equivalent" — portfolio might count
- 0.4: 3-5 years, no escape hatch — significant friction
- 0.2: 5-7 years required — very hard but not impossible at flexible companies
- 0.1: 8+ years required, strict corporate leveling — near-impossible

### stack_fit (weight: 0.10)
How much of the required tech stack does the candidate already use?
- 1.0: Swift/SwiftUI, Python, LLM APIs, RAG, vector DBs — exact match
- 0.8: Mostly overlapping (e.g. Python + some unfamiliar framework)
- 0.5: Partial overlap — some familiar, some new but learnable
- 0.3: Mostly unfamiliar stack but transferable concepts
- 0.1: Entirely different ecosystem (e.g. pure Java/Go/Rust with no Python/Swift)

## Caveats

Extract 0-4 caveats — factual friction points the candidate should know about before applying.
Each caveat should be a short, specific statement of fact.
Good: "Requires 4+ years Python backend experience — you have 1 year via personal projects."
Good: "Title says 'Senior' — at this 30-person startup, that may be flexible."
Good: "Stack is React + Node — you'd need to learn these; your Swift/Python skills transfer partially."
Bad: "You'd need to convince them." (vague)
Bad: "Might be a stretch." (not specific)

## Score Calibration — Apply-Worthiness

The final builder_score is computed from weighted factors. Your factor scores should reflect genuine alignment — the formula handles the rest. But as guidance:

- 0.80+: Strong alignment across domain, role, and culture. Few caveats. Worth prioritizing.
- 0.60-0.79: Good alignment with some friction. Caveats exist but the application is worth sending.
- 0.40-0.59: Mixed signals. Real friction but also real alignment. Show with caveats visible.
- 0.20-0.39: Weak alignment or heavy friction. Still surface it but flag as a long shot.
- Below 0.20: Set passed_filter to false. Truly no connection to the candidate's profile.

**Anchor at 0.55.** A generic "Software Engineer" posting with no special alignment = ~0.50.
A HealthTech AI role that values builders = 0.75+.

### Location adjustments (applied as a multiplier on the final score):
User's preferred locations: {preferred_locations}
- Remote / remote-first: 1.0 (no adjustment)
- Target city: 1.0
- Nearby: multiply by {nearby_penalty_mult}
- Regional: multiply by {regional_penalty_mult}
- Relocation required: multiply by {relocation_penalty_mult}
- International: multiply by {international_penalty_mult}

## Output Instructions — Facts Only

### logic_fit
2-3 factual sentences. Map the role's day-to-day work to your SPECIFIC apps and your
healthcare background. Reference the company's mission if stated.

### domain_leverage
2-3 sentences. State your exact unfair advantage. If healthcare-adjacent, lead with
Stryker/VA/clinical ops. If AI, lead with prompt-to-production velocity. If neither,
say "no significant domain leverage."

### risk_reward
2-3 sentences. Be brutally honest about realistic friction and upside.

### why_interesting (backward compat)
Same as logic_fit content.

### red_flags
1-5 concerns. EVERY job has at least one.

### dealbreaker_warnings
0-3 brutally honest gap statements framed as facts.

### company_oneliner
One factual sentence: what does this company DO?

### they_want
2-4 bullet points pulled directly from the listing.

### job_snapshot
2-3 factual sentences about the actual role.

### ai_pitch_summary
3 bullets of FACTUAL alignment. Each must cite something from the listing AND
something from the portfolio.

### fit_reasons
2-4 short factual reasons (5-8 words each).

### caveats
0-4 specific friction points the candidate should know.

### drafted_cover_letter
120-150 words. Brutally direct.
- NO "I'm excited/thrilled/passionate."
- NO corporate filler.
- If healthcare role: open with Stryker/VA clinical ops.
- If AI role: open with specific app you built.
- Mention gunnarguy.me once as portfolio.
- Close with a specific question about their product.
- Tone: confident peer.

## Output Format
Return ONLY valid JSON:
{{
  "passed_filter": true/false,
  "rejection_reason": "string (empty if passed)",
  "company_name": "string",
  "role_title": "string",
  "salary_floor": integer,
  "salary_max": integer,
  "is_remote": true/false,
  "domain_alignment": float,
  "role_alignment": float,
  "culture_fit": float,
  "experience_friction": float,
  "stack_fit": float,
  "builder_score": float,
  "ai_pitch_summary": "• bullet1\\n• bullet2\\n• bullet3",
  "drafted_cover_letter": "string",
  "location": "string",
  "tags": ["string"],
  "company_description": "string",
  "company_size": "string",
  "company_stage": "string",
  "company_url": "string",
  "requirements": ["string"],
  "nice_to_haves": ["string"],
  "tech_stack": ["string"],
  "why_interesting": "string",
  "job_snapshot": "string",
  "company_oneliner": "string",
  "they_want": ["string"],
  "logic_fit": "string",
  "domain_leverage": "string",
  "risk_reward": "string",
  "red_flags": ["string"],
  "apply_url": "string",
  "experience_level": "string",
  "job_type": "string",
  "benefits": ["string"],
  "fit_reasons": ["string"],
  "dealbreaker_warnings": ["string"],
  "caveats": ["string"]
}}
"""


TRIAGE_PROMPT = """\
You are a maximally permissive job triage filter. Your DEFAULT answer is PASS (dominated=true).
Only reject jobs that are OBVIOUSLY wrong — clear garbage that no software builder would ever want.
The full scorer handles ALL nuance. Your job is just to remove spam and non-software roles.
When in doubt, ALWAYS pass.

## Candidate snapshot
{professional_profile}
Prefers remote. US-based. Builds AI-powered iOS/Python apps. Healthcare domain expertise.

## ONLY reject (dominated=false) if the role is CLEARLY one of these:
1. Pure non-tech role: sales, marketing, HR, legal, accounting, recruiting — NOT building software
2. IT Support / Helpdesk / SysAdmin / Network Admin — no software development component
3. E-commerce platform dev (Shopify themes, Magento, WooCommerce, WordPress plugins, Drupal)
4. Hard geographic restriction outside the US with ZERO remote option mentioned anywhere
5. Role description is spam, garbled, or clearly a scam

## PASS everything else, including:
- ANY seniority level (Senior, Staff, Lead, Principal — the full scorer evaluates these)
- ANY experience requirement (even "10+ years" — the full scorer handles friction)
- ANY tech stack (the full scorer evaluates transferability)
- ANY degree requirement (the full scorer evaluates flexibility)
- Roles you're not sure about — let the full scorer decide

Return ONLY valid JSON:
{{"dominated": true/false, "reason": "one sentence"}}
"""


async def triage_job(raw: RawJobListing, prefs: UserPreferences | None = None) -> bool:
    """Fast triage with Flash model. Returns True if worth full scoring."""
    if prefs is None:
        prefs = UserPreferences()

    # ── Programmatic pre-triage: only reject obvious non-software junk ────
    title_lower = raw.title.lower()
    junk_titles = [
        "account executive",
        "sales representative",
        "recruiter",
        "human resources",
        "copywriter",
        "content writer",
        "helpdesk",
        "help desk",
        "it support",
    ]
    for junk in junk_titles:
        if junk in title_lower:
            logger.info(
                f"[TRIAGE] PRE-REJECT (junk title '{junk}') | {raw.title} @ {raw.company}"
            )
            return False

    triage_sys = TRIAGE_PROMPT.replace(
        "{professional_profile}", prefs.professional_profile
    )
    user_msg = f"Title: {raw.title}\nCompany: {raw.company}\nLocation: {raw.location}\nRemote: {raw.is_remote}\n\nDescription (first 1500 chars):\n{raw.description[:1500]}"

    try:
        content = await _call_llm(triage_sys, user_msg, use_flash=True)
        data: dict = json.loads(content)
        if isinstance(data, list) and len(data) > 0:
            data = data[0]
        passed = data.get("dominated", False)
        reason = data.get("reason", "")
        logger.info(f"[TRIAGE] {'PASS' if passed else 'FAIL'} | {raw.title} @ {raw.company} | {reason}")
        return passed
    except Exception as e:
        logger.warning(
            f"[TRIAGE] ERROR for {raw.title} @ {raw.company}: {type(e).__name__}: {e or '(empty)'} — PASSING to full scorer"
        )
        return True  # On error, let full scoring evaluate (don't silently kill listings)


async def score_job(
    raw: RawJobListing,
    prefs: UserPreferences | None = None,
) -> ScoringResult:
    """Run a raw job listing through the LLM bouncer. Returns ScoringResult."""
    if prefs is None:
        prefs = UserPreferences()

    locations_formatted = (
        ", ".join(prefs.preferred_locations)
        if prefs.preferred_locations
        else "Kalamazoo, Michigan"
    )

    system = SYSTEM_PROMPT.replace("{min_salary}", str(prefs.min_salary))
    system = system.replace("{prefs.professional_profile}", prefs.professional_profile)
    system = system.replace("{nearby_penalty_mult}", f"{prefs.nearby_penalty_mult:.2f}")
    system = system.replace(
        "{regional_penalty_mult}", f"{prefs.regional_penalty_mult:.2f}"
    )
    system = system.replace(
        "{relocation_penalty_mult}", f"{prefs.relocation_penalty_mult:.2f}"
    )
    system = system.replace(
        "{international_penalty_mult}", f"{prefs.international_penalty_mult:.2f}"
    )
    system = system.replace("{preferred_locations}", locations_formatted)

    # Classify location tier and inject into prompt
    loc_tier = classify_location(
        raw.location or "",
        prefs.home_city,
        prefs.home_state,
        raw.is_remote,
        preferred_locations=prefs.preferred_locations,
    )
    tier_label = TIER_LABELS.get(loc_tier, "unknown")

    user_msg = f"""Evaluate this job listing and extract EVERYTHING useful:

**Title:** {raw.title}
**Company:** {raw.company}
**Location:** {raw.location}
**Location Tier:** {tier_label} (tier {loc_tier} — use the matching penalty from the location adjustments above)
**Remote:** {raw.is_remote if raw.is_remote is not None else "Unknown"}
**Salary info:** {raw.salary_text or "Not specified"}
**URL:** {raw.url}

**Full Description:**
{raw.description[:8000]}

**User preferences:**
- Min salary: ${prefs.min_salary}
- Remote required: {prefs.require_remote}
- Preferred roles: {", ".join(prefs.preferred_roles)}
- Excluded keywords: {", ".join(prefs.excluded_keywords)}
- Location pref: {prefs.location_preference}
"""

    try:
        content = await _call_llm(system, user_msg, use_flash=True)
        data: dict = json.loads(content)

        # Gemini sometimes wraps the response in an array
        if isinstance(data, list) and len(data) > 0:
            data = data[0]

        if not data.get("passed_filter", False):
            reason = data.get("rejection_reason", "Did not pass filters")
            logger.info(f"[SCORE] REJECTED by LLM | {raw.title} @ {raw.company} | {reason}")
            return ScoringResult(
                passed_filter=False,
                rejection_reason=reason,
            )

        # Extract structured factor scores from LLM response
        domain_alignment = max(0.0, min(1.0, data.get("domain_alignment") or 0.0))
        role_alignment = max(0.0, min(1.0, data.get("role_alignment") or 0.0))
        culture_fit = max(0.0, min(1.0, data.get("culture_fit") or 0.0))
        experience_friction = max(0.0, min(1.0, data.get("experience_friction") or 0.0))
        stack_fit = max(0.0, min(1.0, data.get("stack_fit") or 0.0))

        # Compute weighted score from factors (server-side truth)
        computed_score = (
            domain_alignment * 0.30
            + role_alignment * 0.25
            + culture_fit * 0.20
            + experience_friction * 0.15
            + stack_fit * 0.10
        )

        # Use computed score if we got factor data, otherwise fall back to LLM's builder_score
        has_factors = any(
            data.get(k)
            for k in [
                "domain_alignment",
                "role_alignment",
                "culture_fit",
                "experience_friction",
                "stack_fit",
            ]
        )
        final_score = round(
            max(
                0.0,
                min(
                    1.0,
                    (
                        computed_score
                        if has_factors
                        else (data.get("builder_score") or 0.0)
                    ),
                ),
            ),
            2,
        )

        job = JobPayload(
            company_name=data.get("company_name", raw.company),
            role_title=data.get("role_title", raw.title),
            salary_floor=data.get("salary_floor") or 0,
            is_remote=data.get("is_remote") or False,
            builder_score=final_score,
            ai_pitch_summary=data.get("ai_pitch_summary", ""),
            drafted_cover_letter=data.get("drafted_cover_letter", ""),
            source_url=raw.url,
            posted_at=datetime.now(timezone.utc),
            location=data.get("location", raw.location),
            tags=data.get("tags", []),
            # Rich company intelligence
            description=raw.description[:12000],  # Preserve original
            company_description=data.get("company_description", ""),
            company_size=data.get("company_size", "Unknown"),
            company_stage=data.get("company_stage", "Unknown"),
            company_url=data.get("company_url", ""),
            salary_max=data.get("salary_max") or 0,
            requirements=data.get("requirements", []),
            nice_to_haves=data.get("nice_to_haves", []),
            tech_stack=data.get("tech_stack", []),
            why_interesting=data.get("why_interesting", ""),
            red_flags=data.get("red_flags", []),
            apply_url=data.get("apply_url", ""),
            experience_level=data.get("experience_level", "Not specified"),
            job_type=data.get("job_type", "Not specified"),
            benefits=data.get("benefits", []),
            fit_reasons=data.get("fit_reasons", []),
            dealbreaker_warnings=data.get("dealbreaker_warnings", []),
            logic_fit=data.get("logic_fit", ""),
            domain_leverage=data.get("domain_leverage", ""),
            risk_reward=data.get("risk_reward", ""),
            company_oneliner=data.get("company_oneliner", ""),
            they_want=data.get("they_want", []),
            job_snapshot=data.get("job_snapshot", ""),
            # Structured scoring factors
            domain_alignment=domain_alignment,
            role_alignment=role_alignment,
            culture_fit=culture_fit,
            experience_friction=experience_friction,
            stack_fit=stack_fit,
            caveats=data.get("caveats", []),
            scoring_version="v2",
        )

        return ScoringResult(passed_filter=True, job=job)

    except Exception as e:
        logger.warning(f"[SCORE] LLM ERROR for {raw.title} @ {raw.company}: {type(e).__name__}: {e or '(empty)'} — RETRY LATER")
        return ScoringResult(passed_filter=False, rejection_reason="LLM_FAILURE_RETRY")


async def score_batch(
    listings: list[RawJobListing],
    prefs: UserPreferences | None = None,
) -> list[ScoringResult]:
    """Score a batch of raw listings. Uses LLM scoring and handles retries."""
    results = []
    for raw in listings:
        result = await score_job(raw, prefs)
        results.append(result)
        await asyncio.sleep(1)  # gentle pacing
    return results


async def triage_and_score(
    listings: list[RawJobListing],
    prefs: UserPreferences | None = None,
    on_triage_start: Callable[[RawJobListing, int, int], None] | None = None,
    on_triage_result: Callable[[RawJobListing, bool], None] | None = None,
    on_scoring_started: Callable[[int], None] | None = None,
    on_score_start: Callable[[RawJobListing, int, int], None] | None = None,
    on_score_result: Callable[[RawJobListing, ScoringResult], None] | None = None,
) -> list[ScoringResult]:
    """Two-tier scoring.

    Tries: Flash triage → Pro scoring. If LLM fails, marks for retry.
    Always returns results — never drops jobs silently.
    """
    if not listings:
        return []

    # Phase 1: Try Flash triage (but if it fails entirely, skip triage and score all)
    logger.info(f"Phase 1: Triaging {len(listings)} listings with Flash...")
    triage_failed = False
    triage_results = []
    import time as _time
    t0 = _time.monotonic()
    try:
        batch_size = 5
        for i in range(0, len(listings), batch_size):
            batch = listings[i : i + batch_size]

            async def _triage_one(offset: int, raw: RawJobListing):
                overall_index = i + offset + 1
                if on_triage_start:
                    on_triage_start(raw, overall_index, len(listings))
                passed = await triage_job(raw, prefs)
                if on_triage_result:
                    on_triage_result(raw, passed)
                return passed

            batch_results = await asyncio.gather(
                *(_triage_one(offset, raw) for offset, raw in enumerate(batch)),
                return_exceptions=True,
            )
            triage_results.extend(batch_results)
            if i + batch_size < len(listings):
                await asyncio.sleep(1)
    except Exception as e:
        logger.warning(f"Triage phase failed entirely: {e}")
        triage_failed = True

    triage_elapsed = _time.monotonic() - t0
    logger.info(f"[TRIAGE] Phase 1 took {triage_elapsed:.1f}s")

    if triage_failed or not triage_results:
        # LLM triage unavailable — let everything through
        logger.info("Triage unavailable — passing all listings to scoring")
        survivors: list[tuple[RawJobListing, int]] = [
            (raw, idx + 1) for idx, raw in enumerate(listings)
        ]
    else:
        survivors = []
        for idx, (raw, passed) in enumerate(zip(listings, triage_results), start=1):
            if isinstance(passed, BaseException):
                survivors.append((raw, idx))  # On error, let it through
            elif passed:
                survivors.append((raw, idx))

    logger.info(f"Phase 1 complete: {len(survivors)}/{len(listings)} passed triage")

    if not survivors:
        return [
            ScoringResult(passed_filter=False, rejection_reason="Failed triage")
        ] * len(listings)

    if on_scoring_started:
        on_scoring_started(len(survivors))

    # Phase 2: Try LLM scoring on first few, detect if LLM is working
    logger.info(f"Phase 2: Scoring {len(survivors)} survivors...")

    # Test LLM with first listing
    t1 = _time.monotonic()
    first_raw, _ = survivors[0]
    if on_score_start:
        on_score_start(first_raw, 1, len(survivors))
    test_result = await score_job(first_raw, prefs)
    if on_score_result:
        on_score_result(first_raw, test_result)
    test_elapsed = _time.monotonic() - t1
    logger.info(f"[SCORE] Test scoring took {test_elapsed:.1f}s")
    llm_works = test_result.passed_filter or test_result.rejection_reason != ""

    # Check if the test itself failed due to LLM error
    if (
        test_result.rejection_reason == "LLM_FAILURE_RETRY"
    ):
        llm_works = False

    results = [test_result]

    if llm_works:
        logger.info("LLM scoring working — using LLM for remaining listings")
        # Score remaining survivors in parallel batches of 3
        sem = asyncio.Semaphore(3)
        consecutive_fallbacks = 0
        fell_back_to_retry = False

        async def _score_one(raw_listing: RawJobListing, score_index: int):
            async with sem:
                if on_score_start:
                    on_score_start(raw_listing, score_index, len(survivors))
                result = await score_job(raw_listing, prefs)
                if on_score_result:
                    on_score_result(raw_listing, result)
                return result

        score_batch_size = 3
        remaining_survivors = survivors[1:]
        for i in range(0, len(remaining_survivors), score_batch_size):
            if fell_back_to_retry:
                break
            batch = remaining_survivors[i : i + score_batch_size]
            batch_results = await asyncio.gather(
                *(
                    _score_one(raw, i + offset + 2)
                    for offset, (raw, _) in enumerate(batch)
                ),
                return_exceptions=True,
            )
            for (raw, _), result in zip(batch, batch_results):
                if isinstance(result, BaseException):
                    logger.warning(f"[SCORE] Exception scoring {raw.title}: {result}")
                    result = ScoringResult(passed_filter=False, rejection_reason="LLM_FAILURE_RETRY")
                    if on_score_result:
                        on_score_result(raw, result)

                is_failure = result.rejection_reason == "LLM_FAILURE_RETRY"
                if is_failure:
                    consecutive_fallbacks += 1
                else:
                    consecutive_fallbacks = 0

                results.append(result)

                if consecutive_fallbacks >= 5:
                    rest = remaining_survivors[i + score_batch_size :]
                    if rest:
                        logger.warning(
                            f"LLM failed {consecutive_fallbacks}x in a row — "
                            f"marking remaining {len(rest)} listings for next cycle"
                        )
                        for r, _ in rest:
                            retry_result = ScoringResult(
                                passed_filter=False,
                                rejection_reason="LLM_FAILURE_RETRY",
                            )
                            results.append(retry_result)
                            if on_score_result:
                                on_score_result(r, retry_result)
                    fell_back_to_retry = True
                    break

            if not fell_back_to_retry:
                await asyncio.sleep(0.3)
    else:
        logger.warning("LLM scoring completely unavailable — delaying remaining listings to next ingest cycle")
        for raw, _ in survivors[1:]:
            retry_result = ScoringResult(
                passed_filter=False, rejection_reason="LLM_FAILURE_RETRY"
            )
            results.append(retry_result)
            if on_score_result:
                on_score_result(raw, retry_result)

    passed = sum(1 for r in results if r.passed_filter)
    logger.info(f"Phase 2 complete: {passed}/{len(survivors)} passed scoring")

    return results
