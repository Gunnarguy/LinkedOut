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

_REMOTE_SIGNAL_TERMS = [
    "remote",
    "remote-first",
    "work from home",
    "distributed team",
    "fully distributed",
    "anywhere in the us",
    "us remote",
    "remote within the us",
    "remote in the united states",
]

_ONSITE_SIGNAL_TERMS = [
    "onsite",
    "on-site",
    "hybrid",
    "in office",
    "in-office",
    "office-first",
    "relocation required",
    "must relocate",
    "5 days in office",
    "4 days in office",
    "3 days in office",
]

_NON_US_REMOTE_TERMS = [
    "emea",
    "eu only",
    "europe only",
    "uk only",
    "canada only",
    "remote canada",
    "latam",
    "apac",
    "remote india",
    "remote australia",
    "must be based in germany",
    "must be based in the uk",
    "remote within canada",
    "remote within europe",
]

_US_REMOTE_TERMS = [
    "remote us",
    "remote-u.s.",
    "anywhere in the us",
    "us-based remote",
    "united states only",
    "must be located in the united states",
    "must be based in the us",
    "u.s. remote",
]

_TARGET_SIGNAL_TERMS = [
    "ai",
    "llm",
    "language model",
    "agentic",
    "agents",
    "rag",
    "prompt",
    "applied ai",
    "generative ai",
    "prototype",
    "prototyping",
    "0-to-1",
    "zero-to-one",
    "product engineer",
    "founding engineer",
    "product development",
    "swift",
    "swiftui",
    "ios",
    "mobile",
    "healthtech",
    "medtech",
    "clinical",
    "healthcare",
    "medical device",
    "developer tools",
    "mcp",
    "automation",
    "orchestration",
]

_PORTFOLIO_SIGNAL_TERMS = [
    "portfolio",
    "what you've built",
    "what you have built",
    "shipped",
    "ship fast",
    "bias for action",
    "rapid prototyping",
    "builders welcome",
    "non-traditional",
    "self-taught",
    "founding",
    "first engineer",
]

_ENTERPRISE_SIGNAL_TERMS = [
    "enterprise scale",
    "large-scale distributed systems",
    "formal engineering ladder",
    "staff level",
    "principal level",
    "leetcode",
    "data structures and algorithms",
    "system design interview",
    "top-tier engineering org",
]

_STARTUP_FLEX_TERMS = [
    "founding",
    "first engineer",
    "startup",
    "0-to-1",
    "zero-to-one",
    "prototype",
    "rapid prototyping",
    "wear many hats",
    "generalist",
    "product development generalist",
    "ai-leveraged",
]

_SENIOR_TITLE_TERMS = [
    "senior",
    "sr ",
    "sr.",
    "staff",
    "principal",
    "lead ",
    "director",
    "head of",
    "vp ",
    "architect",
]

_EXTREME_EXPERIENCE_PATTERNS = [
    re.compile(r"\b(?:8|9|10|11|12|13|14|15)\+?\s+years\b", re.IGNORECASE),
    re.compile(r"\b(?:eight|nine|ten|eleven|twelve)\+?\s+years\b", re.IGNORECASE),
]

_CORE_BUILDER_TITLE_TERMS = [
    "founding engineer",
    "product engineer",
    "ai engineer",
    "applied ai",
    "llm engineer",
    "machine learning engineer",
    "ml engineer",
    "ios engineer",
    "mobile engineer",
    "swift engineer",
    "full-stack engineer",
    "full stack engineer",
    "backend engineer",
    "software engineer",
    "prototype engineer",
    "product development generalist",
    "generalist",
    "developer platform",
    "platform engineer",
]

