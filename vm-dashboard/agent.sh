#!/bin/bash
# VM Health Agent — collects system metrics and POSTs them to the dashboard server.
# Run on each VM: either manually or via cron every 30 seconds.
#
# Usage: ./agent.sh [SERVER_URL]
# Default server: http://localhost:5000/api/report

SERVER_URL="${1:-http://localhost:5000/api/report}"

# ── Collect hostname and IP ───────────────────────────────────────────────────
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')

# ── OS info ───────────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    OS_INFO=$(. /etc/os-release && echo "$PRETTY_NAME")
else
    OS_INFO=$(uname -s -r)
fi

# ── CPU usage (1-second sample via /proc/stat) ────────────────────────────────
read_cpu() {
    awk '/^cpu / {idle=$5; total=$2+$3+$4+$5+$6+$7+$8; print idle, total}' /proc/stat
}
read1=$(read_cpu); sleep 1; read2=$(read_cpu)
idle1=$(echo $read1 | cut -d' ' -f1); total1=$(echo $read1 | cut -d' ' -f2)
idle2=$(echo $read2 | cut -d' ' -f1); total2=$(echo $read2 | cut -d' ' -f2)
DIFF_IDLE=$((idle2 - idle1))
DIFF_TOTAL=$((total2 - total1))
if [ "$DIFF_TOTAL" -gt 0 ]; then
    CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", (1 - $DIFF_IDLE/$DIFF_TOTAL) * 100}")
else
    CPU_USAGE="0.0"
fi

# ── RAM usage ─────────────────────────────────────────────────────────────────
RAM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)   # kB
RAM_FREE=$(awk '/MemAvailable/ {print $2}' /proc/meminfo) # kB
RAM_USED=$((RAM_TOTAL - RAM_FREE))
RAM_TOTAL_MB=$((RAM_TOTAL / 1024))
RAM_USED_MB=$((RAM_USED / 1024))
RAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")

# ── Disk usage (root filesystem) ─────────────────────────────────────────────
DISK_INFO=$(df -BM / | awk 'NR==2 {gsub("M",""); print $3, $2, $5}')
DISK_USED=$(echo $DISK_INFO | cut -d' ' -f1)   # MB
DISK_TOTAL=$(echo $DISK_INFO | cut -d' ' -f2)  # MB
DISK_PCT=$(echo $DISK_INFO | cut -d' ' -f3 | tr -d '%')

# ── Uptime ────────────────────────────────────────────────────────────────────
UPTIME_SECS=$(awk '{print int($1)}' /proc/uptime)
UPTIME_DAYS=$((UPTIME_SECS / 86400))
UPTIME_HOURS=$(( (UPTIME_SECS % 86400) / 3600 ))
UPTIME_MINS=$(( (UPTIME_SECS % 3600) / 60 ))
UPTIME_STR="${UPTIME_DAYS}d ${UPTIME_HOURS}h ${UPTIME_MINS}m"

# ── Running services ──────────────────────────────────────────────────────────
SERVICES=()
for SVC in ssh sshd apache2 nginx cron; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        # Normalise sshd → ssh for display consistency
        DISPLAY_NAME="$SVC"
        [ "$SVC" = "sshd" ] && DISPLAY_NAME="ssh"
        SERVICES+=("\"$DISPLAY_NAME\"")
    fi
done
SERVICES_JSON="[$(IFS=,; echo "${SERVICES[*]}")]"

# ── Timestamp ────────────────────────────────────────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Build JSON payload ────────────────────────────────────────────────────────
PAYLOAD=$(cat <<EOF
{
  "hostname":    "$HOSTNAME",
  "ip":          "$IP",
  "os":          "$OS_INFO",
  "cpu_pct":     $CPU_USAGE,
  "ram_used_mb": $RAM_USED_MB,
  "ram_total_mb":$RAM_TOTAL_MB,
  "ram_pct":     $RAM_PCT,
  "disk_used_mb":$DISK_USED,
  "disk_total_mb":$DISK_TOTAL,
  "disk_pct":    $DISK_PCT,
  "uptime":      "$UPTIME_STR",
  "services":    $SERVICES_JSON,
  "timestamp":   "$TIMESTAMP"
}
EOF
)

# ── POST to server ────────────────────────────────────────────────────────────
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if [ "$RESPONSE" = "200" ]; then
    echo "[$(date +%T)] Reported metrics for $HOSTNAME → $SERVER_URL (HTTP $RESPONSE)"
else
    echo "[$(date +%T)] ERROR: Server returned HTTP $RESPONSE for $HOSTNAME" >&2
fi
