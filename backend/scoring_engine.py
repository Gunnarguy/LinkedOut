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
from datetime import datetime, timezone

from openai import AsyncOpenAI

from config import settings
from models import JobPayload, RawJobListing, ScoringResult, UserPreferences

logger = logging.getLogger(__name__)

_openai_client: AsyncOpenAI | None = None
_gemini_client = None


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


async def _call_gemini(system: str, user_msg: str, use_flash: bool = False) -> str:
    """Call Google Gemini (Pro or Flash). Raises on failure."""
    client = _get_gemini_client()
    model = settings.gemini_flash_model if use_flash else settings.gemini_model
    combined = f"{system}\n\n---\n\n{user_msg}"
    resp = await asyncio.wait_for(
        client.aio.models.generate_content(
            model=model,
            contents=combined,
            config={
                "temperature": 0.3,
                "response_mime_type": "application/json",
            },
        ),
        timeout=30,
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


async def _call_llm(system: str, user_msg: str, use_flash: bool = False) -> str:
    """Route LLM call with automatic fallback chain.

    Chain: Gemini Pro/Flash → Flash (if Pro rate-limited) → OpenAI GPT-5.4
    """
    provider = settings.llm_provider.lower()
    max_retries = 2

    for attempt in range(max_retries):
        try:
            if provider == "openai":
                return await _call_openai(system, user_msg)
            elif provider == "gemini":
                return await _call_gemini(system, user_msg, use_flash=use_flash)
            else:
                raise ValueError(f"Unknown LLM provider: {provider}")

        except Exception as e:
            error_str = str(e)
            is_rate_limit = "429" in error_str or "RESOURCE_EXHAUSTED" in error_str

            if is_rate_limit and attempt < max_retries - 1:
                wait_time = 3 * (attempt + 1)
                logger.warning(
                    f"Rate limited (attempt {attempt + 1}/{max_retries}), "
                    f"waiting {wait_time}s..."
                )
                await asyncio.sleep(wait_time)
                continue

            if is_rate_limit:
                # Exhausted retries — walk the fallback chain
                if provider == "gemini" and not use_flash:
                    logger.warning("Gemini Pro exhausted → trying Flash...")
                    try:
                        return await _call_gemini(system, user_msg, use_flash=True)
                    except Exception as flash_err:
                        logger.warning(f"Flash also failed: {flash_err}")

                # Final fallback: OpenAI GPT-5.4
                if provider != "openai" and settings.openai_api_key:
                    logger.warning("Gemini exhausted → falling back to OpenAI GPT-5.4")
                    try:
                        return await _call_openai(system, user_msg)
                    except Exception as oai_err:
                        logger.error(f"OpenAI fallback also failed: {oai_err}")
                        raise oai_err from e

            raise

    raise RuntimeError("LLM call failed after max retries")


SYSTEM_PROMPT = """\
You are the AI Bouncer for LinkedOut — an elite career-screening and intelligence engine.

Your job: evaluate a raw job listing, extract EVERYTHING knowable about the company
and role, and decide if it's worth the user's time. Be thorough. The user will use
your output as their primary research document for this opportunity.

## User Profile
The user is a HOBBYIST AI product builder, NOT a traditional software engineer.
- Builds iOS apps for fun (SwiftUI, on-device ML) — self-taught, ships real products
- Deep interest in agentic AI, LLM tooling, and AI-augmented workflows
- Believes agentic AI is making traditional SWE gatekeeping obsolete
- Looking for roles where building/shipping/taste matter more than CS pedigree
- Product-minded: thinks about UX, user problems, and 0→1 creation
- Comfortable with ambiguity, prototyping, and wearing many hats

## Hard Filters (REJECT if ANY of these are true — these are the ONLY hard stops)
- REJECT if the listing STRICTLY requires a CS/engineering degree with NO "or equivalent
  experience" escape hatch (if degree is "preferred" or "or equivalent", it PASSES)
- REJECT roles titled "Senior", "Staff", "Lead", "Principal", "Head of", or "Director"
- REJECT if it explicitly requires 7+ years of professional software engineering experience

Everything else is a SCORING factor, not a reject. Be generous — let things through.

## Scoring (builder_score: 0.0–1.0)
Score HIGHER (0.75–1.0) for:
- "AI Product Engineer", "AI Engineer", "Founding Engineer", "Product Engineer"
- Early-stage startups building with LLMs, agents, copilots
- Small teams, high autonomy, 0→1 product building, "wear many hats"
- Companies that explicitly value shipped products, side projects, builder mentality
- Junior/mid-level roles, or roles with NO seniority level (just "Engineer")
- Roles where AI/ML is the PRODUCT, not just a buzzword
- Intersection of AI + consumer products, creative tools, or developer tools
- Remote-friendly roles

Score MEDIUM (0.4–0.74) for:
- iOS/Mobile engineer roles at interesting companies
- Generalist roles at startups where you'd touch product
- Roles that mention "product-minded engineer" or "full-stack"
- Internships or apprenticeships at cool companies
- Roles at mid-size companies that look interesting
- Hybrid roles (if the company/product is compelling enough)
- Roles that are slightly outside comfort zone but have growth potential

Score LOWER (0.1–0.39) for:
- Pure backend/infrastructure with zero product surface
- Enterprise middleware, ERP, or B2B sales tools
- Large bureaucratic orgs with rigid processes
- Roles that are 100% maintenance/legacy
- Roles that require heavy interview gauntlets (LeetCode-only)

Score ZERO / REJECT for:
- Senior/Staff/Lead/Principal/Director titles
- Strict CS degree requirements with no flexibility
- 7+ years experience required

## EXTRACTION INSTRUCTIONS — Be Thorough!

### company_description
Write 2-3 sentences about what this company ACTUALLY builds/does. Their mission,
product, target market. If the listing mentions funding, team size, or notable
customers — include it. Don't guess; if you don't know, say "Not specified in listing."

### company_size
Extract the company size. Look for phrases like "small team", "50+ engineers",
"Series A startup", team headcount mentions. Output one of: "1-10", "10-50",
"50-200", "200-500", "500+", or "Unknown".

### company_stage
Infer the company stage: "Pre-seed", "Seed", "Series A", "Series B", "Series C+",
"Public", "Bootstrapped", or "Unknown". Use clues like funding mentions, team size,
product maturity.

### company_url
If the company website URL is mentioned or inferable, include it. Otherwise empty string.

### requirements
List the KEY requirements (hard skills, experience thresholds). Each item should be
one concise line. Include years of experience, specific technologies, degree requirements.
Maximum 8 items. Only include things explicitly stated.

### nice_to_haves
List the "nice to have" or "bonus" qualifications. Maximum 5 items.

### tech_stack
Extract ALL technologies, frameworks, languages, tools, platforms mentioned.
Include infrastructure (AWS, GCP), languages (Python, Swift), frameworks (React, FastAPI),
tools (Docker, K8s), ML/AI tools (PyTorch, LangChain, etc).

### why_interesting
Write 2-3 sentences explaining why THIS specific opportunity is interesting for the user,
given their builder background. Be specific: reference what the company builds,
why their culture might suit a self-taught builder, what excites about the problem space.
This should feel like a trusted friend giving career advice.

### red_flags
List potential concerns/red flags. Examples: "posting mentions on-call rotation",
"vague about salary", "mentions 'fast-paced environment' (potential burnout)",
"requires degree with no flexibility", "posting has been up for 6+ months".
Maximum 5 items. If none, use empty list.

### experience_level
One of: "Entry", "Junior", "Mid", "Senior", "Staff", "Lead", "Any", or "Not specified".

### job_type
One of: "Full-time", "Part-time", "Contract", "Freelance", "Internship", or "Not specified".

### benefits
Extract ALL mentioned benefits/perks: equity, health insurance, PTO policy, remote stipend,
learning budget, gym membership, etc. Maximum 10 items.

### apply_url
If there's a direct application link (different from the source URL), include it.
Often job postings link to an ATS or careers page.

### salary_floor / salary_max
Extract salary range if mentioned. salary_floor = lower bound, salary_max = upper bound.
If only one number, use it for both. If not mentioned, salary_floor = 0, salary_max = 0.

### ai_pitch_summary
Write exactly 3 bullet points bridging the user's background (hobbyist iOS builder,
AI product tinkerer, self-taught shipper) to THIS specific role. Be specific about
what THIS company does and why the user's builder DNA fits. No generic platitudes.

### drafted_cover_letter
Write a punchy 150-word cover letter from the user's perspective. Tone: confident,
curious, zero-fluff, slightly irreverent. The user is not begging for a job — they're
exploring where their energy fits best. Reference specific things from the job listing.
Acknowledge they're non-traditional but frame it as a superpower.

## Output Format
Return ONLY valid JSON matching this schema:
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
  "red_flags": ["string"],
  "apply_url": "string",
  "experience_level": "string",
  "job_type": "string",
  "benefits": ["string"]
}}
"""


TRIAGE_PROMPT = """\
You are a fast job-listing triage filter. Given a job listing, decide if it MIGHT be
relevant for a self-taught builder who loves AI, product engineering, and shipping apps.

PASS (dominated=true) if the job is ANY of:
- Tech/engineering roles at startups or small-to-mid companies
- AI/ML roles at any company
- Product engineer, mobile/iOS, full-stack, or generalist roles
- Roles that don't require a CS degree (or say "or equivalent experience")
- Entry, junior, or mid-level roles (or roles with no seniority specified)
- Anything that sounds interesting for a builder/product person

REJECT (dominated=false) ONLY if the job clearly is:
- Titled "Senior", "Staff", "Lead", "Principal", "Director", or "VP"
- Explicitly requires a CS/engineering degree with NO alternative
- Requires 5+ years of professional experience with no flexibility
- Pure non-tech roles (sales, marketing, HR, legal, finance)

When in doubt, PASS it through. Be GENEROUS — let the full scoring decide.

Return ONLY valid JSON:
{{"dominated": true/false, "reason": "one sentence why"}}
"""


async def triage_job(raw: RawJobListing) -> bool:
    """Fast triage with Flash model. Returns True if worth full scoring."""
    user_msg = f"Title: {raw.title}\nCompany: {raw.company}\nLocation: {raw.location}\nRemote: {raw.is_remote}\n\nDescription (first 1500 chars):\n{raw.description[:1500]}"

    try:
        content = await _call_llm(TRIAGE_PROMPT, user_msg, use_flash=True)
        data = json.loads(content)
        passed = data.get("dominated", False)
        reason = data.get("reason", "")
        logger.info(f"[TRIAGE] {'PASS' if passed else 'FAIL'} | {raw.title} @ {raw.company} | {reason}")
        return passed
    except Exception as e:
        logger.warning(f"[TRIAGE] ERROR for {raw.title} @ {raw.company}: {e} — letting through")
        return True


async def score_job(
    raw: RawJobListing,
    prefs: UserPreferences | None = None,
) -> ScoringResult:
    """Run a raw job listing through the LLM bouncer. Returns ScoringResult."""
    if prefs is None:
        prefs = UserPreferences()

    system = SYSTEM_PROMPT.replace("{min_salary}", str(prefs.min_salary))

    user_msg = f"""Evaluate this job listing and extract EVERYTHING useful:

**Title:** {raw.title}
**Company:** {raw.company}
**Location:** {raw.location}
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
        data = json.loads(content)

        if not data.get("passed_filter", False):
            reason = data.get("rejection_reason", "Did not pass filters")
            logger.info(f"[SCORE] REJECTED by LLM | {raw.title} @ {raw.company} | {reason}")
            return ScoringResult(
                passed_filter=False,
                rejection_reason=reason,
            )

        job = JobPayload(
            company_name=data.get("company_name", raw.company),
            role_title=data.get("role_title", raw.title),
            salary_floor=data.get("salary_floor") or 0,
            is_remote=data.get("is_remote") or False,
            builder_score=max(0.0, min(1.0, data.get("builder_score") or 0.0)),
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
        )

        return ScoringResult(passed_filter=True, job=job)

    except Exception as e:
        logger.warning(f"[SCORE] LLM ERROR for {raw.title} @ {raw.company}: {e} — falling back to local")
        return score_job_locally(raw)


# ── Local keyword-based scorer (no LLM needed) ──────────────────────────────

# Seniority terms that are hard rejects
_SENIOR_RE = re.compile(
    r"\bsenior\b|\bstaff\b|\blead\b|\bprincipal\b|\bdirector\b|\bVP\b|\bhead of\b",
    re.IGNORECASE,
)

# Strict degree requirements (hard reject)
_STRICT_DEGREE_RE = re.compile(
    r"(require[ds]?|must have).{0,30}(CS|computer science|engineering) (degree|bachelor)",
    re.IGNORECASE,
)

# High-value keywords (boost score)
_POSITIVE_KEYWORDS = [
    (r"\bAI\b|artificial intelligence", 0.15),
    (r"\bLLM\b|large language model|generative AI", 0.15),
    (r"machine learning|\bML\b", 0.12),
    (r"product engineer", 0.12),
    (r"founding engineer", 0.15),
    (r"\biOS\b|SwiftUI|mobile engineer", 0.10),
    (r"\bstartup\b|early.stage|seed|series A", 0.10),
    (r"full.stack", 0.08),
    (r"\bremote\b", 0.08),
    (r"python|typescript|react", 0.05),
    (r"agent(?:ic)?|copilot|chatbot", 0.10),
    (r"\bjunior\b|\bintern\b|\bentry.level\b", 0.08),
    (r"product.minded|ship|builder", 0.10),
]
_POSITIVE_COMPILED = [(re.compile(p, re.IGNORECASE), s) for p, s in _POSITIVE_KEYWORDS]

# Negative keywords (reduce score)
_NEGATIVE_KEYWORDS = [
    (r"10\+ years|15\+ years|8\+ years", -0.20),
    (r"PhD required", -0.15),
    (r"\bFortune 500\b|\bFAANG\b", -0.05),
    (r"enterprise|legacy|CRUD|mainframe", -0.05),
    (r"\bDevOps\b|\bSRE\b|infrastructure only", -0.03),
]
_NEGATIVE_COMPILED = [(re.compile(p, re.IGNORECASE), s) for p, s in _NEGATIVE_KEYWORDS]


def score_job_locally(raw: RawJobListing) -> ScoringResult:
    """Fast keyword-based scoring — no LLM, works offline. Used as fallback."""
    title = raw.title
    text = f"{raw.title} {raw.company} {raw.description}"

    # Hard reject: Senior titles
    if _SENIOR_RE.search(title):
        logger.info(f"[LOCAL] REJECTED (senior title) | {title} @ {raw.company}")
        return ScoringResult(
            passed_filter=False,
            rejection_reason=f"Title contains seniority keyword: {title}",
        )

    # Hard reject: Strict CS degree requirement
    if _STRICT_DEGREE_RE.search(raw.description):
        logger.info(f"[LOCAL] REJECTED (CS degree) | {title} @ {raw.company}")
        return ScoringResult(
            passed_filter=False,
            rejection_reason="Strict CS degree requirement detected",
        )

    # Score based on keyword matches
    score = 0.35  # Base score — be generous

    for pattern, boost in _POSITIVE_COMPILED:
        if pattern.search(text):
            score += boost

    for pattern, penalty in _NEGATIVE_COMPILED:
        if pattern.search(text):
            score += penalty  # penalty is negative

    score = max(0.05, min(1.0, score))
    logger.info(f"[LOCAL] PASS score={score:.2f} | {title} @ {raw.company}")

    # Extract basic info
    tech_stack = []
    tech_patterns = [
        "Python",
        "TypeScript",
        "JavaScript",
        "React",
        "Swift",
        "SwiftUI",
        "Kotlin",
        "Go",
        "Rust",
        "Java",
        "Ruby",
        "Rails",
        "Django",
        "FastAPI",
        "Node.js",
        "Next.js",
        "Vue",
        "Angular",
        "Docker",
        "Kubernetes",
        "AWS",
        "GCP",
        "Azure",
        "PostgreSQL",
        "MongoDB",
        "Redis",
        "PyTorch",
        "TensorFlow",
        "LangChain",
        "OpenAI",
    ]
    for tech in tech_patterns:
        if re.search(r"\b" + re.escape(tech) + r"\b", text, re.IGNORECASE):
            tech_stack.append(tech)

    is_remote = raw.is_remote or bool(re.search(r"\bremote\b", text, re.IGNORECASE))

    # Parse salary from text
    salary_floor = 0
    salary_max = 0
    salary_match = re.search(r"\$(\d{2,3})[,.]?(\d{3})", raw.salary_text or text)
    if salary_match:
        salary_floor = int(salary_match.group(1) + salary_match.group(2))

    job = JobPayload(
        company_name=raw.company,
        role_title=raw.title,
        salary_floor=salary_floor,
        salary_max=salary_max,
        is_remote=is_remote,
        builder_score=round(score, 2),
        ai_pitch_summary="Scored by local keyword matcher (LLM unavailable)",
        drafted_cover_letter="",
        source_url=raw.url,
        posted_at=datetime.now(timezone.utc),
        location=raw.location or ("Remote" if is_remote else "Unknown"),
        tags=tech_stack[:5],
        description=raw.description[:12000],
        company_description="",
        company_size="Unknown",
        company_stage="Unknown",
        company_url="",
        requirements=[],
        nice_to_haves=[],
        tech_stack=tech_stack,
        why_interesting="",
        red_flags=[],
        apply_url="",
        experience_level="Not specified",
        job_type="Not specified",
        benefits=[],
    )

    return ScoringResult(passed_filter=True, job=job)


async def score_batch(
    listings: list[RawJobListing],
    prefs: UserPreferences | None = None,
) -> list[ScoringResult]:
    """Score a batch of raw listings. Falls back to local scoring on LLM failure."""
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
    """Two-tier scoring with local fallback.

    Tries: Flash triage → Pro scoring → Local keyword scorer (if LLM fails).
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
                *(triage_job(raw) for raw in batch),
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

    # Check if the test itself used local fallback (it would have ai_pitch_summary starting with "Scored by local")
    if (
        test_result.job
        and "local keyword" in (test_result.job.ai_pitch_summary or "").lower()
    ):
        llm_works = False

    results = [test_result]

    if llm_works:
        logger.info("LLM scoring working — using LLM for remaining listings")
        consecutive_fallbacks = 0
        for raw in survivors[1:]:
            result = await score_job(raw, prefs)
            # Detect if this job fell back to local scorer
            is_local = (
                result.job
                and "local keyword" in (result.job.ai_pitch_summary or "").lower()
            )
            if is_local:
                consecutive_fallbacks += 1
            else:
                consecutive_fallbacks = 0

            results.append(result)

            # If LLM failed 2+ times in a row, give up and use local for the rest
            if consecutive_fallbacks >= 2:
                remaining = survivors[len(results):]
                if remaining:
                    logger.warning(
                        f"LLM failed {consecutive_fallbacks}x in a row — "
                        f"switching to local scorer for remaining {len(remaining)} listings"
                    )
                    for r in remaining:
                        results.append(score_job_locally(r))
                break

            await asyncio.sleep(0.5)
    else:
        logger.warning("LLM scoring failed — using local keyword scorer for all")
        for raw in survivors[1:]:
            results.append(score_job_locally(raw))

    passed = sum(1 for r in results if r.passed_filter)
    logger.info(f"Phase 2 complete: {passed}/{len(survivors)} passed scoring")

    return results