_NON_BUILDER_TITLE_TERMS = [
    "product manager",
    "product management",
    "project manager",
    "program manager",
    "engineering manager",
    "manager, product management",
    "design technologist",
    "designer",
    "product design",
    "product designer",
    "product operations",
    "operations lead",
    "category specialist",
    "specialist",
    "trainer",
    "ai trainer",
    "data scientist",
    "data science engineer",
    "qa engineer",
    "quality assurance",
    "test engineer",
    "sdet",
    "gtm engineer",
    "growth engineer",
    "solutions architect",
    "solutions consultant",
    "revops",
    "customer success",
    "sales",
    "marketing",
    "analyst",
    "vp, product",
    "vice president of product",
]

_NON_US_LOCATION_TERMS = [
    "uk",
    "united kingdom",
    "europe",
    "eu",
    "spain",
    "germany",
    "poland",
    "australia",
    "au only",
    "canada",
    "latam",
    "apac",
    "india",
]

_HARDSTOP_DEGREE_PATTERNS = [
    re.compile(
        r"(?:requires?|required|must have|must hold)\s+(?:a\s+)?(?:bachelor'?s|master'?s|bs|b\.s\.|ms|m\.s\.)?\s*(?:degree\s+in\s+)?(?:computer science|software engineering|computer engineering)",
        re.IGNORECASE,
    ),
    re.compile(
        r"(?:computer science|software engineering|computer engineering)\s+degree\s+(?:required|is required)",
        re.IGNORECASE,
    ),
]

_HARDSTOP_CLEARANCE_PATTERNS = [
    re.compile(r"active\s+(?:ts/sci|top secret|secret)\s+clearance", re.IGNORECASE),
    re.compile(r"security clearance required", re.IGNORECASE),
    re.compile(
        r"must be able to obtain a\s+(?:ts/sci|top secret|secret)\s+clearance",
        re.IGNORECASE,
    ),
]

_HARDSTOP_LICENSE_PATTERNS = [
    re.compile(
        r"must be a licensed\s+(?:rn|nurse|physician|therapist|social worker|pharmacist)",
        re.IGNORECASE,
    ),
    re.compile(r"active\s+(?:rn|nursing|medical|clinical)\s+license", re.IGNORECASE),
    re.compile(r"board certified", re.IGNORECASE),
    re.compile(r"clinical credential required", re.IGNORECASE),
]

_ESCAPE_HATCH_TERMS = [
    "or equivalent",
    "equivalent experience",
    "equivalent practical experience",
    "equivalent professional experience",
    "equivalent projects",
    "comparable experience",
    "relevant experience may substitute",
]


def _normalize_match_text(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower()).strip()


def _job_match_text(raw: RawJobListing) -> str:
    return _normalize_match_text(
        f"{raw.title} {raw.company} {raw.location} {raw.description}"
    )


def _contains_any(text: str, terms: list[str]) -> bool:
    return any(term in text for term in terms)


def _count_matches(text: str, terms: list[str]) -> int:
    return sum(1 for term in terms if term in text)


def _has_escape_hatch(text: str) -> bool:
    return _contains_any(text, _ESCAPE_HATCH_TERMS)


