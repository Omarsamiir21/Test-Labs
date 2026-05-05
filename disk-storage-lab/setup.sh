#!/usr/bin/env bash
# setup.sh — Creates the broken/incomplete disk and storage lab environment.
# Must be run as root: sudo bash setup.sh

set -e

LAB_DIR="/var/lib/disk-storage-lab"
DISK1_IMG="$LAB_DIR/disk1.img"
DISK2_IMG="$LAB_DIR/disk2.img"
LAB_ENV="$LAB_DIR/lab.env"
VG_NAME="labvg"
LV_NAME="lablv"
MOUNT_POINT="/mnt/labdata"
INITIAL_LV_SIZE_MB=60

# ── Preflight ────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root (sudo bash setup.sh)." >&2
    exit 1
fi

for cmd in dd losetup pvcreate vgcreate lvcreate mkfs.ext4 mount blkid; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: '$cmd' not found. Install lvm2 and e2fsprogs."; exit 1; }
done

# ── Lab directory ─────────────────────────────────────────────────────────────

echo "==> Creating lab state directory: $LAB_DIR"
mkdir -p "$LAB_DIR"

# ── Disk 1: 100 MB image — will host the LVM volume group ────────────────────

echo "==> Creating 100 MB disk image (disk1) ..."
dd if=/dev/zero of="$DISK1_IMG" bs=1M count=100 status=none
echo "    disk1.img created (100 MB)"

echo "==> Attaching disk1 as a loop device ..."
LOOP1=$(losetup -f --show "$DISK1_IMG")
echo "    disk1 → $LOOP1"

# ── LVM setup on LOOP1 ───────────────────────────────────────────────────────

echo "==> Initialising LVM physical volume on $LOOP1 ..."
pvcreate -ff -y "$LOOP1" >/dev/null

echo "==> Creating volume group '$VG_NAME' ..."
vgcreate "$VG_NAME" "$LOOP1" >/dev/null

echo "==> Creating logical volume '$LV_NAME' (${INITIAL_LV_SIZE_MB} MiB) ..."
lvcreate -L "${INITIAL_LV_SIZE_MB}M" -n "$LV_NAME" "$VG_NAME" >/dev/null

echo "==> Formatting /dev/$VG_NAME/$LV_NAME with ext4 ..."
mkfs.ext4 -F -q "/dev/$VG_NAME/$LV_NAME"

# ── Mount with deliberately wrong permissions ─────────────────────────────────

echo "==> Mounting /dev/$VG_NAME/$LV_NAME at $MOUNT_POINT ..."
mkdir -p "$MOUNT_POINT"
mount "/dev/$VG_NAME/$LV_NAME" "$MOUNT_POINT"

# Intentional mistake: root-only, no write access for other users
echo "==> Setting intentionally restrictive permissions (root-only) ..."
chmod 700 "$MOUNT_POINT"
chown root:root "$MOUNT_POINT"

# ── Disk 2: 50 MB image — unformatted, unattached to LVM ─────────────────────

echo "==> Creating 50 MB disk image (disk2) ..."
dd if=/dev/zero of="$DISK2_IMG" bs=1M count=50 status=none
echo "    disk2.img created (50 MB)"

echo "==> Attaching disk2 as a loop device (raw, unformatted) ..."
LOOP2=$(losetup -f --show "$DISK2_IMG")
echo "    disk2 → $LOOP2"

# ── Broken fstab entry ────────────────────────────────────────────────────────

echo "==> Injecting a broken /etc/fstab entry ..."
# Remove any previous lab entries to stay idempotent
sed -i '/# BEGIN disk-storage-lab/,/# END disk-storage-lab/d' /etc/fstab

cat >> /etc/fstab <<EOF

# BEGIN disk-storage-lab
# TASK 5: The UUID below is wrong — fix it with the real UUID of /dev/$VG_NAME/$LV_NAME
UUID=00000000-0000-0000-0000-000000000000  $MOUNT_POINT  ext4  defaults  0  2
# END disk-storage-lab
EOF

# ── Persist lab state for validate.sh / reset.sh ─────────────────────────────

cat > "$LAB_ENV" <<EOF
LOOP1=$LOOP1
LOOP2=$LOOP2
VG_NAME=$VG_NAME
LV_NAME=$LV_NAME
MOUNT_POINT=$MOUNT_POINT
DISK1_IMG=$DISK1_IMG
DISK2_IMG=$DISK2_IMG
INITIAL_LV_SIZE_MB=$INITIAL_LV_SIZE_MB
EOF

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║       Disk & Storage Lab — Environment Ready     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Loop devices:"
echo "    $LOOP1  ← disk1 (100 MB) — LVM PV, VG=$VG_NAME"
echo "    $LOOP2  ← disk2 ( 50 MB) — unformatted, not in LVM"
echo ""
echo "  LVM:"
echo "    VG  : $VG_NAME"
echo "    LV  : /dev/$VG_NAME/$LV_NAME  (${INITIAL_LV_SIZE_MB} MiB)"
echo "    Mounted at $MOUNT_POINT  (permissions intentionally broken)"
echo ""
echo "  Your 5 tasks:"
echo "    1. Fix permissions on $MOUNT_POINT so all users can write to it"
echo "    2. Format $LOOP2 with ext4"
echo "    3. Add $LOOP2 to volume group '$VG_NAME'"
echo "    4. Extend the logical volume and resize the filesystem"
echo "    5. Fix the broken UUID in /etc/fstab"
echo ""
echo "  Check progress : sudo bash validate.sh"
echo "  Reset lab      : sudo bash reset.sh"
echo ""
