"""
LinkedOut Internal MCP Server
Exposes LinkedIn UGC sharing, OAuth status, and LinkedOut pipeline stats to your local LLM.
"""

from mcp.server.fastmcp import FastMCP
from linkedin_oauth import get_all_sessions
from linkedin_api import share_to_linkedin
from job_store import store
import httpx
from models import JobAction

# Create the FastMCP server
mcp = FastMCP("LinkedOut-Internal")

@mcp.tool()
async def post_linkedin_update(text: str, article_url: str | None = None) -> str:
    """Share an update to your personal LinkedIn network.
    
    Args:
        text: The text content of your LinkedIn post
        article_url: Optional URL to include as a linked article
    """
    sessions = get_all_sessions()
    if not sessions:
        return "Error: No authenticated LinkedIn sessions found in LinkedOut database. Please open the iOS app and log in first to authorize the backend."
    
    # Just grab the first session (single user app)
    person_id, auth_session = list(sessions.items())[0]
    
    try:
        result = await share_to_linkedin(
            access_token=auth_session.linkedin_access_token,
            person_id=person_id,
            text=text,
            article_url=article_url
        )
        return f"Successfully posted to LinkedIn! Post ID: {result.get('id')}"
    except Exception as e:
        return f"Failed to post to LinkedIn: {str(e)}"

@mcp.tool()
async def get_my_linkedin_profile() -> dict:
    """Fetch your full LinkedIn profile details from the LinkedIn API."""
    sessions = get_all_sessions()
    if not sessions:
        return {"error": "Not authenticated. Please log in first via the iOS app."}
    
    person_id, auth_session = list(sessions.items())[0]
    headers = {"Authorization": f"Bearer {auth_session.linkedin_access_token}"}
    
    async with httpx.AsyncClient() as client:
        # Try v2/me endpoint for richer profile data
        resp = await client.get("https://api.linkedin.com/v2/me", headers=headers)
        if resp.status_code == 200:
            return resp.json()
            
        # Fallback to Userinfo API
        resp_fallback = await client.get("https://api.linkedin.com/v2/userinfo", headers=headers)
        if resp_fallback.status_code == 200:
            data = resp_fallback.json()
            data["_source"] = "OIDC Fallback"
            return data
            
        return {"error": f"Failed (Status {resp.status_code}): {resp.text}"}

@mcp.tool()
def get_linkedin_auth_status() -> str:
    """Check if the user is currently authenticated with LinkedIn via the LinkedOut backend."""
    sessions = get_all_sessions()
    if not sessions:
        return "Not authenticated. Zero sessions found."
    
    person_id, session = list(sessions.items())[0]
    return f"Authenticated as {session.profile.first_name} {session.profile.last_name} (ID: {person_id}). Token expires at {session.expires_at}."

@mcp.tool()
def get_linkedout_pipeline_stats() -> dict:
    """Get the current counts of jobs in the LinkedOut job tracker pipeline."""
    stats = store.stats
    return stats

@mcp.tool()
def get_saved_jobs_to_share() -> str:
    """Retrieve jobs currently marked as 'saved' to potentially share/post about on LinkedIn."""
    jobs = store._saved
    if not jobs:
        return "No saved jobs at the moment."
    
    out = "Saved Jobs ready for sharing/review:\n\n"
    for jid, j in jobs.items():
        out += f"- {j.role_title} @ {j.company_name} (ID: {jid})\n"
        out += f"  Match Score: {j.builder_score}\n"
        out += f"  Location: {j.location}\n"
        out += f"  URL: {j.source_url}\n\n"
    
    return out

@mcp.tool()
def query_pending_jobs() -> str:
    """Retrieve top 5 pending jobs from the queue with highest score."""
    jobs = list(store._pending.values())
    if not jobs:
        return "No pending jobs at the moment."
    
    jobs.sort(key=lambda x: x.builder_score, reverse=True)
    out = "Top 5 Pending Jobs:\n\n"
    for j in jobs[:5]:
        out += f"- [{j.builder_score:.2f}] {j.role_title} @ {j.company_name} (ID: {j.id})\n"
        
    return out

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
        action: Must be one of 'apply', 'reject', 'save'
    """
    valid_actions = {
        "apply": JobAction.apply,
        "reject": JobAction.reject,
        "save": JobAction.save
    }
    
    if action not in valid_actions:
        return "Error: Action must be 'apply', 'reject', or 'save'."
        
    success = store.act_on_job(job_id, valid_actions[action])
    if success:
        return f"Successfully acted on job {job_id} ({action})."
    return f"Failed to act on job {job_id}. Check if it exists."

@mcp.tool()
async def trigger_linkedout_ingest() -> str:
    """Trigger a background ingestion of remote jobs from LinkedOut's fetcher APIs."""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post("http://localhost:8443/api/ingest/refresh", timeout=10.0)
            if resp.status_code == 200:
                return "Successfully triggered ingestion on the LinkedOut backend."
            return f"Failed to trigger ingestion: {resp.status_code} - {resp.text}"
        except httpx.RequestError as e:
            return f"Failed to connect to LinkedOut backend (is it running on port 8443?): {e}"

if __name__ == "__main__":
    mcp.run()
