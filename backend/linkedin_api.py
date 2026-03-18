"""LinkedIn API client — posting, sharing, reactions, comments.

Uses the modern Community Management API (/rest/posts) with w_member_social scope.
Available operations with consumer-tier scopes:
  - Create/delete posts (text, article, image, multi-image, document)
  - Comment on posts
  - React to posts (LIKE, CELEBRATE, SUPPORT, LOVE, INSIGHTFUL, FUNNY)
  - Get user's own posts
  - Reshare posts
"""

from __future__ import annotations

import logging
import mimetypes
import os
from enum import Enum

import httpx

logger = logging.getLogger(__name__)

API_VERSION = "202501"


class ReactionType(str, Enum):
    LIKE = "LIKE"
    CELEBRATE = "PRAISE"
    SUPPORT = "EMPATHY"
    LOVE = "APPRECIATION"
    INSIGHTFUL = "INTEREST"
    FUNNY = "ENTERTAINMENT"


def _rest_headers(access_token: str) -> dict:
    return {
        "Authorization": f"Bearer {access_token}",
        "LinkedIn-Version": API_VERSION,
        "Content-Type": "application/json",
        "X-Restli-Protocol-Version": "2.0.0",
    }


# ── Image Upload ─────────────────────────────────────────────────────────────


async def upload_image(access_token: str, person_id: str, image_path: str) -> str:
    """Upload an image to LinkedIn via the /rest/images API. Returns the image URN."""
    headers = _rest_headers(access_token)

    # 1. Initialize upload
    init_body = {
        "initializeUploadRequest": {
            "owner": f"urn:li:person:{person_id}",
        }
    }
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/images?action=initializeUpload",
            json=init_body,
            headers=headers,
        )
        resp.raise_for_status()
        data = resp.json()["value"]
        upload_url = data["uploadUrl"]
        image_urn = data["image"]

        # 2. Upload binary
        with open(image_path, "rb") as f:
            file_data = f.read()

        mime_type = mimetypes.guess_type(image_path)[0] or "application/octet-stream"
        upload_headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": mime_type,
            "LinkedIn-Version": API_VERSION,
        }
        upload_resp = await client.put(
            upload_url, content=file_data, headers=upload_headers
        )
        upload_resp.raise_for_status()

    logger.info("Uploaded image %s → %s", os.path.basename(image_path), image_urn)
    return image_urn


# ── Document Upload ──────────────────────────────────────────────────────────


async def upload_document(access_token: str, person_id: str, doc_path: str) -> str:
    """Upload a document (PDF, slides, etc.) via /rest/documents. Returns the document URN."""
    headers = _rest_headers(access_token)

    init_body = {
        "initializeUploadRequest": {
            "owner": f"urn:li:person:{person_id}",
        }
    }
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/documents?action=initializeUpload",
            json=init_body,
            headers=headers,
        )
        resp.raise_for_status()
        data = resp.json()["value"]
        upload_url = data["uploadUrl"]
        document_urn = data["document"]

        with open(doc_path, "rb") as f:
            file_data = f.read()

        mime_type = mimetypes.guess_type(doc_path)[0] or "application/octet-stream"
        upload_headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": mime_type,
            "LinkedIn-Version": API_VERSION,
        }
        upload_resp = await client.put(
            upload_url, content=file_data, headers=upload_headers
        )
        upload_resp.raise_for_status()

    logger.info("Uploaded document %s → %s", os.path.basename(doc_path), document_urn)
    return document_urn


# ── Create Posts ─────────────────────────────────────────────────────────────


