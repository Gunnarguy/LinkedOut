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
    job_snapshot: str = ""  # Factual summary of what the job is (from listing)
    company_oneliner: str = ""  # One sentence: what the company actually does
    they_want: list[str] = Field(default_factory=list)  # What they're looking for (from listing)
    logic_fit: str = ""  # How the role maps to what Gunnar actually does
    domain_leverage: str = ""  # Where he has an unfair advantage
    risk_reward: str = ""  # Realistic friction and upside

    # ── Structured Scoring Factors (v2) ──────────────────────────────────
    domain_alignment: float = 0.0  # 0-1: company domain match
    role_alignment: float = 0.0  # 0-1: daily work match
    culture_fit: float = 0.0  # 0-1: company culture signals
    experience_friction: float = 0.0  # 0-1: inverted friction (1=no friction)
    stack_fit: float = 0.0  # 0-1: tech stack overlap
    caveats: list[str] = Field(default_factory=list)  # Factual friction points
    scoring_version: str = ""  # "v1" or "v2" — tracks which prompt scored this

    # ── User-Managed Fields (not from LLM) ───────────────────────────────
    notes: str = ""  # User's personal notes
    application_status: str = (
        "new"  # new, applied, phone_screen, interview, offer, rejected
    )

    # ── Notion Sync ──────────────────────────────────────────────────────
    notion_page_id: str = ""  # Notion page UUID for bidirectional sync

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
    job_data: JobPayload | None = None  # Backup payload if backend lost state


class JobActionResponse(BaseModel):
    job_id: str
    action: JobAction
    success: bool
    message: str = ""


# ── LinkedIn Profile Models ──────────────────────────────────────────────────


class LinkedInPosition(BaseModel):
    title: str = ""
    company_name: str = ""
    location: str = ""
    description: str = ""
    start_year: int | None = None
    start_month: int | None = None
    end_year: int | None = None
    end_month: int | None = None
    is_current: bool = False


class LinkedInEducation(BaseModel):
    school_name: str = ""
    degree: str = ""
    field_of_study: str = ""
    start_year: int | None = None
    end_year: int | None = None
    activities: str = ""
    grade: str = ""


class LinkedInCertification(BaseModel):
    name: str = ""
    authority: str = ""
    license_number: str = ""
    url: str = ""
    start_year: int | None = None
    end_year: int | None = None


