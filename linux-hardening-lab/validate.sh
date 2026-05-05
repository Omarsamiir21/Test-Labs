#!/usr/bin/env bash
# validate.sh — Checks each of the 5 hardening tasks and reports PASS/FAIL.
# Must be run as root: sudo bash validate.sh

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: run this script as root (sudo bash validate.sh)" >&2
  exit 1
fi

PASS=0
FAIL=0

# Prints a coloured result line and updates counters.
result() {
  local label="$1"
  local status="$2"   # "PASS" or "FAIL"
  local detail="$3"

  if [[ "$status" == "PASS" ]]; then
    printf "  [\e[32mPASS\e[0m] %s\n" "$label"
    (( PASS++ )) || true
  else
    printf "  [\e[31mFAIL\e[0m] %s\n        → %s\n" "$label" "$detail"
    (( FAIL++ )) || true
  fi
}

echo
echo "=== Linux Hardening Lab — Validation ==="
echo

# ── Check 1: labuser password strength ──────────────────────────────────────
echo "Check 1: Weak password for 'labuser'"

SHADOW_HASH=$(getent shadow labuser 2>/dev/null | cut -d: -f2)

if [[ -z "$SHADOW_HASH" || "$SHADOW_HASH" == "!" || "$SHADOW_HASH" == "*" ]]; then
  # Account locked or does not exist — cannot have weak password.
  result "labuser does not use password '123456'" "PASS" ""
else
  # Try to verify the known weak password against the stored hash.
  WEAK_MATCH=$(python3 -c "
import crypt, sys
stored = sys.argv[1]
# Extract the salt (everything up to the last \$)
parts = stored.split('\$')
if len(parts) >= 4:
    salt = '\$'.join(parts[:3]) + '\$'
else:
    salt = stored[:2]
computed = crypt.crypt('123456', salt)
print('yes' if computed == stored else 'no')
" "$SHADOW_HASH" 2>/dev/null || echo "unknown")

  if [[ "$WEAK_MATCH" == "yes" ]]; then
    result "labuser does not use password '123456'" "FAIL" \
      "Password is still '123456'. Change it with: passwd labuser"
  else
    result "labuser does not use password '123456'" "PASS" ""
  fi
fi

# ── Check 2: SSH root login disabled ────────────────────────────────────────
echo "Check 2: SSH PermitRootLogin"

SSHD_CONF="/etc/ssh/sshd_config"
# Grab the last effective PermitRootLogin line (later lines override earlier ones).
PERMIT=$(grep -i '^\s*PermitRootLogin' "$SSHD_CONF" 2>/dev/null | tail -1 | awk '{print tolower($2)}')

if [[ "$PERMIT" == "no" || "$PERMIT" == "prohibit-password" || "$PERMIT" == "forced-commands-only" ]]; then
  result "PermitRootLogin is not 'yes'" "PASS" ""
else
  result "PermitRootLogin is not 'yes'" "FAIL" \
    "Set 'PermitRootLogin no' in $SSHD_CONF, then reload SSH."
fi

# ── Check 3: /etc/lab-secrets.txt permissions ───────────────────────────────
echo "Check 3: /etc/lab-secrets.txt permissions"

SECRETS="/etc/lab-secrets.txt"
if [[ ! -f "$SECRETS" ]]; then
  # File removed entirely — that also counts as fixed.
  result "$SECRETS is not world-readable/writable" "PASS" ""
else
  PERMS=$(stat -c "%a" "$SECRETS")
  # Fail if world-readable (others read bit set).
  WORLD_BITS=$(( 10#$PERMS % 10 ))   # ones digit = other bits
  if (( WORLD_BITS == 0 )); then
    result "$SECRETS is not world-readable/writable" "PASS" ""
  else
    result "$SECRETS is not world-readable/writable" "FAIL" \
      "Current permissions: $PERMS. Run: chmod 600 $SECRETS"
  fi
fi

# ── Check 4: Telnet not running ──────────────────────────────────────────────
echo "Check 4: Telnet service"

TELNET_RUNNING=false

# Check systemd socket unit.
if systemctl is-active --quiet telnet.socket 2>/dev/null; then
  TELNET_RUNNING=true
fi

# Check if anything is listening on port 23.
if ss -tlnp 2>/dev/null | grep -q ':23\b'; then
  TELNET_RUNNING=true
fi

# Check inetd/xinetd for an active telnet entry.
if grep -qiE '^\s*telnet' /etc/inetd.conf 2>/dev/null; then
  TELNET_RUNNING=true
fi

if $TELNET_RUNNING; then
  result "Telnet service is not running on port 23" "FAIL" \
    "Disable telnet: systemctl disable --now telnet.socket  (or remove from inetd)"
else
  result "Telnet service is not running on port 23" "PASS" ""
fi

# ── Check 5: UFW firewall enabled ────────────────────────────────────────────
echo "Check 5: UFW firewall status"

UFW_STATUS=$(ufw status 2>/dev/null | head -1)
if echo "$UFW_STATUS" | grep -qi "Status: active"; then
  result "UFW firewall is active" "PASS" ""
else
  result "UFW firewall is active" "FAIL" \
    "Enable the firewall: ufw enable"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL ))
echo
echo "─────────────────────────────────────"
printf "  Score: %d / %d checks passed\n" "$PASS" "$TOTAL"
echo "─────────────────────────────────────"

if (( PASS == TOTAL )); then
  echo "  All checks passed — well done!"
else
  echo "  Keep going — review the FAIL items above."
fi
echo
