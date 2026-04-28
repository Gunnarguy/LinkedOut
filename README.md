# LinkedOut

**Tinder for jobs** — an AI-powered job discovery app that fetches listings from 5 remote job boards, scores them with LLMs against your profile, and lets you swipe through the best matches on iOS.

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-iOS_17+-blue?logo=swift" />
  <img src="https://img.shields.io/badge/FastAPI-Python_3.12-green?logo=fastapi" />
  <img src="https://img.shields.io/badge/LLM-Gemini_%7C_OpenAI-orange" />
  <img src="https://img.shields.io/badge/Deploy-Render-purple?logo=render" />
</p>

---

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────┐
│  5 Job APIs  │────▶│  Dedup +     │────▶│  LLM Scoring │────▶│  iOS App  │
│  (Remotive,  │     │  Ingest      │     │  (Gemini /   │     │  Swipe UI │
│  Himalayas,  │     │  Pipeline    │     │  OpenAI /    │     │  + Map    │
│  HN, Jobicy, │     │              │     │  Fallback)   │     │           │
│  RemoteOK)   │     └──────────────┘     └──────────────┘     └───────────┘
└─────────────┘
```

1. **Fetch** — Backend pulls listings from 5 remote job boards on a timer (or manual trigger)
2. **Deduplicate** — 3-layer URL dedup prevents the same listing from appearing twice
3. **Score** — Each listing is run through an LLM scoring pipeline with anti-sycophancy prompts, the Why Matrix, and configurable penalty/boost weights
4. **Discover** — iOS app presents scored jobs as swipeable cards. Swipe right to apply, left to reject, up to save for later
5. **Track** — Applied and saved jobs live in separate lists with notes and status tracking

---

## Table of Contents

- [LinkedOut](#linkedout)
  - [How It Works](#how-it-works)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Architecture](#architecture)
    - [Tech Stack](#tech-stack)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Local Development (Docker)](#local-development-docker)
    - [Deploy to Raspberry Pi (Tailscale)](#deploy-to-raspberry-pi-tailscale)
    - [Deploy to Render](#deploy-to-render)
    - [iOS App Setup](#ios-app-setup)
  - [Configuration](#configuration)
    - [Environment Variables](#environment-variables)
    - [Scoring Weights \& Presets](#scoring-weights--presets)
  - [Scoring Engine](#scoring-engine)
    - [Two-Tier Pipeline](#two-tier-pipeline)
    - [The Why Matrix](#the-why-matrix)
    - [Score Calibration](#score-calibration)
    - [Penalties \& Boosts](#penalties--boosts)
    - [LLM Fallback Chain](#llm-fallback-chain)
  - [Job Sources](#job-sources)
    - [Deduplication](#deduplication)
  - [Location Intelligence](#location-intelligence)
  - [iOS App](#ios-app)
    - [Tabs](#tabs)
    - [Swipe Mechanics](#swipe-mechanics)
    - [Server Discovery](#server-discovery)
    - [Settings](#settings)
  - [API Reference](#api-reference)
    - [Health](#health)
    - [Authentication](#authentication)
    - [Profile](#profile)
    - [Jobs](#jobs)
    - [Scoring \& Ingestion](#scoring--ingestion)
    - [Preferences](#preferences)
    - [LinkedIn Social](#linkedin-social)
    - [Notion Sync](#notion-sync)
    - [Telemetry](#telemetry)
    - [Development (debug mode only)](#development-debug-mode-only)
  - [Data Models](#data-models)
    - [JobPayload](#jobpayload)
    - [UserPreferences](#userpreferences)
  - [Project Structure](#project-structure)
  - [License](#license)

---

## Features

- **5 job sources** aggregated and deduplicated (Remotive, Himalayas, HN Who's Hiring, Jobicy, RemoteOK)
- **LLM-powered scoring** with Gemini Flash triage + Gemini Pro full analysis, OpenAI fallback
- **Dynamic AI Candidate Persona** — edit your professional profile in the iOS app to reshape the AI evaluation prompt and re-score all pending jobs instantly
- **Session persistence** — OAuth sessions survive Docker rebuilds; iOS auto-restores cached profile to the backend seamlessly
- **Embedded MCP Server** — includes an internal FastMCP server connecting your LinkedIn profile and Job Pipeline state directly to Claude Desktop
- **Notion sync** — bidirectional sync with a Notion database (push jobs, pull status changes, runtime config from iOS)
- **Why Matrix** — structured `logic_fit`, `domain_leverage`, `risk_reward` assessment for every job
- **Tinder-style swipe UI** — swipe right (apply), left (reject), up (save), with undo
- **List/card toggle** — switch between swipe cards and a scrollable list with enriched job rows (score ring, tags, tech stack, fit reasons, red flags, AI pitch)
- **Interactive map view** — all jobs plotted on Apple Maps with color-coded score pins
- **Unified "You" hub** — tappable pipeline dashboard (In Queue, Applied, Saved, Passed) that navigates directly to each job list
- **Configurable scoring weights** — 3 presets (Relaxed/Balanced/Strict) + per-slider fine-tuning with real-time sync indicators
- **Multi-location preferences** — score jobs against multiple preferred cities
- **LinkedIn OAuth** — authenticate and share applications to your LinkedIn profile
- **Application tracking** — notes, status pipeline (new → applied → phone screen → interview → offer)
- **Auto server discovery** — iOS app keeps the selected backend if healthy, then falls back across Raspberry Pi over Tailscale, local Docker, and Render
- **3-layer URL dedup** — fetch-time, ingest-time, and store-time protection against duplicates
- **Concurrency-safe ingest** — `asyncio.Lock` prevents overlapping periodic and manual ingest cycles
- **Smart content-aware pruner** — 3-tier job freshness system: HTTP HEAD checks, page content scanning for "position filled" signals, and HN thread analysis via Algolia API + Gemini Flash LLM judge
- **3 sort modes** — Best Match (score), Newest (date), Highest Pay (salary) with deterministic multi-key tiebreakers
- **Auto-paginating fetch** — iOS fetches jobs in 100-item pages, works with any backend limit
- **Job eviction protection** — high-salience jobs (score ≥ 0.60) never expire, extended 30-day TTL, seen URLs as timestamped dict with 30-day expiry

---

## Architecture

```
LinkedOut/
├── backend/               # FastAPI Python backend
│   ├── main.py            # API endpoints + ingest orchestration
│   ├── scoring_engine.py  # LLM scoring pipeline (Gemini/OpenAI/local)
│   ├── job_fetcher.py     # 5 async job source fetchers
│   ├── job_store.py       # JSON file-backed persistent store + dedup
│   ├── location_mapper.py # 5-tier location classification
│   ├── models.py          # Pydantic models (JobPayload, UserPreferences, etc.)
│   ├── config.py          # pydantic-settings environment config
│   ├── linkedin_api.py    # LinkedIn API client (profile, sharing)
│   ├── linkedin_oauth.py  # OAuth 2.0 flow + session persistence
│   ├── notion_sync.py     # Bidirectional Notion database sync
│   ├── mcp_server.py      # FastMCP server for Claude Desktop
│   ├── Dockerfile         # Python 3.12-slim + uvicorn
│   └── requirements.txt   # Dependencies
├── LinkedOut/             # SwiftUI iOS app
│   ├── LinkedOutApp.swift # App entry point (@main)
│   ├── ContentView.swift  # Auth-gated root view
│   ├── Models/            # Codable structs matching backend
│   ├── ViewModels/        # AuthViewModel, JobsViewModel
│   ├── Views/             # All SwiftUI views (22 files)
│   ├── Network/           # APIClient (actor), ServerDiscovery
│   └── Utils/             # ScoreRing, SwipeHintOverlay, LocationGeocoder, ApplicationTracker
├── LinkedOut.xcodeproj/   # Xcode project
├── docker-compose.yml     # Local dev: port 8443, volume mount
├── render.yaml            # Render Blueprint (one-click deploy)
└── docs/                  # LinkedIn API reference docs
```

### Tech Stack

| Layer           | Technology                                                                        |
| --------------- | --------------------------------------------------------------------------------- |
| **iOS App**     | SwiftUI, iOS 26.2+, MapKit, WebKit, Foundation Models                             |
| **Backend**     | FastAPI, Python 3.12, Pydantic v2, uvicorn                                        |
| **LLM Scoring** | Google Gemini (primary), OpenAI (fallback)                                        |
| **Job APIs**    | Remotive, Himalayas, HN Algolia, Jobicy, RemoteOK                                 |
| **Auth**        | LinkedIn OAuth 2.0                                                                |
| **Storage**     | JSON file-backed (job_store.json, seen_urls.json, user_prefs.json, sessions.json) |
| **Deployment**  | Docker on Raspberry Pi via Tailscale or Render                                    |

---

## Getting Started

### Prerequisites

- **Xcode 26+** (for iOS app)
- **Docker** (for backend)
- **API Keys**: At least one of Google Gemini or OpenAI
- **LinkedIn Developer App** (optional, for OAuth)

### Local Development (Docker)

```bash
# 1. Clone
git clone https://github.com/Gunnarguy/LinkedOut.git
cd LinkedOut

