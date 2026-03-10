"""LinkedIn OAuth 2.0 service — handles 3-legged auth flow.

Sessions are persisted to disk so restarts/sleep don't log users out.
"""

from __future__ import annotations

import json
import logging
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode

import httpx

from config import settings
from models import AuthSession, LinkedInProfile, OAuthTokenResponse

logger = logging.getLogger(__name__)

# LinkedIn OAuth endpoints
AUTHORIZE_URL = "https://www.linkedin.com/oauth/v2/authorization"
TOKEN_URL = "https://www.linkedin.com/oauth/v2/accessToken"
USERINFO_URL = "https://api.linkedin.com/v2/userinfo"

# Persistent storage
DATA_DIR = Path("/app/data") if Path("/app").exists() else Path("./data")
SESSIONS_FILE = DATA_DIR / "sessions.json"

# In-memory caches
_pending_states: dict[str, datetime] = {}
_sessions: dict[str, AuthSession] = {}  # keyed by person_id


def _load_sessions() -> None:
    """Load persisted sessions from disk on startup."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if SESSIONS_FILE.exists():
        try:
            raw = json.loads(SESSIONS_FILE.read_text())
            for pid, data in raw.items():
                _sessions[pid] = AuthSession(**data)
            logger.info(f"Loaded {len(_sessions)} persisted auth sessions")
        except Exception as e:
            logger.error(f"Failed to load sessions: {e}")


def _save_sessions() -> None:
    """Persist sessions to disk."""
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        data = {}
        for pid, session in _sessions.items():
            data[pid] = session.model_dump(mode="json")
        SESSIONS_FILE.write_text(json.dumps(data, default=str))
    except Exception as e:
        logger.error(f"Failed to save sessions: {e}")


# Load on import
_load_sessions()


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
    _save_sessions()
    return session


def get_session(person_id: str) -> AuthSession | None:
    """Retrieve a stored session by person ID.

    Returns the session even if expired — the caller or iOS client
    can decide whether to refresh or re-authenticate.
    """
    return _sessions.get(person_id)


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
    _save_sessions()
    return new_session
