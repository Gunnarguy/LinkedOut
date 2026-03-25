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
            "Senior",
            "Sr.",
            "Sr ",
            "Staff Engineer",
            "Principal Engineer",
            "Lead Engineer",
            "Engineering Manager",
            "Director of Engineering",
            "VP of Engineering",
            "Head of Engineering",
            "Architect",
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
    score_cutoff: float = 0.40
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
    professional_profile: str = """### Background — Read This Carefully
You have ZERO professional software engineering experience. Your day job is OnSite Specialist at Stryker (VA Palo Alto Health Care System, since August 2022). You support Stanford surgical teams — setting up medical devices, troubleshooting equipment during live surgeries, training staff. You hold Government Contractor PIV clearance. You have witnessed 1,000+ surgeries.

Your education is a B.S. in Exercise Science (Kinesiology). No CS degree.

Outside of work, you are a self-taught solo iOS developer with 4 apps on the App Store. All projects are personal — none were built for an employer. You use AI tools (Claude, GPT, Gemini) to help you build.

### Shipped Personal Projects (gunnarguy.me)
- **OpenIntelligence**: On-device RAG engine — 102 services, 29-step pipeline, hybrid search, Core ML, runs offline. Live on App Store Jan 2026.
- **OpenResponses**: OpenAI Responses API client — MCP integration, 15+ models, 43+ file formats. Live on App Store Jan 2026.
- **OpenCone**: Pinecone vector DB RAG app — hybrid search, reranking, document ingestion. Live on App Store May 2025.
- **OpenAssistant**: OpenAI Assistants API v2 client — threads, runs, vector stores, Code Interpreter. Live on App Store Oct 2024.
- **LinkedOut**: Full-stack job matching app — SwiftUI + FastAPI + Docker.
- **PlaudBlender**: Voice recordings → knowledge graph — Python, Gemini, Qdrant, Dash UI.
- 824 total commits, 697 in the last year.

### Technical Skills (from resume)
- **Mobile**: SwiftUI, Swift, MVVM, Combine, URLSession, XCTest, Core ML, Metal, SQLite, PDFKit, Vision
- **Languages**: Swift, Python, HTML, CSS
- **Backend**: RESTful APIs, JSON, Docker, MCP Servers, Async/Await, SSE
- **AI/ML**: RAG Architecture, Vector DBs (Pinecone/Qdrant), LLM Integration (OpenAI), Embeddings, On-Device ML
- **Healthcare**: HIPAA Compliance, Clinical Workflows, Medical Device Support, PIV Clearance
- **NOT in your stack**: React, Vue, Angular, Java, Go, Rust, C++, Kubernetes, TypeScript, Node.js

### Experience Level — CRITICAL
You are an ENTRY-LEVEL / JUNIOR software engineering candidate. Your portfolio is impressive for a self-taught developer, but:
- You have never held a software engineering job title
- You have never worked on a software team
- You have never done code reviews, sprint planning, or agile ceremonies professionally
- You have never shipped software for an employer
- All your projects are solo personal projects

Do NOT match you with Senior, Staff, Lead, or Principal roles. These require years of professional engineering experience you do not have. Even 'Mid-level' is a stretch — you should target Junior, Entry-Level, Associate, or roles that explicitly say 'no experience required' or 'portfolio over resume.'

### What You Want
- Entry-level or junior roles where your personal projects and healthcare domain knowledge give you an edge
- Companies that value what you've built over credentials and job titles
- HealthTech, MedTech, Clinical AI, AI tooling, iOS — places where your O.R. background is an unfair advantage
- Startups that judge by shipped work, not years of professional experience"""


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
