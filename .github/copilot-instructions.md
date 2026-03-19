# LinkedOut — Copilot Instructions

## Project Overview

LinkedOut is a **"Tinder for jobs"** app: a FastAPI backend fetches listings from 5 remote job boards, scores them with LLMs, and serves them to an iOS SwiftUI app where users swipe to apply, reject, or save.

## Architecture

- **Backend**: FastAPI (Python 3.12) in Docker on port 8443
- **iOS App**: SwiftUI, iOS 17+, MVVM, NavigationStack
- **LLM Scoring**: Gemini Pro/Flash (primary) → OpenAI GPT-5.4 (fallback)
- **Storage**: JSON file-backed (`job_store.json`, `seen_urls.json`, `user_prefs.json`, `sessions.json`)
- **Notion Sync**: Bidirectional sync with Notion database via API v2026-03-11 (`backend/notion_sync.py`)
- **MCP Server**: FastMCP implementation bridging LinkedOut backend to Claude Desktop (`backend/mcp_server.py`) with LinkedIn OAuth integration.
- **Deployment**: Docker locally, Render cloud (`render.yaml`)

## Key Patterns

### Backend (Python)

- **Pydantic v2** models in `backend/models.py` — all API request/response types
- **`pydantic-settings`** for config in `backend/config.py` — env vars with defaults
- **`asyncio.Lock`** guards the ingest pipeline — never run parallel ingests
- **Job store** (`backend/job_store.py`) has 4 buckets: `pending`, `applied`, `saved`, `rejected` — all operations deduplicate by URL across every bucket
- **Scoring engine** (`backend/scoring_engine.py`) uses a two-tier pipeline: Gemini Flash triage (fast pass/fail) → Gemini Pro full scoring (Why Matrix, cover letter, etc.)
- **Scoring prompts** use **second-person voice** ("your skills", "you built") — never third-person ("the candidate", "Gunnar")
- **Cover letter drafts** use confident peer tone — no "excited/thrilled/passionate", no corporate filler, no groveling
- **LLM fallback chain**: Gemini Pro → Gemini Flash → OpenAI
- **Session persistence** (`backend/linkedin_oauth.py`) — OAuth sessions save to `data/sessions.json`, survive Docker rebuilds; `restore_session()` re-creates server-side session from cached iOS profile
- All API routes are in `backend/main.py`

### iOS (SwiftUI)

- **MVVM**: `AuthViewModel` and `JobsViewModel` in `ViewModels/`, injected via `@EnvironmentObject`
- **NavigationStack** at the root (`MainTabView`) — child views use `NavigationLink` and `navigationDestination`, never nested `NavigationStack`
- **`@AppStorage`** (UserDefaults) for local settings persistence — survives offline/backend-down
- **`APIClient`** is an `actor` (`Network/APIClient.swift`) — all HTTP calls are async/await, never Combine publishers
- **`ServerDiscovery`** probes multiple backend candidates (Render → mDNS → LAN → localhost) with 2s timeouts
- **5 tabs** in `MainTabView`: Discover, Map, Applied, Saved, You
- **`YourHubView`** is the unified "You" tab — tappable stat cards navigate to `PendingJobsListView`, `EmbeddedAppliedJobsView`, `EmbeddedSavedJobsView`, `RejectedJobsView`
- **`CardStackView`** supports list/card toggle — list mode uses `JobListRow` (enriched rows with score ring, tags, tech stack, fit reasons)
- **Session auto-restore**: `AuthViewModel.checkExistingSession()` detects backend mismatches (e.g. Docker rebuild) and calls `POST /auth/restore` with cached profile — seamless reconnection
- **Rescore flow**: `ProfileEditorView` → "Save & Rescore All Jobs" → `JobsViewModel.rescoreAllJobs()` → `POST /api/jobs/rescore` + polling `/api/jobs/rescore/status`
- **Xcode uses `PBXFileSystemSynchronizedRootGroup`** — new `.swift` files added to the `LinkedOut/` directory tree are auto-discovered; no manual Xcode project file editing needed
- **Models** in `LinkedOut/Models/` are `Codable` structs matching backend Pydantic models field-for-field

### Data Flow

1. Backend fetches from 5 job APIs → deduplicates → LLM scores → stores in `pending` bucket
2. iOS polls `/api/ingest/status` during active ingests, fetches `/api/jobs/pending` when ready
3. User swipes → `POST /api/jobs/action` moves job to `applied`/`rejected`/`saved` bucket
4. All state changes round-trip to backend; iOS caches locally for responsiveness
5. Profile edit → save preferences → rescore all pending jobs → updated scores and match signals
6. Auth sessions persist to `sessions.json`; iOS auto-restores session on backend restart via `POST /auth/restore`
7. Notion sync (manual): push all LinkedOut jobs → Notion pages, pull Notion changes → LinkedOut

### Notion Integration

