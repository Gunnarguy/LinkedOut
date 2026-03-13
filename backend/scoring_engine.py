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
from location_mapper import classify_location, TIER_LABELS
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


async def _call_gemini(
    system: str, user_msg: str, use_flash: bool = False, timeout: int = 60
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
    system: str, user_msg: str, use_flash: bool = False, timeout: int = 60
) -> str:
    """Route LLM call with automatic fallback chain.

    Chain: Gemini Pro/Flash → Flash (if Pro rate-limited) → OpenAI GPT-5.4
    Retries on transient errors (rate limits, timeouts, server disconnects).
    """
    provider = settings.llm_provider.lower()
    max_retries = 3

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
            is_transient = (
                is_rate_limit
                or isinstance(e, asyncio.TimeoutError)
                or "disconnected" in error_str.lower()
                or "server" in error_str.lower()
                or "connection" in error_str.lower()
                or error_str == ""  # empty error = timeout
            )

            if is_transient and attempt < max_retries - 1:
                wait_time = 3 * (attempt + 1)
                logger.warning(
                    f"[LLM] {error_type} (attempt {attempt + 1}/{max_retries}): "
                    f"{error_str or '(empty)'} — retrying in {wait_time}s..."
                )
                await asyncio.sleep(wait_time)
                continue

            if is_rate_limit:
                # Exhausted retries — walk the fallback chain
                if provider == "gemini" and not use_flash:
                    logger.warning("Gemini Pro exhausted → trying Flash...")
                    try:
                        return await _call_gemini(
                            system, user_msg, use_flash=True, timeout=timeout
                        )
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

            logger.error(
                f"[LLM] Final failure ({error_type}): {error_str or '(empty)'}"
            )
            raise

    raise RuntimeError("LLM call failed after max retries")


