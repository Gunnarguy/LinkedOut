"""Persistent job store — JSON file-backed so restarts don't nuke your queue."""

from __future__ import annotations

import json
import logging
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
        self._load()

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

    # ── URL dedup ────────────────────────────────────────────────────────

    def is_url_seen(self, url: str) -> bool:
        return url in self._seen_urls

    def mark_url_seen(self, url: str) -> None:
        self._seen_urls.add(url)

    def flush_seen(self) -> None:
        self._save_seen()

    # ── Core operations ──────────────────────────────────────────────────

    def add_pending(self, job: JobPayload) -> None:
        self._pending[job.id] = job
        self._seen_urls.add(job.source_url)
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
        job = self._pending.pop(job_id, None)
        if job is None:
            if action == JobAction.apply:
                job = self._saved.pop(job_id, None)
            if job is None:
                return False

        match action:
            case JobAction.apply:
                self._applied[job_id] = job
            case JobAction.reject:
                self._rejected[job_id] = job
            case JobAction.save:
                self._saved[job_id] = job

        self._save()
        return True

    def get_applied(self) -> list[JobPayload]:
        return list(self._applied.values())

    def get_saved(self) -> list[JobPayload]:
        return list(self._saved.values())

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


# Singleton
store = JobStore()