class LinkedInProfile(BaseModel):
    person_id: str = ""
    first_name: str = ""
    last_name: str = ""
    headline: str = ""
    vanity_name: str = ""
    profile_picture_url: str = ""
    email: str = ""
    profile_url: str = ""
    verifications: list[str] = Field(default_factory=list)
    positions: list[LinkedInPosition] = Field(default_factory=list)
    education: list[LinkedInEducation] = Field(default_factory=list)
    skills: list[str] = Field(default_factory=list)
    certifications: list[LinkedInCertification] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)


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
    min_salary: int = 70000
    require_remote: bool = True
    preferred_roles: list[str] = Field(
        default_factory=lambda: [
            "Forward Deployed Engineer",
            "Forward-Deployed Engineer",
            "Solutions Engineer",
            "Technical Solutions Engineer",
            "Clinical Solutions Engineer",
            "Implementation Engineer",
            "Technical Implementation Engineer",
            "Customer Engineer",
            "Integration Engineer",
            "Workflow Engineer",
            "AI Product Engineer",
            "AI Product Builder",
            "Applied AI Engineer",
            "AI Prototyper",
            "Founding Engineer",
            "Product Engineer",
            "Prototype Engineer",
            "iOS Engineer",
            "iOS Developer",
            "SwiftUI Engineer",
            "Mobile Engineer",
            "Healthcare AI Engineer",
            "MedTech Engineer",
            "Clinical Software Engineer",
            "Digital Health Engineer",
            "Workflow Automation Engineer",
        ]
    )
    excluded_keywords: list[str] = Field(
        default_factory=lambda: [
            "Senior Engineer",
            "Senior Software Engineer",
            "Senior Backend Engineer",
            "Senior Platform Engineer",
            "Sr. Engineer",
            "Staff Engineer",
            "Principal Engineer",
            "Lead Engineer",
            "Lead Software Engineer",
            "Engineering Manager",
            "Director of Engineering",
            "Head of Engineering",
            "Architect",
            "LeetCode",
            "whiteboard",
            "competitive programming",
            "6+ years",
            "7+ years",
            "8+ years",
            "9+ years",
            "10+ years",
            "11+ years",
            "12+ years",
            "DevOps",
            "SRE",
            "Platform Engineer",
            "Infrastructure Engineer",
            "Site Reliability Engineer",
            "data structures and algorithms",
            "Shopify",
            "Magento",
            "WordPress",
            "PHP",
            "Ruby on Rails",
            ".NET",
            "C#",
            "IT Support",
            "Helpdesk",
            "SysAdmin",
            "QA Engineer",
            "SDET",
            "Penetration Testing",
            "Full-Stack Engineer",
            "Full Stack Engineer",
            "Full-Stack Software Engineer",
            "Full-Stack Developer",
            "Backend Engineer",
            "Backend Developer",
            "Machine Learning Engineer",
            "ML Engineer",
            "Cyber Security",
            "Cybersecurity",
            "Security Engineer",
            "Sales Engineer",
        ]
    )
    location_preference: str = "Remote"
    preferred_locations: list[str] = Field(
        default_factory=lambda: ["Campbell, California", "Palo Alto, California"]
    )

    @property
    def home_city(self) -> str:
        """Primary city for backward compat."""
        if self.preferred_locations:
            parts = self.preferred_locations[0].split(",", 1)
            return parts[0].strip()
        return "Campbell"

    @property
    def home_state(self) -> str:
        """Primary state for backward compat."""
        if self.preferred_locations:
            parts = self.preferred_locations[0].split(",", 1)
            return parts[1].strip() if len(parts) > 1 else ""
        return "California"

    # ── Scoring Weights (adjustable from app) ──
    score_cutoff: float = 0.58
    convincing_penalty: float = -0.20
    convincing_boost: float = 0.10
    nearby_penalty: float = -0.03
    nearby_penalty_mult: float = 0.97
    regional_penalty: float = -0.08
    regional_penalty_mult: float = 0.92
    relocation_penalty: float = -0.15
    relocation_penalty_mult: float = 0.85
    international_penalty: float = -0.25
    international_penalty_mult: float = 0.75
    experience_penalty: float = -0.10
    credential_penalty: float = -0.15
    portfolio_boost: float = 0.10
    max_seniority_level: str = "Mid"
    professional_profile: str = """### Target: High-Agency Product and Workflow Builder

Treat this candidate as a high-agency, AI-enabled product and workflow builder with real healthcare context, not as a conventional generic software engineer. Do not stretch into roles that only make sense if the candidate were already a traditional backend, infrastructure, security, or ML specialist.

### Current Role
- OnSite Specialist at Stryker embedded at VA Palo Alto supporting Stanford surgical teams since August 2022
- Strong healthcare workflow context, medical device troubleshooting, clinician support, training, HIPAA awareness, and government-site access

### Software Profile
- Solo iOS developer with 4 shipped App Store apps
- Strongest in SwiftUI, mobile product work, API integration, iteration speed, and turning ideas into working software
- Uses AI heavily as implementation leverage for prototyping, architecture iteration, and shipping complete products
- Comfortable with Python/FastAPI backends, RAG patterns, vector databases, Core ML, Docker, integrations, and workflow automation, but not as a generic backend or platform candidate

### Honest Boundaries
- No CS degree
- No 5-10 years of traditional professional software engineering experience
- Not a senior platform, backend, infrastructure, security, or ML specialist candidate
- Not a fit for quota-carrying pre-sales or sales-heavy solutions roles

### Target Lanes
- iOS or mobile product building
- Healthcare, clinical software, digital health, medtech, medical device, patient engagement, care navigation, provider workflow, or interoperability software
- Forward-deployed, solutions, implementation, customer engineering, integration, or workflow roles that are genuinely technical and close to users
- Applied-AI product builder or prototype roles where shipping, iteration, and problem-solving matter more than pedigree

### Matching Rule
Prioritize jobs where AI leverage, speed, user empathy, and workflow problem-solving are the job. Reject roles that expect a conventional software engineer first and only secondarily value builder instincts."""


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
