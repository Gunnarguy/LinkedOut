"""Persistent job store — JSON file-backed so restarts don't nuke your queue."""

from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path

from models import JobAction, JobPayload

logger = logging.getLogger(__name__)

DATA_DIR = Path("/app/data") if Path("/app").exists() else Path("./data")
STORE_FILE = DATA_DIR / "job_store.json"
SEEN_FILE = DATA_DIR / "seen_urls.json"


# Jobs scoring at or above this threshold are "high salience" and
# protected from age-based expiry.  They clearly describe *you*.
HIGH_SALIENCE_THRESHOLD = 0.65


class JobStore:
    def __init__(self) -> None:
        self._pending: dict[str, JobPayload] = {}
        self._applied: dict[str, JobPayload] = {}
        self._rejected: dict[str, JobPayload] = {}
        self._saved: dict[str, JobPayload] = {}
        self._seen_urls: dict[str, str] = {}  # url → ISO timestamp when first seen
        self._url_index: set[str] = set()  # fast URL lookup across all buckets
        self._undo_stack: list[tuple[str, str, str]] = (
            []
        )  # (job_id, action, source_bucket)
        self._load()
        self._dedup_on_load()
        self._normalize_scoring_on_load()

    def _normalize_signature_text(self, value: str) -> str:
        return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()

    def _content_signature(self, job: JobPayload) -> str:
        company = self._normalize_signature_text(job.company_name or "")
        title = self._normalize_signature_text(job.role_title or "")
        if job.is_remote:
            location_marker = "remote"
        else:
            location_marker = self._normalize_signature_text(job.location or "")[:48]
        return f"{company}|{title}|{location_marker}"

    def _is_placeholder_source(self, url: str) -> bool:
        lower = (url or "").lower()
        return any(token in lower for token in ["example.com", "test-key-check"])

    def _job_quality_key(self, job: JobPayload) -> tuple:
        return (
            not self._is_placeholder_source(job.source_url),
            len(job.description or ""),
            len(job.ai_pitch_summary or ""),
            float(job.builder_score or 0.0),
            bool(job.salary_floor or job.salary_max),
        )

    def _normalize_assessment_text(self, value: str) -> str:
        trimmed = (value or "").strip()
        normalized = trimmed.lower()

        if (
            "generic full-stack or backend software role" in normalized
            and "target lanes" in normalized
        ):
            return (
                "Listing leans toward a general full-stack or backend seat and looks less tied "
                "to your strongest product, workflow, mobile, or healthcare angles."
            )

        if (
            "generic full-stack or backend work" in normalized
            and "builder lanes" in normalized
        ):
            return (
                "Role reads more like a general full-stack or backend seat than one built around "
                "your strongest product, workflow, mobile, or healthcare angles."
            )

        if (
            "specialist ml or security role" in normalized
            and "product-builder lane" in normalized
        ):
            return (
                "Role leans toward specialized ML or security work and looks less aligned with "
                "your strongest product, workflow, mobile, or healthcare angles."
            )

        if (
            "specialized ml or security work" in normalized
            and "lane you're actually targeting" in normalized
        ):
            return (
                "Role leans toward specialized ML or security work and looks less aligned with "
                "your strongest product, workflow, mobile, or healthcare angles."
            )

        return trimmed

    def _normalized_builder_score(self, job: JobPayload) -> float:
        adjusted = max(0.0, min(1.0, float(job.builder_score or 0.0)))
        weighted_composite = (
            (float(job.domain_alignment or 0.0) * 0.20)
            + (float(job.role_alignment or 0.0) * 0.30)
            + (float(job.culture_fit or 0.0) * 0.20)
            + (float(job.experience_friction or 0.0) * 0.15)
            + (float(job.stack_fit or 0.0) * 0.15)
        )

        if job.scoring_version == "apple-intelligence-v1" and weighted_composite > 0:
            adjusted = min(adjusted, min(1.0, weighted_composite + 0.05))

        role_alignment = float(job.role_alignment or 0.0)
        if role_alignment > 0:
            if role_alignment < 0.25:
                adjusted = min(adjusted, 0.35)
            elif role_alignment < 0.35:
                adjusted = min(adjusted, 0.45)
            elif role_alignment < 0.45:
                adjusted = min(adjusted, 0.60)

        return round(adjusted, 2)

    def _normalize_scoring_on_load(self) -> None:
        changed = False

        for bucket_name, bucket in [
            ("pending", self._pending),
            ("applied", self._applied),
            ("saved", self._saved),
            ("rejected", self._rejected),
        ]:
            for job in bucket.values():
                if job.posted_at and job.posted_at.tzinfo is None:
                    job.posted_at = job.posted_at.replace(tzinfo=timezone.utc)
                    changed = True

                normalized_warnings = [
                    self._normalize_assessment_text(item)
                    for item in (job.dealbreaker_warnings or [])
                    if self._normalize_assessment_text(item)
                ]
                normalized_caveats = [
                    self._normalize_assessment_text(item)
                    for item in (job.caveats or [])
                    if self._normalize_assessment_text(item)
                ]
                normalized_red_flags = [
                    self._normalize_assessment_text(item)
                    for item in (job.red_flags or [])
                    if self._normalize_assessment_text(item)
                ]

                if normalized_warnings != (job.dealbreaker_warnings or []):
                    job.dealbreaker_warnings = normalized_warnings
                    changed = True
                if normalized_caveats != (job.caveats or []):
                    job.caveats = normalized_caveats
                    changed = True
                if normalized_red_flags != (job.red_flags or []):
                    job.red_flags = normalized_red_flags
                    changed = True

                normalized_score = self._normalized_builder_score(job)
                if abs(normalized_score - float(job.builder_score or 0.0)) >= 0.01:
                    logger.info(
                        "[STORE] Normalized inflated score for %s @ %s in %s: %.2f -> %.2f",
                        job.role_title,
                        job.company_name,
                        bucket_name,
                        float(job.builder_score or 0.0),
                        normalized_score,
                    )
                    job.builder_score = normalized_score
                    changed = True

        if changed:
            self._save()

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
                raw_seen = json.loads(SEEN_FILE.read_text())
                if isinstance(raw_seen, list):
                    # Migrate from old flat list format → timestamped dict
                    now_iso = datetime.now(timezone.utc).isoformat()
                    self._seen_urls = {url: now_iso for url in raw_seen}
                    logger.info(f"Migrated {len(self._seen_urls)} seen URLs from list to timestamped dict")
                elif isinstance(raw_seen, dict):
                    self._seen_urls = raw_seen
                else:
                    self._seen_urls = {}
                logger.info(f"Loaded {len(self._seen_urls)} seen URLs")
            except Exception as e:
                logger.error(f"Failed to load seen URLs: {e}")

    def _save(self) -> None:
        """Persist state to disk with atomic write to prevent corruption."""
        import os
        import tempfile

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
            fd, tmp_path = tempfile.mkstemp(dir=DATA_DIR, suffix=".tmp")
            try:
                with os.fdopen(fd, "w") as f:
                    json.dump(data, f, default=str)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp_path, STORE_FILE)
            except Exception:
                os.unlink(tmp_path)
                raise
        except Exception as e:
            logger.error(f"Failed to save store: {e}")

    def _save_seen(self) -> None:
        """Persist seen URLs (with timestamps) to disk."""
        try:
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            SEEN_FILE.write_text(json.dumps(self._seen_urls))
        except Exception as e:
            logger.error(f"Failed to save seen URLs: {e}")

    def _rebuild_url_index(self) -> None:
        """Rebuild the URL index from all buckets."""
        self._url_index.clear()
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            for job in bucket.values():
                self._url_index.add(job.source_url)

    def _dedup_on_load(self) -> None:
        """Remove duplicate jobs (same URL or same role signature) within and across buckets on startup.

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

        # Phase 1b: Intra-bucket content-signature dedup (same role/company cross-posted)
        for bucket_name, bucket in [
            ("pending", self._pending),
            ("applied", self._applied),
            ("saved", self._saved),
            ("rejected", self._rejected),
        ]:
            seen_signatures: dict[str, str] = {}  # signature -> winning job_id
            to_remove: list[str] = []
            for jid, job in bucket.items():
                signature = self._content_signature(job)
                if signature in seen_signatures:
                    winner_id = seen_signatures[signature]
                    winner = bucket[winner_id]
                    if self._job_quality_key(job) > self._job_quality_key(winner):
                        to_remove.append(winner_id)
                        seen_signatures[signature] = jid
                    else:
                        to_remove.append(jid)
                else:
                    seen_signatures[signature] = jid
            for jid in set(to_remove):
                bucket.pop(jid, None)
                removed += 1
            if to_remove:
                logger.info(
                    f"[DEDUP] Removed {len(set(to_remove))} intra-bucket signature dupes from {bucket_name}"
                )

        # Phase 2: Cross-bucket dedup — higher-priority bucket wins
        # Priority order: applied > saved > pending > rejected
        # A URL in "saved" should NOT also be in "pending" or "rejected"
        global_seen: dict[str, str] = {}  # url → bucket_name that owns it
        global_signatures: dict[str, str] = {}  # signature -> bucket_name that owns it
        priority_order = [
            ("applied", self._applied),
            ("saved", self._saved),
            ("pending", self._pending),
            ("rejected", self._rejected),
        ]
        for bucket_name, bucket in priority_order:
            to_remove: list[str] = []
            for jid, job in bucket.items():
                signature = self._content_signature(job)
                if job.source_url in global_seen:
                    owner = global_seen[job.source_url]
                    logger.info(
                        f"[DEDUP] Cross-bucket: removing '{job.role_title}' from "
                        f"{bucket_name} (already in {owner})"
                    )
                    to_remove.append(jid)
                elif signature in global_signatures:
                    owner = global_signatures[signature]
                    logger.info(
                        f"[DEDUP] Cross-bucket signature: removing '{job.role_title}' from "
                        f"{bucket_name} (already in {owner})"
                    )
                    to_remove.append(jid)
                else:
                    global_seen[job.source_url] = bucket_name
                    global_signatures[signature] = bucket_name
            for jid in to_remove:
                bucket.pop(jid)
                removed += 1

        if removed:
            logger.info(f"[DEDUP] Removed {removed} total duplicate jobs on startup")
            self._save()
        self._rebuild_url_index()
        # Sync seen_urls with what's actually in the store
        now_iso = datetime.now(timezone.utc).isoformat()
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            for job in bucket.values():
                if job.source_url not in self._seen_urls:
                    self._seen_urls[job.source_url] = now_iso
        self._save_seen()

    # ── URL dedup ────────────────────────────────────────────────────────

    def is_url_seen(self, url: str) -> bool:
        return url in self._seen_urls

    def mark_url_seen(self, url: str) -> None:
        if url not in self._seen_urls:
            self._seen_urls[url] = datetime.now(timezone.utc).isoformat()

    def flush_seen(self) -> None:
        self._save_seen()

    def clear_seen(self) -> None:
        """Clear all seen URLs so the next ingest fetches everything fresh."""
        self._seen_urls.clear()
        self._save_seen()

    def expire_stale_seen_urls(self, max_age_days: int = 30) -> int:
        """Remove seen URLs older than max_age_days IF they aren't stored in any bucket.
        This lets discarded jobs be re-evaluated with updated preferences/models."""
        cutoff = datetime.now(timezone.utc) - timedelta(days=max_age_days)
        stored_urls = self._url_index  # URLs that are actually in a bucket
        to_remove = []
        for url, ts_str in self._seen_urls.items():
            if url in stored_urls:
                continue  # job is stored — keep it seen
            try:
                seen_at = datetime.fromisoformat(ts_str)
                if seen_at < cutoff:
                    to_remove.append(url)
            except (ValueError, TypeError):
                to_remove.append(url)  # bad timestamp → allow re-fetch
        for url in to_remove:
            del self._seen_urls[url]
        if to_remove:
            self._save_seen()
            logger.info(f"Expired {len(to_remove)} stale seen URLs older than {max_age_days} days")
        return len(to_remove)

    def clear_pending(self) -> int:
        """Clear all pending jobs. Returns count of jobs cleared."""
        count = len(self._pending)
        self._pending.clear()
        self._save()
        return count

    def expire_old_jobs(self, max_age_days: int = 30) -> int:
        """Remove pending jobs older than max_age_days.
        High-salience jobs (score >= HIGH_SALIENCE_THRESHOLD) are NEVER expired.
        Jobs with no posted_at are kept (not silently deleted).
        Returns count removed."""
        cutoff = datetime.now(timezone.utc) - timedelta(days=max_age_days)
        to_remove = []
        for jid, job in self._pending.items():
            # Never expire high-salience jobs — these are your best matches
            if job.builder_score >= HIGH_SALIENCE_THRESHOLD:
                continue
            # Keep jobs with no posted_at rather than silently deleting them
            if not job.posted_at:
                continue
            if job.posted_at < cutoff:
                to_remove.append(jid)
        for jid in to_remove:
            self._pending.pop(jid)
        if to_remove:
            self._save()
            logger.info(f"Expired {len(to_remove)} low-score jobs older than {max_age_days} days")
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
            self._seen_urls.pop(job.source_url, None)
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
        new_signature = self._content_signature(job)
        for bucket in (self._pending, self._applied, self._saved, self._rejected):
            for existing in bucket.values():
                if self._content_signature(existing) == new_signature:
                    logger.info(
                        f"[DEDUP] Skipping duplicate role signature: {job.role_title} @ {job.company_name}"
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
        self.mark_url_seen(job.source_url)
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

    def act_on_job(
        self, job_id: str, action: JobAction, fallback_job: JobPayload | None = None
    ) -> bool:
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
            if fallback_job:
                # Reconstruct state from client if backend lost it via ephemeral container reset
                logger.warning(f"Reconstructing lost job {job_id} from client payload")
                job = fallback_job
                source_bucket = self._pending
                source_name = "pending"
                self.mark_url_seen(job.source_url)
                self._save_seen()
            else:
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
