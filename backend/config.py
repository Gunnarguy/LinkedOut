import os
import secrets

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # LinkedIn OAuth
    linkedin_client_id: str = ""
    linkedin_client_secret: str = ""
    linkedin_redirect_uri: str = (
        "https://linkedout-backend-9q4t.onrender.com/auth/callback"
    )

    # LLM Provider: "openai" or "gemini"
    llm_provider: str = "gemini"

    # OpenAI
    openai_api_key: str = ""
    openai_model: str = "gpt-5.4"

    # Google Gemini
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.1-pro-preview"
    gemini_flash_model: str = "gemini-3-flash-preview"

    # Server
    host: str = "0.0.0.0"
    port: int = 8443
    debug: bool = os.getenv("RENDER", "") == ""  # Auto-disable debug on Render

    # Job scoring defaults
    min_salary: int = 70000
    require_remote: bool = True

    # Notion integration
    notion_token: str = ""
    notion_database_id: str = ""

    # SerpAPI (Google Jobs aggregator — free 250 searches/month at serpapi.com)
    serpapi_api_key: str = ""

    # Adzuna (job search aggregator — free at developer.adzuna.com)
    adzuna_app_id: str = ""
    adzuna_app_key: str = ""

    # FindWork.dev (dev/startup jobs — free at findwork.dev/developers)
    findwork_api_token: str = ""

    # Reed.co.uk (UK + remote jobs — free at reed.co.uk/developers)
    reed_api_key: str = ""

    # USAJobs (federal tech jobs — free at developer.usajobs.gov)
    usajobs_api_key: str = ""
    usajobs_email: str = ""

    # CORS
    allowed_origins: list[str] = ["*"]

    # Secret key for signing tokens (auto-generated if not set)
    secret_key: str = os.getenv("SECRET_KEY", secrets.token_urlsafe(32))

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
