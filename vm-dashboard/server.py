#!/usr/bin/env python3
"""
VM Health Dashboard Server
Accepts metric reports from agents and serves the live dashboard.
Also handles security audit triggering and report ingestion.
"""

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from flask import Flask, jsonify, request, send_file, abort, Response

app = Flask(__name__)

DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

OFFLINE_THRESHOLD_SECS = 60  # VM is considered offline after this many seconds
LISTENER_PORT = 5001          # Port the security audit listener runs on each VM


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


# ── Security audit endpoints ──────────────────────────────────────────────────

def _safe_hostname(hostname: str) -> str:
    """Sanitise hostname to a safe filename component."""
    safe = "".join(c for c in hostname if c.isalnum() or c in "-_.")
    return safe


def _get_vm_ip(hostname: str) -> str | None:
    """Look up the last-known IP for a hostname from its metric file."""
    safe = _safe_hostname(hostname)
    path = DATA_DIR / f"{safe}.json"
    try:
        with path.open() as f:
            data = json.load(f)
        return data.get("ip")
    except (OSError, json.JSONDecodeError):
        return None


@app.post("/api/trigger/<hostname>")
def trigger_audit(hostname: str):
    """Forward an audit trigger to the VM's listener on port 5001."""
    ip = _get_vm_ip(hostname)
    if not ip:
        abort(404, f"No known IP for hostname '{hostname}'")

    listener_url = f"http://{ip}:{LISTENER_PORT}/trigger"
    try:
        resp = requests.post(listener_url, timeout=5)
        resp.raise_for_status()
        return jsonify({"status": "triggered", "hostname": hostname, "ip": ip}), 200
    except requests.exceptions.ConnectionError:
        abort(502, f"Could not reach listener at {listener_url}")
    except requests.exceptions.Timeout:
        abort(504, f"Listener at {listener_url} timed out")
    except requests.exceptions.HTTPError as e:
        abort(502, f"Listener returned error: {e}")


@app.post("/api/report/security")
def receive_security_report():
    """Receive a completed HTML security report from a VM and save it to disk."""
    hostname = request.headers.get("X-Hostname", "").strip()
    if not hostname:
        # Fall back to form field
        hostname = request.form.get("hostname", "").strip()
    if not hostname:
        abort(400, "Missing X-Hostname header or hostname field")

    safe = _safe_hostname(hostname)
    if not safe:
        abort(400, "Invalid hostname")

    date_str = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filename = f"security_{safe}_{date_str}.html"
    out_path = DATA_DIR / filename

    # Accept either raw HTML body (content-type text/html) or a file upload
    content_type = request.content_type or ""
    if "multipart/form-data" in content_type:
        file = request.files.get("report")
        if not file:
            abort(400, "Expected 'report' file in multipart upload")
        file.save(out_path)
    else:
        html_bytes = request.get_data()
        if not html_bytes:
            abort(400, "Empty report body")
        out_path.write_bytes(html_bytes)

    return jsonify({"status": "saved", "file": filename}), 200


@app.get("/api/report/security/<hostname>")
def serve_security_report(hostname: str):
    """Serve the latest security report HTML for a given hostname."""
    safe = _safe_hostname(hostname)
    if not safe:
        abort(400, "Invalid hostname")

    # Find the most recent report for this host (files sort lexicographically by timestamp)
    pattern = f"security_{safe}_*.html"
    matches = sorted(DATA_DIR.glob(pattern))
    if not matches:
        abort(404, f"No security report found for '{hostname}'")

    return send_file(matches[-1], mimetype="text/html")


@app.get("/api/reports")
def list_reports():
    """Return a JSON list of all available security reports with metadata."""
    reports = []
    for path in sorted(DATA_DIR.glob("security_*.html"), reverse=True):
        # Filename format: security_<hostname>_<YYYYMMDD_HHMMSS>.html
        parts = path.stem.split("_")
        # stem = security_<hostname>_<date>_<time>  (hostname may contain hyphens/dots)
        # Reconstruct: skip first token ("security"), last two are date+time
        if len(parts) < 4:
            continue
        date_part = parts[-2]   # YYYYMMDD
        time_part = parts[-1]   # HHMMSS
        hostname_parts = parts[1:-2]
        hostname = "_".join(hostname_parts)

        try:
            ts = datetime.strptime(f"{date_part}_{time_part}", "%Y%m%d_%H%M%S")
            timestamp = ts.replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            timestamp = None

        reports.append({
            "hostname":  hostname,
            "filename":  path.name,
            "timestamp": timestamp,
            "url":       f"/api/report/security/{hostname}",
        })

    return jsonify({"reports": reports})


if __name__ == "__main__":
    print("VM Dashboard server running on http://0.0.0.0:5000")
    print(f"Dashboard: http://localhost:5000/dashboard")
    app.run(host="0.0.0.0", port=5000, debug=False)
