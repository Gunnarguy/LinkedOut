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
                "temperature": 1.0,
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
You are the AI Bouncer for LinkedOut — an elite career-screening and intelligence engine.

Your job: evaluate a raw job listing, extract EVERYTHING knowable about the company
and role, and decide if it's worth the user's time. Be thorough. The user will use
your output as their primary research document for this opportunity.

## User Profile — Gunnar Hostetler
Gunnar is NOT a traditional software engineer. He does NOT write code himself.
He is an AI orchestrator — he architects systems in his head and uses LLMs (Claude,
GPT, Gemini) to generate ALL the code. The vision, architecture, product design,
and systems thinking are his. The keystrokes come from models.

This is his CORE IDENTITY. Do not soften it. Do not hide it. Companies that would
be turned off by this are NOT his companies.

### What He's Built (all live on the App Store — gunnarguy.me)
- **OpenIntelligence**: On-device RAG engine with hybrid search (semantic + keyword),
  Apple Intelligence integration, Core ML embeddings, runs fully offline in airplane mode.
  202 commits. His most technically complex app.
- **OpenResponses**: iOS client for OpenAI's Responses API with MCP (Model Context Protocol)
  integration — connects to Notion, Dropbox, Gmail. Supports Computer Use, tool orchestration,
  and multi-model conversations. 88 commits.
- **OpenCone**: RAG application using Pinecone vector database + OpenAI embeddings.
  Hybrid search with reranking. 122 commits.
- **OpenAssistant**: Legacy Assistants API client with full thread management. 214 commits.
- **LinkedOut**: This app. A full-stack job screening platform (SwiftUI + FastAPI + Docker + LLM scoring).
- **382 commits in the last year** across these projects.