def _programmatic_hard_reject(
    raw: RawJobListing,
    prefs: UserPreferences,
    loc_tier: int,
) -> str | None:
    text = _job_match_text(raw)
    title = _normalize_match_text(raw.title)
    location_text = _normalize_match_text(f"{raw.title} {raw.location}")
    remote_signal = raw.is_remote is True or _contains_any(text, _REMOTE_SIGNAL_TERMS)
    onsite_signal = _contains_any(text, _ONSITE_SIGNAL_TERMS)
    us_remote_signal = _contains_any(text, _US_REMOTE_TERMS)
    non_us_remote_signal = _contains_any(text, _NON_US_REMOTE_TERMS)
    non_us_location_signal = _contains_any(location_text, _NON_US_LOCATION_TERMS)
    startup_flex = _contains_any(text, _STARTUP_FLEX_TERMS)
    portfolio_signal = _contains_any(text, _PORTFOLIO_SIGNAL_TERMS)
    senior_exception = _contains_any(
        title,
        [
            "ai product",
            "product engineer",
            "founding engineer",
            "generalist",
            "prototype engineer",
        ],
    )

    title_rank = 1
    if _contains_any(
        title, ["staff", "principal", "director", "head of", "vp ", "architect"]
    ):
        title_rank = 3
    elif _contains_any(title, ["senior", "sr ", "sr.", "lead "]):
        title_rank = 2
    elif _contains_any(title, ["junior", "jr ", "jr.", "associate", "entry", "intern"]):
        title_rank = 0

    allowed_rank = {
        "junior": 0,
        "mid": 1,
        "senior": 2,
        "any": 3,
    }.get(prefs.max_seniority_level.lower(), 1)

    if _contains_any(title, _NON_BUILDER_TITLE_TERMS):
        return "Listing title is not a software-building role aligned with your target profile."

    if not _contains_any(title, _CORE_BUILDER_TITLE_TERMS) and not _contains_any(
        text,
        [
            "build and ship",
            "ai-powered features",
            "llm workflows",
            "rag pipelines",
            "native mobile",
            "swiftui",
            "fastapi",
            "agents",
            "tool-calling",
        ],
    ):
        return "Listing does not look like a builder-first software role for your target profile."

    if prefs.require_remote:
        if onsite_signal:
            return "Remote-only search: listing is onsite or hybrid."
        if raw.is_remote is not True and not remote_signal:
            return "Remote-only search: listing is not clearly remote."
        if (loc_tier == 4 or non_us_location_signal) and not us_remote_signal:
            return "International or non-US remote role does not match your US remote search."
        if (non_us_remote_signal or non_us_location_signal) and not us_remote_signal:
            return "Remote eligibility is restricted outside the US."

    if loc_tier == 4 and not remote_signal:
        return "International onsite role outside your target geography."

    if any(
        pattern.search(text) for pattern in _HARDSTOP_DEGREE_PATTERNS
    ) and not _has_escape_hatch(text):
        return "Listing hard-requires a CS or engineering degree with no equivalent-experience escape hatch."

    if any(pattern.search(text) for pattern in _HARDSTOP_CLEARANCE_PATTERNS):
        return "Listing requires an active security clearance."

    if any(pattern.search(text) for pattern in _HARDSTOP_LICENSE_PATTERNS):
        return "Listing requires a professional clinical or licensed credential."

    if title_rank >= 3 and title_rank > allowed_rank:
        return "Listing seniority exceeds your configured max seniority level."

    if title_rank == 2 and title_rank > allowed_rank and not senior_exception:
        return "Listing seniority exceeds your configured max seniority level."

    return None


def _apply_alignment_clamp(
    raw: RawJobListing,
    prefs: UserPreferences,
    score: float,
) -> tuple[float, list[str]]:
    text = _job_match_text(raw)
    title = _normalize_match_text(raw.title)
    preferred_role_hits = sum(
        1 for role in prefs.preferred_roles if _normalize_match_text(role) in text
    )
    target_hits = _count_matches(text, _TARGET_SIGNAL_TERMS)
    portfolio_hits = _count_matches(text, _PORTFOLIO_SIGNAL_TERMS)
    enterprise_hits = _count_matches(text, _ENTERPRISE_SIGNAL_TERMS)
    startup_flex = _contains_any(text, _STARTUP_FLEX_TERMS)
    senior_title = _contains_any(title, _SENIOR_TITLE_TERMS)
    extreme_experience = any(
        pattern.search(text) for pattern in _EXTREME_EXPERIENCE_PATTERNS
    )

    multiplier = 1.0
    max_score = 1.0
    extra_caveats: list[str] = []

    if target_hits == 0 and preferred_role_hits == 0:
        multiplier *= 0.35
        max_score = min(max_score, 0.19)
        extra_caveats.append(
            "Listing does not mention AI, healthtech, mobile, product engineering, or portfolio-first builder signals."
        )
    elif target_hits <= 1 and preferred_role_hits == 0:
        multiplier *= 0.60
        max_score = min(max_score, 0.29)

    if enterprise_hits > 0 and portfolio_hits == 0 and not startup_flex:
        multiplier *= 0.70
        max_score = min(max_score, 0.38)
        extra_caveats.append(
            "Listing reads like a conventional enterprise engineering role rather than a builder-first role."
        )

    if senior_title and portfolio_hits == 0 and not startup_flex:
        multiplier *= 0.65
        max_score = min(max_score, 0.35)
        extra_caveats.append(
            "Title is senior-level without obvious startup or portfolio-first flexibility."
        )

    if extreme_experience:
        multiplier *= 0.75
        max_score = min(max_score, 0.29)
        extra_caveats.append(
            "Listing asks for 8+ years or equivalent senior-level background."
        )

    if target_hits >= 3 and (portfolio_hits > 0 or startup_flex):
        multiplier *= 1.15

    adjusted = round(min(max_score, max(0.0, min(1.0, score * multiplier))), 2)
    return adjusted, extra_caveats


