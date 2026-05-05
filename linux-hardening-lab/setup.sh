#!/usr/bin/env bash
# setup.sh — Introduces 5 deliberate misconfigurations for the hardening lab.
# Must be run as root: sudo bash setup.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: run this script as root (sudo bash setup.sh)" >&2
  exit 1
fi

echo "=== Linux Hardening Lab — Setting up misconfigured environment ==="
echo

# ── Issue 1: Weak password user ─────────────────────────────────────────────
echo "[1/5] Creating 'labuser' with password '123456'..."
if id labuser &>/dev/null; then
  echo "      labuser already exists — resetting password."
else
  useradd -m -s /bin/bash labuser
fi
echo "labuser:123456" | chpasswd
echo "      Done."

# ── Issue 2: SSH root login enabled ─────────────────────────────────────────
echo "[2/5] Enabling SSH root login..."
SSHD_CONF="/etc/ssh/sshd_config"

# Remove any existing PermitRootLogin lines, then append the insecure setting.
sed -i '/^\s*PermitRootLogin/d' "$SSHD_CONF"
echo "PermitRootLogin yes" >> "$SSHD_CONF"

# Reload SSH if it is running; ignore errors if the service is absent.
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo "      Done."

# ── Issue 3: World-writable secrets file ────────────────────────────────────
echo "[3/5] Creating /etc/lab-secrets.txt with permissions 777..."
cat > /etc/lab-secrets.txt <<'EOF'
# Lab Secrets File
DB_PASSWORD=SuperSecret123
API_KEY=sk-abc123xyz789
ADMIN_TOKEN=tok-letmein
EOF
chmod 777 /etc/lab-secrets.txt
echo "      Done."

# ── Issue 4: Telnet installed and running ────────────────────────────────────
echo "[4/5] Installing and enabling telnet..."
if command -v telnetd &>/dev/null || dpkg -l telnetd &>/dev/null 2>&1; then
  echo "      telnetd already installed."
else
  apt-get install -y telnetd 2>/dev/null || \
    apt-get install -y inetutils-telnetd 2>/dev/null || \
    echo "      Warning: could not install telnetd — package unavailable."
fi

# Enable via inetd / xinetd if present; also try the systemd socket unit.
if systemctl list-unit-files telnet.socket &>/dev/null 2>&1; then
  systemctl enable --now telnet.socket 2>/dev/null || true
fi
if command -v update-inetd &>/dev/null; then
  update-inetd --enable telnet 2>/dev/null || true
fi
echo "      Done."

# ── Issue 5: UFW firewall disabled ──────────────────────────────────────────
echo "[5/5] Disabling UFW firewall..."
if command -v ufw &>/dev/null; then
  ufw disable
else
  echo "      ufw not found — installing..."
  apt-get install -y ufw 2>/dev/null
  ufw disable
fi
echo "      Done."

echo
echo "=== Misconfigured environment is ready. ==="
echo "    Run validate.sh to check the current state of each issue."
