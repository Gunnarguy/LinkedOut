import httpx
from models import JobAction

@mcp.tool()
def get_job_details(job_id: str) -> str:
    """Get the full complete details, including AI match reasons and company description, for a specific Job ID."""
    job = store.get_job(job_id)
    if not job:
        return f"Error: No job found with ID {job_id}"

    return f"""
Role: {job.role_title} @ {job.company_name}
URL: {job.source_url}
Score: {job.builder_score}
Location: {job.location} | Remote: {job.is_remote}
Company Size/Stage: {job.company_size} / {job.company_stage}

AI Pitch Summary:
{job.ai_pitch_summary}

Drafted Prompt/Cover Letter:
{job.drafted_cover_letter}

Full Description:
{job.description}
"""

@mcp.tool()
def action_job(job_id: str, action: str) -> str:
    """Take action on a job in the pipeline.

    Args:
        job_id: The ID of the job
        action: Must be one of 'applied', 'rejected', 'saved'
    """
    valid_actions = {
        "applied": JobAction.APPLY,
        "rejected": JobAction.REJECT,
        "saved": JobAction.SAVE
    }

    if action not in valid_actions:
        return "Error: Action must be 'applied', 'rejected', or 'saved'."

    success = store.act_on_job(job_id, valid_actions[action])
    if success:
        return f"Successfully moved job {job_id} to the {action} bucket."
    return f"Failed to act on job {job_id}. Check if it exists and wasn't already moved."

@mcp.tool()
async def get_my_linkedin_profile() -> dict:
    """Fetch the full LinkedIn profile details for the authenticated user (you)."""
    sessions = get_all_sessions()
    if not sessions:
        return {"error": "Not authenticated. Please log in first via the iOS app."}

    person_id, auth_session = list(sessions.items())[0]

    # Try the v2/me endpoint (Basic Profile)
    headers = {"Authorization": f"Bearer {auth_session.linkedin_access_token}"}
    async with httpx.AsyncClient() as client:
        resp = await client.get("https://api.linkedin.com/v2/me", headers=headers)
        if resp.status_code == 200:
            return resp.json()

        # Fallback to OpenID Userinfo
        resp_oidc = await client.get("https://api.linkedin.com/v2/userinfo", headers=headers)
        if resp_oidc.status_code == 200:
            data = resp_oidc.json()
            data["_source"] = "OIDC Fallback"
            return data

        return {"error": f"Failed to fetch profile: {resp.text}"}
