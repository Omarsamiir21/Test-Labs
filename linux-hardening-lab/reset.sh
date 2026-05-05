#!/usr/bin/env bash
# reset.sh — Restores the misconfigured lab state for the next learner.
# Must be run as root: sudo bash reset.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: run this script as root (sudo bash reset.sh)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Linux Hardening Lab — Resetting to broken state ==="
echo "    This will re-introduce all 5 misconfigurations."
echo

read -rp "Are you sure you want to reset the lab? [y/N] " confirm
if [[ "${confirm,,}" != "y" ]]; then
  echo "Reset cancelled."
  exit 0
fi

bash "$SCRIPT_DIR/setup.sh"

echo
echo "=== Lab has been reset. Hand off to the next learner. ==="
