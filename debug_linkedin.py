"""Debug script: test all LinkedIn API endpoints with live token."""

import asyncio
import json
from pathlib import Path

import httpx

SESSIONS_FILE = Path("data/sessions.json")


async def raw_test():
    sessions = json.loads(SESSIONS_FILE.read_text())
    token = list(sessions.values())[0]["linkedin_access_token"]
    print(f"Token length: {len(token)}")

    headers_v2 = {
        "Authorization": f"Bearer {token}",
        "X-RestLi-Protocol-Version": "2.0.0",
    }
    rest_headers = {
        "Authorization": f"Bearer {token}",
        "LinkedIn-Version": "202503",
    }

    async with httpx.AsyncClient(timeout=15) as client:
        # Test 1: /v2/me with projections
        print("\n=== 1. /v2/me (with projections) ===")
        me_url = (
            "https://api.linkedin.com/v2/me"
            "?projection=(id,localizedFirstName,localizedLastName,"
            "localizedHeadline,vanityName,profilePicture,"
            "positions,education,skills,certifications,languages)"
        )
        r1 = await client.get(me_url, headers=headers_v2)
        print(f"Status: {r1.status_code}")
        print(json.dumps(r1.json(), indent=2)[:3000])

        # Test 2: /v2/me WITHOUT projections
        print("\n=== 2. /v2/me (no projections) ===")
        r2 = await client.get("https://api.linkedin.com/v2/me", headers=headers_v2)
        print(f"Status: {r2.status_code}")
        d2 = r2.json()
        print("Keys:", list(d2.keys()))
        print(json.dumps(d2, indent=2)[:2000])

        # Test 3: /rest/identityMe
        print("\n=== 3. /rest/identityMe ===")
        r3 = await client.get(
            "https://api.linkedin.com/rest/identityMe", headers=rest_headers
        )
        print(f"Status: {r3.status_code}")
        d3 = r3.json()
        print("Keys:", list(d3.keys()))
        print(json.dumps(d3, indent=2)[:3000])

        # Test 4: OIDC userinfo
        print("\n=== 4. /v2/userinfo (OIDC) ===")
        r4 = await client.get(
            "https://api.linkedin.com/v2/userinfo",
            headers={"Authorization": f"Bearer {token}"},
        )
        print(f"Status: {r4.status_code}")
        print(json.dumps(r4.json(), indent=2)[:1000])

        # Test 5: Try REST memberMe with full decoration
        print("\n=== 5. /rest/me (full decoration) ===")
        r5 = await client.get(
            "https://api.linkedin.com/rest/me"
            "?decoration=(id,firstName,lastName,headline,vanityName,"
            "profilePicture,positions,educations,skills,certifications,languages)",
            headers=rest_headers,
        )
        print(f"Status: {r5.status_code}")
        print(json.dumps(r5.json(), indent=2)[:3000])

        # Test 6: Try member profile positions endpoint
        print("\n=== 6. /rest/memberPositions (me) ===")
        r6 = await client.get(
            "https://api.linkedin.com/rest/positions?q=member&member=me",
            headers=rest_headers,
        )
        print(f"Status: {r6.status_code}")
        print(json.dumps(r6.json(), indent=2)[:2000])

        # Test 7: Try /v2/positions
        print("\n=== 7. /v2/positions?q=members ===")
        r7 = await client.get(
            "https://api.linkedin.com/v2/positions?q=members&projection=(elements*(*))",
            headers=headers_v2,
        )
        print(f"Status: {r7.status_code}")
        print(json.dumps(r7.json(), indent=2)[:2000])

        # Test 8: Profile API
        print("\n=== 8. /rest/me (profile fields) ===")
        r8 = await client.get(
            "https://api.linkedin.com/rest/me",
            headers=rest_headers,
        )
        print(f"Status: {r8.status_code}")
        d8 = r8.json()
        print("Keys:", list(d8.keys()) if isinstance(d8, dict) else "not a dict")
        print(json.dumps(d8, indent=2)[:3000])

        # Test 9: /rest/memberSnapshotData — broader data
        print("\n=== 9. /rest/memberSnapshotData ===")
        r9 = await client.get(
            "https://api.linkedin.com/rest/memberSnapshotData?q=memberSnapshot",
            headers=rest_headers,
        )
        print(f"Status: {r9.status_code}")
        print(json.dumps(r9.json(), indent=2)[:2000])

        # Test 10: /rest/memberProfileFields
        print("\n=== 10. /rest/memberProfileFields ===")
        r10 = await client.get(
            "https://api.linkedin.com/rest/memberProfileFields?q=member",
            headers=rest_headers,
        )
        print(f"Status: {r10.status_code}")
        print(json.dumps(r10.json(), indent=2)[:2000])


if __name__ == "__main__":
    asyncio.run(raw_test())
