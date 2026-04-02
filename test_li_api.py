import asyncio
import json
import httpx
from backend.linkedin_oauth import get_all_sessions


async def main():
    sessions = get_all_sessions()
    if not sessions:
        print("No sessions")
        return
    session = list(sessions.values())[0]
    person_id = session.profile.person_id
    token = session.linkedin_access_token

    headers = {
        "Authorization": f"Bearer {token}",
        "LinkedIn-Version": "202401",
        "X-Restli-Protocol-Version": "2.0.0",
    }

    async with httpx.AsyncClient() as client:
        # Get posts
        print(f"Fetching posts for person: {person_id}")
        resp = await client.get(
            f"https://api.linkedin.com/rest/posts?author=urn:li:person:{person_id}&q=author&count=2",
            headers=headers,
        )
        print("--- POSTS ---")
        try:
            print(json.dumps(resp.json(), indent=2))
        except Exception as e:
            print("Failed to decode JSON:", e, resp.text)

        posts = resp.json().get("elements", [])
        if posts:
            post_urn = posts[0].get("id")
            # Get comments
            print("\n--- COMMENTS ---")
            c_resp = await client.get(
                f"https://api.linkedin.com/rest/socialActions/{post_urn}/comments",
                headers=headers,
            )
            print(json.dumps(c_resp.json(), indent=2))

            # Get reactions
            print("\n--- REACTIONS ---")
            r_resp = await client.get(
                f"https://api.linkedin.com/rest/socialActions/{post_urn}/reactions",
                headers=headers,
            )
            print(json.dumps(r_resp.json(), indent=2))


asyncio.run(main())