def _apply_llm_specificity_clamp(
    raw: RawJobListing,
    score: float,
    domain_alignment: float,
    role_alignment: float,
    culture_fit: float,
) -> tuple[float, list[str]]:
    text = _job_match_text(raw)
    title = _normalize_match_text(raw.title)
    extra_caveats: list[str] = []
    capped_score = score

    if _contains_any(
        title,
        [
            "backend engineer",
            "software engineer",
            "full stack",
            "full-stack",
            "platform engineer",
        ],
    ):
        if (
            not _contains_any(
                title,
                [
                    "product engineer",
                    "founding engineer",
                    "ios engineer",
                    "mobile engineer",
                    "ai engineer",
                ],
            )
            and domain_alignment < 0.88
            and role_alignment < 0.82
        ):
            capped_score = min(capped_score, 0.68)
            extra_caveats.append(
                "Role reads more like a general backend or platform engineering role than a direct builder fit."
            )

    if _contains_any(
        text,
        [
            "sre",
            "data platform",
            "platform team",
            "infra",
            "infrastructure",
            "internal tools",
            "people innovation",
        ],
    ):
        if domain_alignment < 0.90 and culture_fit < 0.85:
            capped_score = min(capped_score, 0.64)
            extra_caveats.append(
                "Listing centers platform or internal-systems work more than product-building leverage."
            )

    if (
        not _contains_any(
            text,
            [
                "healthtech",
                "healthcare",
                "medtech",
                "clinical",
                "swift",
                "swiftui",
                "ios",
                "mobile",
                "founding engineer",
                "product engineer",
                "ai product builder",
            ],
        )
        and role_alignment < 0.85
        and culture_fit < 0.85
    ):
        capped_score = min(capped_score, 0.72)

    return round(capped_score, 2), extra_caveats


def _is_anonymous_company_name(company_name: str) -> bool:
    normalized = _normalize_match_text(company_name)
    return (
        not normalized
        or normalized == "unknown"
        or normalized.startswith("unknown company")
        or "hn hiring post" in normalized
        or normalized in {"stealth startup", "confidential"}
    )


