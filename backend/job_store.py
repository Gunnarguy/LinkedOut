"""Persistent job store — JSON file-backed so restarts don't nuke your queue."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone, timedelta
from pathlib import Path

from models import JobAction, JobPayload

logger = logging.getLogger(__name__)

DATA_DIR = Path("/app/data") if Path("/app").exists() else Path("./data")
STORE_FILE = DATA_DIR / "job_store.json"
SEEN_FILE = DATA_DIR / "seen_urls.json"


class JobStore:
    def __init__(self) -> None:
        self._pending: dict[str, JobPayload] = {}
        self._applied: dict[str, JobPayload] = {}
        self._rejected: dict[str, JobPayload] = {}
        self._saved: dict[str, JobPayload] = {}
        self._seen_urls: set[str] = set()
        self._url_index: set[str] = set()  # fast URL lookup across all buckets
        self._undo_stack: list[tuple[str, str, str]] = (
            []
        )  # (job_id, action, source_bucket)
        self._load()
        self._dedup_on_load()

    # ── Persistence ──────────────────────────────────────────────────────

    def _load(self) -> None:
        """Load state from disk on startup."""
        DATA_DIR.mkdir(parents=True, exist_ok=True)

        if STORE_FILE.exists():
            try:
                raw = json.loads(STORE_FILE.read_text())
                for key, bucket in [
                    ("pending", self._pending),
                    ("applied", self._applied),
                    ("rejected", self._rejected),
                    ("saved", self._saved),
                ]:
                    for job_data in raw.get(key, []):
                        job = JobPayload(**job_data)
                        bucket[job.id] = job
                logger.info(
                    f"Loaded store from disk: {len(self._pending)} pending, "
                    f"{len(self._applied)} applied, {len(self._saved)} saved"
                )
            except Exception as e:
                logger.error(f"Failed to load store: {e}")

        if SEEN_FILE.exists():
            try:
                self._seen_urls = set(json.loads(SEEN_FILE.read_text()))
                logger.info(f"Loaded {len(self._seen_urls)} seen URLs")
            except Exception as e:
                logger.error(f"Failed to load seen URLs: {e}")

    def _save(self) -> None:
        """Persist state to disk."""
        try:
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            data = {
                "pending": [j.model_dump(mode="json") for j in self._pending.values()],
                "applied": [j.model_dump(mode="json") for j in self._applied.values()],
                "rejected": [
                    j.model_dump(mode="json") for j in self._rejected.values()
                ],
                "saved": [j.model_dump(mode="json") for j in self._saved.values()],
            }
            STORE_FILE.write_text(json.dumps(data, default=str))
        except Exception as e:
            logger.error(f"Failed to save store: {e}")

    def _save_seen(self) -> None:
        """Persist seen URLs to disk."""
        try:
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            SEEN_FILE.write_text(json.dumps(list(self._seen_urls)))
        except Exception as e:
            logger.error(f"Failed to save seen URLs: {e}")

    def _rebuild_url_index(self) -> None:
        """Rebuild the URL index from all buckets."""
        self._url_index.clear()
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            for job in bucket.values():
                self._url_index.add(job.source_url)

    def _dedup_on_load(self) -> None:
        """Remove duplicate jobs (same URL) within and across buckets on startup.

        Priority: applied > saved > pending > rejected.
        If the same URL exists in saved AND pending, the pending copy is removed.
        """
        removed = 0

        # Phase 1: Intra-bucket dedup (same URL twice in one bucket)
        for bucket_name, bucket in [
            ("pending", self._pending),
            ("applied", self._applied),
            ("saved", self._saved),
            ("rejected", self._rejected),
        ]:
            seen: dict[str, str] = {}  # url → first job_id
            to_remove: list[str] = []
            for jid, job in bucket.items():
                if job.source_url in seen:
                    to_remove.append(jid)
                else:
                    seen[job.source_url] = jid
            for jid in to_remove:
                bucket.pop(jid)
                removed += 1
            if to_remove:
                logger.info(
                    f"[DEDUP] Removed {len(to_remove)} intra-bucket dupes from {bucket_name}"
                )

        # Phase 2: Cross-bucket dedup — higher-priority bucket wins
        # Priority order: applied > saved > pending > rejected
        # A URL in "saved" should NOT also be in "pending" or "rejected"
        global_seen: dict[str, str] = {}  # url → bucket_name that owns it
        priority_order = [
            ("applied", self._applied),
            ("saved", self._saved),
            ("pending", self._pending),
            ("rejected", self._rejected),
        ]
        for bucket_name, bucket in priority_order:
            to_remove: list[str] = []
            for jid, job in bucket.items():
                if job.source_url in global_seen:
                    owner = global_seen[job.source_url]
                    logger.info(
                        f"[DEDUP] Cross-bucket: removing '{job.role_title}' from "
                        f"{bucket_name} (already in {owner})"
                    )
                    to_remove.append(jid)
                else:
                    global_seen[job.source_url] = bucket_name
            for jid in to_remove:
                bucket.pop(jid)
                removed += 1

        if removed:
            logger.info(f"[DEDUP] Removed {removed} total duplicate jobs on startup")
            self._save()
        self._rebuild_url_index()
        # Sync seen_urls with what's actually in the store
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            for job in bucket.values():
                self._seen_urls.add(job.source_url)
        self._save_seen()

    # ── URL dedup ────────────────────────────────────────────────────────

    def is_url_seen(self, url: str) -> bool:
        return url in self._seen_urls

    def mark_url_seen(self, url: str) -> None:
        self._seen_urls.add(url)

    def flush_seen(self) -> None:
        self._save_seen()

    def clear_seen(self) -> None:
        """Clear all seen URLs so the next ingest fetches everything fresh."""
        self._seen_urls.clear()
        self._save_seen()

    def clear_pending(self) -> int:
        """Clear all pending jobs. Returns count of jobs cleared."""
        count = len(self._pending)
        self._pending.clear()
        self._save()
        return count

    def expire_old_jobs(self, max_age_days: int = 14) -> int:
        """Remove pending jobs older than max_age_days. Returns count removed."""
        cutoff = datetime.now(timezone.utc) - timedelta(days=max_age_days)
        to_remove = []
        for jid, job in self._pending.items():
            if not job.posted_at or job.posted_at < cutoff:
                to_remove.append(jid)
        for jid in to_remove:
            self._pending.pop(jid)
        if to_remove:
            self._save()
            logger.info(f"Expired {len(to_remove)} jobs older than {max_age_days} days")
        return len(to_remove)

    def purge_keyword_scored(self) -> int:
        """Remove jobs scored by local keyword matcher (bogus scores).
        Also removes their source URLs from seen so they get re-fetched."""
        to_remove = [
            jid for jid, job in self._pending.items()
            if "keyword" in (job.ai_pitch_summary or "").lower()
        ]
        for jid in to_remove:
            job = self._pending.pop(jid)
            self._seen_urls.discard(job.source_url)
        if to_remove:
            self._save()
            self._save_seen()
        return len(to_remove)

    # ── Core operations ──────────────────────────────────────────────────

    def has_url(self, url: str) -> bool:
        """Check if a URL already exists in any bucket (O(1) via index)."""
        return url in self._url_index

    def add_pending(self, job: JobPayload) -> None:
        # Refuse duplicates — same URL in any bucket (belt + suspenders)
        if self.has_url(job.source_url):
            logger.info(
                f"[DEDUP] Skipping duplicate URL (index): {job.source_url[:80]}"
            )
            return
        # Fallback: linear scan in case _url_index drifted
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            for existing in bucket.values():
                if existing.source_url == job.source_url:
                    logger.warning(
                        f"[DEDUP] URL index miss! URL exists in bucket but not index: {job.source_url[:80]}"
                    )
                    self._url_index.add(job.source_url)
                    return
        self._pending[job.id] = job
        self._seen_urls.add(job.source_url)
        self._url_index.add(job.source_url)
        self._save()
        self._save_seen()

    def get_pending(self, limit: int = 20, offset: int = 0) -> list[JobPayload]:
        jobs = list(self._pending.values())
        jobs.sort(key=lambda j: j.builder_score, reverse=True)
        return jobs[offset : offset + limit]

    def get_job(self, job_id: str) -> JobPayload | None:
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            if job_id in bucket:
                return bucket[job_id]
        return None

    def act_on_job(self, job_id: str, action: JobAction) -> bool:
        # Search all buckets to find the job
        job = None
        source_bucket: dict[str, JobPayload] | None = None
        source_name: str = ""
        bucket_map = {
            "pending": self._pending,
            "applied": self._applied,
            "saved": self._saved,
            "rejected": self._rejected,
        }
        for name, bucket in bucket_map.items():
            if job_id in bucket:
                job = bucket[job_id]
                source_bucket = bucket
                source_name = name
                break

        if job is None or source_bucket is None:
            return False

        # Track undo (keep last 20)
        self._undo_stack.append((job_id, action.value, source_name))
        if len(self._undo_stack) > 20:
            self._undo_stack.pop(0)

        # Remove from current bucket
        source_bucket.pop(job_id, None)

        # Place in destination bucket
        match action:
            case JobAction.apply:
                self._applied[job_id] = job
            case JobAction.reject:
                self._rejected[job_id] = job
            case JobAction.save:
                self._saved[job_id] = job

        self._save()
        return True

    def undo_last(self) -> JobPayload | None:
        """Undo the last swipe action. Returns the restored job or None."""
        if not self._undo_stack:
            return None

        job_id, action, source_name = self._undo_stack.pop()

        # Find the job in its current bucket
        dest_map = {
            "apply": self._applied,
            "reject": self._rejected,
            "save": self._saved,
        }
        source_map = {
            "pending": self._pending,
            "applied": self._applied,
            "saved": self._saved,
            "rejected": self._rejected,
        }

        current_bucket = dest_map.get(action)
        if current_bucket is None or job_id not in current_bucket:
            return None

        job = current_bucket.pop(job_id)
        original_bucket = source_map.get(source_name, self._pending)
        original_bucket[job_id] = job

        self._save()
        return job

    def update_job(self, job_id: str, updated: JobPayload) -> bool:
        """Replace a job in-place in whatever bucket it lives in."""
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            if job_id in bucket:
                bucket[job_id] = updated
                self._save()
                return True
        return False

    def all_jobs(self) -> list[JobPayload]:
        """Return every job across all buckets."""
        jobs: list[JobPayload] = []
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            jobs.extend(bucket.values())
        return jobs

    def update_job_notes(self, job_id: str, notes: str) -> bool:
        """Update notes on any job in any bucket."""
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            if job_id in bucket:
                bucket[job_id].notes = notes
                self._save()
                return True
        return False

    def update_job_status(self, job_id: str, status: str) -> bool:
        """Update application status on any job."""
        valid = {"new", "applied", "phone_screen", "interview", "offer", "rejected"}
        if status not in valid:
            return False
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            if job_id in bucket:
                bucket[job_id].application_status = status
                self._save()
                return True
        return False

    def get_applied(self) -> list[JobPayload]:
        _STATUS_ORDER = {
            "interview": 0,
            "phone_screen": 1,
            "offer": 2,
            "applied": 3,
            "new": 4,
            "rejected": 5,
        }
        return sorted(
            self._applied.values(),
            key=lambda j: (
                _STATUS_ORDER.get(j.application_status or "new", 4),
                -j.builder_score,
            ),
        )

    def get_saved(self) -> list[JobPayload]:
        return sorted(
            self._saved.values(),
            key=lambda j: -j.builder_score,
        )

    def get_rejected(self) -> list[JobPayload]:
        return list(self._rejected.values())

    @property
    def pending_count(self) -> int:
        return len(self._pending)

    @property
    def applied_count(self) -> int:
        return len(self._applied)

    @property
    def seen_count(self) -> int:
        return len(self._seen_urls)

    @property
    def stats(self) -> dict:
        return {
            "pending": len(self._pending),
            "applied": len(self._applied),
            "saved": len(self._saved),
            "rejected": len(self._rejected),
        }

    # ── Notion sync helpers ──────────────────────────────────────────────

    def update_notion_page_id(self, job_id: str, page_id: str) -> bool:
        """Set the Notion page ID on a job (cross-reference for sync)."""
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            if job_id in bucket:
                bucket[job_id].notion_page_id = page_id
                self._save()
                return True
        return False

    def get_job_bucket(self, job_id: str) -> str | None:
        """Return which bucket a job lives in."""
        if job_id in self._pending:
            return "pending"
        if job_id in self._applied:
            return "applied"
        if job_id in self._saved:
            return "saved"
        if job_id in self._rejected:
            return "rejected"
        return None

    def move_to_bucket(self, job_id: str, target: str) -> bool:
        """Move a job to a different bucket (used by Notion pull sync)."""
        job = None
        source = None
        for name, bucket in [
            ("pending", self._pending),
            ("applied", self._applied),
            ("saved", self._saved),
            ("rejected", self._rejected),
        ]:
            if job_id in bucket:
                job = bucket.pop(job_id)
                source = name
                break
        if not job:
            return False

        dest_map = {
            "pending": self._pending,
            "applied": self._applied,
            "saved": self._saved,
            "rejected": self._rejected,
        }
        dest = dest_map.get(target)
        if dest is None:
            return False

        dest[job_id] = job
        self._save()
        logger.info(f"[SYNC] Moved {job_id} from {source} → {target}")
        return True


# Singleton
store = JobStore()
