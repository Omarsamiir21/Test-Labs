#!/usr/bin/env python3
"""
VM Health Dashboard Server
Accepts metric reports from agents and serves the live dashboard.
"""

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request, send_file, abort

app = Flask(__name__)

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

OFFLINE_THRESHOLD_SECS = 60  # VM is considered offline after this many seconds


def load_all_vms() -> list[dict]:
    """Read every JSON file in data/ and annotate with online/offline status."""
    vms = []
    now = datetime.now(timezone.utc)

    for path in sorted(DATA_DIR.glob("*.json")):
        try:
            with path.open() as f:
                vm = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue  # skip corrupt files

        # Determine online status from last timestamp
        try:
            last_seen = datetime.fromisoformat(vm["timestamp"].replace("Z", "+00:00"))
            age_secs = (now - last_seen).total_seconds()
            vm["online"] = age_secs <= OFFLINE_THRESHOLD_SECS
            vm["age_secs"] = int(age_secs)
        except (KeyError, ValueError):
            vm["online"] = False
            vm["age_secs"] = -1

        vms.append(vm)

    return vms


@app.post("/api/report")
def receive_report():
    """Accept a JSON payload from an agent and persist it to data/HOSTNAME.json."""
    data = request.get_json(silent=True)
    if not data:
        abort(400, "Expected JSON body")

    hostname = data.get("hostname", "").strip()
    if not hostname:
        abort(400, "Missing hostname field")

    # Sanitise hostname so it's safe as a filename
    safe_name = "".join(c for c in hostname if c.isalnum() or c in "-_.")
    if not safe_name:
        abort(400, "Invalid hostname")

    out_path = DATA_DIR / f"{safe_name}.json"
    with out_path.open("w") as f:
        json.dump(data, f, indent=2)

    return jsonify({"status": "ok", "hostname": hostname}), 200


@app.get("/api/vms")
def get_vms():
    """Return all VM data as a JSON array, with online/offline annotations."""
    vms = load_all_vms()
    online = sum(1 for v in vms if v["online"])
    return jsonify({
        "vms": vms,
        "summary": {
            "total":   len(vms),
            "online":  online,
            "offline": len(vms) - online,
        },
        "server_time": datetime.now(timezone.utc).isoformat(),
    })


@app.get("/dashboard")
@app.get("/")
def serve_dashboard():
    """Serve the static dashboard HTML."""
    html_path = Path(__file__).parent / "dashboard.html"
    if not html_path.exists():
        abort(404, "dashboard.html not found")
    return send_file(html_path)


if __name__ == "__main__":
    print("VM Dashboard server running on http://0.0.0.0:5000")
    print(f"Dashboard: http://localhost:5000/dashboard")
    app.run(host="0.0.0.0", port=5000, debug=False)