def _apply_listing_confidence_penalty(
    raw: RawJobListing,
    score: float,
    company_name: str,
    company_description: str,
    company_url: str,
    salary_floor: int,
    salary_max: int,
    requirements: list[str],
    tech_stack: list[str],
) -> tuple[float, list[str]]:
    url = (raw.url or "").lower()
    is_hn = "news.ycombinator.com" in url
    anonymous_company = _is_anonymous_company_name(
        company_name
    ) or _is_anonymous_company_name(raw.company or "")
    salary_known = bool(salary_floor or salary_max)
    company_detail_len = len((company_description or "").strip())
    requirements_count = len(requirements or [])
    tech_count = len(tech_stack or [])
    description_len = len((raw.description or "").strip())

    capped_score = score
    extra_caveats: list[str] = []

    if is_hn and anonymous_company and not salary_known:
        capped_score = min(capped_score, 0.84)
        extra_caveats.append(
            "HN post lacks a clearly named company and compensation detail, so confidence is lower than for a normal listing."
        )
    elif anonymous_company and not salary_known:
        capped_score = min(capped_score, 0.86)
        extra_caveats.append(
            "Company identity and compensation are both weakly specified, so confidence is capped."
        )

    thin_scope = description_len < 900 or (requirements_count < 5 and tech_count < 5)
    weak_company_detail = company_detail_len < 120 or not company_url

    if thin_scope and not salary_known:
        capped_score = min(capped_score, 0.82)
        extra_caveats.append(
            "Listing is relatively thin on salary and concrete scope detail compared with stronger matches."
        )
    elif thin_scope and weak_company_detail:
        capped_score = min(capped_score, 0.85)
        extra_caveats.append(
            "Listing leaves important company or scope detail vague, which lowers confidence in the match quality."
        )

    return round(capped_score, 2), extra_caveats


def _infer_is_remote(raw: RawJobListing) -> bool:
    text = _job_match_text(raw)
    if _contains_any(text, _ONSITE_SIGNAL_TERMS):
        return False
    if _contains_any(text, _REMOTE_SIGNAL_TERMS) or _contains_any(
        _normalize_match_text(f"{raw.title} {raw.location}"), _US_REMOTE_TERMS
    ):
        return True
    if raw.is_remote is not None:
        return raw.is_remote
    return False


def _parse_salary_bounds(salary_text: str) -> tuple[int, int]:
    matches = [
        int(m.replace(",", ""))
        for m in re.findall(r"\$?([0-9]{2,3}(?:,[0-9]{3})+)", salary_text)
    ]
    if not matches:
        matches = [
            int(m) * 1000 for m in re.findall(r"\b([0-9]{2,3})k\b", salary_text.lower())
        ]
    if not matches:
        return 0, 0
    return min(matches), max(matches)


