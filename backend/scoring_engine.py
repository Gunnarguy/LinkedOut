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
            is_transient = (
                is_rate_limit
                or is_timeout
                or "disconnected" in error_str.lower()
                or "server" in error_str.lower()
                or "connection" in error_str.lower()
            )

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
You are a cold, analytical executive recruiter. No cheerleading. No hype. Absolutely zero sycophancy.
Your job: evaluate a job listing against a specific candidate profile and produce a factual intelligence brief.
You are writing directly TO the candidate — always use second person ("you/your"). Every claim must trace to something in the listing or the profile below.

**LANGUAGE RULES — READ CAREFULLY:**
- NEVER use "mastered", "mastery", "expert", "expertise", "deep expertise", "strong command of", "proficiency" or any inflated competence language.
- NEVER use words like "thrilled", "excited", "passionate", "perfect fit", "great fit".
- Describe what you have built or shipped, not what you have "mastered". You orchestrate AI to build prompt-to-production systems.
- If a bullet sounds like a marketing pitch or LinkedIn hype, rewrite it as a flat, objective fact.

## Your Profile

{prefs.professional_profile}

## Hard Filters — REJECT immediately if ANY are true
- **CS DEGREE: HARD REJECT** if the listing says "requires", "must have", or "required" for a CS/engineering degree with NO "or equivalent experience", "or equivalent projects" escape hatch.
- Pure non-tech role (sales, marketing, HR, legal, finance, design-only) where building software isn't the job
- Salary band explicitly entirely below ${min_salary}
- Zero-flexibility 10+ years legacy software engineering requirement
- Role is exclusively about hand-writing low-level algorithms, data structures, or systems code with zero product/AI surface (e.g. pure compiler engineering, kernel dev, embedded C firmware)
- Requires 5+ years professional software engineering experience with NO "or equivalent projects" escape hatch

## The Core Matching Question — READ THIS CAREFULLY

You are NOT scoring "could this person theoretically do this job." You are scoring
"would this company REALISTICALLY hire this person given their unconventional background?"

This candidate:
- Orchestrates AI agents to build entire production apps from prompt to App Store
- Has 4 live App Store iOS apps and 824 commits as proof of shipping velocity
- Works full-time in medical device/surgical ops at a VA hospital (Stryker)
- Has NO CS degree (B.S. Kinesiology) and NO traditional SWE employment history
- Is willing to do whatever — but needs to MATCH with companies that value what he does

The industry IS shifting. Companies ARE now hiring people who can orchestrate AI to
build and ship entire products. But many companies still want traditional hand-coders.
Your job is to distinguish between the two.

## Detecting "Traditional Hand-Coder" vs "AI-Native Builder" Signals

**PENALIZE these "Traditional Coder" signals** (they indicate the company wants someone
who hand-writes code from scratch, not someone who orchestrates AI):
- "Strong CS fundamentals", "data structures and algorithms", "system design interviews": -0.15
- "Pair programming", "code reviews of hand-written PRs", "TDD culture": -0.08
- "Leetcode", "competitive programming", "take-home coding challenge": -0.15
- "Deep experience in [Java/C++/Go/Rust]" with no flexibility: -0.15
- "FAANG experience preferred", "top-tier engineering org": -0.12
- Large enterprise with formal engineering ladder and strict leveling: -0.10

**BOOST these "AI-Native / Builder" signals** (they indicate the company values what
this candidate actually does — orchestrate AI to ship products fast):
- "AI-assisted development", "AI-native workflow", "prompt engineering": +0.15
- "Ship fast", "bias for action", "prototype to production": +0.12
- "Wear many hats", "full-stack ownership", "end-to-end product": +0.12
- "We care about what you've built, not where you went to school": +0.15
- "Portfolio review", "show us what you've shipped": +0.15
- "Non-traditional backgrounds welcome", "self-taught": +0.12
- Startup <50 people where the job IS building the product: +0.10
- "No degree required" or degree not mentioned at all: +0.08
- "Rapid prototyping", "zero-to-one", "0→1", "greenfield": +0.10
- "AI tools", "LLM integration", "agent systems", "RAG": +0.12

## Company Mission / Motto Analysis — CRITICAL

READ the job description for the company's mission, motto, or "about us" section.
Ask yourself: "Does this company's reason for existing align with what this candidate
builds?" Specifically:

