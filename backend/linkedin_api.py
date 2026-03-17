"""LinkedIn API client — profile data, sharing."""

from __future__ import annotations

import httpx
import os
import mimetypes


async def _upload_image_to_linkedin(
    access_token: str, person_id: str, image_path: str
) -> str:
    """Register and upload an image to LinkedIn, returning its DigitalMediaAssetURN."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Restli-Protocol-Version": "2.0.0",
    }

    register_body = {
        "registerUploadRequest": {
            "recipes": ["urn:li:digitalmediaRecipe:feedshare-image"],
            "owner": f"urn:li:person:{person_id}",
            "serviceRelationships": [
                {
                    "relationshipType": "OWNER",
                    "identifier": "urn:li:userGeneratedContent",
                }
            ],
        }
    }

    async with httpx.AsyncClient() as client:
        # 1. Register Upload
        reg_resp = await client.post(
            "https://api.linkedin.com/v2/assets?action=registerUpload",
            json=register_body,
            headers=headers,
        )
        reg_resp.raise_for_status()
        reg_data = reg_resp.json()

        asset_urn = reg_data["value"]["asset"]
        upload_url = reg_data["value"]["uploadMechanism"][
            "com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest"
        ]["uploadUrl"]

        # 2. Upload actual file bytes
        with open(image_path, "rb") as f:
            file_data = f.read()

        mime_type, _ = mimetypes.guess_type(image_path)
        upload_headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": mime_type or "application/octet-stream",
        }

        # NOTE: LinkedIn accepts POST or PUT for the upload URL. We use POST as indicated by the docs or standard behavior.
        # But wait, docs actually used POST in the curl request: `curl -i --upload-file ...` is actually PUT by default in curl unless specified!
        # But the documentation explicitly says "send a POST request to the uploadUrl with your image or video included as a binary file". We will use client.post, but sometimes it is actually client.put depending on how LinkedIn proxy behaves. We will try post.
        # actually, curl --upload-file uses PUT! Wait, the docs say: "send a POST request ... The example below uses curl --upload-file".
        # Let's use put() just to be safe if curl uses put, or we can use request("PUT", ...) / request("POST", ...)
        upload_resp = await client.request(
            "PUT",  # curl --upload-file defaults to PUT
            upload_url,
            content=file_data,
            headers=upload_headers,
        )
        # If PUT fails with 405 Method Not Allowed, we can fallback to POST
        if upload_resp.status_code == 405:
            upload_resp = await client.post(
                upload_url, content=file_data, headers=upload_headers
            )

        upload_resp.raise_for_status()
        return asset_urn


async def share_to_linkedin(
    access_token: str,
    person_id: str,
    text: str,
    article_url: str | None = None,
    image_path: str | None = None,
) -> dict:
    """Create a share (post) on the authenticated user's LinkedIn feed."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Restli-Protocol-Version": "2.0.0",
    }

    media_category = "NONE"
    media = []

    if image_path and os.path.exists(image_path):
        asset_urn = await _upload_image_to_linkedin(access_token, person_id, image_path)
        media_category = "IMAGE"
        mediaItem = {"status": "READY", "media": asset_urn}
        if article_url:
            mediaItem["originalUrl"] = (
                article_url  # Add the URL so the image links to it if supported
            )
        media = [mediaItem]
    elif article_url:
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