# 2. Configure environment
cp backend/.env.example backend/.env
# Edit backend/.env with your API keys

# 3. Build and run
docker compose up --build -d

# 4. Verify
curl http://localhost:8443/health
# → {"status": "ok", "store": {"pending": 0, ...}}

# 5. Trigger first job ingest
curl -X POST http://localhost:8443/api/ingest/refresh
```

The backend runs on **port 8443** with job data persisted to `./data/`.

### Deploy to Raspberry Pi (Tailscale)

If you want the backend off your Mac entirely, this repo includes a Pi deploy script that syncs the backend to a Tailscale-reachable Raspberry Pi and starts Docker there.

```bash
# First deploy or normal code update
./deploy-to-pi.sh

# Intentionally overwrite the Pi's env or persisted data from your local copy
./deploy-to-pi.sh --sync-env --sync-data
```

What it does:

- Syncs `backend/` and `docker-compose.yml` to `~/linkedout` on the Pi
- Preserves the Pi's live `data/` and `backend/.env` by default
- Seeds `data/` and `backend/.env` automatically if the Pi copy does not exist yet
- Rebuilds and restarts the backend with `docker compose up --build -d`
- Verifies health both on the Pi and through the Pi's Tailscale MagicDNS URL

Operational notes:

- The Pi backend URL is `http://gunzino.taildb93d4.ts.net:8443`
- iPhone and iPad clients need Tailscale enabled to reach the Pi backend directly
- Tailscale `Serve` is optional. If it is disabled, the app still works over raw tailnet HTTP
- Keep `LINKEDIN_REDIRECT_URI` pointed at a stable HTTPS callback registered in LinkedIn unless you later add a Pi-side HTTPS front door