def _local_score_job(raw: RawJobListing, prefs: UserPreferences) -> ScoringResult:
    text = _job_match_text(raw)
    title = _normalize_match_text(raw.title)
    loc_tier = classify_location(
        raw.location or "",
        prefs.home_city,
        prefs.home_state,
        raw.is_remote,
        preferred_locations=prefs.preferred_locations,
    )

    hard_reject_reason = _programmatic_hard_reject(raw, prefs, loc_tier)
    if hard_reject_reason:
        return ScoringResult(
            passed_filter=False,
            rejection_reason=hard_reject_reason,
        )

    target_hits = _count_matches(text, _TARGET_SIGNAL_TERMS)
    portfolio_hits = _count_matches(text, _PORTFOLIO_SIGNAL_TERMS)
    startup_hits = _count_matches(text, _STARTUP_FLEX_TERMS)
    enterprise_hits = _count_matches(text, _ENTERPRISE_SIGNAL_TERMS)
    core_builder_hits = _count_matches(title, _CORE_BUILDER_TITLE_TERMS)

    health_hits = _count_matches(
        text,
        [
            "healthtech",
            "healthcare",
            "medtech",
            "clinical",
            "medical",
            "hipaa",
            "patient",
            "provider",
            "surgical",
        ],
    )
    ai_hits = _count_matches(
        text,
        [
            "ai",
            "llm",
            "agent",
            "agentic",
            "rag",
            "prompt",
            "generative ai",
            "applied ai",
            "automation",
        ],
    )
    mobile_hits = _count_matches(
        text,
        ["ios", "swift", "swiftui", "iphone", "ipad", "mobile", "apple"],
    )
    backend_hits = _count_matches(
        text,
        [
            "python",
            "fastapi",
            "api",
            "backend",
            "full stack",
            "docker",
            "mcp",
            "qdrant",
            "pinecone",
        ],
    )
    bad_stack_hits = _count_matches(
        text,
        [
            "php",
            "magento",
            "wordpress",
            "salesforce",
            "power bi",
            "power platform",
            "c++",
            ".net",
            "c#",
            "devops",
        ],
    )

    domain_alignment = 0.30
    if health_hits >= 2:
        domain_alignment = 0.95
    elif ai_hits >= 2:
        domain_alignment = 0.85
    elif mobile_hits >= 2:
        domain_alignment = 0.78
    elif "developer tools" in text or "mcp" in text:
        domain_alignment = 0.72
    elif enterprise_hits > 0:
        domain_alignment = 0.22
    elif target_hits >= 1:
        domain_alignment = 0.55

    role_alignment = 0.18
    if _contains_any(
        title, ["founding engineer", "product engineer", "prototype", "generalist"]
    ):
        role_alignment = 0.95
    elif _contains_any(
        title,
        [
            "ai engineer",
            "applied ai",
            "machine learning",
            "llm engineer",
            "ai product",
            "backend / product engineer",
        ],
    ):
        role_alignment = 0.90
    elif _contains_any(title, ["ios", "swift", "mobile engineer"]):
        role_alignment = 0.92
    elif _contains_any(
        title, ["full stack", "full-stack", "software engineer", "backend engineer"]
    ):
        role_alignment = 0.78
    elif _contains_any(title, ["product manager", "designer", "devops", "sre"]):
        role_alignment = 0.08

    culture_fit = 0.22
    if portfolio_hits >= 2 or startup_hits >= 2:
        culture_fit = 0.88
    elif portfolio_hits >= 1 or startup_hits >= 1 or core_builder_hits > 0:
        culture_fit = 0.72
    elif enterprise_hits > 0:
        culture_fit = 0.18
    elif target_hits >= 2:
        culture_fit = 0.50

    experience_friction = 0.38
    if _contains_any(
        text, ["no experience required", "entry level", "junior", "associate"]
    ):
        experience_friction = 0.90
    elif re.search(r"\b(?:0|1|2)\+?\s+years\b", text):
        experience_friction = 0.78
    elif re.search(r"\b(?:3|4|5)\+?\s+years\b", text):
        experience_friction = 0.55
    elif any(pattern.search(text) for pattern in _EXTREME_EXPERIENCE_PATTERNS):
        experience_friction = 0.15

    stack_fit = 0.25
    if mobile_hits >= 2 and (ai_hits >= 1 or backend_hits >= 1):
        stack_fit = 0.95
    elif ai_hits >= 2 and backend_hits >= 1:
        stack_fit = 0.90
    elif mobile_hits >= 1 or backend_hits >= 1:
        stack_fit = 0.72
    if bad_stack_hits >= 2:
        stack_fit = min(stack_fit, 0.18)

    computed_score = (
        domain_alignment * 0.30
        + role_alignment * 0.25
        + culture_fit * 0.20
        + experience_friction * 0.15
        + stack_fit * 0.10
    )
    final_score, extra_caveats = _apply_alignment_clamp(raw, prefs, computed_score)

    if core_builder_hits > 0 and ai_hits >= 2:
        final_score = max(final_score, 0.82)
    if _contains_any(title, ["founding engineer", "product engineer", "ios engineer"]):
        final_score = max(final_score, 0.86)
    if health_hits >= 2 and ai_hits >= 2:
        final_score = max(final_score, 0.88)
    final_score = round(min(final_score, 0.96), 2)

    caveats: list[str] = []
    if bad_stack_hits > 0:
        caveats.append("Stack leans away from Swift/Python/AI-builder work.")
    if enterprise_hits > 0:
        caveats.append("Listing reads like a conventional enterprise role.")
    if any(pattern.search(text) for pattern in _EXTREME_EXPERIENCE_PATTERNS):
        caveats.append("Listing asks for 8+ years of experience.")
    for caveat in extra_caveats:
        if caveat not in caveats:
            caveats.append(caveat)

    tags: list[str] = []
    if health_hits:
        tags.append("HealthTech")
    if ai_hits:
        tags.append("AI")
    if mobile_hits:
        tags.append("iOS")
    if startup_hits:
        tags.append("Startup")
    if backend_hits:
        tags.append("Python")

    fit_reasons: list[str] = []
    if health_hits:
        fit_reasons.append("healthcare domain leverage")
    if ai_hits:
        fit_reasons.append("AI-native product builder")
    if mobile_hits:
        fit_reasons.append("SwiftUI and mobile overlap")
    if startup_hits or portfolio_hits:
        fit_reasons.append("builder-first startup signals")
    fit_reasons = fit_reasons[:4]

    salary_floor, salary_max = _parse_salary_bounds(raw.salary_text or "")
    inferred_remote = _infer_is_remote(raw)
    company_oneliner = "Company description not extracted in local fallback mode."
    logic_fit = (
        "This role was scored with deterministic local fallback because both configured LLM providers failed authentication. "
        "It lines up best when the listing shows AI, product-building, mobile, or healthcare signals that map to your shipped Swift and Python projects."
    )
    domain_leverage = (
        "Your edge is strongest when the job touches healthcare workflows, AI products, or mobile app delivery. "
        "You have real O.R. exposure plus shipped AI apps on the App Store."
    )
    risk_reward = (
        "This local score is conservative and based on keyword heuristics rather than full LLM extraction. "
        "Use the caveats to decide whether the role is still worth a quick application."
    )
    ai_pitch_bullets = [
        "• Local fallback mode: deterministic score from title, domain, stack, and culture signals.",
        f"• Signals found: AI={ai_hits}, health={health_hits}, mobile={mobile_hits}, startup={startup_hits}.",
        (
            f"• Seniority / enterprise friction capped this role at {final_score:.2f}."
            if caveats
            else f"• Local heuristic score landed at {final_score:.2f}."
        ),
    ]
    cover_letter = (
        f"I build AI-heavy products with SwiftUI and Python, and I tend to work from product idea to shipped implementation quickly. "
        f"My portfolio at gunnarguy.me includes OpenIntelligence, OpenResponses, and LinkedOut, all built through an AI-orchestrated workflow. "
        f"I also bring healthcare operations context from Stryker at the VA in Palo Alto. "
        f"If this role is genuinely remote and values shipped builder work over pedigree, I would want to understand how much of the job is product creation versus maintaining an existing stack."
    )

    job = JobPayload(
        company_name=raw.company,
        role_title=raw.title,
        salary_floor=salary_floor,
        is_remote=inferred_remote,
        builder_score=final_score,
        ai_pitch_summary="\n".join(ai_pitch_bullets),
        drafted_cover_letter=cover_letter,
        source_url=raw.url,
        posted_at=datetime.now(timezone.utc),
        location=raw.location,
        tags=tags,
        description=raw.description[:12000],
        company_description="",
        company_size="Unknown",
        company_stage="Unknown",
        company_url="",
        salary_max=salary_max,
        requirements=[],
        nice_to_haves=[],
        tech_stack=[],
        why_interesting=logic_fit,
        red_flags=caveats[:3],
        apply_url="",
        experience_level="Not specified",
        job_type="Not specified",
        benefits=[],
        fit_reasons=fit_reasons,
        dealbreaker_warnings=caveats[:3],
        logic_fit=logic_fit,
        domain_leverage=domain_leverage,
        risk_reward=risk_reward,
        company_oneliner=company_oneliner,
        they_want=[],
        job_snapshot="Local fallback mode: factual extraction unavailable because the configured LLM providers failed.",
        domain_alignment=domain_alignment,
        role_alignment=role_alignment,
        culture_fit=culture_fit,
        experience_friction=experience_friction,
        stack_fit=stack_fit,
        caveats=caveats[:4],
        scoring_version="local-v1",
    )

    if final_score < 0.15:
        return ScoringResult(
            passed_filter=False,
            rejection_reason="Local fallback score too low.",
        )

    return ScoringResult(passed_filter=True, job=job)


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
- If remote is required, any onsite / hybrid / non-US-eligible role should be treated as a reject
- Treat hard credential stop-signs as rejects: active security clearance, active clinical license, or CS degree explicitly required with no equivalent-experience escape hatch

