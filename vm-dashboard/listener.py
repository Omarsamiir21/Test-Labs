#!/usr/bin/env python3
"""
VM Security Audit Listener
Runs on each monitored VM on port 5001.
Receives trigger requests from the dashboard and launches security_audit.sh.
"""

import os
import subprocess
from pathlib import Path

from flask import Flask, jsonify

app = Flask(__name__)

# Directory containing this script — security_audit.sh lives alongside it
SCRIPT_DIR = Path(__file__).parent
AUDIT_SCRIPT = SCRIPT_DIR / "security_audit.sh"


@app.post("/trigger")
def trigger_audit():
    """
    Receive an audit trigger from the dashboard server.
    Launches security_audit.sh in the background and returns immediately.
    """
    vt_api_key = os.environ.get("VT_API_KEY", "")
    dashboard_url = os.environ.get("DASHBOARD_URL", "http://localhost:5000")

    if not AUDIT_SCRIPT.exists():
        return jsonify({"status": "error", "message": "security_audit.sh not found"}), 500

    # Pass environment variables through to the child process
    env = os.environ.copy()
    env["VT_API_KEY"] = vt_api_key
    env["DASHBOARD_URL"] = dashboard_url

    # Launch audit script detached from this process; stdout/stderr go to a log file
    log_path = SCRIPT_DIR / "audit.log"
    with open(log_path, "a") as log:
        subprocess.Popen(
            ["bash", str(AUDIT_SCRIPT)],
            env=env,
            stdout=log,
            stderr=log,
            # Detach from the Flask process so it survives request teardown
            start_new_session=True,
        )

    return jsonify({"status": "started"}), 200


if __name__ == "__main__":
    port = int(os.environ.get("LISTENER_PORT", 5001))
    print(f"Security audit listener running on http://0.0.0.0:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)