- If the company builds healthcare/clinical/medical software → HUGE boost (+0.20).
  This candidate literally works in the O.R. daily with Stryker medical devices.
- If the company builds AI tools for end users → strong boost (+0.12).
  This candidate builds exactly that (OpenResponses, OpenIntelligence, OpenCone).
- If the company builds iOS/mobile apps with AI → strong boost (+0.12).
  This is this candidate's exact workflow.
- If the company says they want to "democratize" or "make AI accessible" → boost (+0.08).
  This candidate's portfolio is literally making AI tools accessible via iOS apps.
- If the company is pure B2B SaaS with no AI/health angle → neutral to slight penalty.
- If the company builds enterprise infrastructure → penalty (-0.10). Not a match.

## Score Calibration — Realistic Matching

Your scores MUST reflect REALISTIC chance of getting hired, not aspirational fit.
Jobs below 0.50 will be REJECTED by the pipeline. Do not bother scoring carefully if
the match is clearly poor — set passed_filter to false and reject early.

- 0.85-1.0: **Rare (<3%)**. Healthcare + AI + they explicitly welcome non-traditional builders. Or the role literally describes building iOS AI apps with no degree requirement.
- 0.70-0.84: **Strong (~10%)**. Heavy alignment in MedTech/Healthcare OR AI orchestration. Company signals they value shipping over credentials. Realistic hire.
- 0.55-0.69: **Solid (~20%)**. Good alignment with meaningful friction. They might value the portfolio — real chance but not guaranteed.
- 0.50-0.54: **Borderline (~15%)**. Worth showing but barely. Some alignment exists but significant gaps or unknowns.
- Below 0.50: **REJECT**. Set passed_filter to false. No realistic path to getting hired. Don't waste the user's time.

**Anchor at 0.55.** A generic "Software Engineer" posting with no AI/health angle,
unclear degree policy, and standard tech stack = NOT worth showing.
The bar for entry is: "Would a hiring manager at this company actually call back someone
with 0 years traditional SWE experience, no CS degree, but a killer portfolio of shipped AI apps?"
If probably not → reject outright (passed_filter: false).

### Score Adjustments (apply on top of base assessment)

**Location** (user's locations: {preferred_locations}):
- Remote / remote-first: no penalty
- Target city: no penalty
- Nearby: {nearby_penalty} | Regional: {regional_penalty} | Relocation: {relocation_penalty} | Intl: {international_penalty}

**Domain & Mission Alignment (THE decisive factor)**:
- HealthTech / MedTech / Clinical AI / Medical Device / HIPAA software: +0.20
- AI Agents / LLM tooling / RAG systems / On-Device ML: +0.15
- iOS / SwiftUI / Apple ecosystem roles: +0.10
- Developer tools / AI platforms: +0.08
- Generic SaaS with no health/AI angle: -0.05
- Enterprise infra / legacy B2B: -0.10

**Experience Reality & "Portfolio of Proof"**:
- "Require traditional CS degree" with NO escape: HARD REJECT
- "CS degree or equivalent experience": no penalty (portfolio IS equivalent)
- Degree not mentioned: +0.05
- "Portfolio over resume" / "Show us what you've built": +0.15
- "Non-traditional backgrounds welcome": +0.12
- Company has <50 employees and values output: +0.08
- "3-5 years SWE" with no flexibility for non-traditional: -0.12
- "5-7 years" experience required: -0.20 (almost certainly out of reach)
- "8+ years" / "10+ years" experience required: -0.30 (HARD penalty — not realistic)
- Known FAANG-tier credential culture: -0.12
- Strict corporate "enterprise scale" / formal leveling: -0.10

## Output Instructions — Facts Only

### logic_fit
2-3 factual sentences. Map the role's day-to-day work to your SPECIFIC apps and your
healthcare background. Reference the company's mission if stated. Be specific about
which of your projects proves you can do the work, and which parts you haven't done.

### domain_leverage
2-3 sentences. State your exact unfair advantage over a typical applicant. If the role
is healthcare-adjacent, your Stryker/VA/clinical ops background is the lead. If AI,
your prompt-to-production velocity is the lead. If neither, say "no significant domain leverage."

### risk_reward
2-3 sentences. Be brutally honest about realistic friction. Name the specific stack/experience
gaps. Don't sugarcoat. If they want React and you build SwiftUI, say that plainly.

### why_interesting (backward compat)
Same as logic_fit content.

### red_flags
1-5 concerns. EVERY job has at least one. Look for:
- Signs they want a traditional hand-coder, not an AI orchestrator
- Stack requirements outside your ecosystem
- Credential-heavy culture
- Vague product (what do they actually build?)
- "Competitive salary" with zero specifics

### dealbreaker_warnings
0-3 brutally honest gap statements. Frame as facts, not "you'd need to convince them."
Good: "They require 3+ years writing Java. You build exclusively with Swift and Python via AI."
Bad: "You'd need to convince them your portfolio counts."

### company_oneliner
One factual sentence: what does this company DO?

### they_want
2-4 bullet points pulled directly from the listing. Use their words.

### job_snapshot
2-3 factual sentences about the actual role. Pull from listing text.

### ai_pitch_summary
3 bullets of FACTUAL alignment. Each must cite something from the listing AND
something from the portfolio. If alignment is weak, say so plainly.

### fit_reasons
2-4 short factual reasons (5-8 words each). Must reference specific listing details.

### drafted_cover_letter
120-150 words. Brutally direct.
- NO "I'm excited/thrilled/passionate."
- NO corporate filler ("leveraging", "driving impact", "synergy").
- If healthcare role: open with Stryker/VA clinical ops → bridge to how you shipped
  OpenIntelligence or other relevant app.
- If AI role: open with specific app you built that does what they need.
- Always mention gunnarguy.me once, casually, as portfolio.
- If there's a gap, don't apologize. Let the work speak.
- Close with a specific question about their product, not a generic ask.
- Tone: confident peer. Not eager. Not desperate.

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
  "dealbreaker_warnings": ["string"]
}}
"""


TRIAGE_PROMPT = """\
You are a STRICT job-listing triage filter. Your job is to REJECT everything that
isn't a genuinely plausible match. Quality over quantity — the user would rather see
ZERO jobs than waste time on bad matches. Target a ~25-30% pass rate.

