#!/usr/bin/env bash
# =============================================================================
# security_audit.sh — Full local security posture assessment
#
# Performs:
#   1. Open ports scan (ss / nmap)
#   2. Running processes with SHA256 hashes checked against VirusTotal
#   3. Network connections with remote IPs checked against VirusTotal
#
# Environment variables:
#   VT_API_KEY    — VirusTotal API key (free tier: 4 req/min)
#   DASHBOARD_URL — Base URL of the dashboard server (default: http://localhost:5000)
#
# Output: POSTs self-contained HTML report to $DASHBOARD_URL/api/report/security
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
VT_API_KEY="${VT_API_KEY:-}"
DASHBOARD_URL="${DASHBOARD_URL:-http://localhost:5000}"
HOSTNAME_VAL="$(hostname)"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
REPORT_DATE="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Temp directory for intermediate data
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ── VirusTotal helpers ────────────────────────────────────────────────────────

# VT_REQUEST_COUNT tracks calls; sleep to stay under 4 req/min on free tier
VT_REQUEST_COUNT=0

vt_throttle() {
    VT_REQUEST_COUNT=$((VT_REQUEST_COUNT + 1))
    # Every 4 requests, sleep 65 seconds to respect the rate limit
    if (( VT_REQUEST_COUNT % 4 == 0 )); then
        echo "[*] VT rate limit pause (65s)..." >&2
        sleep 65
    fi
}

# Check a file hash against VirusTotal. Echoes "clean", "suspicious:<detections>/<total>", or "unknown"
vt_check_hash() {
    local hash="$1"
    if [[ -z "$VT_API_KEY" || -z "$hash" ]]; then
        echo "unknown"
        return
    fi
    vt_throttle
    local response
    response="$(curl -s --max-time 10 \
        -H "x-apikey: $VT_API_KEY" \
        "https://www.virustotal.com/api/v3/files/${hash}" 2>/dev/null || true)"

    local malicious harmless total
    malicious="$(echo "$response" | grep -o '"malicious":[0-9]*' | head -1 | cut -d: -f2)"
    harmless="$(echo "$response"  | grep -o '"harmless":[0-9]*'  | head -1 | cut -d: -f2)"
    total="$(echo "$response"     | grep -o '"total":[0-9]*'      | head -1 | cut -d: -f2)"

    if [[ -z "$malicious" ]]; then
        echo "unknown"
    elif (( malicious > 0 )); then
        echo "suspicious:${malicious}/${total:-?}"
    else
        echo "clean"
    fi
}

