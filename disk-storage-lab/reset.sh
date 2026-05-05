#!/usr/bin/env bash
# reset.sh — Cleanly tears down the lab and re-runs setup.sh from scratch.
# Must be run as root: sudo bash reset.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="/var/lib/disk-storage-lab"
LAB_ENV="$LAB_DIR/lab.env"
VG_NAME="labvg"
MOUNT_POINT="/mnt/labdata"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root (sudo bash reset.sh)." >&2
    exit 1
fi

echo "==> Tearing down lab environment ..."

# ── Unmount filesystem ────────────────────────────────────────────────────────

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "    Unmounting $MOUNT_POINT ..."
    umount "$MOUNT_POINT" || umount -l "$MOUNT_POINT"
fi

# ── Deactivate and remove LVM objects ────────────────────────────────────────

if vgs "$VG_NAME" &>/dev/null; then
    echo "    Deactivating volume group '$VG_NAME' ..."
    vgchange -an "$VG_NAME" >/dev/null

    echo "    Removing volume group '$VG_NAME' (and its LVs/PVs) ..."
    vgremove -f "$VG_NAME" >/dev/null
fi

# ── Detach loop devices ───────────────────────────────────────────────────────

for IMG in "$LAB_DIR/disk1.img" "$LAB_DIR/disk2.img"; do
    if [[ -f "$IMG" ]]; then
        # Find every loop device backed by this image
        while IFS= read -r LOOP; do
            [[ -z "$LOOP" ]] && continue
            # Clear any remaining LVM metadata so losetup -d succeeds cleanly
            pvremove -ff -y "$LOOP" 2>/dev/null || true
            echo "    Detaching $LOOP ← $(basename "$IMG") ..."
            losetup -d "$LOOP" 2>/dev/null || true
        done < <(losetup -j "$IMG" 2>/dev/null | cut -d: -f1)
    fi
done

# ── Remove disk images and state file ────────────────────────────────────────

echo "    Removing disk images and state file ..."
rm -f "$LAB_DIR/disk1.img" "$LAB_DIR/disk2.img" "$LAB_ENV"

# ── Clean lab entries from /etc/fstab ────────────────────────────────────────

echo "    Cleaning /etc/fstab ..."
sed -i '/# BEGIN disk-storage-lab/,/# END disk-storage-lab/d' /etc/fstab

echo ""
echo "==> Teardown complete. Re-running setup.sh ..."
echo ""
exec bash "$SCRIPT_DIR/setup.sh"
