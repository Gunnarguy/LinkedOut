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
    require_remote: bool = True
    preferred_roles: list[str] = Field(
        default_factory=lambda: [
            "AI Product Engineer",
            "AI Engineer",
            "Founding Engineer",
            "Product Engineer",
            "iOS Engineer",
            "Machine Learning Engineer",
        ]
    )
    excluded_keywords: list[str] = Field(
        default_factory=lambda: [
            "LeetCode",
            "whiteboard",
            "competitive programming",
            "10+ years",
            "Staff Engineer",
            "Principal Engineer",
            "DevOps",
            "SRE",
        ]
    )
    location_preference: str = "Remote"


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