# Check an IP address against VirusTotal. Echoes "clean", "suspicious:<score>", or "unknown"
vt_check_ip() {
    local ip="$1"
    if [[ -z "$VT_API_KEY" || -z "$ip" ]]; then
        echo "unknown"
        return
    fi
    # Skip private/loopback ranges — no point querying VT for them
    if [[ "$ip" =~ ^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
        echo "private"
        return
    fi
    vt_throttle
    local response malicious
    response="$(curl -s --max-time 10 \
        -H "x-apikey: $VT_API_KEY" \
        "https://www.virustotal.com/api/v3/ip_addresses/${ip}" 2>/dev/null || true)"

    malicious="$(echo "$response" | grep -o '"malicious":[0-9]*' | head -1 | cut -d: -f2)"

    if [[ -z "$malicious" ]]; then
        echo "unknown"
    elif (( malicious > 0 )); then
        echo "suspicious:${malicious}"
    else
        echo "clean"
    fi
}

# ── 1. Open ports ─────────────────────────────────────────────────────────────
echo "[*] Scanning open ports..." >&2
PORTS_DATA="$TMPDIR_WORK/ports.txt"

if command -v ss &>/dev/null; then
    # ss output: State, Recv-Q, Send-Q, Local Address:Port, Peer Address:Port, Process
    ss -tlnpH 2>/dev/null | awk '{print $1, $4, $6}' > "$PORTS_DATA" || true
    # Also get UDP
    ss -ulnpH 2>/dev/null | awk '{print $1, $4, $6}' >> "$PORTS_DATA" || true
elif command -v nmap &>/dev/null; then
    nmap -p- --open -T4 127.0.0.1 2>/dev/null \
        | grep '^[0-9]' \
        | awk '{print "LISTEN", $1, ""}' > "$PORTS_DATA" || true
else
    echo "LISTEN N/A (ss and nmap not found)" > "$PORTS_DATA"
fi

# Build port rows for HTML table: proto, port, process
PORT_ROWS=""
OPEN_PORT_COUNT=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local_addr="$(echo "$line" | awk '{print $2}')"
    process="$(echo "$line"    | awk '{print $3}')"
    proto="$(echo "$line"      | awk '{print $1}')"
    port="$(echo "$local_addr" | rev | cut -d: -f1 | rev)"
    OPEN_PORT_COUNT=$((OPEN_PORT_COUNT + 1))
    PORT_ROWS+="<tr><td>${proto}</td><td>${port}</td><td>${local_addr}</td><td>${process:-—}</td></tr>"
done < "$PORTS_DATA"

# ── 2. Running processes with hashes ─────────────────────────────────────────
echo "[*] Collecting process hashes..." >&2
PROC_DATA="$TMPDIR_WORK/procs.txt"

# Get unique executable paths for running processes
ps -eo pid,comm,exe 2>/dev/null \
    | awk 'NR>1 && $3!="" && $3!="exe" {print $3}' \
    | sort -u \
    | head -50 \
    > "$PROC_DATA" || true   # cap at 50 to limit VT calls

PROC_ROWS=""
SUSPICIOUS_PROC_COUNT=0
declare -A HASH_CACHE  # avoid re-querying the same hash twice

while IFS= read -r exe; do
    [[ -z "$exe" || ! -f "$exe" ]] && continue
    hash="$(sha256sum "$exe" 2>/dev/null | awk '{print $1}' || true)"
    [[ -z "$hash" ]] && continue

    if [[ -n "${HASH_CACHE[$hash]+_}" ]]; then
        vt_result="${HASH_CACHE[$hash]}"
    else
        vt_result="$(vt_check_hash "$hash")"
        HASH_CACHE["$hash"]="$vt_result"
    fi

    row_class=""
    vt_badge="<span class='badge clean'>Clean</span>"
    if [[ "$vt_result" == suspicious:* ]]; then
        row_class="class='row-danger'"
        detail="${vt_result#suspicious:}"
        vt_badge="<span class='badge danger'>Suspicious (${detail})</span>"
        SUSPICIOUS_PROC_COUNT=$((SUSPICIOUS_PROC_COUNT + 1))
    elif [[ "$vt_result" == "unknown" ]]; then
        vt_badge="<span class='badge unknown'>Unknown</span>"
    elif [[ "$vt_result" == "clean" ]]; then
        vt_badge="<span class='badge clean'>Clean</span>"
    fi

    PROC_ROWS+="<tr ${row_class}><td style='word-break:break-all'>${exe}</td><td style='font-family:monospace;font-size:0.75rem'>${hash}</td><td>${vt_badge}</td></tr>"
done < "$PROC_DATA"

# ── 3. Network connections ────────────────────────────────────────────────────
echo "[*] Auditing network connections..." >&2
CONN_DATA="$TMPDIR_WORK/conns.txt"

if command -v ss &>/dev/null; then
    ss -tnpH state established 2>/dev/null \
        | awk '{print $4, $5, $6}' > "$CONN_DATA" || true
else
    netstat -tn 2>/dev/null \
        | grep ESTABLISHED \
        | awk '{print $4, $5, ""}' > "$CONN_DATA" || true
fi

CONN_ROWS=""
SUSPICIOUS_CONN_COUNT=0
declare -A IP_CACHE

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local_addr="$(echo "$line"  | awk '{print $1}')"
    remote_addr="$(echo "$line" | awk '{print $2}')"
    process="$(echo "$line"     | awk '{print $3}')"
    remote_ip="$(echo "$remote_addr" | rev | cut -d: -f2- | rev)"

    if [[ -n "${IP_CACHE[$remote_ip]+_}" ]]; then
        vt_result="${IP_CACHE[$remote_ip]}"
    else
        vt_result="$(vt_check_ip "$remote_ip")"
        IP_CACHE["$remote_ip"]="$vt_result"
    fi

    row_class=""
    vt_badge="<span class='badge clean'>Clean</span>"
    if [[ "$vt_result" == suspicious:* ]]; then
        row_class="class='row-warning'"
        detail="${vt_result#suspicious:}"
        vt_badge="<span class='badge warning'>Suspicious (${detail} engines)</span>"
        SUSPICIOUS_CONN_COUNT=$((SUSPICIOUS_CONN_COUNT + 1))
    elif [[ "$vt_result" == "unknown" ]]; then
        vt_badge="<span class='badge unknown'>Unknown</span>"
    elif [[ "$vt_result" == "private" ]]; then
        vt_badge="<span class='badge info'>Private</span>"
    fi

    CONN_ROWS+="<tr ${row_class}><td>${local_addr}</td><td>${remote_addr}</td><td>${process:-—}</td><td>${vt_badge}</td></tr>"
done < "$CONN_DATA"

# ── Risk level calculation ────────────────────────────────────────────────────
if (( SUSPICIOUS_PROC_COUNT > 0 )); then
    RISK_LEVEL="Critical"
    RISK_CLASS="risk-critical"
elif (( SUSPICIOUS_CONN_COUNT > 0 )); then
    RISK_LEVEL="High"
    RISK_CLASS="risk-high"
elif (( OPEN_PORT_COUNT > 10 )); then
    RISK_LEVEL="Medium"
    RISK_CLASS="risk-medium"
else
    RISK_LEVEL="Low"
    RISK_CLASS="risk-low"
fi

# ── Recommendations ───────────────────────────────────────────────────────────
RECOMMENDATIONS=""
(( SUSPICIOUS_PROC_COUNT > 0 )) && RECOMMENDATIONS+="<li class='rec-critical'>⚠️ <strong>${SUSPICIOUS_PROC_COUNT} process(es)</strong> flagged by VirusTotal — investigate immediately and consider isolating this host.</li>"
(( SUSPICIOUS_CONN_COUNT > 0 )) && RECOMMENDATIONS+="<li class='rec-high'>⚠️ <strong>${SUSPICIOUS_CONN_COUNT} network connection(s)</strong> to suspicious IPs — review with <code>ss -tnp</code> and block via firewall if unrecognised.</li>"
(( OPEN_PORT_COUNT > 10 ))      && RECOMMENDATIONS+="<li class='rec-medium'>Consider closing unused open ports to reduce attack surface.</li>"
[[ -z "$VT_API_KEY" ]]          && RECOMMENDATIONS+="<li class='rec-info'>ℹ️ VT_API_KEY not set — VirusTotal checks were skipped. Set the variable and re-run for full analysis.</li>"
[[ -z "$RECOMMENDATIONS" ]]     && RECOMMENDATIONS="<li class='rec-clean'>✅ No significant issues detected. Continue routine monitoring.</li>"

# ── Generate HTML report ──────────────────────────────────────────────────────
echo "[*] Generating HTML report..." >&2
REPORT_FILE="$TMPDIR_WORK/report.html"

cat > "$REPORT_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Security Audit — ${HOSTNAME_VAL}</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3e;
      --text: #e2e8f0; --muted: #8892a4;
      --red: #ef4444; --orange: #f97316; --yellow: #eab308;
      --green: #22c55e; --blue: #3b82f6; --purple: #a855f7;
    }
    body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 2rem; }
    h1 { font-size: 1.6rem; font-weight: 700; margin-bottom: 0.25rem; }
    .subtitle { color: var(--muted); font-size: 0.85rem; margin-bottom: 2rem; }
    .risk-banner {
      border-radius: 10px; padding: 1.25rem 1.5rem; margin-bottom: 2rem;
      display: flex; align-items: center; gap: 1rem;
    }
    .risk-critical { background: rgba(239,68,68,0.2);  border: 1px solid var(--red);    }
    .risk-high      { background: rgba(249,115,22,0.2); border: 1px solid var(--orange); }
    .risk-medium    { background: rgba(234,179,8,0.2);  border: 1px solid var(--yellow); }
    .risk-low       { background: rgba(34,197,94,0.2);  border: 1px solid var(--green);  }
    .risk-label { font-size: 1.1rem; font-weight: 700; }
    .risk-critical .risk-label { color: var(--red);    }
    .risk-high      .risk-label { color: var(--orange); }
    .risk-medium    .risk-label { color: var(--yellow); }
    .risk-low       .risk-label { color: var(--green);  }
    section { margin-bottom: 2.5rem; }
    h2 { font-size: 1.1rem; font-weight: 600; border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; margin-bottom: 1rem; }
    table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
    th, td { padding: 0.55rem 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }
    th { background: var(--surface); color: var(--muted); font-weight: 600; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.05em; }
    tr:hover td { background: rgba(255,255,255,0.03); }
    .row-danger td  { background: rgba(239,68,68,0.1); }
    .row-warning td { background: rgba(249,115,22,0.1); }
    .badge { display: inline-block; padding: 0.15rem 0.55rem; border-radius: 999px; font-size: 0.72rem; font-weight: 600; }
    .badge.clean    { background: rgba(34,197,94,0.15);  color: var(--green);  border: 1px solid rgba(34,197,94,0.3); }
    .badge.danger   { background: rgba(239,68,68,0.2);   color: var(--red);    border: 1px solid rgba(239,68,68,0.4); }
    .badge.warning  { background: rgba(249,115,22,0.2);  color: var(--orange); border: 1px solid rgba(249,115,22,0.4); }
    .badge.unknown  { background: rgba(136,146,164,0.15); color: var(--muted);  border: 1px solid rgba(136,146,164,0.3); }
    .badge.info     { background: rgba(59,130,246,0.15); color: var(--blue);   border: 1px solid rgba(59,130,246,0.3); }
    ul.recs { list-style: none; display: flex; flex-direction: column; gap: 0.6rem; }
    ul.recs li { padding: 0.65rem 1rem; border-radius: 8px; font-size: 0.85rem; }
    .rec-critical { background: rgba(239,68,68,0.1);  border-left: 3px solid var(--red);    }
    .rec-high     { background: rgba(249,115,22,0.1); border-left: 3px solid var(--orange); }
    .rec-medium   { background: rgba(234,179,8,0.1);  border-left: 3px solid var(--yellow); }
    .rec-info     { background: rgba(59,130,246,0.1); border-left: 3px solid var(--blue);   }
    .rec-clean    { background: rgba(34,197,94,0.1);  border-left: 3px solid var(--green);  }
    .stats { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1.5rem; }
    .stat-box { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 0.75rem 1.25rem; min-width: 120px; }
    .stat-box .n { font-size: 1.8rem; font-weight: 700; line-height: 1; }
    .stat-box .l { font-size: 0.7rem; color: var(--muted); text-transform: uppercase; margin-top: 0.2rem; }
    .n.danger { color: var(--red); }
    .n.warn   { color: var(--orange); }
    .n.ok     { color: var(--green); }
    footer { margin-top: 3rem; font-size: 0.75rem; color: var(--muted); border-top: 1px solid var(--border); padding-top: 1rem; }
  </style>
