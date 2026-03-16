import json

with open("data/job_store.json", "r") as f:
    data = json.load(f)

old_pending_count = len(data.get("pending", []))

# Filter out jobs that were scored locally
data["pending"] = [j for j in data.get("pending", []) 
                   if "local keyword matcher" not in j.get("ai_pitch_summary", "")]

new_pending_count = len(data["pending"])

print(f"Removed {old_pending_count - new_pending_count} local scorer jobs. Left with {new_pending_count}")

with open("data/job_store.json", "w") as f:
    json.dump(data, f, indent=2)
