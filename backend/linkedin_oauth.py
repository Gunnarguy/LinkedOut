"""LinkedIn OAuth 2.0 service — handles 3-legged auth flow."""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx

from config import settings
from models import AuthSession, LinkedInProfile, OAuthTokenResponse

# LinkedIn OAuth endpoints
AUTHORIZE_URL = "https://www.linkedin.com/oauth/v2/authorization"
TOKEN_URL = "https://www.linkedin.com/oauth/v2/accessToken"
USERINFO_URL = "https://api.linkedin.com/v2/userinfo"

# In-memory state store (swap for Redis in production)
_pending_states: dict[str, datetime] = {}
_sessions: dict[str, AuthSession] = {}  # keyed by person_id


def generate_authorization_url() -> tuple[str, str]:
    """Return (authorization_url, state) for the LinkedIn OAuth consent screen."""
    state = secrets.token_urlsafe(32)
    _pending_states[state] = datetime.now(timezone.utc) + timedelta(minutes=10)

    params = {
        "response_type": "code",
        "client_id": settings.linkedin_client_id,
        "redirect_uri": settings.linkedin_redirect_uri,
        "state": state,
        "scope": "openid profile email w_member_social r_verify r_profile_basicinfo",
    }
    return f"{AUTHORIZE_URL}?{urlencode(params)}", state


def validate_state(state: str) -> bool:
    """Check that the state token is known and not expired."""
    expiry = _pending_states.pop(state, None)
    if expiry is None:
        return False
    return datetime.now(timezone.utc) < expiry


async def exchange_code_for_token(code: str) -> OAuthTokenResponse:
    """Exchange the authorization code for an access token."""
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            TOKEN_URL,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": settings.linkedin_redirect_uri,
                "client_id": settings.linkedin_client_id,
                "client_secret": settings.linkedin_client_secret,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        resp.raise_for_status()
        data = resp.json()
        return OAuthTokenResponse(**data)


async def fetch_profile(access_token: str) -> LinkedInProfile:
    """Fetch the authenticated member's profile via OpenID Connect userinfo."""
    headers = {"Authorization": f"Bearer {access_token}"}
    async with httpx.AsyncClient() as client:
        resp = await client.get(USERINFO_URL, headers=headers)
        resp.raise_for_status()
        p = resp.json()

        return LinkedInProfile(
            person_id=p.get("sub", ""),
            first_name=p.get("given_name", ""),
            last_name=p.get("family_name", ""),
            headline="",
            vanity_name="",
            profile_picture_url=p.get("picture", ""),
            email=p.get("email", ""),
        )


async def create_session(code: str) -> AuthSession:
    """Full OAuth callback handler: exchange code → fetch profile → store session."""
    token = await exchange_code_for_token(code)
    profile = await fetch_profile(token.access_token)
    session = AuthSession(
        linkedin_access_token=token.access_token,
        linkedin_refresh_token=token.refresh_token,
        profile=profile,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=token.expires_in),
    )
    _sessions[profile.person_id] = session
    return session


def get_session(person_id: str) -> AuthSession | None:
    """Retrieve a stored session by person ID."""
    session = _sessions.get(person_id)
    if session and session.expires_at > datetime.now(timezone.utc):
        return session
    return None


def get_all_sessions() -> dict[str, AuthSession]:
    return _sessions


async def refresh_access_token(person_id: str) -> AuthSession | None:
    """Use refresh token to get new access token."""
    session = _sessions.get(person_id)
    if not session or not session.linkedin_refresh_token:
        return None

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            TOKEN_URL,
            data={
                "grant_type": "refresh_token",
                "refresh_token": session.linkedin_refresh_token,
                "client_id": settings.linkedin_client_id,
                "client_secret": settings.linkedin_client_secret,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        resp.raise_for_status()
        data = resp.json()

    new_session = AuthSession(
        linkedin_access_token=data["access_token"],
        linkedin_refresh_token=data.get(
            "refresh_token", session.linkedin_refresh_token
        ),
        profile=session.profile,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=data["expires_in"]),
    )
    _sessions[person_id] = new_session
    return new_session