</head>
<body>

<h1>🔒 Security Audit Report</h1>
<div class="subtitle">Host: <strong>${HOSTNAME_VAL}</strong> &nbsp;|&nbsp; Generated: ${REPORT_DATE}</div>

<div class="risk-banner ${RISK_CLASS}">
  <div>
    <div class="risk-label">Overall Risk: ${RISK_LEVEL}</div>
    <div style="font-size:0.82rem;margin-top:0.2rem;color:var(--muted)">
      ${SUSPICIOUS_PROC_COUNT} suspicious process(es) &nbsp;·&nbsp;
      ${SUSPICIOUS_CONN_COUNT} suspicious connection(s) &nbsp;·&nbsp;
      ${OPEN_PORT_COUNT} open port(s)
    </div>
  </div>
</div>

<section>
  <h2>Executive Summary</h2>
  <div class="stats">
    <div class="stat-box">
      <div class="n $([ $OPEN_PORT_COUNT -gt 10 ] && echo warn || echo ok)">${OPEN_PORT_COUNT}</div>
      <div class="l">Open Ports</div>
    </div>
    <div class="stat-box">
      <div class="n $([ $SUSPICIOUS_PROC_COUNT -gt 0 ] && echo danger || echo ok)">${SUSPICIOUS_PROC_COUNT}</div>
      <div class="l">Suspicious Procs</div>
    </div>
    <div class="stat-box">
      <div class="n $([ $SUSPICIOUS_CONN_COUNT -gt 0 ] && echo warn || echo ok)">${SUSPICIOUS_CONN_COUNT}</div>
      <div class="l">Suspicious Conns</div>
    </div>
  </div>