async def create_text_post(
    access_token: str,
    person_id: str,
    text: str,
    visibility: str = "PUBLIC",
) -> dict:
    """Create a text-only post."""
    body = {
        "author": f"urn:li:person:{person_id}",
        "commentary": text,
        "visibility": visibility,
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "lifecycleState": "PUBLISHED",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/posts",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        post_urn = resp.headers.get("x-restli-id", "")
        logger.info("Created text post: %s", post_urn)
        return {"status": "posted", "post_urn": post_urn}


async def create_article_post(
    access_token: str,
    person_id: str,
    text: str,
    article_url: str,
    article_title: str = "",
    article_description: str = "",
    visibility: str = "PUBLIC",
) -> dict:
    """Create a post with an article link (URL preview card)."""
    article = {"source": article_url}
    if article_title:
        article["title"] = article_title
    if article_description:
        article["description"] = article_description

    body = {
        "author": f"urn:li:person:{person_id}",
        "commentary": text,
        "visibility": visibility,
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "content": {
            "article": article,
        },
        "lifecycleState": "PUBLISHED",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/posts",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        post_urn = resp.headers.get("x-restli-id", "")
        logger.info("Created article post: %s → %s", article_url, post_urn)
        return {"status": "posted", "post_urn": post_urn}


async def create_image_post(
    access_token: str,
    person_id: str,
    text: str,
    image_path: str,
    alt_text: str = "",
    visibility: str = "PUBLIC",
) -> dict:
    """Create a post with a single image."""
    image_urn = await upload_image(access_token, person_id, image_path)

    image_content = {"id": image_urn}
    if alt_text:
        image_content["altText"] = alt_text

    body = {
        "author": f"urn:li:person:{person_id}",
        "commentary": text,
        "visibility": visibility,
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "content": {
            "media": image_content,
        },
        "lifecycleState": "PUBLISHED",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/posts",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        post_urn = resp.headers.get("x-restli-id", "")
        logger.info("Created image post: %s", post_urn)
        return {"status": "posted", "post_urn": post_urn}


async def create_multi_image_post(
    access_token: str,
    person_id: str,
    text: str,
    image_paths: list[str],
    alt_texts: list[str] | None = None,
    visibility: str = "PUBLIC",
) -> dict:
    """Create a post with multiple images (up to 9)."""
    images = []
    for i, path in enumerate(image_paths[:9]):
        urn = await upload_image(access_token, person_id, path)
        img = {"id": urn}
        if alt_texts and i < len(alt_texts):
            img["altText"] = alt_texts[i]
        images.append(img)

    body = {
        "author": f"urn:li:person:{person_id}",
        "commentary": text,
        "visibility": visibility,
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "content": {
            "multiImage": {"images": images},
        },
        "lifecycleState": "PUBLISHED",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/posts",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        post_urn = resp.headers.get("x-restli-id", "")
        logger.info("Created multi-image post (%d images): %s", len(images), post_urn)
        return {"status": "posted", "post_urn": post_urn}


async def create_document_post(
    access_token: str,
    person_id: str,
    text: str,
    doc_path: str,
    doc_title: str = "",
    visibility: str = "PUBLIC",
) -> dict:
    """Create a post with an attached document (PDF, slides)."""
    doc_urn = await upload_document(access_token, person_id, doc_path)

    media = {"id": doc_urn}
    if doc_title:
        media["title"] = doc_title

    body = {
        "author": f"urn:li:person:{person_id}",
        "commentary": text,
        "visibility": visibility,
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "content": {
            "media": media,
        },
        "lifecycleState": "PUBLISHED",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/posts",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        post_urn = resp.headers.get("x-restli-id", "")
        logger.info("Created document post: %s", post_urn)
        return {"status": "posted", "post_urn": post_urn}


async def reshare_post(
    access_token: str,
    person_id: str,
    original_post_urn: str,
    text: str = "",
    visibility: str = "PUBLIC",
) -> dict:
    """Reshare an existing post with optional commentary."""
    body = {
        "author": f"urn:li:person:{person_id}",
        "commentary": text,
        "visibility": visibility,
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "reshareContext": {
            "parent": original_post_urn,
        },
        "lifecycleState": "PUBLISHED",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://api.linkedin.com/rest/posts",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        post_urn = resp.headers.get("x-restli-id", "")
        logger.info("Reshared %s → %s", original_post_urn, post_urn)
        return {"status": "reshared", "post_urn": post_urn}


# ── Backward-compat wrapper ─────────────────────────────────────────────────


async def share_to_linkedin(
    access_token: str,
    person_id: str,
    text: str,
    article_url: str | None = None,
    image_path: str | None = None,
) -> dict:
    """Backward-compatible share function used by existing endpoints."""
    if image_path and os.path.exists(image_path):
        return await create_image_post(access_token, person_id, text, image_path)
    elif article_url:
        return await create_article_post(access_token, person_id, text, article_url)
    else:
        return await create_text_post(access_token, person_id, text)


# ── Get/Delete Posts ─────────────────────────────────────────────────────────


async def get_post(access_token: str, post_urn: str) -> dict:
    """Get a single post by URN."""
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(
            f"https://api.linkedin.com/rest/posts/{post_urn}",
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        return resp.json()


async def get_user_posts(
    access_token: str, person_id: str, count: int = 20, start: int = 0
) -> dict:
    """Get the authenticated user's own posts."""
    author_urn = f"urn:li:person:{person_id}"
    params = {
        "author": author_urn,
        "q": "author",
        "count": min(count, 100),
        "start": start,
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(
            "https://api.linkedin.com/rest/posts",
            params=params,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        data = resp.json()
        elements = data.get("elements", [])
        logger.info("Fetched %d user posts (start=%d)", len(elements), start)
        return data


async def delete_post(access_token: str, post_urn: str) -> dict:
    """Delete a post by URN."""
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.delete(
            f"https://api.linkedin.com/rest/posts/{post_urn}",
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        logger.info("Deleted post: %s", post_urn)
        return {"status": "deleted", "post_urn": post_urn}


# ── Comments ─────────────────────────────────────────────────────────────────


async def create_comment(
    access_token: str,
    person_id: str,
    post_urn: str,
    text: str,
) -> dict:
    """Add a comment to a post."""
    body = {
        "actor": f"urn:li:person:{person_id}",
        "message": {"text": text},
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            f"https://api.linkedin.com/rest/socialActions/{post_urn}/comments",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        comment_id = resp.headers.get("x-restli-id", "")
        logger.info("Commented on %s: %s", post_urn, comment_id)
        return {"status": "commented", "comment_id": comment_id}


async def get_comments(
    access_token: str, post_urn: str, count: int = 20, start: int = 0
) -> dict:
    """Get comments on a post."""
    params = {"count": min(count, 100), "start": start}
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(
            f"https://api.linkedin.com/rest/socialActions/{post_urn}/comments",
            params=params,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        return resp.json()


async def delete_comment(access_token: str, post_urn: str, comment_id: str) -> dict:
    """Delete a comment."""
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.delete(
            f"https://api.linkedin.com/rest/socialActions/{post_urn}/comments/{comment_id}",
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        logger.info("Deleted comment %s on %s", comment_id, post_urn)
        return {"status": "deleted", "comment_id": comment_id}


# ── Reactions ────────────────────────────────────────────────────────────────


async def react_to_post(
    access_token: str,
    person_id: str,
    post_urn: str,
    reaction: ReactionType = ReactionType.LIKE,
) -> dict:
    """React to a post (like, celebrate, support, love, insightful, funny)."""
    body = {
        "root": post_urn,
        "reactionType": reaction.value,
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            f"https://api.linkedin.com/rest/reactions",
            json=body,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        logger.info("Reacted %s to %s", reaction.value, post_urn)
        return {"status": "reacted", "reaction": reaction.value, "post_urn": post_urn}


async def remove_reaction(
    access_token: str,
    person_id: str,
    post_urn: str,
) -> dict:
    """Remove your reaction from a post."""
    actor_urn = f"urn:li:person:{person_id}"
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.delete(
            f"https://api.linkedin.com/rest/reactions/(actor:{actor_urn},entity:{post_urn})",
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        logger.info("Removed reaction from %s", post_urn)
        return {"status": "removed", "post_urn": post_urn}


async def get_reactions(
    access_token: str, post_urn: str, count: int = 20, start: int = 0
) -> dict:
    """Get reactions on a post."""
    params = {"count": min(count, 100), "start": start}
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(
            f"https://api.linkedin.com/rest/socialActions/{post_urn}/likes",
            params=params,
            headers=_rest_headers(access_token),
        )
        resp.raise_for_status()
        return resp.json()