### Deploy to Render

1. Fork this repo
2. Connect to [Render](https://render.com) → **New Blueprint Instance** → select your fork
3. Set secret environment variables in the Render dashboard:
   - `LINKEDIN_CLIENT_ID`
   - `LINKEDIN_CLIENT_SECRET`
   - `GEMINI_API_KEY`
   - `OPENAI_API_KEY` (optional fallback)
4. Deploy — Render uses `render.yaml` to configure everything else

> **Note:** Render's free tier uses an ephemeral disk. Job data persists in memory during uptime but resets on redeploy. The 3-layer dedup system handles this gracefully.

### iOS App Setup

1. Open `LinkedOut.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a simulator or device (iOS 26.2+)
4. The app auto-discovers the backend via `ServerDiscovery`:

- Keeps the current backend if it is still healthy
- Falls back to Raspberry Pi over Tailscale → local Docker → Render
- Caches the result for 5 minutes
- Re-discovers on network errors

---

## MCP Server Integration

LinkedOut includes a **FastMCP** server that exposes your job pipeline and LinkedIn OAuth session directly to Claude Desktop (or other MCP-compatible clients). This creates a dedicated AI agent capable of reviewing pending jobs, posting to LinkedIn, returning personal insights, and triggering ingest workflows.

### Claude Desktop Setup

Add the following to your Claude Desktop `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "linkedout": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "linkedout-backend-1",
        "python",
        "-m",
        "mcp_server"
      ]
    }
  }
}
```

_Note: Adjust `linkedout-backend-1` if your Docker container is named differently. Command assumes you are running docker via `docker compose up` in the LinkedOut directory._

Available Tools:

- `get_linkedin_auth_status` / `get_my_linkedin_profile`
- `post_linkedin_update`
- `get_linkedout_pipeline_stats`
- `query_pending_jobs` / `get_job_details` / `action_job`
- `trigger_linkedout_ingest`
- `get_saved_jobs_to_share`

---

## Configuration

### Environment Variables

Create `backend/.env` from the example template. All variables with defaults are optional.

| Variable                 | Required   | Default                          | Description                           |
| ------------------------ | ---------- | -------------------------------- | ------------------------------------- |
| `LINKEDIN_CLIENT_ID`     | For OAuth  | `""`                             | LinkedIn app client ID                |
| `LINKEDIN_CLIENT_SECRET` | For OAuth  | `""`                             | LinkedIn app secret                   |
| `LINKEDIN_REDIRECT_URI`  | For OAuth  | Render callback URL              | OAuth redirect URI                    |
| `LLM_PROVIDER`           | No         | `gemini`                         | Primary LLM: `"gemini"` or `"openai"` |
| `GEMINI_API_KEY`         | For Gemini | `""`                             | Google Gemini API key                 |
| `GEMINI_MODEL`           | No         | `gemini-3.1-pro-preview`         | Full scoring model                    |
| `GEMINI_FLASH_MODEL`     | No         | `gemini-3-flash-preview`         | Triage (fast) model                   |
| `OPENAI_API_KEY`         | For OpenAI | `""`                             | OpenAI API key                        |
| `OPENAI_MODEL`           | No         | `gpt-5.4`                        | OpenAI model name                     |
| `SECRET_KEY`             | No         | Auto-generated                   | Token signing key                     |
| `MIN_SALARY`             | No         | `90000`                          | Minimum salary filter                 |
| `REQUIRE_REMOTE`         | No         | `true`                           | Remote-only filter                    |
| `DEBUG`                  | No         | `true` (local), `false` (Render) | Enable dev endpoints                  |

### Scoring Weights & Presets

Weights are configurable from the iOS Settings tab or via `PUT /api/preferences`. Three presets ship out of the box:

| Weight                       | Relaxed 🌊 | Balanced ⚖️ | Strict 🎯 |
| ---------------------------- | ---------- | ----------- | --------- |
| **Score cutoff**             | 0.20       | 0.35        | 0.50      |
| **Stack mismatch**           | –0.10      | –0.20       | –0.35     |
| **"Builders welcome" boost** | +0.15      | +0.10       | +0.05     |
| **Portfolio-first boost**    | +0.15      | +0.10       | +0.05     |
| **Nearby penalty**           | –0.01      | –0.03       | –0.05     |
| **Regional penalty**         | –0.03      | –0.08       | –0.15     |
| **Relocation penalty**       | –0.05      | –0.15       | –0.25     |
| **International penalty**    | –0.10      | –0.25       | –0.35     |
| **Experience penalty**       | –0.05      | –0.10       | –0.20     |
| **Credential penalty**       | –0.05      | –0.15       | –0.25     |

---

## Scoring Engine

### Two-Tier Pipeline

Every raw listing goes through two stages:

1. **Triage** (Gemini Flash, fast) — Quick pass/fail filter. ~40% of listings survive. Rejects obvious mismatches (wrong seniority, irrelevant domain, hard credential gates) before spending tokens on full analysis.

2. **Full Scoring** (Gemini Pro) — Deep analysis producing the Why Matrix, score, cover letter draft, company intel, red flags, and fit reasons. Temperature **0.3** for factual consistency. Prompts use second-person voice ("your skills", "you built") and cover letter drafts avoid corporate filler — confident peer tone, no "excited/thrilled/passionate".

### The Why Matrix

Every scored job gets four structured fields:

| Field                 | Purpose                                                                           | Length        |
| --------------------- | --------------------------------------------------------------------------------- | ------------- |
| **`logic_fit`**       | How the role's day-to-day maps to what you actually do                            | 2–3 sentences |
| **`domain_leverage`** | Where you have an unfair advantage over typical applicants                        | 2–3 sentences |
| **`risk_reward`**     | Realistic friction and upside                                                     | 2–3 sentences |
| **`red_flags`**       | Every job has at least one. Hard requirements, vague products, credential signals | 1–5 bullets   |

### Score Calibration

Scores are calibrated to a realistic distribution, not inflated:

| Range            | % of Jobs | Meaning                                                                                 |
| ---------------- | --------- | --------------------------------------------------------------------------------------- |
| **0.85–1.00**    | ~5%       | Listing practically describes you. Company explicitly values portfolio over credentials |
| **0.70–0.84**    | ~15%      | Strong alignment, minimal convincing needed                                             |
| **0.55–0.69**    | ~30%      | Decent opportunity with real friction. Interesting but unclear fit                      |
| **0.40–0.54**    | ~30%      | Significant convincing required. Stack or experience gaps                               |
| **Below cutoff** | ~20%      | Rejected. Enterprise, legacy, rigid HR, hard degree requirements                        |

**Anchor score: 0.55** — A job with interesting mission and AI relevance but no explicit portfolio signal.

**Score deflation**: `if raw_score > 0.55: deflated = 0.55 + (raw_score - 0.55) * 0.78`

### Penalties & Boosts

Applied on top of the base LLM assessment:

**Location** (relative to preferred locations):

- Remote / in preferred city: +0
- Nearby (same state, ~1–2hr drive): `nearby_penalty`
- Regional (neighboring state): `regional_penalty`
- Full US relocation: `relocation_penalty`
- International: `international_penalty`

**Stack Friction** — the decisive factor:

- Hard requirement in unfamiliar stack: `convincing_penalty`
- "Any modern framework" / "we value builders": `convincing_boost`
- Explicitly values shipped products / portfolio-first: `portfolio_boost`

**Experience Reality**:

- "1–3 years" or "any": +0
- "5+ years" with flexibility: `experience_penalty`
- Known elite/selective (FAANG, Jane Street): `credential_penalty`

**Industry Multiplier**:

- HealthTech / MedTech / Clinical AI: +0.08 (domain differentiator)
- Developer/AI tools: +0.05

### LLM Fallback Chain

When the primary LLM is rate-limited or unavailable:

```
Gemini Flash (Triage) → Gemini Pro (Deep Score) → OpenAI GPT (Fallback)
```

The system uses Gemini Flash 2.5 for rapid discard of poor-fitting jobs, preserving longer latency Gemini Pro context windows strictly for legitimate potential matches.

---

## Job Sources

Five remote job boards are fetched asynchronously and deduplicated:

| Source              | API                             | What It Provides                      | Queries                                                                               |
| ------------------- | ------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------- |
| **Remotive**        | `remotive.com/api/remote-jobs`  | Remote-first jobs                     | 8 search queries (AI engineer, founding engineer, iOS engineer, etc.)                 |
| **Himalayas**       | `himalayas.app/jobs/api`        | Remote-first jobs                     | 6 search queries                                                                      |
| **HN Who's Hiring** | `hn.algolia.com/api/v1`         | Monthly hiring threads on Hacker News | Finds latest thread → fetches up to 300 comments → filters by AI/product/iOS keywords |
| **Jobicy**          | `jobicy.com/api/v2/remote-jobs` | Remote jobs by tag                    | 7 tags (ai, python, javascript, ios, react, devops, data-science)                     |
| **RemoteOK**        | `remoteok.com/api`              | Remote jobs aggregator                | Top 100 listings                                                                      |

### Deduplication

Three layers prevent duplicate jobs:

1. **Fetch-time**: `fetch_all_sources()` deduplicates by URL and by company+title across all sources
2. **Ingest-time**: `_run_ingest_cycle()` checks both `seen_urls` (persisted) and `store.has_url()` (in-memory index across all buckets), plus within-batch dedup
3. **Store-time**: `add_pending()` refuses any URL already present in any bucket (pending, applied, saved, rejected). On startup, `_dedup_on_load()` cleans any existing duplicates

---

## Job Freshness & Smart Pruning

A background task runs every **2 hours** to check whether pending jobs are still live. The pruner uses a conservative 3-tier approach to avoid false positives:

### Tier 1: Dead Link Detection (HTTP HEAD)

Sends a HEAD request to each job's source URL. If the server returns **404** or **410**, the job is pruned. LinkedIn and HN URLs are skipped (they always return 200).

### Tier 2: Page Content Scanning

For non-HN, non-LinkedIn URLs, fetches the first **20KB** of the page and scans for filled/closed signals:

- "this position has been filled"
- "no longer accepting applications"
- "this job listing has expired"
- "this listing is no longer active"
- "applications closed"

Only `text/html` and `text/plain` content types are scanned. Transient HTTP errors (4xx/5xx) do not trigger removal.

### Tier 3: HN Thread Analysis (Hacker News–Specific)

For HN "Who's Hiring" comment URLs:

1. Extracts the comment ID from the URL
2. Re-fetches the comment via the **Algolia HN API** (`hn.algolia.com/api/v1/items/{id}`)
3. Checks **OP (original poster) replies** for filled language ("position filled", "no longer hiring", "hiring is closed")
4. If OP hasn't confirmed but **3+ replies** contain suggestive keywords → calls **Gemini Flash** as an LLM judge
5. LLM prompt is conservative: only flags "filled" with strong explicit evidence

All checks are rate-limited to **1 request per second**. Up to 500 jobs are checked per cycle.

---

## iOS Sorting

The iOS app supports **3 sort modes**, selectable via a dropdown menu in both the card stack and list views:

| Mode            | Primary Key       | Tiebreak 1        | Tiebreak 2       | Icon   | Color  |
| --------------- | ----------------- | ----------------- | ---------------- | ------ | ------ |
| **Best Match**  | `builder_score` ↓ | `posted_at` ↓     | `role_title` A→Z | star   | blue   |
| **Newest**      | `posted_at` ↓     | `builder_score` ↓ | `role_title` A→Z | clock  | orange |
| **Highest Pay** | `salary_floor` ↓  | `builder_score` ↓ | `role_title` A→Z | dollar | green  |

Sort mode is shared across `CardStackView` and `PendingJobsListView` via the `JobsViewModel`. All sorting uses deterministic multi-key comparators so the order never shuffles between renders.

---

## Job Eviction Protection

Several mechanisms prevent good jobs from being lost:

| Protection                  | Detail                                                                |
| --------------------------- | --------------------------------------------------------------------- |
| **High-salience threshold** | Jobs with `builder_score ≥ 0.60` **never expire**, even after 30 days |
| **Extended TTL**            | Standard jobs expire after **30 days** (was 14)                       |
| **Seen URL expiry**         | `seen_urls` entries expire after **30 days** so jobs can be re-scored |
| **Timestamped seen URLs**   | `seen_urls.json` stores `{url: ISO_timestamp}` instead of flat list   |
| **Minimum score threshold** | Only jobs below `0.20` are silently dropped during ingest             |

---

## Location Intelligence

A 5-tier classification system scores job locations relative to your preferred locations:

| Tier  | Name          | Example (from Kalamazoo, MI)                  | Default Penalty |
| ----- | ------------- | --------------------------------------------- | --------------- |
| **0** | Home          | Remote, or job in Kalamazoo                   | +0              |
| **1** | Nearby        | Grand Rapids, Lansing, Detroit (same state)   | –0.03           |
| **2** | Regional      | Ohio, Indiana, Wisconsin (neighboring states) | –0.08           |
| **3** | Far US        | California, Texas, etc.                       | –0.15           |
| **4** | International | London, Berlin, Toronto, etc.                 | –0.25           |

All 50 US states have their neighbors mapped. The system includes Michigan-specific metro areas (Grand Rapids, Battle Creek, Lansing, Jackson, etc.) for fine-grained nearby detection.

**Multi-location support**: If you have `preferred_locations: ["Kalamazoo, Michigan", "New York, New York"]`, a job in NYC gets Tier 0 (home) even though it's far from Kalamazoo. The system returns the best tier across all preferred locations.

---

## iOS App

### Tabs

The app has 5 tabs:

| Tab          | View              | Description                                                         |
| ------------ | ----------------- | ------------------------------------------------------------------- |
| **Discover** | `CardStackView`   | Swipeable card stack or list of pending jobs, with list/card toggle |
| **Map**      | `JobMapView`      | Apple Maps with all jobs pinned (green = on-site, blue = remote HQ) |
| **Applied**  | `AppliedJobsView` | Jobs you swiped right on, with status tracking                      |
| **Saved**    | `SavedJobsView`   | Bookmarked jobs (swiped up)                                         |
| **You**      | `YourHubView`     | Unified dashboard — tappable pipeline stats, profile, and settings  |

### Swipe Mechanics

Tinder-style card gestures with physics-based animation:

| Gesture                     | Threshold         | Action    |
| --------------------------- | ----------------- | --------- |
| **Swipe right**             | >120px horizontal | Apply     |
| **Swipe left**              | >120px horizontal | Reject    |
| **Swipe up**                | >120px vertical   | Save      |
| **Release below threshold** | <120px            | Snap back |

- **Card rotation**: `atan(offset.width / 20)` degrees as you drag
- **Animation**: `easeOut(duration: 0.3)` on release
- **Stack depth**: Top 3 cards visible (scaled at 1.0, 0.96, 0.92)
- **Undo**: Restores the last swipe action
- **Sort picker**: Menu dropdown with 3 modes (Best Match / Newest / Highest Pay) — shared with list view
- **Auto-pagination**: Fetches all jobs in 100-item pages — seamlessly loads 100+ jobs

### Server Discovery

The app auto-discovers the backend on launch by probing these candidates in priority order:

1. `https://linkedout-backend-9q4t.onrender.com` (Render cloud)
2. `http://Gunnars-Brain-Extension.local:8443` (local Docker via mDNS)
3. `http://10.0.0.175:8443` (LAN IP)
4. `http://localhost:8443` (simulator)