SYSTEM_PROMPT = """\
You are a cold, analytical executive recruiter. No cheerleading. No hype.
Your job: evaluate a job listing against a specific candidate profile and produce
a factual intelligence brief. The candidate will use this as his primary research
document. Every claim must trace to something concrete in the listing or the profile.

## Candidate Profile — Gunnar Hostetler

### Classification: High-Agency Product Engineer
He does NOT write code by hand. He architectures systems and orchestrates AI agents
(Claude, GPT, Gemini) to generate all implementation. The skill is the orchestration:
seeing whole systems, decomposing them into buildable units, and shipping at extreme
velocity via LLMs. He is stack-agnostic — iOS is his current medium because it was
accessible, but the method transfers to any platform.

### Shipped Portfolio (all live — gunnarguy.me)
- **OpenIntelligence**: On-device RAG engine, hybrid search (semantic + keyword),
  Core ML embeddings, Apple Intelligence integration, fully offline. 202 commits.
- **OpenResponses**: OpenAI Responses API client with MCP integration (Notion,
  Dropbox, Gmail). Tool orchestration, multi-model conversations. 88 commits.
- **OpenCone**: Pinecone vector DB RAG app with hybrid search + reranking. 122 commits.
- **OpenAssistant**: Assistants API client with full thread management. 214 commits.
- **LinkedOut**: Full-stack job screening platform (SwiftUI + FastAPI + Docker + LLM scoring).
- 382 commits in the last year across these projects.

### Technical Reality
- **Strong in**: Swift/iOS, Python/FastAPI, RAG pipelines, vector databases, API
  integrations, LLM orchestration, on-device ML, system architecture
- **Has NOT used professionally**: React, Vue, Angular, Flutter, Java, Go, Rust,
  C++, Ruby on Rails, .NET, Kubernetes at scale
- **No CS degree. No professional software engineering experience.**
- His App Store apps are real but would need to be argued as "equivalent experience"
  at any company that lists years-of-experience requirements.

### Day Job
Medical device specialist at VA Palo Alto (Stryker contractor). Supports Stanford
Cardiothoracic & Vascular Surgery. Deep HIPAA, surgical workflow, regulated-environment expertise.

### What He Wants
Companies where his portfolio ALREADY excites them. Not companies where he'd need to
argue why his background qualifies. The test: if the hiring manager saw gunnarguy.me
with 5 shipped products, would they say "get this person an interview" or "but where's
the CS degree?" He wants the former ONLY.

## Hard Filters — REJECT immediately if ANY are true
- Strictly requires CS/engineering degree with NO "or equivalent" escape hatch
- Above "{max_seniority_level}" seniority (hierarchy: Junior < Mid < Senior < Any)
- Requires 7+ years professional software engineering
- Requires 5+ years with no flexibility language
- Pure non-tech role (sales, marketing, HR, legal, finance, design-only)
- Salary band explicitly entirely below ${min_salary}
- Cultural red flags: "legacy codebase maintenance," "migrating monoliths," strict
  "ticket-taking" with no architectural input

## Score Calibration — READ THIS BEFORE SCORING

Your scores MUST follow this distribution for the post-triage pool:
- 0.85-1.0: **~5% of jobs.** The listing practically describes Gunnar already.
  Company EXPLICITLY signals portfolio > credentials. Rare.
- 0.70-0.84: **~15% of jobs.** Strong alignment, no hard convincing needed, but
  maybe one minor concern (unknown stance on non-traditional, unlisted salary, etc.)
- 0.55-0.69: **~30% of jobs.** Decent opportunity with real friction. Interesting
  mission but unclear if they'd value his background. Or good signals but unfamiliar stack.
- 0.40-0.54: **~30% of jobs.** Significant convincing would be required. Stack
  mismatch, experience gap, or credential-heavy signals.
- Below {score_cutoff}: **~20% of jobs.** Reject. Enterprise, legacy, rigid HR,
  hard degree requirements, or he'd be arguing uphill the whole process.

**Anchor at 0.55.** A typical post-triage job with an interesting mission, some AI
relevance, but no explicit signal they welcome non-traditional builders = ~0.55.
Adjust UP only for concrete evidence they'd want Gunnar specifically. Adjust DOWN
for concrete friction (hard stack reqs, credential signals, convincing needed).

**The critical test for every score**: "Is this score based on something the listing
ACTUALLY SAYS, or am I inferring enthusiasm that isn't there?"

### Score Adjustments (apply on top of base assessment)

**Location** (user lives in {home_city}, {home_state}):
- Remote / remote-first: no penalty
- Same city/metro: no penalty
- Nearby (~1-2hr): {nearby_penalty}
- Neighboring state: {regional_penalty}
- Full US relocation: {relocation_penalty}
- International: {international_penalty}

**Stack Friction** (THE decisive factor):
- Hard requirement in stack he hasn't used, no "or equivalent": {convincing_penalty}
- Preferred but not required in unfamiliar stack: -0.05
- "Any modern framework" / "we value builders": {convincing_boost}
- Company explicitly values shipped products / portfolio-first: {portfolio_boost}

**Experience Reality**:
- "1-3 years" or "any": no penalty
- "3-5 years professional": -0.05 (his apps MAY count — FLAG it)
- "5+ years" with flexibility: {experience_penalty} (FLAG)
- "CS degree preferred": -0.03 (FLAG)
- "CS degree or equivalent": -0.05 (FLAG)
- Known elite/selective (FAANG, Jane Street): {credential_penalty}

**Industry Multiplier**:
- HealthTech / MedTech / Clinical AI: +0.08 (his Stryker/VA domain is a real differentiator)
- Developer/AI tools: +0.05 (he's a power user of the exact category)

## Output Instructions — Facts Only

### logic_fit
2-3 sentences. How does this role's DAY-TO-DAY work map to what Gunnar actually does?
Be specific: which of his projects demonstrates relevant experience? What's the gap?
Example: "The role requires building RAG pipelines for enterprise search — directly
aligned with OpenIntelligence and OpenCone. However, they specify 'production-scale
distributed systems' which he hasn't operated at that level."

### domain_leverage
2-3 sentences. Where does Gunnar have an UNFAIR ADVANTAGE over a typical applicant?
Consider: his healthcare/surgical ops background, his shipped-product velocity, his
RAG expertise, his AI-native workflow. If there's no domain leverage, say so.
Example: "His Stryker medical device background gives him direct credibility for
their health-data compliance requirements that a typical SWE applicant wouldn't have."

### risk_reward
2-3 sentences. What's the realistic friction? Early-stage chaos? Unknown if they'd
accept AI-generated code? Unfamiliar stack? Remote culture mismatch? Be honest about
both the upside and the specific risk.
Example: "High upside — 8-person team building exactly in his wheelhouse. Risk: they
mention 'deep React experience' twice, which means his first conversation will be
explaining why SwiftUI translates. That's the convincing he doesn't want to do."

### why_interesting (keep for backward compat)
Same as logic_fit content — 2-3 factual sentences about alignment.

### red_flags
List 1-5 concerns. EVERY job has at least one. If you can't find any, you're not
looking hard enough. Watch for:
- Hard stack requirements he'd need to argue around
- Credential-heavy culture signals ("top-tier university," "years at FAANG")
- Vague product description (what do they actually build?)
- No salary range
- Signs they want a traditional coder, not an AI-native builder
- "Competitive salary" with zero specifics
- Remote-but-not-really ("remote with quarterly onsites" vs "remote-first")

### dealbreaker_warnings
0-3 brutally honest items. The question: "Would Gunnar need to CONVINCE them?"
If yes, that's a dealbreaker. Most jobs should have at least one.

### ai_pitch_summary
3 bullets of FACTUAL alignment between the listing and Gunnar's profile.
Each bullet must cite something specific from the listing AND something specific
from his portfolio. No generic startup praise. No "perfect fit" language.
If alignment is weak, say so: "Limited direct overlap — his RAG experience is
adjacent but the role primarily needs distributed systems expertise he hasn't
demonstrated."

### fit_reasons
2-4 short factual reasons (5-8 words each). Must reference specific listing details.

### drafted_cover_letter
150 words, confident but honest. Lead with shipped products and gunnarguy.me.
Be upfront about AI-orchestrated development. Connect to the specific company's
product. Close with curiosity.

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
You are a fast job-listing triage filter. Be AGGRESSIVE about rejecting.
The goal is a ~40% pass rate — most jobs should NOT make it through.

## Candidate snapshot
Gunnar: High-agency product engineer. Orchestrates AI to generate all code.
Shipped 5 products (4 on App Store). Swift/iOS, Python, RAG, vector DBs.
NO CS degree, no professional SWE experience. Healthcare ops day job (Stryker/VA).
Home: {home_city}, {home_state}. Wants 100% remote.

## REJECT (dominated=false) if ANY are true:
- Requires on-site or hybrid attendance (must be 100% remote or highly autonomous)
- Salary band explicitly entirely below $90,000
- Senior, Staff, Lead, Principal, Director, VP title (unless max seniority allows)
- Strictly requires CS/engineering degree with NO "or equivalent"
- Requires 5+ years professional SWE experience with no flexibility
- Hard requires a specific stack (React, Java, Go, C++, etc.) with NO signal they
  accept portfolio or fast learners — he'd have to CONVINCE them
- Pure non-tech (sales, marketing, HR, legal, finance, design-only)
- Pure infra / DevOps / SRE with no product surface
- Legacy codebase maintenance, monolith migration, ticket-taking roles
- Large enterprise / bureaucratic companies with rigid keyword-filter hiring
- Zero overlap with AI/ML, iOS, product engineering, or healthcare tech

## PASS (dominated=true) if:
- AI/ML roles (RAG, embeddings, agents, LLM tooling, GenAI)
- Founding / first engineer at startups (<50 people)
- Explicitly welcomes non-traditional backgrounds or portfolio-first hiring
- Product engineer or generalist at small companies
- Healthcare AI / MedTech / clinical technology
- Developer tools, AI platforms, developer experience roles
- iOS/mobile at AI-forward companies
- Mentions "rapid iteration," "zero-to-one," "autonomy," "AI-native"
- Entry, junior, or mid-level (or unspecified seniority)

When in doubt, REJECT. Better to miss a borderline job than waste his time.

Return ONLY valid JSON:
{{"dominated": true/false, "reason": "one sentence why"}}
"""


