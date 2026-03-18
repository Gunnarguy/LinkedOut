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
from models import (
    AuthSession,
    LinkedInProfile,
    OAuthTokenResponse,
)

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
    logger.info(
        "[LI-AUTH] Generated authorization URL state=%s redirect=%s",
        state[:10],
        settings.linkedin_redirect_uri,
    )
    return f"{AUTHORIZE_URL}?{urlencode(params)}", state


def validate_state(state: str) -> bool:
    """Check that the state token is known and not expired."""
    expiry = _pending_states.pop(state, None)
    if expiry is None:
        logger.warning("[LI-AUTH] Rejected OAuth state=%s (missing)", state[:10])
        return False
    is_valid = datetime.now(timezone.utc) < expiry
    if not is_valid:
        logger.warning("[LI-AUTH] Rejected OAuth state=%s (expired)", state[:10])
    else:
        logger.info("[LI-AUTH] Accepted OAuth state=%s", state[:10])
    return is_valid


async def exchange_code_for_token(code: str) -> OAuthTokenResponse:
    """Exchange the authorization code for an access token."""
    logger.info("[LI-AUTH] Exchanging authorization code=%s...", code[:10])
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
        logger.info(
            "[LI-AUTH] Token exchange OK expires_in=%s has_refresh=%s",
            data.get("expires_in"),
            bool(data.get("refresh_token")),
        )
        return OAuthTokenResponse(**data)


def _localized(obj: dict) -> str:
    """Extract a plain string from a LinkedIn MultiLocaleString."""
    if isinstance(obj, str):
        return obj
    localized = obj.get("localized", {})
    return next(iter(localized.values()), "") if localized else ""


async def fetch_profile(access_token: str) -> LinkedInProfile:
    """Fetch the authenticated member's profile from LinkedIn.

    Consumer-tier scopes (openid profile email w_member_social r_verify r_profile_basicinfo)
    only provide basic identity data. Positions, education, skills require r_fullprofile
    which LinkedIn has CLOSED to new applications.

    Strategy:
      1. /rest/identityMe (v202501) — name, headline, picture, email (r_profile_basicinfo)
      2. /v2/userinfo (OIDC) — fallback for name/email/picture
      3. /rest/verificationReport — verification badges (r_verify)
    """
    rest_headers = {
        "Authorization": f"Bearer {access_token}",
        "LinkedIn-Version": "202501",
    }

    profile_data: dict = {}
    verifications: list[str] = []
    profile_url = ""
    headline = ""
    pic_url = ""
    email = ""

    async with httpx.AsyncClient(timeout=15) as client:
        # ── 1. /rest/identityMe — primary source (r_profile_basicinfo) ──
        try:
            resp = await client.get(
                "https://api.linkedin.com/rest/identityMe",
                headers=rest_headers,
            )
            if resp.status_code == 200:
                identity = resp.json()
                basic = identity.get("basicInfo", {})
                profile_data["id"] = identity.get("id", "")
                profile_url = basic.get("profileUrl", "")

                fn_loc = basic.get("firstName", {}).get("localized", {})
                ln_loc = basic.get("lastName", {}).get("localized", {})
                profile_data["localizedFirstName"] = next(iter(fn_loc.values()), "")
                profile_data["localizedLastName"] = next(iter(ln_loc.values()), "")

                hl_loc = basic.get("headline", {}).get("localized", {})
                headline = next(iter(hl_loc.values()), "")

                pic_url = (
                    basic.get("profilePicture", {})
                    .get("croppedImage", {})
                    .get("downloadUrl", "")
                )
                email = basic.get("primaryEmailAddress", "")

                logger.info(
                    "Fetched /rest/identityMe: %s %s — headline=%r",
                    profile_data.get("localizedFirstName"),
                    profile_data.get("localizedLastName"),
                    headline,
                )
            else:
                logger.warning(
                    "/rest/identityMe returned %s: %s",
                    resp.status_code,
                    resp.text[:300],
                )
        except Exception as e:
            logger.warning(f"/rest/identityMe failed: {e}")

        # ── 2. OIDC userinfo — reliable fallback for name/email/picture ──
        try:
            uresp = await client.get(
                USERINFO_URL, headers={"Authorization": f"Bearer {access_token}"}
            )
            if uresp.status_code == 200:
                ui = uresp.json()
                if not profile_data.get("id"):
                    profile_data["id"] = ui.get("sub", "")
                if not profile_data.get("localizedFirstName"):
                    profile_data["localizedFirstName"] = ui.get("given_name", "")
                if not profile_data.get("localizedLastName"):
                    profile_data["localizedLastName"] = ui.get("family_name", "")
                if not email:
                    email = ui.get("email", "")
                if not pic_url:
                    pic_url = ui.get("picture", "")
                logger.info(
                    "OIDC userinfo OK — email=%s, pic=%s",
                    bool(email),
                    bool(pic_url),
                )
        except Exception as e:
            logger.warning(f"/v2/userinfo failed: {e}")

        # ── 3. /rest/verificationReport — verification badges (r_verify) ──
        try:
            vresp = await client.get(
                "https://api.linkedin.com/rest/verificationReport",
                headers=rest_headers,
            )
            if vresp.status_code == 200:
                verifications = [
                    v.get("type", "")
                    for v in vresp.json().get("verifications", [])
                    if v.get("type")
                ]
                logger.info(
                    "/rest/verificationReport verifications=%s",
                    verifications,
                )
            else:
                logger.info(
                    "/rest/verificationReport returned %s",
                    vresp.status_code,
                )
        except Exception:
            pass

        # Note: Positions, education, skills, certifications, languages
        # require r_fullprofile or r_basicprofile scopes which LinkedIn has
        # CLOSED to new consumer applications. Use manual entry or PDF import.

        return LinkedInProfile(
            person_id=profile_data.get("id", ""),
            first_name=profile_data.get("localizedFirstName", ""),
            last_name=profile_data.get("localizedLastName", ""),
            headline=headline,
            vanity_name=profile_data.get("vanityName", ""),
            profile_picture_url=pic_url,
            email=email,
            profile_url=profile_url,
            verifications=verifications,
        )


async def create_session(code: str) -> AuthSession:
    """Full OAuth callback handler: exchange code → fetch profile → store session."""
    logger.info("[LI-AUTH] Creating session from authorization code")
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
    logger.info(
        "[LI-AUTH] Session stored person_id=%s name=%s %s expires_at=%s",
        profile.person_id,
        profile.first_name,
        profile.last_name,
        session.expires_at.isoformat() if session.expires_at else None,
    )
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
        logger.info(
            "[LI-AUTH] Refresh skipped person_id=%s has_session=%s has_refresh=%s",
            person_id,
            bool(session),
            bool(session and session.linkedin_refresh_token),
        )
        return None

    logger.info("[LI-AUTH] Refreshing access token for person_id=%s", person_id)
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

    if "access_token" not in data:
        logger.error(
            f"LinkedIn refresh returned invalid response (missing access_token)"
        )
        return None

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
    logger.info(
        "[LI-AUTH] Refresh OK person_id=%s expires_in=%s has_refresh=%s",
        person_id,
        data.get("expires_in"),
        bool(new_session.linkedin_refresh_token),
    )
    return new_session