Probes hit `/health` with a 2-second timeout. The result is cached for 5 minutes and invalidated on network errors. The Settings tab allows manual override.

### Settings

The Settings view (accessible from the "You" hub) provides full control over scoring behavior:

- **Quick Presets**: Relaxed 🌊, Balanced ⚖️, Strict 🎯 — one tap to switch
- **Score Simulator**: Shows how your current weights would score example jobs
- **Basics**: Max seniority level, minimum salary ($0–$300k), remote-only toggle
- **Acceptable Locations**: Add/remove preferred cities (multi-location)
- **Preferred Roles**: Customize which role titles to search for
- **Excluded Keywords**: Block specific keywords (Staff, Principal, Director, etc.)
- **Advanced Weight Sliders**: Fine-tune every penalty and boost individually
- **Backend Sync**: Shows connection status + manual server URL override
- **Sync Indicators**: Toolbar cloud badge (idle → syncing → synced → failed) + floating "Saved & synced" toast on successful save
- **Reset to Defaults**: One tap to restore all settings

All settings persist locally via `@AppStorage` (UserDefaults) — they survive even when the backend is offline. When connected, settings sync to the backend via `PUT /api/preferences`.

---

## API Reference

### Health

| Method | Path      | Description                 |
| ------ | --------- | --------------------------- |
| GET    | `/health` | Server health + store stats |