async def triage_job(raw: RawJobListing, prefs: UserPreferences | None = None) -> bool:
    """Fast triage with Flash model. Returns True if worth full scoring."""
    if prefs is None:
        prefs = UserPreferences()
    triage_sys = TRIAGE_PROMPT.replace("{home_city}", prefs.home_city)
    triage_sys = triage_sys.replace("{home_state}", prefs.home_state)
    user_msg = f"Title: {raw.title}\nCompany: {raw.company}\nLocation: {raw.location}\nRemote: {raw.is_remote}\n\nDescription (first 1500 chars):\n{raw.description[:1500]}"

    try:
        content = await _call_llm(triage_sys, user_msg, use_flash=True)
        data = json.loads(content)
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

    system = SYSTEM_PROMPT.replace("{min_salary}", str(prefs.min_salary))
    system = system.replace("{score_cutoff}", f"{prefs.score_cutoff:.2f}")
    system = system.replace("{convincing_penalty}", f"{prefs.convincing_penalty:+.2f}")
    system = system.replace("{convincing_boost}", f"{prefs.convincing_boost:+.2f}")
    system = system.replace("{nearby_penalty}", f"{prefs.nearby_penalty:+.2f}")
    system = system.replace("{regional_penalty}", f"{prefs.regional_penalty:+.2f}")
    system = system.replace("{relocation_penalty}", f"{prefs.relocation_penalty:+.2f}")
    system = system.replace(
        "{international_penalty}", f"{prefs.international_penalty:+.2f}"
    )
    system = system.replace("{home_city}", prefs.home_city)
    system = system.replace("{home_state}", prefs.home_state)
    system = system.replace("{experience_penalty}", f"{prefs.experience_penalty:+.2f}")
    system = system.replace("{credential_penalty}", f"{prefs.credential_penalty:+.2f}")
    system = system.replace("{portfolio_boost}", f"{prefs.portfolio_boost:+.2f}")
    system = system.replace("{max_seniority_level}", prefs.max_seniority_level)

    # Classify location tier and inject into prompt
    loc_tier = classify_location(
        raw.location or "", prefs.home_city, prefs.home_state, raw.is_remote
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
        data = json.loads(content)

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
        )

        return ScoringResult(passed_filter=True, job=job)

    except Exception as e:
        logger.warning(f"[SCORE] LLM ERROR for {raw.title} @ {raw.company}: {type(e).__name__}: {e or '(empty)'} — falling back to local")
        return score_job_locally(raw, prefs)


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