IMPORTANT: Do NOT hard-reject based on:
- Seniority in title alone — many "Senior" roles at startups are flexible, and the candidate can learn. Flag it as a caveat, not a reject.
- Years of experience — treat as friction, not a gate. "3+ years" is a caveat. "10+ years" is a strong caveat. Neither is an auto-reject.
- CS degree requirements — "or equivalent experience/projects" counts, and many companies are flexible even when the listing says "required". Flag as caveat.
- Stack mismatches — the candidate can learn new stacks. Flag what's unfamiliar as a caveat.
- Credential culture signals — penalize in scoring, don't reject.

## The Core Matching Question

You are scoring: "Is this role worth applying to?"

This means: Would the time invested in applying have a reasonable chance of leading somewhere — an interview, a conversation, a connection — given the candidate's unique profile? The candidate can learn anything technical. The question is whether the role aligns with their trajectory and whether the company is likely to engage.

Important: this candidate is not a generic fit for conventional enterprise software jobs. If the listing does not show any AI-builder, healthtech, mobile, product-engineering, startup, or portfolio-friendly signals, keep the factor scores low enough that the role likely falls below the cutoff.
Generic backend, platform, SRE, internal-tools, or people-systems roles should not rise above the high 0.60s unless the listing has unusually strong AI-product, healthtech, or iOS/mobile alignment.

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