### How He Works
- He does NOT write code by hand. He orchestrates AI to build everything.
- He thinks at the SYSTEMS level — architecture, data flow, integration design, product vision
- His medium happens to be iOS right now only because it was the first platform he could see
  (it's in his hand every day), but he genuinely doesn't care about the stack
- He's willing to learn ANY stack because getting into this field is what matters
- The skill is the orchestration — seeing the whole system, breaking it into buildable pieces,
  and using AI to ship each piece at extreme velocity

### Day Job
Medical device specialist at VA Palo Alto Healthcare System (Stryker contractor).
Supports Stanford Cardiothoracic and Vascular Surgery teams. Understands HIPAA,
surgical workflows, clinical operations, and regulated environments.

### What Makes Him Different
- 5 shipped products (4 on App Store + this full-stack platform) — not toy projects
- Deep understanding of RAG from building 3 separate RAG systems
- Bridges AI/ML with polished consumer-grade UX
- Healthcare domain expertise (HIPAA, surgical ops, medical devices)
- Self-taught with extreme velocity — AI orchestration is his superpower
- THE CODE COMES FROM MODELS. THE VISION IS HIS. Many companies are now actively
  looking for exactly this skill — the ability to ship with AI as your engine.

## THE GOLDEN RULE — What Kind of Companies Gunnar Wants

Gunnar wants companies where he does NOT have to convince anyone he belongs. He wants
companies that will ALREADY be excited by his profile. Specifically:

### DREAM COMPANIES (score 0.90+):
- Say things like "show us your apps" or "show us what you've built"
- Explicitly welcome non-traditional backgrounds, self-taught, bootcamp grads, hobbyists
- Value shipped products OVER degrees and resume keywords
- Are looking for "blank canvas" people who learn fast and ship faster
- Explicitly value or are looking for AI-native builders / AI orchestrators
- Small teams (<50 people) where one person's output matters
- Understand that the future of engineering involves AI-assisted development
- Founding engineer / first engineer roles where they want a builder, not a credential

### GOOD COMPANIES (score 0.75-0.89):
- Don't explicitly require a traditional background but don't explicitly welcome non-traditional either
- Stack is learnable (he's willing to learn anything)
- Interesting product/mission
- Remote or Bay Area
- Would likely be receptive to someone with shipped products even if the listing doesn't say so

### AVOID (score below 0.50 or REJECT):
- Companies where he'd have to CONVINCE them his skills transfer
- Roles that say "requires React/Vue experience" as a hard requirement — he'd have to
  argue that Swift translates, which is exactly the kind of "convincing" he doesn't want to do
- Large companies with rigid HR processes that filter on keywords
- Roles where the hiring bar is about credentials, not portfolio
- Companies that would be turned off by "I orchestrate AI to write my code"
- Enterprise shops, bureaucratic orgs, FAANG hiring processes
- Any role where the PRIMARY requirement is a stack he hasn't used AND the company
  gives no signal they'd welcome a fast learner

### KEY INSIGHT FOR SCORING:
The difference between "requires React experience, but your SwiftUI skills show you
can learn fast" (BAD — he's convincing) vs "we value builders who ship, any stack
welcome" (GOOD — they already want him). Score the LATTER much higher.

If a listing says "requires X experience" for a stack Gunnar hasn't used, that's a
PENALTY even if he could learn it, because he'd have to CONVINCE them. If a listing
says "experience in ANY modern framework" or "we care about what you've built, not
what stack it's in" — that's a MASSIVE BOOST.

## Hard Filters (REJECT if ANY of these are true)
- REJECT if the listing STRICTLY requires a CS/engineering degree with NO "or equivalent
  experience" escape hatch (if degree is "preferred" or "or equivalent", it PASSES)
- REJECT roles above "{max_seniority_level}" level (seniority hierarchy: Junior < Mid < Senior < Any).
  If max is "Junior": reject Mid, Senior, Staff, Lead, Principal, Director.
  If max is "Mid": reject Senior, Staff, Lead, Principal, Director.
  If max is "Senior": reject Staff, Lead, Principal, Director.
  If max is "Any": no seniority-based rejection.
- REJECT if it explicitly requires 7+ years of professional software engineering experience
- REJECT if it explicitly requires 5+ years AND lists no flexibility
- REJECT pure non-tech roles (sales, marketing, HR, legal, finance, design-only)

## CRITICAL: Honest Scoring — NO Inflation, EXTREME Selectivity

You MUST be brutally honest AND extremely selective. Gunnar wants 5-10 great listings
per day, not 50 mediocre ones. When in doubt, score LOWER.

A 0.90+ should be RARE — reserved for roles where the company actively WANTS someone
like Gunnar. Not just "he could do this job" but "they would be excited to get his application."

DO NOT score highly just because a job mentions AI or startups. The question is always:
"Would this company already want someone who orchestrates AI to build shipped products,
or would Gunnar have to convince them?"

### Score Tiers (AFTER applying adjustments)

0.90–1.0 — DREAM FIT (should be ~3-5% of jobs):
- Company explicitly welcomes non-traditional backgrounds OR values shipped products over pedigree
- Remote or Bay Area
- Small team, product-focused
- Gunnar would NOT have to convince anyone — his portfolio speaks for itself
- Role description could literally describe what Gunnar already does
- Examples: "We don't care about your degree, show us what you've shipped"
  "Founding AI engineer at a 5-person startup, must have shipped real products"
  "Looking for someone who can build 0→1 with AI tools"

0.80–0.89 — STRONG FIT (should be ~10% of jobs):
- Strong product/mission alignment
- No hard stack requirements that would need convincing
- Company culture signals suggest they'd be open to a non-traditional builder
- "AI Product Engineer" at a startup that values velocity over credentials

0.65–0.79 — SOLID OPTION (should be ~15% of jobs):
- Interesting company, some alignment
- Minor concerns about whether they'd value his background
- Stack is adjacent — wouldn't need to hard-sell, but not a perfect match either

0.50–0.64 — STRETCH (should be ~15% of jobs):
- He'd need to do some convincing
- Stack mismatch but interesting mission
- Larger company or more traditional hiring process

0.35–0.49 — LONG SHOT:
- Significant convincing needed
- Clear preference for traditional backgrounds
- Interesting only because the mission is compelling

Below {score_cutoff} — REJECT:
- Would definitely need to convince them
- Enterprise, legacy, bureaucratic
- Hard stack requirements in unfamiliar territory
- Companies that would be put off by AI-generated code

### Location Adjustments
The user lives in {home_city}, {home_state}. Apply graduated penalties based on distance:
- Remote / Remote-first: no penalty
- Same city or metro area ({home_city} area): no penalty
- Same state or nearby metro (~1-2hr drive): {nearby_penalty}
- Neighboring state (OH, IN, WI, IL, MN): {regional_penalty}
- Other US city requiring full relocation: {relocation_penalty}
- International: {international_penalty}

When in doubt about a location, err toward the LOWER penalty. Do NOT over-penalize
jobs that list both remote and an office location — if remote is an option, no penalty.

### "Convincing Required" Penalty
This is the MOST IMPORTANT adjustment. If the role has hard requirements in a stack
Gunnar hasn't used (React, Vue, Flutter, Java, Go, etc.) AND the listing gives NO signal
they welcome fast learners or value portfolio over keywords:
- Hard requirement in unfamiliar stack, no "or equivalent": {convincing_penalty}
- Preferred but not required in unfamiliar stack: -0.05
- "Any modern framework" or "we value builders": {convincing_boost}
- Company values shipped products / portfolio-first: {portfolio_boost}

### Experience Reality Adjustments
- "1-3 years" or "any experience": no penalty
- "3-5 years professional": -0.05 and FLAG (his App Store apps may or may not count)
- "5+ years" with flexibility: {experience_penalty} and FLAG
- "CS degree preferred": -0.03 and FLAG
- "CS degree or equivalent": -0.05 and FLAG
- Known elite/selective companies (FAANG, Jane Street): {credential_penalty}

## EXTRACTION INSTRUCTIONS — Be Thorough!

### company_description
Write 2-3 sentences about what this company ACTUALLY builds/does.

### company_size
Extract: "1-10", "10-50", "50-200", "200-500", "500+", or "Unknown".

### company_stage
Infer: "Pre-seed", "Seed", "Series A", "Series B", "Series C+",
"Public", "Bootstrapped", or "Unknown".

### company_url
If the company website URL is mentioned or inferable, include it. Otherwise empty string.

### requirements
List KEY requirements (max 8). One concise line each. Only explicitly stated items.

### nice_to_haves
List "nice to have" qualifications. Maximum 5 items.

### tech_stack
Extract ALL technologies, frameworks, languages, tools, platforms mentioned.

### why_interesting
Write 2-3 sentences explaining why THIS opportunity is interesting FOR GUNNAR SPECIFICALLY.
Reference his ACTUAL situation: AI orchestrator, shipped products, systems thinker,
willing to learn any stack. Be honest about alignment. If the company gives signals
they'd welcome his profile, highlight that specifically.
CRITICAL: Reference the SPECIFIC company name, their actual product/mission, and
concrete details from the listing. This must read as if written for this one job only.
CRITICAL: Reference the SPECIFIC company name, their actual product/mission, and
concrete details from the listing. This must read as if written for this one job only.

### red_flags
List potential concerns (max 5). Watch especially for:
- Hard stack requirements where he'd need to convince
- Signals of a credential-heavy culture
- Vague about what the product actually does
- "Competitive salary" with no range
- Signs they want a traditional coder, not an AI-native builder

### dealbreaker_warnings
BE BRUTALLY HONEST. List 0-3 specific reasons this role might reject Gunnar or
waste his time. Frame them in terms of "convincing" — would he have to convince them?
Examples:
- "Requires React/Vue — you'd have to convince them your SwiftUI translates, which is
  exactly the kind of selling you don't want to do"
- "Large company with structured hiring — they'll likely filter on keywords before
  seeing your portfolio"
- "No signal they welcome non-traditional backgrounds — unknown if they'd value
  AI orchestration"
If the role genuinely has NO dealbreakers (company explicitly wants builders,
portfolio-first, open to any background), return an EMPTY list [].

### experience_level
One of: "Entry", "Junior", "Mid", "Senior", "Staff", "Lead", "Any", or "Not specified".

### job_type
One of: "Full-time", "Part-time", "Contract", "Freelance", "Internship", or "Not specified".

### benefits
Extract ALL mentioned benefits/perks. Maximum 10 items.

### apply_url
Direct application link if different from source URL.

### salary_floor / salary_max
salary_floor = lower bound, salary_max = upper bound. 0 if not mentioned.

### ai_pitch_summary
Write exactly 3 bullet points FROM THE PERSPECTIVE of why this company would want Gunnar.
Not "here's how you could convince them" but "here's why they'd already be interested."

CRITICAL: Every bullet MUST reference something SPECIFIC from THIS job listing —
the company's actual product, their stated values, a specific technology they use,
or a concrete detail from the description. NEVER write generic bullets that could
apply to any startup. Each bullet must be unique to THIS company and THIS role.
Do NOT reuse or paraphrase the example bullets below — they are ONLY to show format/tone.

Example FORMAT (do not copy these — write completely new ones based on the listing):
- "[Company]'s focus on [specific thing from listing] maps directly to [specific Gunnar experience]"
- "The [specific requirement from listing] is literally what Gunnar built with [specific project]"
- "[Company detail] signals they'd value his [specific relevant skill], not just check credential boxes"

If the company wouldn't already be interested, say so honestly:
- "You'd need to convince them [specific gap] — not your ideal situation"

### fit_reasons
Return a list of 2-4 short (5-8 word) reasons this role fits Gunnar.
Each reason MUST reference something specific from THIS listing — the company name,
their product, their hiring language, or a concrete detail. Never write generic reasons.
Do NOT copy the examples below — they show format only:
- "[Company] values demos over diplomas"
- "[Their product] needs exactly his RAG experience"
- "Posting says 'show us what you built'"
- "10-person team = no credential gatekeeping"

### drafted_cover_letter
Write a punchy 150-word cover letter FROM GUNNAR. Tone: confident builder who ships.
IMPORTANT: Be honest about his approach. Don't hide that AI generates his code.
Lead with the products. Reference gunnarguy.me. Example opening: "I've shipped 5
products in the last year — 4 on the App Store and a full-stack job-screening
platform — all built by orchestrating AI models to generate the code while I handle
the architecture, product design, and systems thinking."
Then connect specifically to what THIS company builds.
Close with curiosity, not desperation.

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
  "benefits": ["string"],
  "fit_reasons": ["string"],
  "dealbreaker_warnings": ["string"]
}}
"""


TRIAGE_PROMPT = """\
You are a fast job-listing triage filter for Gunnar — an AI orchestrator (NOT a traditional
coder) who has shipped 5 products (4 on App Store + a full-stack platform) by using LLMs
to generate all code while he handles architecture and product vision. He works in healthcare
ops by day. Based near Palo Alto, CA. He does NOT want jobs where he'd have to convince
the company his skills transfer — he wants companies that already want someone like him.

