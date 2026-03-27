"""Job fetcher — pulls real listings from free APIs and feeds them to the scoring engine.

Sources (free, no auth):
  1. Remotive (remote-first jobs)
  2. HimalayanJobs / Arbeitnow (remote-first)
  3. HackerNews "Who's Hiring" (Algolia API)
  4. Jobicy (remote-first)
  5. RemoteOK
  6. We Work Remotely (RSS feed — top remote job board)
  7. Arbeitnow (EU + global remote)
  8. The Muse (career platform)
  9. Working Nomads (curated remote dev/data jobs — JSON API)
 10. Jobspresso (curated remote jobs — RSS feed with keyword search)

Sources (API key required — gracefully skipped if not configured):
 11. SerpAPI Google Jobs (aggregates LinkedIn, Indeed, Glassdoor, ZipRecruiter, etc.)
 12. Adzuna (major aggregator — US + 18 countries)
 13. FindWork.dev (dev/startup focused)
 14. Reed.co.uk (UK + remote jobs)
 15. FindWork.dev (dev/startup focused)
 14. Reed.co.uk (UK + remote jobs)
 15. USAJobs (federal tech/health IT jobs)
"""

from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timezone

import httpx

from models import RawJobListing

logger = logging.getLogger(__name__)

# Search queries — MedTech/AI orchestration/iOS focused
# These determine what enters the pipeline. Every query should attract roles
# where Gunnar's prompt-to-production + clinical domain background is an asset.
SEARCH_QUERIES = [
    # Healthcare / MedTech / Clinical AI — PRIMARY TARGET
    "healthcare AI",
    "healthtech engineer",
    "medtech engineer",
    "clinical AI",
    "medical device software",
    "healthcare software engineer",
    "health tech startup",
    "digital health engineer",
    "clinical software",
    "HIPAA engineer",
    "biotech software",
    "healthcare iOS",
    "medical AI",
    "health AI startup",
    "healthcare technology",
    "health informatics",
    "clinical data",
    # AI Orchestration / Prompt-to-Production — CORE SKILL
    "AI engineer",
    "AI product engineer",
    "applied AI engineer",
    "AI solutions engineer",
    "generative AI engineer",
    "LLM engineer",
    "RAG engineer",
    "AI agent engineer",
    "prompt engineer",
    "AI app builder",
    "AI prototyping",
    "AI automation engineer",
    "AI implementation",
    "AI integration engineer",
    "AI application developer",
    "AI tools engineer",
    "agentic AI",
    "AI workflow",
    "conversational AI",
    # iOS / Mobile at AI companies
    "iOS engineer AI",
    "iOS engineer startup",
    "SwiftUI engineer",
    "mobile AI engineer",
    "on-device ML",
    "iOS developer remote",
    "mobile engineer startup",
    # Product / Founding / Zero-to-One — builder culture
    "founding engineer",
    "product engineer AI",
    "founding engineer startup",
    "zero to one engineer",
    "full stack engineer AI",
    "startup engineer",
    "early stage engineer",
    "first engineer",
    # General AI + emerging roles
    "AI startup",
    "developer tools AI",
    "machine learning startup",
    "AI developer",
    "AI native",
    "no degree engineer",
    "technical AI",
    "AI platform engineer",
]

TIMEOUT = httpx.Timeout(15.0, connect=10.0)