**Anchor at 0.45.** A generic "Software Engineer" posting with no AI, healthtech, mobile, startup, or product-builder alignment should land around 0.20-0.35, not 0.50.
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

    hard_reject_reason = _programmatic_hard_reject(raw, prefs, loc_tier)
    if hard_reject_reason:
        logger.info(
            f"[SCORE] PROGRAMMATIC REJECT | {raw.title} @ {raw.company} | {hard_reject_reason}"
        )
        return ScoringResult(
            passed_filter=False,
            rejection_reason=hard_reject_reason,
        )

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
        final_score, extra_caveats = _apply_alignment_clamp(raw, prefs, final_score)
        final_score, specificity_caveats = _apply_llm_specificity_clamp(
            raw,
            final_score,
            domain_alignment,
            role_alignment,
            culture_fit,
        )
        final_score, confidence_caveats = _apply_listing_confidence_penalty(
            raw,
            final_score,
            data.get("company_name", raw.company),
            data.get("company_description", ""),
            data.get("company_url", ""),
            data.get("salary_floor") or 0,
            data.get("salary_max") or 0,
            data.get("requirements", []),
            data.get("tech_stack", []),
        )

        merged_caveats = list(data.get("caveats", []))
        for caveat in extra_caveats:
            if caveat not in merged_caveats:
                merged_caveats.append(caveat)
        for caveat in specificity_caveats:
            if caveat not in merged_caveats:
                merged_caveats.append(caveat)
        for caveat in confidence_caveats:
            if caveat not in merged_caveats:
                merged_caveats.append(caveat)

        llm_remote = data.get("is_remote")
        if prefs.require_remote and llm_remote is False and loc_tier > 0:
            reason = "Remote-only search: LLM classified the role as non-remote."
            logger.info(
                f"[SCORE] POST-LLM REJECT | {raw.title} @ {raw.company} | {reason}"
            )
            return ScoringResult(passed_filter=False, rejection_reason=reason)

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
            caveats=merged_caveats,
            scoring_version="v2",
        )

        return ScoringResult(passed_filter=True, job=job)

    except Exception as e:
        logger.warning(
            f"[SCORE] LLM ERROR for {raw.title} @ {raw.company}: {type(e).__name__}: {e or '(empty)'} — using deterministic local fallback"
        )
        return _local_score_job(raw, prefs)


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
