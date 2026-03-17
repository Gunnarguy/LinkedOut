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
    LinkedInCertification,
    LinkedInEducation,
    LinkedInPosition,
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
        "scope": "openid profile email w_member_social r_verify r_profile_basicinfo r_basicprofile",
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


def _localized(obj: dict) -> str:
    """Extract a plain string from a LinkedIn MultiLocaleString."""
    if isinstance(obj, str):
        return obj
    localized = obj.get("localized", {})
    return next(iter(localized.values()), "") if localized else ""


def _parse_positions(elements: list[dict]) -> list[LinkedInPosition]:
    """Parse LinkedIn positions array into structured models."""
    results = []
    for el in elements:
        start = el.get("startMonthYear", {})
        end = el.get("endMonthYear", {})
        loc = _localized(
            el.get("geoPositionLocation", {}).get("displayLocationName", {})
        ) or _localized(el.get("locationName", {}))
        results.append(
            LinkedInPosition(
                title=_localized(el.get("title", {})),
                company_name=_localized(el.get("companyName", {})),
                location=loc,
                description=_localized(el.get("description", {})),
                start_year=start.get("year"),
                start_month=start.get("month"),
                end_year=end.get("year"),
                end_month=end.get("month"),
                is_current=not bool(end),
            )
        )
    return results


def _parse_education(elements: list[dict]) -> list[LinkedInEducation]:
    """Parse LinkedIn education array."""
    results = []
    for el in elements:
        fos = el.get("fieldsOfStudy", [])
        field = _localized(fos[0].get("fieldOfStudyName", {})) if fos else ""
        start = el.get("startMonthYear", {})
        end = el.get("endMonthYear", {})
        results.append(
            LinkedInEducation(
                school_name=_localized(el.get("schoolName", {})),
                degree=_localized(el.get("degreeName", {})),
                field_of_study=field,
                start_year=start.get("year"),
                end_year=end.get("year"),
                activities=_localized(el.get("activities", {})),
                grade=_localized(el.get("grade", {}).get("grade", {})),
            )
        )
    return results


def _parse_certifications(elements: list[dict]) -> list[LinkedInCertification]:
    """Parse LinkedIn certifications array."""
    results = []
    for el in elements:
        start = el.get("startMonthYear", {})
        end = el.get("endMonthYear", {})
        results.append(
            LinkedInCertification(
                name=_localized(el.get("name", {})),
                authority=_localized(el.get("authority", {})),
                license_number=_localized(el.get("licenseNumber", {})),
                url=el.get("url", ""),
                start_year=start.get("year"),
                end_year=end.get("year"),
            )
        )
    return results


