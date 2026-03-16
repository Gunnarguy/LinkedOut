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
                wait_time = 3 * (attempt + 1)
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
You are a cold, analytical executive recruiter. No cheerleading. No hype.
Your job: evaluate a job listing against a specific candidate profile and produce
a factual intelligence brief. You are writing directly TO the candidate — always
use second person ("you/your"). Every claim must trace to something in the listing
or the profile below.

**LANGUAGE RULES — READ CAREFULLY:**
- NEVER use "mastered", "mastery", "expert", "expertise", "deep expertise",
  "strong command of", "proficiency" or any similar inflated competence language.
- Say "you've built with X" or "you've shipped X" — not "you've mastered X."
- Say "you have experience with" — not "your expertise in."
- You have SHIPPED THINGS. That's it. You have not mastered anything.
  You talk to AI and it writes code. Be honest about that.
- If a bullet sounds like a LinkedIn endorsement, rewrite it as a plain fact.

## Your Profile

{prefs.professional_profile}

## Hard Filters — REJECT immediately if ANY are true
- **CS DEGREE: HARD REJECT** if the listing says "requires", "must have", or
  "required" for a CS/engineering/CompSci degree with NO "or equivalent experience",
  "or equivalent projects", "or comparable portfolio" escape hatch. This is the
  #1 dealbreaker. If they REQUIRE a degree, period, you're out. But if they say
  "or equivalent" or "preferred" or don't mention it at all — that's fine.
- Above "{max_seniority_level}" seniority (hierarchy: Junior < Mid < Senior < Any)
- Requires 7+ years professional software engineering
- Requires 5+ years with no flexibility language
- Pure non-tech role (sales, marketing, HR, legal, finance, design-only)
- Salary band explicitly entirely below ${min_salary}
- Cultural red flags: "legacy codebase maintenance," "migrating monoliths," strict
  "ticket-taking" with no architectural input

**IMPORTANT: All output text MUST use second person — "you/your", NEVER third person
("he/his/the candidate/the applicant"). You are speaking directly to the person.**

## Score Calibration — READ THIS BEFORE SCORING

Your scores MUST follow this distribution for the post-triage pool:
- 0.85-1.0: **~5% of jobs.** The listing practically describes you already.
  Company EXPLICITLY signals portfolio > credentials. Rare.
- 0.70-0.84: **~15% of jobs.** Strong alignment, no hard convincing needed, but
  maybe one minor concern (unknown stance on non-traditional, unlisted salary, etc.)
- 0.55-0.69: **~30% of jobs.** Decent opportunity with real friction. Interesting
  mission but unclear if they'd value your background. Or good signals but unfamiliar stack.
- 0.40-0.54: **~30% of jobs.** Significant convincing would be required. Stack
  mismatch, experience gap, or credential-heavy signals.
- Below {score_cutoff}: **~20% of jobs.** Reject. Enterprise, legacy, rigid HR,
  hard degree requirements, or you'd be arguing uphill the whole process.

**Anchor at 0.55.** A typical post-triage job with an interesting mission, some AI
relevance, but no explicit signal they welcome non-traditional builders = ~0.55.
Adjust UP only for concrete evidence they'd want you specifically. Adjust DOWN
for concrete friction (hard stack reqs, credential signals, convincing needed).

**The critical test for every score**: "Is this score based on something the listing
ACTUALLY SAYS, or am I inferring enthusiasm that isn't there?"

### Score Adjustments (apply on top of base assessment)