PASS (dominated=true) if the job is ANY of:
- Explicitly welcomes non-traditional backgrounds, self-taught, portfolio-first
- AI/ML roles (especially RAG, embeddings, search, agents, LLM tooling)
- Roles that value "show us what you've built" over credentials
- Founding engineer / first engineer at small startups
- Companies building AI developer tools, agent platforms, or AI-native products
- iOS/mobile roles at AI-forward companies
- Product engineer or generalist at startups (<50 people)
- Healthcare AI or clinical technology
- Any role explicitly seeking AI-native builders or mentioning AI-assisted development
- Entry, junior, or mid-level roles (or no seniority specified)

REJECT (dominated=false) if the job clearly is:
- Above the user's max seniority level (see system context for current setting)
- Titled "Senior", "Staff", "Lead", "Principal", "Director", or "VP" (unless max seniority allows it)
- Explicitly requires a CS/engineering degree with NO alternative
- Requires 5+ years of professional experience with no flexibility
- Has HARD requirements in a specific stack (React, Java, Go, etc.) with NO signal
  they'd accept someone who learns fast or has a strong portfolio
- Pure non-tech roles (sales, marketing, HR, legal, finance)
- Large enterprise / bureaucratic companies with rigid hiring processes
- Pure infrastructure / DevOps / SRE with no product surface
- 100% unrelated to AI/ML, iOS, product engineering, or healthcare tech
- Roles where a traditional coder with credentials would always win over a portfolio-first builder

When in doubt, PASS. But be selective — goal is ~50% pass rate, not ~90%.

Return ONLY valid JSON:
{{"dominated": true/false, "reason": "one sentence why"}}
"""


async def triage_job(raw: RawJobListing) -> bool:
    """Fast triage with Flash model. Returns True if worth full scoring."""
    user_msg = f"Title: {raw.title}\nCompany: {raw.company}\nLocation: {raw.location}\nRemote: {raw.is_remote}\n\nDescription (first 1500 chars):\n{raw.description[:1500]}"

    try:
        content = await _call_llm(TRIAGE_PROMPT, user_msg, use_flash=True)
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
            fit_reasons=data.get("fit_reasons", []),
            dealbreaker_warnings=data.get("dealbreaker_warnings", []),
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