### Authentication

| Method | Path                       | Description                               |
| ------ | -------------------------- | ----------------------------------------- |
| GET    | `/auth/login`              | Get LinkedIn OAuth URL                    |
| GET    | `/auth/callback`           | OAuth callback (redirects to app)         |
| POST   | `/auth/token`              | Exchange auth code for profile            |
| GET    | `/auth/status/{person_id}` | Check session validity                    |
| POST   | `/auth/restore`            | Restore cached profile to backend session |

### Profile

| Method | Path                  | Description                          |
| ------ | --------------------- | ------------------------------------ |
| GET    | `/api/profile/resume` | Fetch full LinkedIn profile + resume |

### Jobs

| Method | Path                        | Description                             |
| ------ | --------------------------- | --------------------------------------- |
| GET    | `/api/jobs/pending`         | Pending jobs (query: `limit`, `offset`) |
| GET    | `/api/jobs/{job_id}`        | Single job by ID                        |
| GET    | `/api/jobs/applied`         | All applied jobs                        |
| GET    | `/api/jobs/saved`           | All saved jobs                          |
| GET    | `/api/jobs/rejected`        | All rejected/passed jobs                |
| GET    | `/api/jobs/stats`           | Pipeline statistics                     |
| POST   | `/api/jobs/action`          | Apply/reject/save a job                 |
| POST   | `/api/jobs/undo`            | Undo last action                        |
| POST   | `/api/jobs/import`          | Bulk-import pre-scored jobs             |
| PUT    | `/api/jobs/{job_id}/notes`  | Update job notes                        |
| PUT    | `/api/jobs/{job_id}/status` | Update application status               |

