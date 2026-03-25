#!/usr/bin/env python3
"""Real-time ingest monitor for LinkedOut backend."""
import urllib.request, json, time, sys, os
from typing import Any, cast

URL = os.environ.get("LINKEDOUT_URL", "https://linkedout-backend-9q4t.onrender.com")


def clear():
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.flush()


def bar(pct, width=30):
    filled = int(width * pct)
    return f"[{'█' * filled}{'░' * (width - filled)}] {pct*100:5.1f}%"


def fetch(path):
    try:
        req = urllib.request.Request(f"{URL}{path}")
        resp = urllib.request.urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}


while True:
    try:
        d = fetch("/api/telemetry")
        if "error" in d:
            clear()
            print(f"  ⚠  Connection error: {d['error']}")
            time.sleep(5)
            continue

        server = cast(dict[str, Any], d.get("server", {}))
        ingest = cast(dict[str, Any], d.get("ingest", {}))
        prog = cast(dict[str, Any], ingest.get("progress", {}))
        store = cast(dict[str, Any], d.get("store", {}))

        phase = prog.get("phase", "idle")
        batch = prog.get("batch", 0)
        total = prog.get("total_batches", 0)
        fetched = prog.get("fetched", 0)
        new = prog.get("new_after_dedup", 0)
        triaged = prog.get("triaged", 0)
        triage_passed = prog.get("triage_passed", 0)
        to_score = prog.get("to_score", 0)
        scored = prog.get("scored", 0)
        queued = prog.get("queued", 0)
        rejected = prog.get("rejected", 0)
        low = prog.get("low_score", 0)
        errors = prog.get("errors", 0)
        current_stage = prog.get("current_stage", "idle")
        current_item = prog.get("current_item", 0)
        current_total = prog.get("current_total", 0)
        current_title = prog.get("current_title", "")
        current_company = prog.get("current_company", "")
        pending = store.get("pending", 0)
        saved = store.get("saved", 0)
        applied = store.get("applied", 0)
        rej_store = store.get("rejected", 0)

        pct = (batch / total) if total > 0 else (1.0 if phase == "complete" else 0.0)
        pass_rate = (queued / scored * 100) if scored > 0 else 0.0

        clear()
        print("  ╔══════════════════════════════════════════════════╗")
        print("  ║         LinkedOut Ingest Monitor                 ║")
        print("  ╠══════════════════════════════════════════════════╣")
        print(
            f"  ║  Phase:  {phase.upper():10s}   Uptime: {server.get('uptime_human', '?'):>12s}  ║"
        )
        print(
            f"  ║  Batch:  {batch}/{total}          {bar(pct)}  ║"
            if total > 0
            else f"  ║  {bar(pct)}                                  ║"
        )
        print("  ╠══════════════════════════════════════════════════╣")
        print(f"  ║  Fetched:    {fetched:>5d}    │  Queued:     {queued:>5d}  ║")
        print(f"  ║  New:        {new:>5d}    │  Rejected:   {rejected:>5d}  ║")
        print(
            f"  ║  Triaged:    {triaged:>5d}    │  Passed:     {triage_passed:>5d}  ║"
        )
        print(f"  ║  To score:   {to_score:>5d}    │  Scored:     {scored:>5d}  ║")
        print(f"  ║  Low score:  {low:>5d}    │  Pass rate: {pass_rate:>5.1f}%  ║")
        print(f"  ║  Errors:     {errors:>5d}    │  Pending:    {pending:>5d}  ║")
        print("  ╠══════════════════════════════════════════════════╣")
        if current_title:
            current_line = f"{current_stage.upper()} {current_item}/{current_total}: {current_title} @ {current_company}".strip()
            current_line = current_line[:52]
            print(f"  ║  {current_line:<52s}║")
            print("  ╠══════════════════════════════════════════════════╣")
        print(
            f"  ║  📱 Pending: {pending:>4d}  Applied: {applied:>4d}  Saved: {saved:>4d}  ║"
        )
        print(f"  ║     Store rejected: {rej_store:>4d}                      ║")
        print("  ╚══════════════════════════════════════════════════╝")

        if phase == "complete":
            print(f"\n  ✅ Ingest complete! {queued} jobs queued.")
            # Show the jobs
            jobs = fetch("/api/jobs/pending?limit=50")
            if isinstance(jobs, list) and jobs:
                print(f"\n  Top {len(jobs)} pending jobs:")
                print(f"  {'Score':>5s}  {'Title':<45s}  {'Company':<20s}")
                print(f"  {'─'*5}  {'─'*45}  {'─'*20}")
                for j in sorted(
                    jobs, key=lambda x: x.get("builder_score", 0), reverse=True
                ):
                    s = j.get("builder_score", 0)
                    t = j.get("role_title", "?")[:45]
                    c = j.get("company_name", "?")[:20]
                    print(f"  {s:5.2f}  {t:<45s}  {c:<20s}")
            print("\n  Press Ctrl+C to exit.")

        time.sleep(5)
    except KeyboardInterrupt:
        print("\n  Bye!")
        break