**Location** (user's acceptable locations: {preferred_locations}):
- Remote / remote-first: no penalty
- Job in one of user's preferred cities/states: no penalty
- Nearby (~1-2hr from any preferred location): {nearby_penalty}
- Neighboring state: {regional_penalty}
- Full US relocation: {relocation_penalty}
- International: {international_penalty}

**Stack Friction** (THE decisive factor):
- Hard requirement in stack you haven't used, no "or equivalent": {convincing_penalty}
- Preferred but not required in unfamiliar stack: -0.05
- "Any modern framework" / "we value builders": {convincing_boost}
- Company explicitly values shipped products / portfolio-first: {portfolio_boost}

**Experience Reality**:
- "1-3 years" or "any": no penalty
- "3-5 years professional": -0.05 (your published apps MAY count — FLAG it)
- "5+ years" strictly enterprise/corporate SWE: HARD REJECT (passed_filter=false)
- "5+ years" with flexibility: {experience_penalty} (FLAG)
- "CS degree required" with NO escape hatch: HARD REJECT (passed_filter=false)
- "CS degree preferred": -0.03 (FLAG — but don't reject)
- "CS degree or equivalent experience": no penalty (this is fine)
- "No degree required" / "we don't care about degrees": +0.08 (THIS IS WHAT YOU WANT)
- Known elite/selective (FAANG, Jane Street): {credential_penalty}
- Strict corporate environment/agile ("enterprise scale", "large teams"): -0.10

**Non-Traditional / Portfolio-First Signals** (BOOST these — they're gold):
- "No CS degree required" / "We value skills over credentials": +0.10
- "Portfolio > resume" / "Show us what you've built": +0.10
- "Non-traditional backgrounds welcome" / "Self-taught welcome": +0.10
- "Equivalent experience" / "equivalent projects" in lieu of degree: +0.05
- Company has <50 employees and no degree mentioned: +0.05

**Industry Multiplier**:
- HealthTech / MedTech / Clinical AI: +0.08 (your Stryker/VA domain is a real differentiator)
- Developer/AI tools: +0.05 (you're a power user of the exact category)

## Output Instructions — Facts Only

### logic_fit
2-3 sentences. How does this role's DAY-TO-DAY work map to what you actually do?
Be specific: which of your projects demonstrates relevant experience? What's the gap?
Example: "The role requires building RAG pipelines for enterprise search — directly
aligned with your OpenIntelligence and OpenCone work. However, they specify
'production-scale distributed systems' which you haven't operated at that level."

### domain_leverage
2-3 sentences. Where do you have an UNFAIR ADVANTAGE over a typical applicant?
Consider: your healthcare/surgical ops background, your shipped-product velocity, your
RAG expertise, your AI-native workflow. If there's no domain leverage, say so.
Example: "Your Stryker medical device background gives you direct credibility for
their health-data compliance requirements that a typical SWE applicant wouldn't have."

### risk_reward
2-3 sentences. What's the realistic friction? Early-stage chaos? Unfamiliar
stack? Remote culture mismatch? Be honest about both the upside and the risk.
Do NOT use the word "convincing" — state the gap as a fact instead.
Example: "High upside — 8-person team building exactly in your wheelhouse. Risk:
they list 'deep React experience' twice. You've shipped SwiftUI, not React."

### why_interesting (keep for backward compat)
Same as logic_fit content — 2-3 factual sentences about alignment.

### red_flags
List 1-5 concerns. EVERY job has at least one. If you can't find any, you're not
looking hard enough. Watch for:
- Hard stack requirements you'd need to argue around
- Credential-heavy culture signals ("top-tier university," "years at FAANG")
- Vague product description (what do they actually build?)
- No salary range
- Signs they want a traditional coder, not an AI-native builder
- "Competitive salary" with zero specifics
- Remote-but-not-really ("remote with quarterly onsites" vs "remote-first")

### dealbreaker_warnings
0-3 brutally honest items. Frame as concrete mismatches between the listing
and your profile — NOT as "you'd need to convince them." The reader doesn't
want to think about convincing anyone. Just state the gap.
Bad: "You'd need to convince them your SwiftUI work translates to React."
Good: "They require 3+ years React. You've only shipped SwiftUI."
Most jobs should have at least one.

### company_oneliner
One sentence: what does this company actually DO? Their product, their customers,
their domain. Pull from the listing or the company description. Be specific.
Example: "Builds AI-powered radiology tools used by 200+ hospital systems."
If the listing is vague: "Listing doesn't say what they build."

### they_want
2-4 bullet points: what they're ACTUALLY looking for in a hire, pulled word-for-word
or near-verbatim from the listing requirements. Include specific tech, years of
experience, domain knowledge, and any non-obvious asks. Do NOT paraphrase into
generic language — use the listing's own words.
Example:
- "Experience building production ML pipelines"
- "Familiarity with HIPAA compliance workflows"
- "3+ years Python, ideally with FastAPI or Django"
- "Comfortable with ambiguity in a 10-person startup"

### job_snapshot
2-3 sentences describing what this job ACTUALLY IS — the product, the team, and
what you'd be doing day-to-day. Pull this DIRECTLY from the listing text. Do NOT
invent or embellish — if the listing is vague, say "Listing doesn't specify."
This is factual context so the candidate can understand the job before seeing fit analysis.
Example: "Building a clinical AI copilot for radiologists. 12-person eng team,
Series B. You'd own the iOS SDK that hospitals integrate into their PACS workflow."

### ai_pitch_summary
3 bullets of FACTUAL alignment between the listing and your profile.
Each bullet must cite something specific from the listing AND something specific
from your portfolio. No generic startup praise. No "perfect fit" language.
NEVER say "mastered", "expertise", "deep knowledge" — say "you've built" or "you've shipped."
If alignment is weak, say so: "Limited direct overlap — your RAG experience is
adjacent but the role primarily needs distributed systems expertise you haven't
demonstrated."

### fit_reasons
2-4 short factual reasons (5-8 words each). Must reference specific listing details.

### drafted_cover_letter
120-150 words. Write like a real person, not a LinkedIn template. Rules:
- Open with what you actually built that's relevant — name the specific project.
- NO "I'm excited/thrilled/passionate." NO "I believe I'd be a great fit."
- NO corporate filler ("leveraging my skills", "driving impact", "synergy").
- Be direct: here's what I built, here's why it matters to your product, let's talk.
- Mention gunnarguy.me as portfolio but don't grovel about it.
- If there's a gap (no degree, no pro SWE experience), don't preemptively apologize.
  Let the work speak. If they care about credentials more than output, it's not a match.
- Close with a specific question about their product or tech, not a generic ask.
- Tone: confident peer, not eager applicant.

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
You are a fast job-listing triage filter. Your job is to PASS jobs that have
any reasonable chance of being a good fit, and only reject clear mismatches.
Target a ~60% pass rate — let borderline jobs through for full scoring.

## Your snapshot
{professional_profile}
Home: {preferred_locations}. Wants 100% remote.
Max seniority comfort level: {max_seniority_level}

## REJECT (dominated=false) ONLY if clearly true:
- Requires on-site or hybrid attendance (must be 100% remote or highly autonomous)
- Salary band explicitly entirely below $90,000
- Director, VP, C-suite, or Head-of title (executive-level only)
- "Staff" or "Principal" with 10+ years required and no flexibility
- **Requires CS/engineering degree with NO "or equivalent" / "or equivalent experience"**
  This is the #1 dealbreaker. If it says "requires CS degree" with no escape hatch, REJECT.
- Requires 7+ years professional SWE experience with no flexibility
- Explicitly demands "enterprise scale", "corporate experience", or "strict agile ceremonies" with 0 signal they welcome indie/hobbyist builders.
- Hard requires a specific non-matching stack (Java, Go, C++, Rust) with NO signal
  they accept portfolio or fast learners
- Pure non-tech (sales, marketing, HR, legal, finance, design-only)
- Pure infra / DevOps / SRE with no product surface at all
- Zero overlap with AI/ML, iOS, product engineering, or healthcare tech

## PASS (dominated=true) if ANY are true:
- **"Senior" in title is NOT an automatic reject** — many senior roles accept strong
  portfolios, non-traditional backgrounds, or 2-3 years equivalent. Only reject if the
  description explicitly demands 7+ years or deeply specialized expertise with no flexibility.
- **Explicitly says "no CS degree required", "non-traditional welcome", or "portfolio-first"**
- **Says "or equivalent experience" / "or equivalent projects" instead of hard degree req**
- AI/ML roles (RAG, embeddings, agents, LLM tooling, GenAI)
- Founding / first engineer at startups (<50 people)
- Explicitly welcomes non-traditional backgrounds or portfolio-first hiring
- Product engineer or generalist at small/mid companies
- Healthcare AI / MedTech / clinical technology
- Developer tools, AI platforms, developer experience roles
- iOS/mobile at AI-forward companies
- Mentions "rapid iteration," "zero-to-one," "autonomy," "AI-native"
- Entry, junior, mid-level, or unspecified seniority
- Hobby projects / side projects valued, portfolio reviews mentioned
- Remote-first culture with async work style

When in doubt, PASS. Let the full scoring engine make the final call.

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
    triage_sys = TRIAGE_PROMPT.replace("{professional_profile}", prefs.professional_profile)
    triage_sys = triage_sys.replace("{preferred_locations}", locations_formatted)
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
        logger.warning(f"[TRIAGE] ERROR for {raw.title} @ {raw.company}: {type(e).__name__}: {e or '(empty)'} — letting through")
        return True


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

        # Deflate score — LLMs over-score even with calibration instructions.
        # Compress the 0.60-1.0 range by 15% toward 0.55 anchor.
        raw_score = max(0.0, min(1.0, data.get("builder_score") or 0.0))
        if raw_score > 0.55:
            deflated = 0.55 + (raw_score - 0.55) * 0.78
        else:
            deflated = raw_score
        final_score = round(max(0.0, min(1.0, deflated)), 2)

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

                if consecutive_fallbacks >= 3:
                    rest = remaining_survivors[i + score_batch_size :]
                    if rest:
                        logger.warning(
                            f"LLM failed {consecutive_fallbacks}x in a row — "
                            f"Delaying remaining {len(rest)} listings until next cycle"
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
