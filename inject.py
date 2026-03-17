import json
import uuid
import datetime

store_path = "data/job_store.json"
try:
    with open(store_path, "r") as f:
        store = json.load(f)
except Exception as e:
    print(f"Error loading: {e}")
    store = {"pending": [], "applied": [], "saved": [], "rejected": []}

# Clean existing to prevent duplicates
store["saved"] = [j for j in store["saved"] if j["id"] != "test-ardent-ai-123"]

mock_job = {
    "id": "test-ardent-ai-123",
    "company_name": "Ardent AI",
    "role_title": "Founding Vibe Coder",
    "salary_floor": 180000,
    "salary_max": 250000,
    "is_remote": True,
    "builder_score": 0.99,
    "ai_pitch_summary": "• Builds wild prototypes daily.\n• Ignores Agile, writes raw Swift + Python.\n• No CS degree required.",
    "drafted_cover_letter": "Yo Ardent AI, I have shipped 4 indie apps and live in the terminal. No leetcode, just execution. Let us build.",
    "source_url": "https://ycombinator.com/jobs/ardent-ai",
    "location": "Remote / San Francisco",
    "tags": ["Indie Hacker", "AI", "Swift", "Python"],
    "tech_stack": ["FastAPI", "SwiftUI", "CoreML", "LLMs"],
    "why_interesting": "Perfect fit for an indie builder wanting to vibe code.",
    "description": "We need a 10x developer who doesnt care about leetcode.",
    "company_description": "Ardent AI is building the next generation of AI tooling for indie devs.",
    "company_size": "1-10",
    "company_stage": "Seed",
    "apply_url": "https://ardent.ai/jobs",
    "experience_level": "Any",
    "job_type": "Full-time",
    "fit_reasons": ["You ship apps", "You hate agile"],
    "posted_at": datetime.datetime.now().isoformat(),
}

store["saved"].append(mock_job)

with open(store_path, "w") as f:
    json.dump(store, f, indent=2)

print("Injected Ardent AI mock job into saved list!")