</section>

<section>
  <h2>Open Ports</h2>
  <table>
    <thead><tr><th>Proto</th><th>Port</th><th>Local Address</th><th>Process</th></tr></thead>
    <tbody>
      ${PORT_ROWS:-<tr><td colspan="4" style="color:var(--muted)">No open ports found</td></tr>}
    </tbody>
  </table>
</section>

<section>
  <h2>Process VirusTotal Analysis</h2>
  <table>
    <thead><tr><th>Executable</th><th>SHA256</th><th>VT Result</th></tr></thead>
    <tbody>
      ${PROC_ROWS:-<tr><td colspan="3" style="color:var(--muted)">No processes analysed</td></tr>}
    </tbody>
  </table>
</section>

<section>
  <h2>Network Connections</h2>
  <table>
    <thead><tr><th>Local</th><th>Remote</th><th>Process</th><th>VT Result</th></tr></thead>
    <tbody>
      ${CONN_ROWS:-<tr><td colspan="4" style="color:var(--muted)">No established connections</td></tr>}
    </tbody>
  </table>
</section>

<section>
  <h2>Recommendations</h2>
  <ul class="recs">
    ${RECOMMENDATIONS}
  </ul>
</section>

<footer>
  Generated by security_audit.sh on ${HOSTNAME_VAL} at ${REPORT_DATE} &nbsp;·&nbsp;
  VirusTotal API used: $([ -n "$VT_API_KEY" ] && echo "Yes" || echo "No (VT_API_KEY not set)")
</footer>

</body>
</html>
HTMLEOF

# ── POST report to dashboard ──────────────────────────────────────────────────
echo "[*] Uploading report to ${DASHBOARD_URL}/api/report/security ..." >&2
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time 30 \
    -X POST \
    -H "Content-Type: text/html" \
    -H "X-Hostname: ${HOSTNAME_VAL}" \
    --data-binary "@${REPORT_FILE}" \
    "${DASHBOARD_URL}/api/report/security")"

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "[+] Report uploaded successfully (HTTP ${HTTP_CODE})" >&2
else
    echo "[!] Upload failed with HTTP ${HTTP_CODE}" >&2
    exit 1
fi

echo "[+] Audit complete. Risk level: ${RISK_LEVEL}" >&2