# High-value keywords (boost score) — calibrated to Gunnar's real stack
_POSITIVE_KEYWORDS = [
    # Core expertise: RAG, embeddings, search (he built 3 RAG systems)
    (r"\bRAG\b|retrieval.augment|vector.search|embedding", 0.18),
    (r"hybrid.search|semantic.search|rerank", 0.15),
    (r"pinecone|weaviate|chroma|qdrant|vector.database", 0.15),
    # Core expertise: AI/ML product building
    (r"\bAI\b|artificial intelligence", 0.12),
    (r"\bLLM\b|large language model|generative AI", 0.15),
    (r"machine learning|\bML\b", 0.10),
    (r"agent(?:ic)?|tool.use|function.calling|MCP|model.context.protocol", 0.15),
    (r"copilot|AI.assistant|chatbot", 0.10),
    # Core expertise: iOS + on-device ML
    (r"\biOS\b|SwiftUI|Swift(?:UI)?|mobile engineer", 0.12),
    (r"Core ML|on.device|edge.AI|Apple Intelligence", 0.18),
    (r"privacy.first|privacy.preserving|on.device.inference", 0.12),
    # Role types that fit
    (r"product engineer", 0.12),
    (r"founding engineer|first engineer", 0.18),
    (r"AI.engineer|ML.engineer", 0.15),
    # Company signals
    (r"\bstartup\b|early.stage|seed|series A", 0.10),
    (r"small.team|<\s*\d{1,2}\s*people", 0.08),
    (r"developer.tools|SDK|API.platform", 0.10),
    (r"healthcare.AI|clinical|health.?tech|medical", 0.12),
    # General positives
    (r"\bremote\b", 0.06),
    (r"product.minded|ship|builder|portfolio", 0.10),
    (r"python|fastapi", 0.05),
    (r"\bjunior\b|\bintern\b|\bentry.level\b", 0.06),
    (r"open.?source|OSS", 0.05),
]
_POSITIVE_COMPILED = [(re.compile(p, re.IGNORECASE), s) for p, s in _POSITIVE_KEYWORDS]