### Scoring & Ingestion

| Method | Path                       | Description                              |
| ------ | -------------------------- | ---------------------------------------- |
| POST   | `/api/score`               | Score a single listing                   |
| POST   | `/api/score/batch`         | Score a batch of listings                |
| POST   | `/api/jobs/rescore`        | Re-score all pending jobs (non-blocking) |
| GET    | `/api/jobs/rescore/status` | Re-score progress                        |
| POST   | `/api/ingest/refresh`      | Trigger background ingest                |
| GET    | `/api/ingest/status`       | Check ingest status                      |

### Preferences

| Method | Path               | Description             |
| ------ | ------------------ | ----------------------- |
| GET    | `/api/preferences` | Get current preferences |
| PUT    | `/api/preferences` | Update preferences      |

### LinkedIn Social

| Method | Path                         | Description                      |
| ------ | ---------------------------- | -------------------------------- |
| POST   | `/api/share`                 | Share job to LinkedIn as article |
| POST   | `/api/share/post`            | Post freeform text to LinkedIn   |
| POST   | `/api/share/media`           | Post with image attachment       |
| POST   | `/api/share/document`        | Post with document attachment    |
| POST   | `/api/share/reshare`         | Reshare existing LinkedIn post   |
| GET    | `/api/linkedin/posts`        | Get user's LinkedIn posts        |
| POST   | `/api/linkedin/comments`     | Add comment to post              |
| POST   | `/api/linkedin/reactions`    | Add reaction to post             |
| DELETE | `/api/linkedin/reactions`    | Remove reaction                  |
| GET    | `/api/linkedin/capabilities` | Available LinkedIn API features  |