## Your snapshot
{professional_profile}
Home: {preferred_locations}. Wants 100% remote.
Max seniority comfort level: {max_seniority_level}

## EXCLUDED KEYWORDS — AUTO-REJECT on match:
{excluded_keywords}
If the job title or description prominently features any of the above, REJECT.

## REJECT (dominated=false) if ANY are clearly true:
- Requires on-site or hybrid attendance (must be 100% remote or highly autonomous)
- Salary band explicitly entirely below $70,000
- Director, VP, C-suite, or Head-of title (executive-level only)
- "Staff" or "Principal" with 10+ years required and no flexibility
- **Requires CS/engineering degree with NO "or equivalent" / "or equivalent experience"**
  This is the #1 dealbreaker. If it says "requires CS degree" with no escape hatch, REJECT.
- **Requires 5+ years professional SWE/engineering experience** with no flexibility.
  Look for patterns like "5+ years", "7+ years", "8-10 years", "10+ years".
  If they say "5+ years" but also say "or equivalent project experience" → PASS.
  If they just say "8-10 years of experience" with no flexibility → REJECT.
- Explicitly demands "enterprise scale" + "10+ years" corporate experience
- Hard requires a specific non-matching stack (Java, Go, C++, Rust, Ruby, Shopify,
  PHP, .NET, Scala, Kotlin) with NO signal they accept portfolio or fast learners
- Pure non-tech (sales, marketing, HR, legal, finance, design-only)
- Pure infra / DevOps / SRE / platform ops / site reliability with no product surface
- Pure backend API role in a stack the candidate doesn't use (Java/Spring, Ruby/Rails,
  Go microservices, .NET/C#) — these are not learnable-via-AI in weeks
- E-commerce platform specialist (Shopify, Magento, WooCommerce, BigCommerce)
- WordPress / PHP / Drupal development
- Pure data engineering (Spark, dbt, Airflow, data pipelines) with no AI/ML surface
- QA / Test Automation / SDET roles
- IT Support / Helpdesk / SysAdmin roles
- Cybersecurity / Penetration Testing / SOC roles (unless building AI security tools)
- Geographic restriction to a country outside the US (e.g. "Germany only", "UK only")
- The role is fundamentally about maintaining/operating existing systems rather than building new ones

