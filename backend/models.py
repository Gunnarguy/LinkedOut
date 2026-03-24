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
    min_salary: int = 90000
    require_remote: bool = False
    preferred_roles: list[str] = Field(
        default_factory=lambda: [
            "AI Engineer",
            "AI Product Engineer",
            "Applied AI Engineer",
            "AI Solutions Engineer",
            "Founding Engineer",
            "Product Engineer",
            "iOS Engineer",
            "Mobile Engineer",
            "Healthcare AI Engineer",
            "MedTech Engineer",
            "Clinical Software Engineer",
            "Digital Health Engineer",
            "Generative AI Engineer",
            "LLM Engineer",
            "Prompt Engineer",
        ]
    )
    excluded_keywords: list[str] = Field(
        default_factory=lambda: [
            "Staff Engineer",
            "Principal Engineer",
            "Engineering Manager",
            "Director of Engineering",
            "LeetCode",
            "whiteboard",
            "competitive programming",
            "10+ years",
            "DevOps",
            "SRE",
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
        ]
    )
    location_preference: str = "Remote"
    preferred_locations: list[str] = Field(
        default_factory=lambda: ["Kalamazoo, Michigan"]
    )

    @property
    def home_city(self) -> str:
        """Primary city for backward compat."""
        if self.preferred_locations:
            parts = self.preferred_locations[0].split(",", 1)
            return parts[0].strip()
        return "Kalamazoo"

    @property
    def home_state(self) -> str:
        """Primary state for backward compat."""
        if self.preferred_locations:
            parts = self.preferred_locations[0].split(",", 1)
            return parts[1].strip() if len(parts) > 1 else ""
        return "Michigan"

    # ── Scoring Weights (adjustable from app) ──
    score_cutoff: float = 0.50
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
    professional_profile: str = """### Classification: AI Orchestrator & MedTech Bridge Builder
You are the bridge between AI orchestration, prompt-to-production app building, and complex healthcare/medical device workflows.
You don't type code by hand. You orchestrate AI agents (Claude, GPT, Gemini) to architect, generate, and ship entire systems at extreme velocity. You see a problem, figure out how it should work, and don't stop until it's a shipped product.

### Core Focus & Superpowers
- **Healthcare/Medical Device/MedTech**: You work full-time at VA Palo Alto (Stryker) supporting Stanford surgical teams in high-pressure O.R. environments. You understand HIPAA, PIV clearance, clinical ops, and exactly how medical devices interact with surgeons and patient care.
- **Prompt-to-Production Velocity**: You use AI to execute your product vision from zero to App Store. Your workflow isn't 'using Copilot to write a function' — it's orchestrating entire multi-agent pipelines to build complex RAG engines.
- **iOS/Apple Ecosystem**: You focus on iOS (SwiftUI) because it's frictionless to build, test on-device, and deploy into the Apple ecosystem.

### Shipped Portfolio of Proof (gunnarguy.me)
- **OpenIntelligence**: On-device RAG engine — 102 services, 29-step pipeline, hybrid search, Core ML embeddings, Apple Intelligence, runs in airplane mode. 202 commits.
- **OpenResponses**: OpenAI Responses API client — MCP integration (Notion, Dropbox, Gmail), Computer Use, 15+ models. Passed App Store review instantly. 88 commits.
- **OpenCone**: Pinecone vector DB RAG app — hybrid search, reranking, document ingestion. 122 commits.
- **OpenAssistant**: Assistants API client — threads, runs, vector stores, Code Interpreter. 214 commits.
- **LinkedOut**: Full-stack AI matching platform — SwiftUI + FastAPI + Docker. Full job scoring pipeline.
- **PlaudBlender**: Voice recordings → knowledge graph — Python, Gemini AI, Qdrant, Dash UI, 11-tool MCP server.
- **Velocity Tracker**: 824 all-time commits, 697 in the last year, 4 live App Store apps.

### Technical Reality
- **Built with**: Swift/SwiftUI, Python/FastAPI, RAG pipelines, vector databases (Pinecone, Qdrant), LLM orchestration, on-device ML (Core ML, Metal GPU), MCP servers, Docker.
- **Haven't used professionally**: React, Vue, Angular, Java, Go, Rust, C++, Kubernetes at scale.
- **Credentials**: B.S. Kinesiology. No traditional CS degree. Your portfolio of deployed applications IS your equivalent experience. Period.

### What You Want
- You are willing to do whatever it takes, provided the role aligns with building real solutions.
- You want to match company mottos, missions, and job requirements directly to your prompt-to-production capability.
- Ideal targets: HealthTech, MedTech, Clinical AI, AI Orchestration, iOS/mobile apps. Roles where they value your clinical domain expertise combined with insane shipping velocity."""


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
