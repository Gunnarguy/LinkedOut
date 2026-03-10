"""Job fetcher — pulls real listings from free APIs and feeds them to the scoring engine.

Sources:
  1. Remotive (free, no auth, remote-first jobs)
  2. HimalayanJobs / Arbeitnow (free, no auth)
  3. HackerNews "Who's Hiring" (Algolia API, free)
"""

from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timezone

import httpx

from models import RawJobListing

logger = logging.getLogger(__name__)

# Search queries tuned for the user's profile
SEARCH_QUERIES = [
    "AI product engineer",
    "AI engineer",
    "founding engineer AI",
    "product engineer LLM",
    "iOS engineer AI",
    "machine learning engineer",
    "AI startup",
    "LLM engineer",
    "agentic AI",
]

TIMEOUT = httpx.Timeout(15.0, connect=10.0)


async def fetch_remotive(queries: list[str] | None = None) -> list[RawJobListing]:
    """Fetch remote jobs from Remotive API (free, no auth)."""
    queries = queries or SEARCH_QUERIES[:4]
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for query in queries:
            try:
                resp = await client.get(
                    "https://remotive.com/api/remote-jobs",
                    params={"search": query, "limit": 15},
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("jobs", []):
                    url = job.get("url", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    # Clean HTML tags from description
                    desc = re.sub(r"<[^>]+>", " ", job.get("description", ""))
                    desc = re.sub(r"\s+", " ", desc).strip()

                    salary_text = job.get("salary", "") or ""

                    all_listings.append(
                        RawJobListing(
                            title=job.get("title", "Unknown"),
                            company=job.get("company_name", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text,
                            location=job.get("candidate_required_location", "Remote"),
                            is_remote=True,
                        )
                    )

            except Exception as e:
                logger.warning(f"Remotive fetch failed for '{query}': {e}")

    logger.info(f"Remotive: fetched {len(all_listings)} listings")
    return all_listings


async def fetch_himalayas() -> list[RawJobListing]:
    """Fetch jobs from Himalayas.app API (free, remote-first)."""
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for query in SEARCH_QUERIES[:3]:
            try:
                resp = await client.get(
                    "https://himalayas.app/jobs/api",
                    params={"q": query, "limit": 15},
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("jobs", []):
                    url = job.get("applicationUrl") or job.get("url", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("description", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    salary_min = job.get("salaryMin")
                    salary_max = job.get("salaryMax")
                    salary_text = ""
                    if salary_min and salary_max:
                        salary_text = f"${salary_min:,} - ${salary_max:,}"
                    elif salary_min:
                        salary_text = f"${salary_min:,}+"

                    all_listings.append(
                        RawJobListing(
                            title=job.get("title", "Unknown"),
                            company=job.get("companyName", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text,
                            location=job.get("location", "Remote"),
                            is_remote=True,
                        )
                    )

            except Exception as e:
                logger.warning(f"Himalayas fetch failed for '{query}': {e}")

    logger.info(f"Himalayas: fetched {len(all_listings)} listings")
    return all_listings


async def fetch_hn_whoishiring() -> list[RawJobListing]:
    """Fetch from latest HN 'Who is hiring?' thread via Algolia API."""
    all_listings: list[RawJobListing] = []

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        try:
            # Find the latest "Who is hiring?" post
            search_resp = await client.get(
                "https://hn.algolia.com/api/v1/search",
                params={
                    "query": "Ask HN: Who is hiring?",
                    "tags": "story",
                    "hitsPerPage": 1,
                },
            )
            search_resp.raise_for_status()
            stories = search_resp.json().get("hits", [])
            if not stories:
                return all_listings

            story_id = stories[0]["objectID"]

            # Fetch comments (each comment = 1 job listing)
            comments_resp = await client.get(
                f"https://hn.algolia.com/api/v1/items/{story_id}"
            )
            comments_resp.raise_for_status()
            children = comments_resp.json().get("children", [])

            ai_keywords = re.compile(
                r"\bAI\b|artificial.intelligence|\bLLM\b|machine.learning|"
                r"product.engineer|founding.engineer|"
                r"agent(?:ic)?|copilot|GPT|generative.AI|deep.learning|"
                r"(?:iOS|SwiftUI).+(?:AI|ML)|(?:AI|ML).+(?:iOS|mobile)",
                re.IGNORECASE,
            )

            # Must also NOT match strong negative signals
            neg_keywords = re.compile(
                r"\bsenior\b|\bstaff\b|\blead\b|\bprincipal\b|"
                r"\bdirector\b|\bVP\b|\bhead of\b|"
                r"10\+.years|15\+.years|8\+.years|PhD.required",
                re.IGNORECASE,
            )

            for child in children[:300]:
                text = child.get("text", "") or ""
                if not text or len(text) < 80:
                    continue

                # Must have AI/product relevance
                if not ai_keywords.search(text):
                    continue

                # Skip senior-gated roles
                if neg_keywords.search(text):
                    continue

                # Parse first line as title (usually "Company | Role | Location")
                clean_text = re.sub(r"<[^>]+>", "\n", text)
                clean_text = re.sub(r"&[a-z]+;", " ", clean_text)
                lines = [l.strip() for l in clean_text.split("\n") if l.strip()]
                if not lines:
                    continue

                first_line = lines[0]
                parts = [p.strip() for p in first_line.split("|")]

                company = parts[0] if len(parts) >= 1 else "Unknown"
                title = parts[1] if len(parts) >= 2 else first_line
                location = parts[2] if len(parts) >= 3 else ""

                is_remote = bool(
                    re.search(r"remote|anywhere|distributed", location, re.IGNORECASE)
                    or re.search(r"remote|REMOTE", clean_text)
                )

                hn_url = (
                    f"https://news.ycombinator.com/item?id={child.get('id', story_id)}"
                )

                all_listings.append(
                    RawJobListing(
                        title=title[:200],
                        company=company[:100],
                        description="\n".join(lines)[:8000],
                        url=hn_url,
                        salary_text="",
                        location=location or ("Remote" if is_remote else ""),
                        is_remote=is_remote,
                    )
                )

        except Exception as e:
            logger.warning(f"HN Who's Hiring fetch failed: {e}")

    logger.info(f"HN Who's Hiring: fetched {len(all_listings)} listings")
    return all_listings


async def fetch_all_sources() -> list[RawJobListing]:
    """Fetch from all sources concurrently. Returns deduplicated listings."""
    results = await asyncio.gather(
        fetch_remotive(),
        fetch_himalayas(),
        fetch_hn_whoishiring(),
        return_exceptions=True,
    )

    all_listings: list[RawJobListing] = []
    seen_titles: set[str] = set()

    for result in results:
        if isinstance(result, BaseException):
            logger.error(f"Source failed: {result}")
            continue
        listings: list[RawJobListing] = result
        for listing in listings:
            dedup_key = f"{listing.company.lower()}:{listing.title.lower()}"
            if dedup_key not in seen_titles:
                seen_titles.add(dedup_key)
                all_listings.append(listing)

    logger.info(f"Total unique listings from all sources: {len(all_listings)}")
    return all_listings