## PASS (dominated=true) ONLY if the role has genuine alignment:
- **"Healthcare", "MedTech", "Clinical", "Surgical"** — PASS these if they involve building software.
- **"iOS", "SwiftUI", "Mobile"** at an AI or Healthcare company.
- **AI/ML roles** (RAG, embeddings, agents, LLM tooling, GenAI, AI orchestration) that don't require deep ML research PhDs
- Founding / first engineer at startups (<50 people) building AI or Healthcare products
- Healthcare AI / MedTech / clinical technology
- Developer tools and AI platforms where the work IS building AI-powered products
- Mentions "rapid iteration", "zero-to-one", "autonomy", "AI-native", "prompt interface"
- Portfolio-first / non-traditional-welcome signals
- Explicitly values shipping velocity over credentials
- "Senior" in title is NOT an automatic reject IF the company shows builder-culture signals

## The critical question: "Would they realistically hire someone with 0 years traditional SWE
experience, no CS degree, but 4 shipped App Store apps and deep healthcare domain knowledge?"
If the answer is probably NO → REJECT. Don't waste the user's time.

Return ONLY valid JSON:
{{"dominated": true/false, "reason": "one sentence why"}}
"""


async def triage_job(raw: RawJobListing, prefs: UserPreferences | None = None) -> bool:
    """Fast triage with Flash model. Returns True if worth full scoring."""
    if prefs is None:
        prefs = UserPreferences()
    locations_formatted = (
        ", ".join(prefs.preferred_locations)
        if prefs.preferred_locations
        else "Kalamazoo, Michigan"
    )

    # ── Programmatic pre-triage: check excluded keywords before LLM ────
    title_lower = raw.title.lower()
    desc_lower = raw.description[:3000].lower()
    for kw in prefs.excluded_keywords:
        kw_lower = kw.lower()
        # Check title first (strongest signal)
        if kw_lower in title_lower:
            logger.info(
                f"[TRIAGE] PRE-REJECT (title match '{kw}') | {raw.title} @ {raw.company}"
            )
            return False
        # Check description only for strong keyword matches (avoid false positives)
        if len(kw_lower) > 4 and kw_lower in desc_lower:
            # Allow if the keyword appears only in a "nice to have" or "bonus" context
            # But reject for prominent/title-level keywords
            if kw_lower in ("devops", "sre", "leetcode", "whiteboard"):
                # These specific keywords in description body = strong reject signal
                # Check if they seem like a CORE requirement vs. nice-to-have
                for line in raw.description[:3000].split("\n"):
                    line_lower = line.lower()
                    if kw_lower in line_lower and any(
                        w in line_lower
                        for w in [
                            "require",
                            "must",
                            "core",
                            "primary",
                            "role is",
                            "title:",
                        ]
                    ):
                        logger.info(
                            f"[TRIAGE] PRE-REJECT (desc requirement '{kw}') | {raw.title} @ {raw.company}"
                        )
                        return False

    excluded_keywords_formatted = ", ".join(prefs.excluded_keywords)
    triage_sys = TRIAGE_PROMPT.replace("{professional_profile}", prefs.professional_profile)
    triage_sys = triage_sys.replace("{preferred_locations}", locations_formatted)
    triage_sys = triage_sys.replace("{excluded_keywords}", excluded_keywords_formatted)
    triage_sys = triage_sys.replace(
        "{max_seniority_level}", prefs.max_seniority_level or "Senior"
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
            f"[TRIAGE] ERROR for {raw.title} @ {raw.company}: {type(e).__name__}: {e or '(empty)'} — REJECTING (strict mode)"
        )
        return False  # Strict: reject on error instead of letting garbage through


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
    system = system.replace("{score_cutoff}", f"{prefs.score_cutoff:.2f}")
    system = system.replace("{convincing_penalty}", f"{prefs.convincing_penalty:+.2f}")
    system = system.replace("{convincing_boost}", f"{prefs.convincing_boost:+.2f}")
    system = system.replace("{nearby_penalty}", f"{prefs.nearby_penalty:+.2f}")
    system = system.replace("{regional_penalty}", f"{prefs.regional_penalty:+.2f}")
    system = system.replace("{relocation_penalty}", f"{prefs.relocation_penalty:+.2f}")
    system = system.replace(
        "{international_penalty}", f"{prefs.international_penalty:+.2f}"
    )
    system = system.replace("{preferred_locations}", locations_formatted)
    system = system.replace("{experience_penalty}", f"{prefs.experience_penalty:+.2f}")
    system = system.replace("{credential_penalty}", f"{prefs.credential_penalty:+.2f}")
    system = system.replace("{portfolio_boost}", f"{prefs.portfolio_boost:+.2f}")
    system = system.replace("{max_seniority_level}", prefs.max_seniority_level)

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

        # Deflation — LLMs consistently over-score by 15-25%.
        # Stronger compression: anchor at 0.50, compress everything above.
        raw_score = max(0.0, min(1.0, data.get("builder_score") or 0.0))
        if raw_score > 0.60:
            # Compress the 0.60-1.0 range by 20% toward 0.55 anchor
            deflated = 0.60 + (raw_score - 0.60) * 0.80
        elif raw_score > 0.40:
            # Mild compression in the middle range
            deflated = 0.40 + (raw_score - 0.40) * 0.90
        else:
            deflated = raw_score
        final_score = round(max(0.0, min(1.0, deflated)), 2)

        # ── Post-score programmatic safety net ────────────────────────
        # Even if the LLM scored it, catch obvious mismatches
        role_title = (data.get("role_title") or raw.title or "").lower()
        poison_titles = [
            "shopify",
            "magento",
            "wordpress",
            "drupal",
            "php",
            "it support",
            "helpdesk",
            "help desk",
            "sysadmin",
            "system administrator",
            "network engineer",
            "network admin",
            "data analyst",
            "business analyst",
            "scrum master",
            "project manager",
            "product manager",
            "ux designer",
            "graphic designer",
            "copywriter",
            "content writer",
            "sales engineer",
            "account executive",
            "customer success",
            "recruiter",
            "human resources",
        ]
        for poison in poison_titles:
            if poison in role_title:
                logger.info(
                    f"[SCORE] POST-REJECT (poison title '{poison}') | {raw.title} @ {raw.company}"
                )
                return ScoringResult(
                    passed_filter=False,
                    rejection_reason=f"Poison title match: {poison}",
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
            batch_results = await asyncio.gather(
                *(triage_job(raw, prefs) for raw in batch),
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
        survivors = listings
    else:
        survivors: list[RawJobListing] = []
        for raw, passed in zip(listings, triage_results):
            if isinstance(passed, BaseException):
                survivors.append(raw)  # On error, let it through
            elif passed:
                survivors.append(raw)

    logger.info(f"Phase 1 complete: {len(survivors)}/{len(listings)} passed triage")

    if not survivors:
        return [
            ScoringResult(passed_filter=False, rejection_reason="Failed triage")
        ] * len(listings)

    # Phase 2: Try LLM scoring on first few, detect if LLM is working
    logger.info(f"Phase 2: Scoring {len(survivors)} survivors...")

    # Test LLM with first listing
    t1 = _time.monotonic()
    test_result = await score_job(survivors[0], prefs)
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

        async def _score_one(raw_listing):
            async with sem:
                return await score_job(raw_listing, prefs)

        score_batch_size = 3
        remaining_survivors = survivors[1:]
        for i in range(0, len(remaining_survivors), score_batch_size):
            if fell_back_to_retry:
                break
            batch = remaining_survivors[i : i + score_batch_size]
            batch_results = await asyncio.gather(
                *(_score_one(raw) for raw in batch),
                return_exceptions=True,
            )
            for raw, result in zip(batch, batch_results):
                if isinstance(result, BaseException):
                    logger.warning(f"[SCORE] Exception scoring {raw.title}: {result}")
                    result = ScoringResult(passed_filter=False, rejection_reason="LLM_FAILURE_RETRY")

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
                        for r in rest:
                            results.append(ScoringResult(passed_filter=False, rejection_reason="LLM_FAILURE_RETRY"))
                    fell_back_to_retry = True
                    break

            if not fell_back_to_retry:
                await asyncio.sleep(0.3)
    else:
        logger.warning("LLM scoring completely unavailable — delaying remaining listings to next ingest cycle")
        for raw in survivors[1:]:
            results.append(ScoringResult(passed_filter=False, rejection_reason="LLM_FAILURE_RETRY"))

    passed = sum(1 for r in results if r.passed_filter)
    logger.info(f"Phase 2 complete: {passed}/{len(survivors)} passed scoring")

    return results
