from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


# ── The Immutable Data Contract ──────────────────────────────────────────────


class JobPayload(BaseModel):
    """Shared contract between Python backend and Swift client."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    company_name: str
    role_title: str
    salary_floor: int
    is_remote: bool
    builder_score: float = Field(ge=0.0, le=1.0)
    ai_pitch_summary: str  # 3 bullet points
    drafted_cover_letter: str
    source_url: str
    posted_at: datetime | None = None
    location: str = ""
    tags: list[str] = Field(default_factory=list)

    # ── Rich Company Intelligence (LLM-extracted) ────────────────────────
    description: str = ""  # Full original job description (preserved)
    company_description: str = ""  # What the company does / mission
    company_size: str = ""  # e.g. "10-50", "50-200", "500+"
    company_stage: str = ""  # e.g. "Seed", "Series A", "Series B", "Public"
    company_url: str = ""  # Company website
    salary_max: int = 0  # Upper end of range (0 = unknown)
    requirements: list[str] = Field(default_factory=list)  # Key requirements
    nice_to_haves: list[str] = Field(
        default_factory=list
    )  # Nice-to-have qualifications
    tech_stack: list[str] = Field(default_factory=list)  # Technologies mentioned
    why_interesting: str = ""  # AI analysis: why this fits the user
    red_flags: list[str] = Field(default_factory=list)  # Potential concerns
    apply_url: str = ""  # Direct application link (if different from source)
    experience_level: str = ""  # "Entry", "Junior", "Mid", "Senior" etc.
    job_type: str = ""  # "Full-time", "Contract", "Part-time", "Internship"
    benefits: list[str] = Field(default_factory=list)  # Perks/benefits mentioned
    fit_reasons: list[str] = Field(
        default_factory=list
    )  # Why this fits the user (short badge-style reasons)
    dealbreaker_warnings: list[str] = Field(
        default_factory=list
    )  # Honest warnings about why this role might reject the user

    # ── Why Matrix (structured factual assessment) ───────────────────────
    logic_fit: str = ""  # How the role maps to what Gunnar actually does
    domain_leverage: str = ""  # Where he has an unfair advantage
    risk_reward: str = ""  # Realistic friction and upside

    # ── User-Managed Fields (not from LLM) ───────────────────────────────
    notes: str = ""  # User's personal notes
    application_status: str = (
        "new"  # new, applied, phone_screen, interview, offer, rejected
    )

    def model_dump(self, **kwargs):
        """Override to serialize datetime as ISO 8601 consistently."""
        data = super().model_dump(**kwargs)
        if data.get("posted_at") and isinstance(data["posted_at"], datetime):
            data["posted_at"] = data["posted_at"].isoformat()
        return data


class JobAction(str, Enum):
    apply = "apply"
    reject = "reject"
    save = "save"


class JobActionRequest(BaseModel):
    job_id: str
    action: JobAction


class JobActionResponse(BaseModel):
    job_id: str
    action: JobAction
    success: bool
    message: str = ""


# ── LinkedIn Profile Models ──────────────────────────────────────────────────


class LinkedInProfile(BaseModel):
    person_id: str = ""
    first_name: str = ""
    last_name: str = ""
    headline: str = ""
    vanity_name: str = ""
    profile_picture_url: str = ""
    email: str = ""


# ── Auth Models ──────────────────────────────────────────────────────────────


class OAuthTokenResponse(BaseModel):
    access_token: str
    expires_in: int
    refresh_token: str = ""
    refresh_token_expires_in: int = 0
    scope: str = ""


class AuthSession(BaseModel):
    linkedin_access_token: str
    linkedin_refresh_token: str = ""
    profile: LinkedInProfile
    expires_at: datetime


class LoginURLResponse(BaseModel):
    authorization_url: str
    state: str


class TokenExchangeRequest(BaseModel):
    code: str
    state: str


class AuthStatusResponse(BaseModel):
    authenticated: bool
    profile: LinkedInProfile | None = None


# ── User Preferences ────────────────────────────────────────────────────────


class UserPreferences(BaseModel):
    min_salary: int = 90000
    require_remote: bool = False
    preferred_roles: list[str] = Field(
        default_factory=lambda: [
            "AI Engineer",
            "AI Product Engineer",
            "Founding Engineer",
            "Product Engineer",
            "iOS Engineer",
            "Mobile Engineer",
            "Machine Learning Engineer",
            "Software Engineer",
            "Full Stack Engineer",
            "Developer Experience Engineer",
            "Applied AI Engineer",
        ]
    )
    excluded_keywords: list[str] = Field(
        default_factory=lambda: [
            "Staff Engineer",
            "Principal Engineer",
            "Engineering Manager",
            "Director of Engineering",
        ]
    )
    location_preference: str = "Remote"
    home_city: str = "Kalamazoo"
    home_state: str = "Michigan"

    # ── Scoring Weights (adjustable from app) ──
    score_cutoff: float = 0.35
    convincing_penalty: float = -0.20
    convincing_boost: float = 0.10
    nearby_penalty: float = -0.03
    regional_penalty: float = -0.08
    relocation_penalty: float = -0.15
    international_penalty: float = -0.25
    experience_penalty: float = -0.10
    credential_penalty: float = -0.15
    portfolio_boost: float = 0.10
    max_seniority_level: str = "Mid"


# ── Batch / Pipeline ────────────────────────────────────────────────────────


class RawJobListing(BaseModel):
    """Incoming raw job data before LLM scoring."""

    title: str
    company: str
    description: str
    url: str
    salary_text: str = ""
    location: str = ""
    is_remote: bool | None = None


class ScoringResult(BaseModel):
    passed_filter: bool
    job: JobPayload | None = None
    rejection_reason: str = ""


# ── Job Update Models ───────────────────────────────────────────────────────


class JobNotesUpdate(BaseModel):
    notes: str


class JobStatusUpdate(BaseModel):
    status: str  # new, applied, phone_screen, interview, offer, rejected