### Notion Sync

| Method | Path                         | Description                                |
| ------ | ---------------------------- | ------------------------------------------ |
| POST   | `/api/notion/configure`      | Runtime Notion setup (token + database_id) |
| GET    | `/api/notion/status`         | Notion integration status + schema         |
| GET    | `/api/notion/schema`         | Notion database schema                     |
| POST   | `/api/notion/sync`           | Bidirectional sync (non-blocking)          |
| POST   | `/api/notion/push`           | Push all jobs to Notion                    |
| POST   | `/api/notion/pull`           | Pull changes from Notion                   |
| GET    | `/api/notion/jobs`           | List all Notion database entries           |
| GET    | `/api/notion/jobs/{page_id}` | Fetch single Notion page                   |
| PATCH  | `/api/notion/jobs/{page_id}` | Update Notion page properties              |
| DELETE | `/api/notion/jobs/{page_id}` | Archive Notion page                        |
| POST   | `/api/notion/jobs`           | Create new Notion page                     |

### Telemetry

| Method | Path             | Description        |
| ------ | ---------------- | ------------------ |
| GET    | `/api/telemetry` | Telemetry snapshot |

### Development (debug mode only)

| Method | Path                            | Description                                |
| ------ | ------------------------------- | ------------------------------------------ |
| POST   | `/api/dev/seed`                 | Seed mock jobs                             |
| POST   | `/api/dev/reset-seen`           | Clear seen URLs                            |
| POST   | `/api/dev/clear-pending`        | Clear pending queue                        |
| POST   | `/api/dev/purge-keyword-scored` | Purge keyword-scored jobs                  |
| GET    | `/api/dev/logs`                 | Recent log lines (query: `n`, default 500) |

---

## Data Models

### JobPayload

The core job object passed between backend and iOS:

```
id                    UUID string
company_name          Company name
role_title            Job title
salary_floor          Minimum salary (0 = unknown)
salary_max            Maximum salary (0 = unknown)
is_remote             Remote flag
builder_score         0.0–1.0 match score
location              Location string
posted_at             Posting date (nullable)
source_url            Original listing URL
apply_url             Direct application link
tags                  Tech/industry tags (max 5)

# AI-Generated Intelligence
ai_pitch_summary      3-bullet pitch (Markdown)
drafted_cover_letter   ~150 word cover letter
description           Full job description
company_description   About the company
company_size          e.g. "10-50", "500+"
company_stage         e.g. "Seed", "Series A", "Public"
company_url           Company website
requirements          Key requirements (list)
nice_to_haves         Nice-to-haves (list)
tech_stack            Technologies mentioned (list)
experience_level      e.g. "Entry", "Mid", "Senior"
job_type              e.g. "Full-time", "Contract"
benefits              Benefits (list)

# Why Matrix
logic_fit             How role maps to your skills
domain_leverage       Your unfair advantage
risk_reward           Realistic friction + upside
red_flags             Concerns (list, always ≥1)

# Match Signals
fit_reasons           2–4 short fit reasons
dealbreaker_warnings  0–3 convincing-needed warnings

# Notion Cross-Reference
notion_page_id        Linked Notion page ID (nullable)

# User Fields
notes                 Personal notes
application_status    "new" | "applied" | "phone_screen" | "interview" | "offer" | "rejected"
```

### UserPreferences

```
min_salary              Minimum salary filter (default: 90000)
require_remote          Remote-only toggle (default: false)
preferred_roles         Role titles to search for
excluded_keywords       Keywords to block
location_preference     "Remote" (default)
preferred_locations     ["Kalamazoo, Michigan"] (multi-city)

# Scoring Weights
score_cutoff            Reject below this (default: 0.35)
convincing_penalty      Stack mismatch (default: -0.20)
convincing_boost        "Builders welcome" (default: +0.10)
portfolio_boost         Portfolio-first signal (default: +0.10)
nearby_penalty          Same state (default: -0.03)
regional_penalty        Neighboring state (default: -0.08)
relocation_penalty      Full US relocation (default: -0.15)
international_penalty   International (default: -0.25)
experience_penalty      5+ years required (default: -0.10)
credential_penalty      FAANG/rigid (default: -0.15)
max_seniority_level     "Junior" | "Mid" | "Senior" | "Any"
```

---

## Project Structure

