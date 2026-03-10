"""LinkedIn API client — profile data, sharing."""

from __future__ import annotations

import httpx


async def share_to_linkedin(
    access_token: str,
    person_id: str,
    text: str,
    article_url: str | None = None,
) -> dict:
    """Create a share (post) on the authenticated user's LinkedIn feed."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Restli-Protocol-Version": "2.0.0",
    }

    media_category = "NONE"
    media = []
    if article_url:
        media_category = "ARTICLE"
        media = [{"status": "READY", "originalUrl": article_url}]

    body = {
        "author": f"urn:li:person:{person_id}",
        "lifecycleState": "PUBLISHED",
        "specificContent": {
            "com.linkedin.ugc.ShareContent": {
                "shareCommentary": {"text": text},
                "shareMediaCategory": media_category,
                **({"media": media} if media else {}),
            }
        },
        "visibility": {"com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"},
    }

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://api.linkedin.com/v2/ugcPosts",
            json=body,
            headers=headers,
        )
        resp.raise_for_status()
        return {"status": "shared", "id": resp.headers.get("X-RestLi-Id", "")}