async def fetch_profile(access_token: str) -> LinkedInProfile:
    """Fetch the authenticated member's full profile including resume data.

    Uses Business tier r_basicprofile for positions/education/skills/certifications,
    /rest/identityMe for profileUrl, and /rest/verificationReport for verification badges.
    """
    headers = {
        "Authorization": f"Bearer {access_token}",
        "X-RestLi-Protocol-Version": "2.0.0",
    }
    rest_headers = {
        "Authorization": f"Bearer {access_token}",
        "LinkedIn-Version": "202503",
    }

    profile_data: dict = {}
    positions: list[LinkedInPosition] = []
    education: list[LinkedInEducation] = []
    skills: list[str] = []
    certifications: list[LinkedInCertification] = []
    languages: list[str] = []
    verifications: list[str] = []
    profile_url = ""

    async with httpx.AsyncClient(timeout=15) as client:
        # ── 1. /v2/me with field projections (Business tier) ──
        try:
            me_url = (
                "https://api.linkedin.com/v2/me"
                "?projection=(id,localizedFirstName,localizedLastName,"
                "localizedHeadline,vanityName,profilePicture,"
                "positions,education,skills,certifications,languages)"
            )
            resp = await client.get(me_url, headers=headers)
            if resp.status_code == 200:
                profile_data = resp.json()
                logger.info(
                    f"Fetched /v2/me with projections for {profile_data.get('localizedFirstName', '?')}"
                )

                # Parse resume sections
                pos_elements = profile_data.get("positions", {}).get("elements", [])
                if pos_elements:
                    positions = _parse_positions(pos_elements)
                    logger.info(f"  → {len(positions)} positions")

                edu_elements = profile_data.get("education", {}).get("elements", [])
                if edu_elements:
                    education = _parse_education(edu_elements)
                    logger.info(f"  → {len(education)} education entries")

                skill_elements = profile_data.get("skills", {}).get("elements", [])
                if skill_elements:
                    skills = [
                        _localized(s.get("name", {}))
                        for s in skill_elements
                        if _localized(s.get("name", {}))
                    ]
                    logger.info(f"  → {len(skills)} skills")

                cert_elements = profile_data.get("certifications", {}).get(
                    "elements", []
                )
                if cert_elements:
                    certifications = _parse_certifications(cert_elements)
                    logger.info(f"  → {len(certifications)} certifications")

                lang_elements = profile_data.get("languages", {}).get("elements", [])
                if lang_elements:
                    languages = [
                        _localized(l.get("name", {}))
                        for l in lang_elements
                        if _localized(l.get("name", {}))
                    ]
                    logger.info(f"  → {len(languages)} languages")
            else:
                logger.warning(f"/v2/me returned {resp.status_code}: {resp.text[:200]}")
        except Exception as e:
            logger.warning(f"/v2/me with projections failed: {e}")

        # ── 2. /rest/identityMe for profileUrl ──
        try:
            resp = await client.get(
                "https://api.linkedin.com/rest/identityMe",
                headers=rest_headers,
            )
            if resp.status_code == 200:
                identity = resp.json()
                basic = identity.get("basicInfo", {})
                profile_url = basic.get("profileUrl", "")
                # Use identity data as fallback for basic fields
                if not profile_data:
                    fn_loc = basic.get("firstName", {}).get("localized", {})
                    ln_loc = basic.get("lastName", {}).get("localized", {})
                    profile_data["localizedFirstName"] = next(iter(fn_loc.values()), "")
                    profile_data["localizedLastName"] = next(iter(ln_loc.values()), "")
                    profile_data["id"] = identity.get("id", "")
                    pic_url = (
                        basic.get("profilePicture", {})
                        .get("croppedImage", {})
                        .get("downloadUrl", "")
                    )
                    if pic_url:
                        profile_data["_pic_url"] = pic_url
                    profile_data["_email"] = basic.get("primaryEmailAddress", "")
        except Exception as e:
            logger.warning(f"/rest/identityMe failed: {e}")

        # ── 3. /rest/verificationReport ──
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
        except Exception:
            pass

        # ── 4. Get email from OIDC userinfo if we don't have it ──
        email = profile_data.get("_email", "")
        if not email:
            try:
                uresp = await client.get(
                    USERINFO_URL, headers={"Authorization": f"Bearer {access_token}"}
                )
                if uresp.status_code == 200:
                    ui = uresp.json()
                    email = ui.get("email", "")
                    if not profile_data.get("id"):
                        profile_data["id"] = ui.get("sub", "")
                    if not profile_data.get("localizedFirstName"):
                        profile_data["localizedFirstName"] = ui.get("given_name", "")
                    if not profile_data.get("localizedLastName"):
                        profile_data["localizedLastName"] = ui.get("family_name", "")
                    if not profile_data.get("_pic_url"):
                        profile_data["_pic_url"] = ui.get("picture", "")
            except Exception:
                pass

        # ── Build profile picture URL ──
        pic_url = profile_data.get("_pic_url", "")
        if not pic_url:
            pic_elements = (
                profile_data.get("profilePicture", {})
                .get("displayImage~", {})
                .get("elements", [])
            )
            if pic_elements:
                identifiers = pic_elements[-1].get("identifiers", [])
                if identifiers:
                    pic_url = identifiers[0].get("identifier", "")

        return LinkedInProfile(
            person_id=profile_data.get("id", ""),
            first_name=profile_data.get("localizedFirstName", ""),
            last_name=profile_data.get("localizedLastName", ""),
            headline=profile_data.get("localizedHeadline", ""),
            vanity_name=profile_data.get("vanityName", ""),
            profile_picture_url=pic_url,
            email=email,
            profile_url=profile_url,
            verifications=verifications,
            positions=positions,
            education=education,
            skills=skills,
            certifications=certifications,
            languages=languages,
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