# Negative keywords (reduce score)
_NEGATIVE_KEYWORDS = [
    (r"10\+ years|15\+ years|8\+ years", -0.20),
    (r"PhD required", -0.15),
    (r"\bFortune 500\b|\bFAANG\b", -0.05),
    (r"enterprise|legacy|CRUD|mainframe|ERP", -0.08),
    (r"\bDevOps\b|\bSRE\b|infrastructure only", -0.05),
    (r"leetcode|whiteboard.coding|algorithm.interview", -0.08),
    (r"Java\b(?!Script)|\.NET|C#|COBOL", -0.05),
]
_NEGATIVE_COMPILED = [(re.compile(p, re.IGNORECASE), s) for p, s in _NEGATIVE_KEYWORDS]


def score_job_locally(raw: RawJobListing, prefs: UserPreferences | None = None) -> ScoringResult:
    """Fast keyword-based scoring — no LLM, works offline. Used as fallback."""
    title = raw.title
    text = f"{raw.title} {raw.company} {raw.description}"

    max_level = (prefs.max_seniority_level if prefs else "Mid").lower()

    # Hard reject: Senior titles (respecting max seniority setting)
    if max_level != "any" and _SENIOR_RE.search(title):
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

    # ── Location penalty (graduated tiers) ──
    loc_tier = classify_location(
        raw.location or "",
        prefs.home_city if prefs else "Kalamazoo",
        prefs.home_state if prefs else "Michigan",
        raw.is_remote,
    )
    if loc_tier == 1:
        score += prefs.nearby_penalty if prefs else -0.03
    elif loc_tier == 2:
        score += prefs.regional_penalty if prefs else -0.08
    elif loc_tier == 3:
        score += prefs.relocation_penalty if prefs else -0.15
    elif loc_tier == 4:
        score += prefs.international_penalty if prefs else -0.25

    score = max(0.05, min(1.0, score))
    logger.info(
        f"[LOCAL] PASS score={score:.2f} tier={loc_tier} | {title} @ {raw.company}"
    )

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
        "Pinecone",
        "Weaviate",
        "Chroma",
        "Qdrant",
        "Core ML",
        "MLX",
        "ONNX",
        "RAG",
        "MCP",
        "LlamaIndex",
        "Anthropic",
        "Hugging Face",
        "Transformers",
        "FAISS",
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
        logic_fit="",
        domain_leverage="",
        risk_reward="",
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
                        results.append(score_job_locally(r, prefs))
                break

            await asyncio.sleep(0.5)
    else:
        logger.warning("LLM scoring failed — using local keyword scorer for all")
        for raw in survivors[1:]:
            results.append(score_job_locally(raw, prefs))

    passed = sum(1 for r in results if r.passed_filter)
    logger.info(f"Phase 2 complete: {passed}/{len(survivors)} passed scoring")

    return results
