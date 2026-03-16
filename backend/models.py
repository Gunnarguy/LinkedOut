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
            "Applied AI Engineer",
            "Founding Engineer",
            "Product Engineer",
            "iOS Engineer",
            "Mobile Engineer",
            "Machine Learning Engineer",
            "Software Engineer",
            "Full Stack Engineer",
            "Developer Experience Engineer",
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
    professional_profile: str = """### Classification: AI-Native Builder
You do not hand-write code. You orchestrate AI agents (Claude, GPT, Gemini) to
architect and generate entire systems. You see a problem, figure out how it should
work, and don't stop until it ships. The code comes from models — the vision,
architecture, and relentless iteration are yours. You do this because you can,
because it's genuinely fun, and because you want to make money doing it.

### Shipped Portfolio (all live — gunnarguy.me)
- **OpenIntelligence**: On-device RAG engine — 102 services, 29-step pipeline,
  hybrid search, Core ML embeddings, Apple Intelligence, runs in airplane mode.
  202 commits.
- **OpenResponses**: OpenAI Responses API client — MCP integration (Notion,
  Dropbox, Gmail), Computer Use, 15+ models, tool orchestration. 88 commits.
  First App Store submission passed review.
- **OpenCone**: Pinecone vector DB RAG app — hybrid search, reranking, document
  ingestion with SHA256 dedup, circuit breaker resilience. 122 commits.
- **OpenAssistant**: Assistants API client — threads, runs, vector stores,
  Code Interpreter, File Search. 214 commits.
- **LinkedOut**: Full-stack AI matching platform — SwiftUI + FastAPI + Docker +
  LLM scoring from 5 job sources. 62 commits and growing.
- **PlaudBlender**: Voice recordings → knowledge graph — Gemini AI, Qdrant
  vector DB, 11-tool MCP server, 91 tests. 70 commits.
- 758 all-time commits, 638 in the last year, 4 apps on the App Store.

### Technical Reality
- **Built with**: Swift/SwiftUI, Python/FastAPI, RAG pipelines, vector databases
  (Pinecone, Qdrant), LLM orchestration (OpenAI, Gemini, Anthropic), on-device ML
  (Core ML, Metal GPU), MCP servers, Docker, API integrations
- **Haven't used professionally**: React, Vue, Angular, Flutter, Java, Go, Rust,
  C++, Ruby on Rails, .NET, Kubernetes at scale
- **No CS degree (B.S. Kinesiology). No professional software engineering experience.**
- 4 published App Store apps and 6 GitHub repos IS the experience. Period.

### Day Job
Medical device specialist at VA Palo Alto (Stryker OnSite). Sole technical specialist
supporting Stanford surgical teams — Cardiothoracic, Vascular, General, Urology, ENT,
Thoracic. Complete autonomy. HIPAA, PIV clearance, regulated environment expertise.

### What You Want
Roles where shipped products matter more than credentials. Companies that look at
gunnarguy.me and say "get this person an interview" — not "where's the CS degree?"
Specifically:
- Roles that explicitly say "no CS degree required" or "equivalent experience accepted"
- Companies that value builders, shippers, and portfolio over pedigree
- AI/ML, iOS, product engineering, healthtech, developer tools
- Startups and small teams where what you've built speaks for itself
- Roles where your AI-native workflow IS the job (AI engineering, LLM tooling, etc.)

You are NOT looking for roles that require traditional credentials with no flexibility.
If they hard-require a CS degree with no "or equivalent" — that's a hard no, move on."""


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