async def fetch_remotive(queries: list[str] | None = None) -> list[RawJobListing]:
    """Fetch remote jobs from Remotive API (free, no auth)."""
    import time as _time
    t0 = _time.monotonic()
    queries = queries or SEARCH_QUERIES
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for query in queries:
            try:
                resp = await client.get(
                    "https://remotive.com/api/remote-jobs",
                    params={"search": query, "limit": 25},
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

    logger.info(f"Remotive: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s")
    return all_listings


async def fetch_himalayas() -> list[RawJobListing]:
    """Fetch jobs from Himalayas.app API (free, remote-first)."""
    import time as _time
    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for query in SEARCH_QUERIES:
            try:
                resp = await client.get(
                    "https://himalayas.app/jobs/api",
                    params={"q": query, "limit": 25},
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

    logger.info(f"Himalayas: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s")
    return all_listings


async def fetch_hn_whoishiring() -> list[RawJobListing]:
    """Fetch from latest HN 'Who is hiring?' thread via Algolia API."""
    import time as _time
    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        try:
            # Find the latest "Who is hiring?" post (sorted by date)
            search_resp = await client.get(
                "https://hn.algolia.com/api/v1/search_by_date",
                params={
                    "query": "Ask HN: Who is hiring?",
                    "tags": "story,ask_hn",
                    "hitsPerPage": 5,
                },
            )
            search_resp.raise_for_status()
            stories = search_resp.json().get("hits", [])
            if not stories:
                return all_listings

            # Pick the actual monthly "Who is hiring?" (not "right now" variants)
            story_id = None
            for story in stories:
                title = story.get("title", "")
                # Monthly threads are titled "Ask HN: Who is hiring? (Month Year)"
                if "who is hiring?" in title.lower() and "right now" not in title.lower():
                    story_id = story["objectID"]
                    logger.info(f"HN thread: {title} (id={story_id})")
                    break
            if not story_id:
                # Fall back to first result
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
                r"(?:iOS|SwiftUI).+(?:AI|ML)|(?:AI|ML).+(?:iOS|mobile)|"
                r"health(?:care|tech)|medtech|clinical|medical.device|HIPAA|"
                r"prompt.engineer|AI.native|ship.fast|zero.to.one|0.to.1|"
                r"\bstartup\b|seed.stage|series.A|early.stage|"
                r"\biOS\b|SwiftUI|mobile.engineer|"
                r"\bRAG\b|vector.(?:db|database)|embeddings|"
                r"on.device.(?:ML|AI)|CoreML",
                re.IGNORECASE,
            )

            # Only filter out clearly executive/director-level roles
            # Let the scoring engine evaluate senior/staff/lead properly
            neg_keywords = re.compile(
                r"\bdirector\b|\bVP\b|\bhead of\b|\bCTO\b|\bCEO\b|"
                r"15\+.years|PhD.required",
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

                # RECURSIVELY FETCH ALL REPLIES
                # Important for context like "position filled" or "no US candidates"
                def gather_replies(node) -> list[str]:
                    collected = []
                    for c in node.get("children", []):
                        ctext = c.get("text") or ""
                        if ctext:
                            cc = re.sub(r"<[^>]+>", "\n", ctext)
                            cc = re.sub(r"&[a-z]+;", " ", cc)
                            cauthor = c.get("author", "someone")
                            collected.append(f"Comment from {cauthor}: {cc.strip()}")
                        collected.extend(gather_replies(c))
                    return collected

                replies = gather_replies(child)
                if replies:
                    clean_text += "\n\n[USER REPLIES TO THIS POSTING - CRITICAL CONTEXT]\n"
                    clean_text += "\n\n".join(replies)

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

    logger.info(f"HN Who's Hiring: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s")
    return all_listings


async def fetch_jobicy() -> list[RawJobListing]:
    """Fetch jobs from Jobicy API (free, no auth, remote-first)."""
    import time as _time
    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for tag in [
            "ai",
            "python",
            "ios",
            "healthcare",
            "machine-learning",
            "data-science",
            "startup",
            "product",
            "mobile",
            "swift",
            "medical",
        ]:
            try:
                resp = await client.get(
                    "https://jobicy.com/api/v2/remote-jobs",
                    params={"count": 20, "tag": tag},
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("jobs", []):
                    url = job.get("url", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("jobDescription", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    salary_min = job.get("annualSalaryMin", "")
                    salary_max = job.get("annualSalaryMax", "")
                    salary_text = ""
                    if salary_min and salary_max:
                        salary_text = f"${salary_min} - ${salary_max}"

                    location = job.get("jobGeo", "") or "Remote"

                    all_listings.append(
                        RawJobListing(
                            title=job.get("jobTitle", "Unknown"),
                            company=job.get("companyName", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text,
                            location=location,
                            is_remote=True,
                        )
                    )

            except Exception as e:
                logger.warning(f"Jobicy fetch failed for tag '{tag}': {e}")

    logger.info(f"Jobicy: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s")
    return all_listings


async def fetch_remoteok() -> list[RawJobListing]:
    """Fetch jobs from RemoteOK API (free, no auth)."""
    import time as _time
    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []

    async with httpx.AsyncClient(
        timeout=TIMEOUT, headers={"User-Agent": "LinkedOut/1.0"}
    ) as client:
        try:
            resp = await client.get("https://remoteok.com/api")
            resp.raise_for_status()
            data = resp.json()

            # First element is metadata, skip it
            jobs = data[1:] if len(data) > 1 else []

            for job in jobs[:100]:
                url = job.get("url", "")
                if not url:
                    url = f"https://remoteok.com/remote-jobs/{job.get('id', '')}"

                desc = job.get("description", "") or ""
                desc = re.sub(r"<[^>]+>", " ", desc)
                desc = re.sub(r"\s+", " ", desc).strip()

                salary_min = job.get("salary_min")
                salary_max = job.get("salary_max")
                salary_text = ""
                if salary_min and salary_max:
                    salary_text = f"${int(salary_min):,} - ${int(salary_max):,}"

                tags = job.get("tags", []) or []
                location = job.get("location", "") or "Remote"

                all_listings.append(
                    RawJobListing(
                        title=job.get("position", "Unknown"),
                        company=job.get("company", "Unknown"),
                        description=desc[:8000],
                        url=url,
                        salary_text=salary_text,
                        location=location,
                        is_remote=True,
                    )
                )

        except Exception as e:
            logger.warning(f"RemoteOK fetch failed: {e}")

    logger.info(f"RemoteOK: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s")
    return all_listings


async def fetch_weworkremotely() -> list[RawJobListing]:
    """Fetch jobs from We Work Remotely RSS feeds (free, no auth, top remote board)."""
    import time as _time
    import xml.etree.ElementTree as ET

    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    categories = [
        "programming",
        "design",
        "devops-sysadmin",
        "product",
        "data",
    ]

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for category in categories:
            try:
                resp = await client.get(
                    f"https://weworkremotely.com/categories/remote-{category}-jobs.rss"
                )
                resp.raise_for_status()

                root = ET.fromstring(resp.text)
                for item in root.findall(".//item"):
                    url = (item.findtext("link") or "").strip()
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    title = item.findtext("title") or "Unknown"
                    # Title format is often "Company: Role"
                    company = "Unknown"
                    if ": " in title:
                        company, title = title.split(": ", 1)

                    desc = item.findtext("description") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"&[a-z]+;", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    all_listings.append(
                        RawJobListing(
                            title=title[:200],
                            company=company[:100],
                            description=desc[:8000],
                            url=url,
                            salary_text="",
                            location="Remote",
                            is_remote=True,
                        )
                    )

            except Exception as e:
                logger.warning(f"WWR fetch failed for '{category}': {e}")

    logger.info(
        f"WeWorkRemotely: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_arbeitnow() -> list[RawJobListing]:
    """Fetch jobs from Arbeitnow API (free, no auth, EU + global remote jobs)."""
    import time as _time

    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        try:
            # Arbeitnow has a simple paginated API — fetch first 2 pages
            for page in range(1, 3):
                resp = await client.get(
                    "https://www.arbeitnow.com/api/job-board-api",
                    params={"page": page},
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("data", []):
                    url = job.get("url", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("description", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    location = job.get("location", "") or "Unknown"
                    is_remote = job.get("remote", False)

                    tags = job.get("tags", []) or []

                    all_listings.append(
                        RawJobListing(
                            title=job.get("title", "Unknown"),
                            company=job.get("company_name", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text="",
                            location=(
                                location if not is_remote else f"{location} (Remote)"
                            ),
                            is_remote=is_remote,
                        )
                    )

        except Exception as e:
            logger.warning(f"Arbeitnow fetch failed: {e}")

    logger.info(
        f"Arbeitnow: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_themuse(locations: list[str] | None = None) -> list[RawJobListing]:
    """Fetch jobs from The Muse public API (free, no auth, well-known career platform).

    When locations are provided, runs additional location-scoped searches.
    """
    import time as _time

    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    categories = [
        "Software Engineer",
        "Data Science",
        "Product Management",
        "Design and UX",
        "IT",
    ]

    # Build search plan: (category, location_filter)
    search_plan: list[tuple[str, str]] = [(c, "") for c in categories]
    if locations:
        for loc in locations:
            for c in categories:
                search_plan.append((c, loc))
        logger.info(
            f"The Muse: {len(search_plan)} total searches ({len(categories)} base + {len(locations)} locations)"
        )

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for category, location_filter in search_plan:
            try:
                params: dict = {"category": category, "page": 0, "descending": "true"}
                if location_filter:
                    params["location"] = location_filter
                resp = await client.get(
                    "https://www.themuse.com/api/public/jobs",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("results", []):
                    # The Muse uses refs.landing_page for the job URL
                    refs = job.get("refs", {})
                    url = refs.get("landing_page", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("contents", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"&[a-z]+;", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    company_obj = job.get("company", {})
                    company = (
                        company_obj.get("name", "Unknown") if company_obj else "Unknown"
                    )

                    job_locations = job.get("locations", [])
                    location_str = (
                        ", ".join(
                            loc.get("name", "")
                            for loc in job_locations
                            if loc.get("name")
                        )
                        or "Unknown"
                    )

                    is_remote = bool(
                        re.search(r"remote|flexible", location_str, re.IGNORECASE)
                    )

                    all_listings.append(
                        RawJobListing(
                            title=job.get("name", "Unknown"),
                            company=company,
                            description=desc[:8000],
                            url=url,
                            salary_text="",
                            location=location_str,
                            is_remote=is_remote,
                        )
                    )

            except Exception as e:
                logger.warning(f"The Muse fetch failed for '{category}': {e}")

    logger.info(
        f"The Muse: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


# ── API-key-based sources (gracefully skipped when keys not configured) ──


async def fetch_serpapi_google_jobs(
    locations: list[str] | None = None,
) -> list[RawJobListing]:
    """Fetch via SerpAPI Google Jobs — aggregates LinkedIn, Indeed, Glassdoor, etc.

    Requires SERPAPI_API_KEY env var (free 250 searches/month at serpapi.com).
    When locations are provided, runs additional location-scoped searches.
    """
    import time as _time
    from config import settings

    t0 = _time.monotonic()
    if not settings.serpapi_api_key:
        logger.debug("SerpAPI: skipped (SERPAPI_API_KEY not set)")
        return []

    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    # Use a targeted subset of queries to stay within free tier budget
    serpapi_queries = [
        "healthcare AI engineer remote",
        "founding engineer AI startup",
        "iOS engineer AI startup",
        "LLM engineer remote",
        "AI product engineer",
        "medical device software engineer",
        "generative AI engineer",
        "health tech startup engineer",
        "SwiftUI engineer remote",
        "machine learning engineer startup",
        "applied AI engineer",
        "RAG engineer",
        "AI agent engineer remote",
        "digital health engineer",
        "clinical AI software",
    ]

    # Build search plan: base queries (no location) + location-scoped queries
    search_plan: list[tuple[str, str]] = [(q, "") for q in serpapi_queries]
    if locations:
        # Top 5 queries per location to stay within free-tier budget
        loc_queries = serpapi_queries[:5]
        for loc in locations:
            for q in loc_queries:
                search_plan.append((q, loc))
        logger.info(
            f"SerpAPI: {len(search_plan)} total searches ({len(serpapi_queries)} base + {len(locations)} locations × {len(loc_queries)} queries)"
        )

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for query, location_filter in search_plan:
            try:
                params = {
                    "engine": "google_jobs",
                    "q": query,
                    "hl": "en",
                    "gl": "us",
                    "api_key": settings.serpapi_api_key,
                }
                if location_filter:
                    params["location"] = location_filter
                resp = await client.get(
                    "https://serpapi.com/search.json",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("jobs_results", []):
                    # Get the best apply URL
                    apply_options = job.get("apply_options", [])
                    url = ""
                    if apply_options:
                        url = apply_options[0].get("link", "")
                    if not url:
                        url = job.get("share_link", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("description", "") or ""
                    desc = re.sub(r"\s+", " ", desc).strip()

                    detected = job.get("detected_extensions", {})
                    salary_text = detected.get("salary", "")
                    is_remote = detected.get("work_from_home", False)
                    location = job.get("location", "") or ""
                    if is_remote and "remote" not in location.lower():
                        location = f"{location} (Remote)" if location else "Remote"

                    all_listings.append(
                        RawJobListing(
                            title=job.get("title", "Unknown"),
                            company=job.get("company_name", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text or "",
                            location=location or "Unknown",
                            is_remote=is_remote,
                        )
                    )

            except Exception as e:
                logger.warning(f"SerpAPI fetch failed for '{query}': {e}")

    logger.info(
        f"SerpAPI Google Jobs: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_adzuna(locations: list[str] | None = None) -> list[RawJobListing]:
    """Fetch from Adzuna API — major aggregator for US + international.

    Requires ADZUNA_APP_ID + ADZUNA_APP_KEY (free at developer.adzuna.com).
    When locations are provided, runs additional location-scoped searches.
    """
    import time as _time
    from config import settings

    t0 = _time.monotonic()
    if not settings.adzuna_app_id or not settings.adzuna_app_key:
        logger.debug("Adzuna: skipped (ADZUNA_APP_ID/ADZUNA_APP_KEY not set)")
        return []

    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    adzuna_queries = [
        "AI engineer",
        "healthcare AI",
        "iOS developer",
        "machine learning engineer",
        "founding engineer",
        "LLM engineer",
        "product engineer startup",
        "health tech software",
        "generative AI",
        "medical software engineer",
    ]

    # Build search plan: (query, location_filter)
    search_plan: list[tuple[str, str]] = [(q, "") for q in adzuna_queries]
    if locations:
        for loc in locations:
            for q in adzuna_queries:
                search_plan.append((q, loc))
        logger.info(
            f"Adzuna: {len(search_plan)} total searches ({len(adzuna_queries)} base + {len(locations)} locations)"
        )

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for query, location_filter in search_plan:
            try:
                params = {
                    "app_id": settings.adzuna_app_id,
                    "app_key": settings.adzuna_app_key,
                    "what": query,
                    "results_per_page": 20,
                    "content-type": "application/json",
                }
                if location_filter:
                    params["where"] = location_filter
                resp = await client.get(
                    "https://api.adzuna.com/v1/api/jobs/us/search/1",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("results", []):
                    url = job.get("redirect_url", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("description", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    salary_min = job.get("salary_min")
                    salary_max = job.get("salary_max")
                    salary_text = ""
                    if salary_min and salary_max:
                        salary_text = f"${int(salary_min):,} - ${int(salary_max):,}"
                    elif salary_min:
                        salary_text = f"${int(salary_min):,}+"

                    loc = job.get("location", {})
                    location = loc.get("display_name", "") or "Unknown"

                    title = job.get("title", "Unknown")
                    title = re.sub(
                        r"<[^>]+>", "", title
                    )  # Adzuna sometimes wraps keywords in <strong>

                    company_obj = job.get("company", {})
                    company = (
                        company_obj.get("display_name", "Unknown")
                        if company_obj
                        else "Unknown"
                    )

                    is_remote = bool(
                        re.search(
                            r"remote|anywhere|work from home",
                            f"{location} {title} {desc}",
                            re.IGNORECASE,
                        )
                    )

                    all_listings.append(
                        RawJobListing(
                            title=title,
                            company=company,
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text,
                            location=location,
                            is_remote=is_remote,
                        )
                    )

            except Exception as e:
                logger.warning(f"Adzuna fetch failed for '{query}': {e}")

    logger.info(
        f"Adzuna: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_findwork(locations: list[str] | None = None) -> list[RawJobListing]:
    """Fetch from FindWork.dev API — dev/startup focused jobs.

    Requires FINDWORK_API_TOKEN (free at findwork.dev/developers).
    When locations are provided, runs additional location-scoped searches.
    """
    import time as _time
    from config import settings

    t0 = _time.monotonic()
    if not settings.findwork_api_token:
        logger.debug("FindWork: skipped (FINDWORK_API_TOKEN not set)")
        return []

    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    findwork_queries = [
        "AI",
        "machine learning",
        "iOS",
        "healthcare",
        "startup",
        "LLM",
        "product engineer",
        "founding engineer",
    ]

    # Build search plan: (query, location_filter)
    search_plan: list[tuple[str, str]] = [(q, "") for q in findwork_queries]
    if locations:
        for loc in locations:
            for q in findwork_queries:
                search_plan.append((q, loc))
        logger.info(
            f"FindWork: {len(search_plan)} total searches ({len(findwork_queries)} base + {len(locations)} locations)"
        )

    async with httpx.AsyncClient(
        timeout=TIMEOUT,
        headers={"Authorization": f"Token {settings.findwork_api_token}"},
    ) as client:
        for query, location_filter in search_plan:
            try:
                params: dict = {"search": query, "sort_by": "relevance"}
                if location_filter:
                    params["location"] = location_filter
                resp = await client.get(
                    "https://findwork.dev/api/jobs/",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("results", []):
                    url = job.get("url", "")
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("text", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    is_remote = job.get("remote", False)
                    location = job.get("location", "") or (
                        "Remote" if is_remote else "Unknown"
                    )

                    all_listings.append(
                        RawJobListing(
                            title=job.get("role", "Unknown"),
                            company=job.get("company_name", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text="",
                            location=location,
                            is_remote=is_remote,
                        )
                    )

            except Exception as e:
                logger.warning(f"FindWork fetch failed for '{query}': {e}")

    logger.info(
        f"FindWork: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_reed(locations: list[str] | None = None) -> list[RawJobListing]:
    """Fetch from Reed.co.uk API — UK + global remote tech jobs.

    Requires REED_API_KEY (free at reed.co.uk/developers).
    When locations are provided, runs additional location-scoped searches.
    """
    import time as _time
    from base64 import b64encode
    from config import settings

    t0 = _time.monotonic()
    if not settings.reed_api_key:
        logger.debug("Reed: skipped (REED_API_KEY not set)")
        return []

    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    # Reed uses basic auth with API key as username, empty password
    auth_str = b64encode(f"{settings.reed_api_key}:".encode()).decode()

    reed_queries = [
        "AI engineer remote",
        "machine learning remote",
        "iOS developer remote",
        "health tech engineer",
        "product engineer startup",
        "LLM engineer",
    ]

    # Build search plan: (query, location_filter)
    search_plan: list[tuple[str, str]] = [(q, "") for q in reed_queries]
    if locations:
        for loc in locations:
            for q in reed_queries:
                search_plan.append((q, loc))
        logger.info(
            f"Reed: {len(search_plan)} total searches ({len(reed_queries)} base + {len(locations)} locations)"
        )

    async with httpx.AsyncClient(
        timeout=TIMEOUT,
        headers={"Authorization": f"Basic {auth_str}"},
    ) as client:
        for query, location_filter in search_plan:
            try:
                params: dict = {"keywords": query, "resultsToTake": 25}
                if location_filter:
                    params["locationName"] = location_filter
                resp = await client.get(
                    "https://www.reed.co.uk/api/1.0/search",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

                for job in data.get("results", []):
                    job_id = job.get("jobId", "")
                    url = (
                        job.get("jobUrl", "") or f"https://www.reed.co.uk/jobs/{job_id}"
                    )
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = job.get("jobDescription", "") or ""
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    salary_min = job.get("minimumSalary")
                    salary_max = job.get("maximumSalary")
                    salary_text = ""
                    if salary_min and salary_max:
                        salary_text = f"£{int(salary_min):,} - £{int(salary_max):,}"
                    elif salary_min:
                        salary_text = f"£{int(salary_min):,}+"

                    location = job.get("locationName", "") or "UK"
                    is_remote = bool(
                        re.search(
                            r"remote|work from home|anywhere",
                            f"{location} {desc}",
                            re.IGNORECASE,
                        )
                    )

                    all_listings.append(
                        RawJobListing(
                            title=job.get("jobTitle", "Unknown"),
                            company=job.get("employerName", "Unknown"),
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text,
                            location=location,
                            is_remote=is_remote,
                        )
                    )

            except Exception as e:
                logger.warning(f"Reed fetch failed for '{query}': {e}")

    logger.info(
        f"Reed: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_usajobs(locations: list[str] | None = None) -> list[RawJobListing]:
    """Fetch from USAJobs API — federal government tech/health IT jobs.

    Requires USAJOBS_API_KEY + USAJOBS_EMAIL (free at developer.usajobs.gov).
    When locations are provided, runs additional location-scoped searches.
    """
    import time as _time
    from config import settings

    t0 = _time.monotonic()
    if not settings.usajobs_api_key or not settings.usajobs_email:
        logger.debug("USAJobs: skipped (USAJOBS_API_KEY/USAJOBS_EMAIL not set)")
        return []

    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    usajobs_queries = [
        "artificial intelligence",
        "software engineer",
        "data scientist",
        "health IT",
        "iOS developer",
        "machine learning",
        "cybersecurity",
        "digital services",
    ]

    # Build search plan: (query, location_filter)
    search_plan: list[tuple[str, str]] = [(q, "") for q in usajobs_queries]
    if locations:
        for loc in locations:
            for q in usajobs_queries:
                search_plan.append((q, loc))
        logger.info(
            f"USAJobs: {len(search_plan)} total searches ({len(usajobs_queries)} base + {len(locations)} locations)"
        )

    async with httpx.AsyncClient(
        timeout=TIMEOUT,
        headers={
            "Authorization-Key": settings.usajobs_api_key,
            "User-Agent": settings.usajobs_email,
            "Host": "data.usajobs.gov",
        },
    ) as client:
        for query, location_filter in search_plan:
            try:
                params: dict = {
                    "Keyword": query,
                    "ResultsPerPage": 25,
                }
                if location_filter:
                    params["LocationName"] = location_filter
                resp = await client.get(
                    "https://data.usajobs.gov/api/search",
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

                items = data.get("SearchResult", {}).get("SearchResultItems", [])

                for item in items:
                    matched = item.get("MatchedObjectDescriptor", {})
                    apply_uris = matched.get("ApplyURI", [])
                    url = (
                        apply_uris[0] if apply_uris else matched.get("PositionURI", "")
                    )
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    desc = (
                        matched.get("UserArea", {})
                        .get("Details", {})
                        .get("JobSummary", "")
                        or ""
                    )
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    # Qualification summary often has good detail
                    qual = matched.get("QualificationSummary", "") or ""
                    if qual:
                        desc = f"{desc}\n\nQualifications: {qual}"

                    remuneration = matched.get("PositionRemuneration", [])
                    salary_text = ""
                    if remuneration:
                        pay = remuneration[0]
                        sal_min = pay.get("MinimumRange", "")
                        sal_max = pay.get("MaximumRange", "")
                        interval = pay.get("Description", "Per Year")
                        if sal_min and sal_max:
                            salary_text = f"${sal_min} - ${sal_max} {interval}"

                    location = matched.get("PositionLocationDisplay", "") or "USA"
                    is_remote = bool(
                        re.search(
                            r"remote|telework|anywhere|virtual",
                            f"{location} {matched.get('PositionOfferingType', [{}])}",
                            re.IGNORECASE,
                        )
                    )

                    org = matched.get("OrganizationName", "") or "US Government"

                    all_listings.append(
                        RawJobListing(
                            title=matched.get("PositionTitle", "Unknown"),
                            company=org,
                            description=desc[:8000],
                            url=url,
                            salary_text=salary_text,
                            location=location,
                            is_remote=is_remote,
                        )
                    )

            except Exception as e:
                logger.warning(f"USAJobs fetch failed for '{query}': {e}")

    logger.info(
        f"USAJobs: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_workingnomads() -> list[RawJobListing]:
    """Fetch from Working Nomads API (free, no auth, curated remote jobs).

    Returns full JSON array with title, company, description, tags, location.
    Filters by Development + Data categories (most relevant to our search profile).
    """
    import time as _time

    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    # Working Nomads returns ALL jobs in one call — filter client-side
    target_categories = {"development", "data", "design", "management", "devops"}

    async with httpx.AsyncClient(
        timeout=TIMEOUT, headers={"User-Agent": "LinkedOut/1.0"}
    ) as client:
        try:
            resp = await client.get("https://www.workingnomads.com/api/exposed_jobs/")
            resp.raise_for_status()
            data = resp.json()

            for job in data:
                category = (job.get("category_name", "") or "").lower()
                if category and category not in target_categories:
                    continue

                url = job.get("url", "")
                if not url or url in seen_urls:
                    continue
                seen_urls.add(url)

                desc = job.get("description", "") or ""
                desc = re.sub(r"<[^>]+>", " ", desc)
                desc = re.sub(r"\s+", " ", desc).strip()

                tags = job.get("tags", "") or ""
                location = job.get("location", "") or "Remote"

                # Append tags to description for better scoring context
                if tags:
                    desc = f"{desc}\n\nTags: {tags}"

                all_listings.append(
                    RawJobListing(
                        title=job.get("title", "Unknown"),
                        company=job.get("company_name", "Unknown"),
                        description=desc[:8000],
                        url=url,
                        salary_text="",
                        location=location,
                        is_remote=True,
                    )
                )

        except Exception as e:
            logger.warning(f"Working Nomads fetch failed: {e}")

    logger.info(
        f"WorkingNomads: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_jobspresso() -> list[RawJobListing]:
    """Fetch from Jobspresso RSS feed (free, no auth, curated remote jobs).

    Supports keyword search and job type filtering via RSS URL params.
    Categories: ai-data, developer, product-mgmt.
    """
    import time as _time
    import xml.etree.ElementTree as ET

    t0 = _time.monotonic()
    all_listings: list[RawJobListing] = []
    seen_urls: set[str] = set()

    # Jobspresso RSS supports search_keywords and job_types params
    rss_urls = [
        "https://jobspresso.co/?feed=job_feed&job_types=ai-data,developer,product-mgmt&search_keywords=AI+engineer",
        "https://jobspresso.co/?feed=job_feed&job_types=ai-data,developer&search_keywords=machine+learning",
        "https://jobspresso.co/?feed=job_feed&job_types=developer&search_keywords=iOS+engineer",
        "https://jobspresso.co/?feed=job_feed&job_types=developer&search_keywords=founding+engineer",
        "https://jobspresso.co/?feed=job_feed&job_types=ai-data,developer&search_keywords=healthcare+AI",
        "https://jobspresso.co/?feed=job_feed&job_types=developer&search_keywords=full+stack+startup",
    ]

    # XML namespaces used by Jobspresso RSS
    ns = {
        "content": "http://purl.org/rss/1.0/modules/content/",
        "job_listing": "https://jobspresso.co",
    }

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        for rss_url in rss_urls:
            try:
                resp = await client.get(rss_url)
                resp.raise_for_status()

                root = ET.fromstring(resp.text)
                for item in root.findall(".//item"):
                    url = (item.findtext("link") or "").strip()
                    if not url or url in seen_urls:
                        continue
                    seen_urls.add(url)

                    title = (item.findtext("title") or "Unknown").strip()

                    # dc:creator contains "Company<br>⚲ Location"
                    creator = (
                        item.findtext("{http://purl.org/dc/elements/1.1/}creator") or ""
                    )
                    # Parse company and location from creator field
                    creator_clean = re.sub(r"<[^>]+>", "|", creator)
                    creator_parts = [
                        p.strip() for p in creator_clean.split("|") if p.strip()
                    ]
                    company = creator_parts[0] if creator_parts else "Unknown"
                    # Location comes after ⚲ symbol
                    location = "Remote"
                    for part in creator_parts:
                        loc_match = re.search(r"[⚲]\s*(.+)", part)
                        if loc_match:
                            location = loc_match.group(1).strip()
                            break

                    # Try content:encoded first (full HTML), fall back to description
                    desc = (
                        item.findtext("content:encoded", namespaces=ns)
                        or item.findtext("description")
                        or ""
                    )
                    desc = re.sub(r"<[^>]+>", " ", desc)
                    desc = re.sub(r"\s+", " ", desc).strip()

                    # Job type/category from custom RSS fields
                    job_type = (
                        item.findtext("job_listing:job_type", namespaces=ns) or ""
                    )
                    if job_type:
                        desc = f"{desc}\n\nCategory: {job_type}"

                    all_listings.append(
                        RawJobListing(
                            title=title,
                            company=company,
                            description=desc[:8000],
                            url=url,
                            salary_text="",
                            location=location,
                            is_remote=True,
                        )
                    )

            except Exception as e:
                logger.warning(f"Jobspresso RSS fetch failed: {e}")

    logger.info(
        f"Jobspresso: fetched {len(all_listings)} listings in {_time.monotonic() - t0:.1f}s"
    )
    return all_listings


async def fetch_all_sources(
    preferred_locations: list[str] | None = None,
) -> list[RawJobListing]:
    """Fetch from all sources concurrently. Returns deduplicated listings.

    When preferred_locations is provided, location-aware sources (SerpAPI, Adzuna,
    TheMuse, FindWork, Reed, USAJobs) will run additional location-scoped searches
    to find jobs in those specific cities. Total: 15 sources (10 free + 5 API-key).
    """
    import time as _time
    t0 = _time.monotonic()
    locs = preferred_locations or None
    if locs:
        logger.info(f"[FETCH] Location-aware search enabled for: {', '.join(locs)}")
    results = await asyncio.gather(
        fetch_remotive(),
        fetch_himalayas(),
        fetch_hn_whoishiring(),
        fetch_jobicy(),
        fetch_remoteok(),
        fetch_weworkremotely(),
        fetch_arbeitnow(),
        fetch_themuse(locations=locs),
        fetch_workingnomads(),
        fetch_jobspresso(),
        # API-key sources (gracefully return [] if not configured)
        fetch_serpapi_google_jobs(locations=locs),
        fetch_adzuna(locations=locs),
        fetch_findwork(locations=locs),
        fetch_reed(locations=locs),
        fetch_usajobs(locations=locs),
        return_exceptions=True,
    )

    all_listings: list[RawJobListing] = []
    seen_titles: set[str] = set()
    seen_urls: set[str] = set()

    source_names = [
        "Remotive",
        "Himalayas",
        "HN",
        "Jobicy",
        "RemoteOK",
        "WWR",
        "Arbeitnow",
        "TheMuse",
        "WorkingNomads",
        "Jobspresso",
        "SerpAPI",
        "Adzuna",
        "FindWork",
        "Reed",
        "USAJobs",
    ]

    for i, result in enumerate(results):
        name = source_names[i] if i < len(source_names) else f"Source{i}"
        if isinstance(result, BaseException):
            logger.error(f"[FETCH] {name} FAILED: {result}")
            continue
        listings: list[RawJobListing] = result
        logger.info(f"[FETCH] {name}: {len(listings)} raw listings")
        for listing in listings:
            # Dedup by both URL and title+company
            if listing.url in seen_urls:
                continue
            dedup_key = f"{listing.company.lower()}:{listing.title.lower()}"
            if dedup_key not in seen_titles:
                seen_titles.add(dedup_key)
                seen_urls.add(listing.url)
                all_listings.append(listing)

    total_elapsed = _time.monotonic() - t0
    logger.info(f"[FETCH] Total unique listings from all sources: {len(all_listings)} in {total_elapsed:.1f}s")
    return all_listings
