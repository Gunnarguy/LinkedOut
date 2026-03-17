"""Notion bidirectional sync — pushes LinkedOut jobs to Notion, pulls changes back.

Uses Notion API v2026-03-11 with the new data_source_id pattern.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import httpx

from config import settings
from models import JobPayload

logger = logging.getLogger(__name__)

NOTION_API = "https://api.notion.com"
NOTION_VERSION = "2026-03-11"

# Runtime config file (persists token+database_id without rebuilding Docker)
_DATA_DIR = Path("/app/data") if Path("/app").exists() else Path("./data")
_NOTION_CONFIG_FILE = _DATA_DIR / "notion_config.json"

# ── Property name constants (Notion database column names) ───────────────────
# These are the expected column names in the user's Notion database.
# The sync adapts: if a property doesn't exist, it's silently skipped.

PROP_NAME = "Company"  # title column — contains company name as page title
PROP_COMPANY = "Company"  # same as title in this database
PROP_ROLE = "Role Title 1"
PROP_STATUS = "Status 1"
PROP_SCORE = "Score"
PROP_SALARY = "Salary Range"
PROP_REMOTE = "Remote"
PROP_LOCATION = "Location"
PROP_SOURCE_URL = "Link"
PROP_APPLY_URL = "Apply URL"
PROP_TAGS = "Tags"
PROP_TECH_STACK = "Tech Stack Summary"
PROP_NOTES = "Notes"
PROP_LINKEDOUT_ID = "LinkedOut ID"
PROP_POSTED = "Date Found"
PROP_AI_SUMMARY = "AI Summary"
PROP_EXPERIENCE = "Experience Level"
PROP_JOB_TYPE = "Job Type"
PROP_COMPANY_STAGE = "Company Stage"
PROP_DATE_APPLIED = "Date Applied"
PROP_COVER_LETTER = "Cover Letter"
PROP_CONTACT = "Contact"
PROP_NEXT_STEP = "Next Step"
PROP_LAST_STEP = "Last Step"
PROP_ENTHUSIASM = "Enthusiasm Level"
PROP_GAPS = "Gaps"
PROP_GAINS = "Gains"
PROP_ICE_BREAKER = "Ice Breaker"


class NotionSync:
    """Async Notion client for bidirectional job sync."""

    def __init__(self) -> None:
        self._token = ""
        self._database_id = ""
        self._data_source_id: str | None = None
        self._db_properties: dict | None = None  # cached schema
        self._load_config()

    def _load_config(self) -> None:
        """Load config from runtime file first, fall back to env vars."""
        if _NOTION_CONFIG_FILE.exists():
            try:
                data = json.loads(_NOTION_CONFIG_FILE.read_text())
                self._token = data.get("token", "")
                self._database_id = data.get("database_id", "")
                if self._token and self._database_id:
                    logger.info("[NOTION] Loaded config from runtime file")
                    return
            except Exception:
                logger.warning("[NOTION] Failed to read runtime config file")
        # Fall back to env vars
        self._token = settings.notion_token
        self._database_id = settings.notion_database_id

    def reconfigure(self, token: str, database_id: str) -> None:
        """Update credentials at runtime and persist to file. No restart needed."""
        self._token = token
        self._database_id = database_id
        self._data_source_id = None
        self._db_properties = None
        # Persist so it survives container restarts
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        _NOTION_CONFIG_FILE.write_text(
            json.dumps({"token": token, "database_id": database_id})
        )
        logger.info("[NOTION] Reconfigured and saved to runtime config file")

    @property
    def configured(self) -> bool:
        return bool(self._token and self._database_id)

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._token}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        }

    # ── Discovery ────────────────────────────────────────────────────────

    async def discover_data_source(self) -> str:
        """Retrieve database metadata to get the data_source_id.

        Notion 2025-09-03+ requires data_source_id for queries and page creation.
        GET /v1/databases/{database_id} → data_sources[0].id
        """
        if self._data_source_id:
            return self._data_source_id

        url = f"{NOTION_API}/v1/databases/{self._database_id}"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url, headers=self._headers())
            resp.raise_for_status()
            data = resp.json()

        sources = data.get("data_sources", [])
        if not sources:
            raise RuntimeError(
                "No data_sources found on this database. "
                "Make sure the Notion integration has access to the database."
            )

        self._data_source_id = sources[0]["id"]
        logger.info(f"[NOTION] Discovered data_source_id: {self._data_source_id}")
        return self._data_source_id

    async def discover_schema(self) -> dict:
        """Get the data source properties schema. Returns {prop_name: prop_type}."""
        if self._db_properties is not None:
            return self._db_properties

        ds_id = await self.discover_data_source()
        url = f"{NOTION_API}/v1/data_sources/{ds_id}"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url, headers=self._headers())
            resp.raise_for_status()
            data = resp.json()

        props = data.get("properties", {})
        self._db_properties = {
            name: info.get("type", "") for name, info in props.items()
        }
        logger.info(f"[NOTION] Schema: {self._db_properties}")
        return self._db_properties

    # ── Read (Pull from Notion) ──────────────────────────────────────────

    async def query_all_pages(self) -> list[dict]:
        """Query all pages from the Notion database, handling pagination."""
        ds_id = await self.discover_data_source()
        url = f"{NOTION_API}/v1/data_sources/{ds_id}/query"
        all_pages: list[dict] = []
        start_cursor: str | None = None

        async with httpx.AsyncClient(timeout=30) as client:
            while True:
                body: dict = {"page_size": 100}
                if start_cursor:
                    body["start_cursor"] = start_cursor

                resp = await client.post(url, headers=self._headers(), json=body)
                resp.raise_for_status()
                data = resp.json()

                results = data.get("results", [])
                all_pages.extend(results)

                if not data.get("has_more", False):
                    break
                start_cursor = data.get("next_cursor")

        logger.info(f"[NOTION] Queried {len(all_pages)} pages from Notion")
        return all_pages

    async def pull_jobs(self) -> list[dict]:
        """Pull all jobs from Notion and return normalized dicts.

        Returns list of dicts with keys:
        - notion_page_id, name, company, role, status, score, salary,
          remote, location, source_url, tags, tech_stack, notes, linkedout_id, posted
        """
        pages = await self.query_all_pages()
        jobs = []
        for page in pages:
            try:
                jobs.append(self._parse_page(page))
            except Exception as e:
                logger.warning(
                    f"[NOTION] Failed to parse page {page.get('id', '?')}: {e}"
                )
        return jobs

    def _parse_page(self, page: dict) -> dict:
        """Extract structured data from a Notion page object."""
        props = page.get("properties", {})
        company = self._get_title(props, PROP_NAME)
        # Tech Stack Summary is rich_text in this database, split by comma
        tech_str = self._get_rich_text(props, PROP_TECH_STACK)
        tech_list = (
            [t.strip() for t in tech_str.split(",") if t.strip()] if tech_str else []
        )
        return {
            "notion_page_id": page["id"],
            "notion_url": page.get("url", ""),
            "name": company,
            "company": company,
            "role": self._get_rich_text(props, PROP_ROLE),
            "status": self._get_select(props, PROP_STATUS),
            "score": self._get_number(props, PROP_SCORE),
            "salary": self._get_rich_text(props, PROP_SALARY),
            "remote": self._get_checkbox(props, PROP_REMOTE),
            "location": self._get_rich_text(props, PROP_LOCATION),
            "source_url": self._get_url(props, PROP_SOURCE_URL),
            "apply_url": self._get_url(props, PROP_APPLY_URL),
            "tags": self._get_multi_select(props, PROP_TAGS),
            "tech_stack": tech_list,
            "notes": self._get_rich_text(props, PROP_NOTES),
            "linkedout_id": self._get_rich_text(props, PROP_LINKEDOUT_ID),
            "posted": self._get_date(props, PROP_POSTED),
            "ai_summary": self._get_rich_text(props, PROP_AI_SUMMARY),
            "experience_level": self._get_rich_text(props, PROP_EXPERIENCE),
            "job_type": self._get_rich_text(props, PROP_JOB_TYPE),
            "company_stage": self._get_rich_text(props, PROP_COMPANY_STAGE),
            "last_edited": page.get("last_edited_time", ""),
        }

    # ── Write (Push to Notion) ───────────────────────────────────────────

    async def push_job(self, job: JobPayload, bucket: str) -> str:
        """Create or update a Notion page for a job.

        Returns the Notion page ID.
        """
        # Check if we already have a Notion page for this job
        if job.notion_page_id:
            await self._update_page(job.notion_page_id, job, bucket)
            return job.notion_page_id

        # Search for existing page by LinkedOut ID
        existing_id = await self._find_page_by_linkedout_id(job.id)
        if existing_id:
            await self._update_page(existing_id, job, bucket)
            return existing_id

        # Create new page
        return await self._create_page(job, bucket)

    async def _create_page(self, job: JobPayload, bucket: str) -> str:
        """Create a new Notion page for a job."""
        ds_id = await self.discover_data_source()
        schema = await self.discover_schema()

        properties = self._build_properties(job, bucket, schema)
        body = {
            "parent": {"type": "data_source_id", "data_source_id": ds_id},
            "properties": properties,
        }

        url = f"{NOTION_API}/v1/pages"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(url, headers=self._headers(), json=body)
            resp.raise_for_status()
            data = resp.json()

        page_id = data["id"]
        logger.info(
            f"[NOTION] Created page {page_id} for {job.role_title} @ {job.company_name}"
        )
        return page_id

    async def _update_page(self, page_id: str, job: JobPayload, bucket: str) -> None:
        """Update an existing Notion page."""
        schema = await self.discover_schema()
        properties = self._build_properties(job, bucket, schema)

        url = f"{NOTION_API}/v1/pages/{page_id}"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.patch(
                url, headers=self._headers(), json={"properties": properties}
            )
            resp.raise_for_status()

        logger.info(
            f"[NOTION] Updated page {page_id} for {job.role_title} @ {job.company_name}"
        )

    async def _find_page_by_linkedout_id(self, job_id: str) -> str | None:
        """Search Notion for a page with matching LinkedOut ID."""
        schema = await self.discover_schema()
        if PROP_LINKEDOUT_ID not in schema:
            return None

        ds_id = await self.discover_data_source()
        url = f"{NOTION_API}/v1/data_sources/{ds_id}/query"
        body = {
            "filter": {
                "property": PROP_LINKEDOUT_ID,
                "rich_text": {"equals": job_id},
            },
            "page_size": 1,
        }

        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(url, headers=self._headers(), json=body)
            resp.raise_for_status()
            data = resp.json()

        results = data.get("results", [])
        if results:
            return results[0]["id"]
        return None

    # ── Single Page CRUD ─────────────────────────────────────────────────

    async def get_page(self, page_id: str) -> dict:
        """Fetch a single Notion page by ID and return parsed data."""
        url = f"{NOTION_API}/v1/pages/{page_id}"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url, headers=self._headers())
            resp.raise_for_status()
            page = resp.json()
        return self._parse_page(page)

    async def update_page_properties(self, page_id: str, updates: dict) -> dict:
        """Update arbitrary properties on a Notion page.

        `updates` is a dict mapping property names to their new values.
        We build the correct Notion property format based on the schema type.
        """
        schema = await self.discover_schema()
        properties: dict = {}

        for prop_name, value in updates.items():
            if prop_name not in schema:
                continue
            prop_type = schema[prop_name]
            properties[prop_name] = self._value_to_notion_property(prop_type, value)

        if not properties:
            return await self.get_page(page_id)

        url = f"{NOTION_API}/v1/pages/{page_id}"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.patch(
                url, headers=self._headers(), json={"properties": properties}
            )
            resp.raise_for_status()
            page = resp.json()

        logger.info(f"[NOTION] Updated page {page_id}: {list(updates.keys())}")
        return self._parse_page(page)

    async def archive_page(self, page_id: str) -> bool:
        """Archive (soft-delete) a Notion page."""
        url = f"{NOTION_API}/v1/pages/{page_id}"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.patch(
                url, headers=self._headers(), json={"in_trash": True}
            )
            # If it's already archived, Notion returns 400 with "Can't edit block that is archived"
            if resp.status_code == 400 and "archived" in resp.text:
                logger.info(f"[NOTION] Page {page_id} already archived")
                return True
            resp.raise_for_status()
        logger.info(f"[NOTION] Archived page {page_id}")
        return True

    async def create_page_from_properties(self, properties: dict) -> dict:
        """Create a new Notion page from raw property name→value pairs."""
        ds_id = await self.discover_data_source()
        schema = await self.discover_schema()

        notion_props: dict = {}
        for prop_name, value in properties.items():
            if prop_name not in schema:
                continue
            prop_type = schema[prop_name]
            notion_props[prop_name] = self._value_to_notion_property(prop_type, value)

        body = {
            "parent": {"type": "data_source_id", "data_source_id": ds_id},
            "properties": notion_props,
        }

        url = f"{NOTION_API}/v1/pages"
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(url, headers=self._headers(), json=body)
            resp.raise_for_status()
            page = resp.json()

        logger.info(f"[NOTION] Created page {page['id']} from raw properties")
        return self._parse_page(page)

    def _value_to_notion_property(self, prop_type: str, value) -> dict:
        """Convert a Python value to the correct Notion property format."""
        if prop_type == "title":
            return {"title": [{"text": {"content": str(value or "")[:2000]}}]}
        elif prop_type == "rich_text":
            return self._make_rich_text(str(value or ""))
        elif prop_type == "number":
            try:
                return {"number": float(value) if value is not None else None}
            except (ValueError, TypeError):
                return {"number": None}
        elif prop_type == "checkbox":
            return {"checkbox": bool(value)}
        elif prop_type in ("select", "status"):
            return {prop_type: {"name": str(value or "")}}
        elif prop_type == "multi_select":
            if isinstance(value, list):
                return {"multi_select": [{"name": str(v)} for v in value]}
            return {"multi_select": [{"name": str(value)}] if value else []}
        elif prop_type == "url":
            return {"url": str(value) if value else None}
        elif prop_type == "date":
            return {"date": {"start": str(value)} if value else None}
        else:
            # Unknown type — try rich_text as fallback
            return self._make_rich_text(str(value or ""))

    def _build_properties(self, job: JobPayload, bucket: str, schema: dict) -> dict:
        """Build Notion properties dict, only including props that exist in the schema."""
        props: dict = {}

        # Title is the Company column
        if PROP_NAME in schema:
            props[PROP_NAME] = {"title": [{"text": {"content": job.company_name}}]}

        # Company is the same as name/title in this database, skip duplicate
        # PROP_COMPANY == PROP_NAME so no separate rich_text needed

        if PROP_ROLE in schema and schema[PROP_ROLE] == "rich_text":
            props[PROP_ROLE] = self._make_rich_text(job.role_title)

        # Map bucket to status
        status_map = {
            "pending": "Not Started",
            "applied": "Applied",
            "saved": "Saved",
            "rejected": "Closed",
        }
        if PROP_STATUS in schema:
            status_val = status_map.get(bucket, bucket.title())
            prop_type = schema[PROP_STATUS]
            if prop_type == "status":
                props[PROP_STATUS] = {"status": {"name": status_val}}
            elif prop_type == "select":
                props[PROP_STATUS] = {"select": {"name": status_val}}

        if PROP_SCORE in schema and schema[PROP_SCORE] == "number":
            props[PROP_SCORE] = {"number": round(job.builder_score * 100, 1)}

        if PROP_SALARY in schema and schema[PROP_SALARY] == "rich_text":
            salary = f"${job.salary_floor:,}"
            if job.salary_max:
                salary += f" – ${job.salary_max:,}"
            props[PROP_SALARY] = self._make_rich_text(salary)

        if PROP_REMOTE in schema and schema[PROP_REMOTE] == "checkbox":
            props[PROP_REMOTE] = {"checkbox": job.is_remote}

        if PROP_LOCATION in schema and schema[PROP_LOCATION] == "rich_text":
            props[PROP_LOCATION] = self._make_rich_text(job.location)

        if PROP_SOURCE_URL in schema and schema[PROP_SOURCE_URL] == "url":
            props[PROP_SOURCE_URL] = {"url": job.source_url or None}

        if PROP_APPLY_URL in schema and schema[PROP_APPLY_URL] == "url":
            props[PROP_APPLY_URL] = {"url": job.apply_url or None}

        if PROP_TAGS in schema and schema[PROP_TAGS] == "multi_select":
            props[PROP_TAGS] = {"multi_select": [{"name": t} for t in (job.tags or [])]}

        if PROP_TECH_STACK in schema:
            tech_text = ", ".join(job.tech_stack or [])
            ptype = schema[PROP_TECH_STACK]
            if ptype == "multi_select":
                props[PROP_TECH_STACK] = {
                    "multi_select": [{"name": t} for t in (job.tech_stack or [])]
                }
            elif ptype == "rich_text":
                props[PROP_TECH_STACK] = self._make_rich_text(tech_text)

        if PROP_NOTES in schema and schema[PROP_NOTES] == "rich_text":
            props[PROP_NOTES] = self._make_rich_text(job.notes)

        if PROP_LINKEDOUT_ID in schema and schema[PROP_LINKEDOUT_ID] == "rich_text":
            props[PROP_LINKEDOUT_ID] = self._make_rich_text(job.id)

        if PROP_POSTED in schema and schema[PROP_POSTED] == "date":
            if job.posted_at:
                iso = (
                    job.posted_at.isoformat()
                    if isinstance(job.posted_at, datetime)
                    else str(job.posted_at)
                )
                props[PROP_POSTED] = {"date": {"start": iso}}

        if PROP_AI_SUMMARY in schema and schema[PROP_AI_SUMMARY] == "rich_text":
            # Truncate to 2000 chars (Notion limit per rich_text block)
            summary = (job.ai_pitch_summary or "")[:2000]
            props[PROP_AI_SUMMARY] = self._make_rich_text(summary)

        if PROP_EXPERIENCE in schema and schema[PROP_EXPERIENCE] == "rich_text":
            props[PROP_EXPERIENCE] = self._make_rich_text(job.experience_level)

        if PROP_JOB_TYPE in schema and schema[PROP_JOB_TYPE] == "rich_text":
            props[PROP_JOB_TYPE] = self._make_rich_text(job.job_type)

        if PROP_COMPANY_STAGE in schema and schema[PROP_COMPANY_STAGE] == "rich_text":
            props[PROP_COMPANY_STAGE] = self._make_rich_text(job.company_stage)

        return props

    # ── Full Sync ────────────────────────────────────────────────────────

    async def full_sync(self, job_store) -> dict:
        """Bidirectional sync: push all LinkedOut jobs to Notion, pull changes back.

        Returns stats dict with push/pull counts.
        """
        stats = {"pushed": 0, "updated": 0, "pulled": 0, "errors": 0, "archived": 0}

        # 1. Push all saved/applied jobs from LinkedOut → Notion
        push_buckets = {
            "applied": job_store.get_applied(),
            "saved": job_store.get_saved(),
        }

        for bucket_name, jobs in push_buckets.items():
            for job in jobs:
                try:
                    page_id = await self.push_job(job, bucket_name)
                    if not job.notion_page_id and page_id:
                        job.notion_page_id = page_id
                        job_store.update_notion_page_id(job.id, page_id)
                        stats["pushed"] += 1
                    else:
                        stats["updated"] += 1
                except Exception as e:
                    logger.error(f"[NOTION] Push failed for {job.id}: {e}")
                    stats["errors"] += 1

        # 1b. Archive pending/rejected jobs that currently exist in Notion
        archive_buckets = {
            "pending": job_store.get_pending(limit=9999),
            "rejected": job_store.get_rejected(),
        }
        for bucket_name, jobs in archive_buckets.items():
            for job in jobs:
                if job.notion_page_id:
                    try:
                        await self.archive_page(job.notion_page_id)
                        job.notion_page_id = ""
                        job_store.update_notion_page_id(job.id, "")
                        stats["archived"] += 1
                    except Exception as e:
                        logger.error(f"[NOTION] Archive failed for {job.id}: {e}")
                        stats["errors"] += 1

        # 2. Pull from Notion → update LinkedOut (status/notes changes)
        try:
            notion_jobs = await self.pull_jobs()
            for nj in notion_jobs:
                linkedout_id = nj.get("linkedout_id")
                if not linkedout_id:
                    continue

                existing = job_store.get_job(linkedout_id)
                if not existing:
                    continue

                # Sync notes from Notion → LinkedOut
                notion_notes = nj.get("notes", "")
                if notion_notes and notion_notes != existing.notes:
                    job_store.update_job_notes(linkedout_id, notion_notes)
                    stats["pulled"] += 1

                # Sync status from Notion → LinkedOut bucket
                notion_status = (nj.get("status") or "").lower()
                current_bucket = job_store.get_job_bucket(linkedout_id)
                bucket_map = {
                    "applied": "applied",
                    "saved": "saved",
                    "rejected": "rejected",
                    "not started": "pending",
                    "pending": "pending",
                }
                target_bucket = bucket_map.get(notion_status)
                if target_bucket and target_bucket != current_bucket:
                    job_store.move_to_bucket(linkedout_id, target_bucket)
                    stats["pulled"] += 1

        except Exception as e:
            logger.error(f"[NOTION] Pull failed: {e}")
            stats["errors"] += 1

        logger.info(f"[NOTION] Sync complete: {stats}")
        return stats

    # ── Property helpers ─────────────────────────────────────────────────

    @staticmethod
    def _make_rich_text(content: str) -> dict:
        """Build a rich_text property value."""
        return {"rich_text": [{"text": {"content": (content or "")[:2000]}}]}

    @staticmethod
    def _get_title(props: dict, name: str) -> str:
        prop = props.get(name, {})
        titles = prop.get("title", [])
        return titles[0]["plain_text"] if titles else ""

    @staticmethod
    def _get_rich_text(props: dict, name: str) -> str:
        prop = props.get(name, {})
        texts = prop.get("rich_text", [])
        return "".join(t.get("plain_text", "") for t in texts)

    @staticmethod
    def _get_number(props: dict, name: str) -> float | None:
        prop = props.get(name, {})
        return prop.get("number")

    @staticmethod
    def _get_select(props: dict, name: str) -> str:
        prop = props.get(name, {})
        # Handle both "select" and "status" property types
        sel = prop.get("select") or prop.get("status")
        if sel and isinstance(sel, dict):
            return sel.get("name", "")
        return ""

    @staticmethod
    def _get_multi_select(props: dict, name: str) -> list[str]:
        prop = props.get(name, {})
        items = prop.get("multi_select", [])
        return [item.get("name", "") for item in items if item.get("name")]

    @staticmethod
    def _get_checkbox(props: dict, name: str) -> bool:
        prop = props.get(name, {})
        return prop.get("checkbox", False)

    @staticmethod
    def _get_url(props: dict, name: str) -> str:
        prop = props.get(name, {})
        return prop.get("url") or ""

    @staticmethod
    def _get_date(props: dict, name: str) -> str:
        prop = props.get(name, {})
        date_obj = prop.get("date")
        if date_obj and isinstance(date_obj, dict):
            return date_obj.get("start", "")
        return ""


# Module-level singleton
notion_sync = NotionSync()