- **`backend/notion_sync.py`** — async httpx client using Notion API v2026-03-11 with `data_source_id` pattern (not the deprecated `database_id` queries)
- **Discovery**: `GET /v1/databases/{database_id}` → extracts `data_sources[0].id` for all subsequent operations
- **Schema-adaptive**: reads the Notion database schema and only writes properties that exist (silently skips missing columns)
- **Cross-reference**: `notion_page_id` field on `JobPayload` links LinkedOut jobs ↔ Notion pages; `LinkedOut ID` property on Notion pages enables reverse lookup
- **Sync modes**: Full bidirectional (`/api/notion/sync`), push-only (`/api/notion/push`), pull-only (`/api/notion/pull`)
- **Pull sync**: reads Notion status/notes changes and moves jobs between LinkedOut buckets accordingly
- **Config**: Runtime via `POST /api/notion/configure` from iOS Settings (saves to `data/notion_config.json`), or `NOTION_TOKEN` + `NOTION_DATABASE_ID` in `.env`

## Build & Deploy

```bash
# Backend (Docker)
docker compose down && docker compose up --build -d

# iOS (deploy to device)
./deploy-to-phone.sh

# Verify backend health
curl http://localhost:8443/health
```

## File Organization

| Directory               | Contents                                                                                     |
| ----------------------- | -------------------------------------------------------------------------------------------- |
| `backend/`              | FastAPI app, scoring engine, job fetcher, mcp server, config                                 |
| `LinkedOut/Models/`     | Swift Codable structs (`JobPayload`, `UserPreferences`, `UserProfile`)                       |
| `LinkedOut/ViewModels/` | `AuthViewModel`, `JobsViewModel`                                                             |
| `LinkedOut/Views/`      | 22 SwiftUI view files                                                                        |
| `LinkedOut/Network/`    | `APIClient` (actor), `ServerDiscovery`                                                       |
| `LinkedOut/Utils/`      | `ScoreRing`, `SwipeHintOverlay`, `LocationGeocoder`, `ApplicationTracker`                    |
| `docs/`                 | LinkedIn API reference documentation                                                         |
| `data/`                 | `job_store.json`, `seen_urls.json`, `user_prefs.json`, `sessions.json`, `notion_config.json` |

## Coding Conventions

- **Python**: Type hints on function signatures. Use `httpx` for async HTTP (not `requests`). Pydantic models for all structured data.
- **Swift**: Use SwiftUI view composition. Prefer `@Published` properties in ObservableObject VMs. Use `async/await` — no Combine/callback patterns for new code.
- **No over-engineering**: Don't add abstractions, utilities, or error handling beyond what's immediately needed.
- **Prompts**: Keep LLM prompts in `scoring_engine.py` — second-person voice, anti-sycophancy design, temperature 0.3.

## API Endpoints (Quick Reference)

- `GET /health` — health check + store stats
- `GET /auth/login` — LinkedIn OAuth URL
- `GET /auth/callback` — OAuth callback (redirects to app)
- `POST /auth/token` — exchange auth code for profile
- `GET /auth/status/{person_id}` — check session validity
- `POST /auth/restore` — restore cached profile to backend session
- `GET /api/profile/resume` — fetch full LinkedIn profile
- `GET /api/jobs/pending` — pending scored jobs
- `GET /api/jobs/{job_id}` — single job by ID
- `GET /api/jobs/applied` — applied jobs
- `GET /api/jobs/saved` — saved jobs
- `GET /api/jobs/rejected` — rejected/passed jobs
- `GET /api/jobs/stats` — pipeline counts
- `POST /api/jobs/action` — apply/reject/save a job
- `POST /api/jobs/undo` — undo last action
- `POST /api/jobs/import` — bulk-import pre-scored jobs
- `PUT /api/jobs/{job_id}/notes` — update job notes
- `PUT /api/jobs/{job_id}/status` — update application status
- `POST /api/score` — score single listing
- `POST /api/score/batch` — score batch of listings
- `POST /api/jobs/rescore` — re-score all pending jobs (non-blocking)
- `GET /api/jobs/rescore/status` — re-score progress
- `POST /api/ingest/refresh` — trigger background ingest
- `GET /api/ingest/status` — ingest cycle progress
- `GET/PUT /api/preferences` — user scoring preferences
- `POST /api/share` — share job to LinkedIn
- `POST /api/share/post` — post freeform text to LinkedIn
- `POST /api/share/media` — post with image attachment
- `POST /api/share/document` — post with document attachment
- `POST /api/share/reshare` — reshare existing LinkedIn post
- `GET /api/linkedin/posts` — get user's LinkedIn posts
- `POST /api/linkedin/comments` — add comment to post
- `POST/DELETE /api/linkedin/reactions` — add/remove reaction
- `GET /api/linkedin/capabilities` — available LinkedIn API features
- `POST /api/notion/configure` — runtime Notion setup (token + database_id, no restart)
- `GET /api/notion/status` — Notion integration status + schema
- `GET /api/notion/schema` — Notion database schema
- `POST /api/notion/sync` — bidirectional Notion sync (non-blocking)
- `POST /api/notion/push` — push all jobs to Notion
- `POST /api/notion/pull` — pull changes from Notion
- `GET /api/notion/jobs` — list all Notion database entries
- `GET /api/notion/jobs/{page_id}` — fetch single Notion page
- `PATCH /api/notion/jobs/{page_id}` — update Notion page
- `DELETE /api/notion/jobs/{page_id}` — archive Notion page
- `POST /api/notion/jobs` — create new Notion page
- `GET /api/telemetry` — telemetry snapshot