```
LinkedOut/
├── backend/
│   ├── main.py              # FastAPI app, all endpoints, ingest orchestration
│   ├── scoring_engine.py    # LLM scoring (triage + full + fallback chain)
│   ├── job_fetcher.py       # 5 async job source fetchers
│   ├── job_store.py         # JSON-backed store with 4 buckets + dedup
│   ├── location_mapper.py   # 5-tier geo classification, 50-state neighbor map
│   ├── models.py            # Pydantic models (JobPayload, UserPreferences, etc.)
│   ├── config.py            # Environment config (pydantic-settings)
│   ├── linkedin_api.py      # LinkedIn profile + sharing API
│   ├── linkedin_oauth.py    # OAuth 2.0 flow + session persistence
│   ├── notion_sync.py       # Bidirectional Notion database sync
│   ├── mcp_server.py        # FastMCP server for Claude Desktop
│   ├── Dockerfile           # Python 3.12-slim container
│   ├── requirements.txt     # fastapi, uvicorn, pydantic, httpx, google-genai, openai
│   └── .env.example         # Environment variable template
├── LinkedOut/
│   ├── LinkedOutApp.swift   # @main entry, injects ViewModels
│   ├── ContentView.swift    # Auth gate → MainTabView or LoginView
│   ├── Models/
│   │   ├── JobPayload.swift       # Codable job model (40+ fields)
│   │   ├── UserPreferences.swift  # Codable preferences model
│   │   └── UserProfile.swift      # LinkedIn profile + auth models
│   ├── ViewModels/
│   │   ├── AuthViewModel.swift    # LinkedIn auth state
│   │   └── JobsViewModel.swift    # Job data, actions, caching
│   ├── Views/
│   │   ├── MainTabView.swift      # 5-tab container (Discover, Map, Applied, Saved, You)
│   │   ├── CardStackView.swift    # Tinder swipe UI + list/card toggle
│   │   ├── JobCardView.swift      # Individual job card
│   │   ├── JobDetailView.swift    # Full job detail (scrollable)
│   │   ├── JobMapView.swift       # MapKit job pins
│   │   ├── AppliedJobsView.swift  # Applied + Saved lists (enriched JobListRow)
│   │   ├── YourHubView.swift      # Unified dashboard: stats, profile, settings
│   │   ├── PendingJobsListView.swift  # Pending queue list (from stat card)
│   │   ├── RejectedJobsView.swift # Passed/rejected jobs list
│   │   ├── ResumeView.swift       # LinkedIn profile display
│   │   ├── SettingsView.swift     # Preferences + weight tuning + sync indicators
│   │   ├── LoginView.swift        # OAuth login flow
│   │   ├── OAuthWebView.swift     # WKWebView for LinkedIn auth
│   │   ├── FilterSheet.swift      # Job filtering controls
│   │   ├── ApplyReviewSheet.swift # Apply confirmation sheet
│   │   ├── ComposePostView.swift  # LinkedIn post composition
│   │   ├── ShareSheetView.swift   # iOS share sheet wrapper
│   │   ├── SafariView.swift       # In-app Safari browser
│   │   ├── NotionDatabaseView.swift # Notion database browser
│   │   ├── TelemetryView.swift    # Backend telemetry dashboard
│   │   ├── OnboardingOverlay.swift # First-launch tutorial overlay
│   │   ├── ErrorBanner.swift      # Error + info banners
│   │   └── SwipeHintOverlay.swift # Visual swipe direction hints
│   ├── Network/
│   │   ├── APIClient.swift        # Actor-based HTTP client
│   │   └── ServerDiscovery.swift  # Auto-discover backend URL
│   └── Utils/
│       ├── LocationGeocoder.swift # CLGeocoder with caching
│       ├── ScoreRing.swift        # Circular score indicator
│       ├── ApplicationTracker.swift # Application status tracking
│       └── SwipeHintOverlay.swift # Visual swipe direction hints
├── docker-compose.yml       # Local dev: backend + volume mount
├── render.yaml              # Render Blueprint config
├── .gitignore               # Ignores .env, data/, __pycache__, xcuserdata/
└── docs/                    # LinkedIn API reference docs
```

---

## Background Tasks

Three periodic tasks run on the backend:

| Task                | Interval   | Description                                                                                                                        |
| ------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Periodic Ingest** | 6 hours    | Fetches from all 5 job APIs, deduplicates, scores, stores. Also runs `expire_old_jobs()` and `expire_stale_seen_urls()` each cycle |
| **Smart Pruner**    | 2 hours    | 3-tier job freshness: HEAD checks → page content scan → HN thread analysis. Rate limited 1 req/sec                                 |
| **Keep-Alive Ping** | 10 minutes | Self-pings `/health` to prevent Render from sleeping the instance                                                                  |

All tasks start on app boot via the FastAPI `lifespan` context manager and are gracefully cancelled on shutdown.

---

## Roadmap

- [x] 5 job source aggregation + 3-layer dedup
- [x] LLM scoring with Why Matrix + anti-sycophancy prompts
- [x] Tinder-style swipe UI with card/list toggle
- [x] LinkedIn OAuth + session persistence
- [x] Bidirectional Notion sync
- [x] MCP server for Claude Desktop
- [x] Dynamic AI candidate persona + rescore flow
- [x] Smart content-aware job pruner (3-tier: HEAD + page scan + HN thread LLM)
- [x] 3-mode sort system (Best Match / Newest / Highest Pay)
- [x] Auto-paginating iOS fetch (100-item pages)
- [x] Job eviction protection (high-salience threshold, 30-day TTL, seen URL expiry)
- [ ] Push notifications for high-score new jobs
- [ ] Auto-apply workflow (one-tap application submission)
- [ ] Interview prep — LLM-generated prep notes per company
- [ ] Analytics dashboard — score distribution, apply rate, source quality

---

## License

Personal project. Not currently licensed for redistribution.
