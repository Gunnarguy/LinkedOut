#!/usr/bin/env python3
"""Quick audit of the job store to check for data loss risks."""
import json

with open("data/job_store.json") as f:
    store = json.load(f)

# Check posted_at status across all buckets
for bucket_name in ["pending", "applied", "saved", "rejected"]:
    jobs = store.get(bucket_name, [])
    has_posted = sum(1 for j in jobs if j.get("posted_at"))
    no_posted = sum(1 for j in jobs if not j.get("posted_at"))
    print(f"{bucket_name}: {len(jobs)} total, {has_posted} with posted_at, {no_posted} WITHOUT (would be expired)")

# Show the score distribution of pending
print()
pending = store.get("pending", [])
if pending:
    scores = sorted([j.get("builder_score", 0) for j in pending], reverse=True)
    print(f"Pending scores: min={min(scores):.2f}, max={max(scores):.2f}, median={scores[len(scores)//2]:.2f}")
    print(f"Jobs >= 0.60: {sum(1 for s in scores if s >= 0.60)}")
    print(f"Jobs >= 0.50: {sum(1 for s in scores if s >= 0.50)}")
    print(f"Jobs < 0.40: {sum(1 for s in scores if s < 0.40)}")

# Check how many seen URLs vs pending
print()
with open("data/seen_urls.json") as f:
    seen = json.load(f)
total_stored = sum(len(store.get(b, [])) for b in ["pending", "applied", "saved", "rejected"])
print(f"Seen URLs: {len(seen)}")
print(f"Total jobs stored: {total_stored}")
print(f"Jobs scored but DISCARDED (seen but not stored): {len(seen) - total_stored}")

# Show high-score jobs that have no posted_at
print()
print("=== HIGH-SCORE PENDING JOBS WITH NO posted_at (at risk of expiry) ===")
at_risk = [j for j in pending if not j.get("posted_at") and j.get("builder_score", 0) >= 0.50]
at_risk.sort(key=lambda j: j.get("builder_score", 0), reverse=True)
for j in at_risk:
    print(f"  {j.get('builder_score', 0):.2f} | {j.get('company_name', '?')[:25]:<25} | {j.get('role_title', '?')[:40]}")
if not at_risk:
    print("  (none)")
