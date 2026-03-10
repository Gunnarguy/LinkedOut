import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # LinkedIn OAuth
    linkedin_client_id: str = ""
    linkedin_client_secret: str = ""
    linkedin_redirect_uri: str = "https://linkedout-backend.onrender.com/auth/callback"

    # LLM Provider: "openai" or "gemini"
    llm_provider: str = "gemini"

    # OpenAI
    openai_api_key: str = ""
    openai_model: str = "gpt-5.4"

    # Google Gemini
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-pro"
    gemini_flash_model: str = "gemini-2.0-flash"

    # Server
    host: str = "0.0.0.0"
    port: int = 8443
    debug: bool = True

    # Job scoring defaults
    min_salary: int = 90000
    require_remote: bool = True

    # CORS
    allowed_origins: list[str] = ["*"]

    # Secret key for signing tokens
    secret_key: str = "change-me-in-production"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
