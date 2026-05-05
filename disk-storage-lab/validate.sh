#!/usr/bin/env bash
# validate.sh — Checks each lab task and prints PASS / FAIL with a final score.
# Must be run as root: sudo bash validate.sh

LAB_DIR="/var/lib/disk-storage-lab"
LAB_ENV="$LAB_DIR/lab.env"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root (sudo bash validate.sh)." >&2
    exit 1
fi

if [[ ! -f "$LAB_ENV" ]]; then
    echo "ERROR: Lab state file not found. Run setup.sh first." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$LAB_ENV"

PASS=0
FAIL=0

_pass() { echo "  [PASS] $1"; (( PASS++ )); }
_fail() { echo "  [FAIL] $1"; (( FAIL++ )); }

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║       Disk & Storage Lab — Validation            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Task 1: Fix mount permissions ────────────────────────────────────────────

echo "[ Task 1 ] Fix permissions on $MOUNT_POINT so all users can write"

if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    _fail "$MOUNT_POINT is not currently mounted"
else
    PERMS=$(stat -c "%a" "$MOUNT_POINT" 2>/dev/null)
    # Test the 'write' bit for 'others' (octal bit 002)
    if (( (8#$PERMS & 8#002) != 0 )); then
        _pass "$MOUNT_POINT is world-writable (mode $PERMS)"
    else
        _fail "$MOUNT_POINT is not world-writable (mode $PERMS). Hint: chmod 777 $MOUNT_POINT"
    fi
fi
echo ""

# ── Task 2: Format LOOP2 with ext4 ───────────────────────────────────────────

echo "[ Task 2 ] Format $LOOP2 with ext4"

if [[ ! -b "$LOOP2" ]]; then
    _fail "$LOOP2 is not attached. Is disk2 still present?"
else
    FS_TYPE=$(blkid -o value -s TYPE "$LOOP2" 2>/dev/null || true)
    if [[ "$FS_TYPE" == "ext4" ]]; then
        _pass "$LOOP2 is formatted as ext4"
    elif [[ "$FS_TYPE" == "LVM2_member" ]]; then
        # pvcreate overwrites the ext4 superblock — treat as OK if in LVM (Task 3 implicitly proves Task 2 was done)
        _pass "$LOOP2 was formatted as ext4 and has since been added to LVM (see Task 3)"
    else
        TYPE_MSG="${FS_TYPE:-none}"
        _fail "$LOOP2 has filesystem type '$TYPE_MSG'. Hint: mkfs.ext4 $LOOP2"
    fi
fi
echo ""

# ── Task 3: Add LOOP2 to the volume group ────────────────────────────────────

echo "[ Task 3 ] Add $LOOP2 to volume group '$VG_NAME'"

if [[ ! -b "$LOOP2" ]]; then
    _fail "$LOOP2 is not attached"
else
    PV_VG=$(pvs --noheadings -o vg_name "$LOOP2" 2>/dev/null | tr -d ' ' || true)
    if [[ "$PV_VG" == "$VG_NAME" ]]; then
        _pass "$LOOP2 is a physical volume in VG '$VG_NAME'"
    elif [[ -n "$PV_VG" ]]; then
        _fail "$LOOP2 is a PV but belongs to VG '$PV_VG', not '$VG_NAME'"
    else
        _fail "$LOOP2 is not a physical volume in any VG. Hint: pvcreate $LOOP2 && vgextend $VG_NAME $LOOP2"
    fi
fi
echo ""

# ── Task 4: Extend the LV and resize the filesystem ──────────────────────────

echo "[ Task 4 ] Extend /dev/$VG_NAME/$LV_NAME and resize the filesystem"

LV_PATH="/dev/$VG_NAME/$LV_NAME"

if ! lvs "$LV_PATH" &>/dev/null; then
    _fail "Logical volume $LV_PATH not found"
else
    LV_SIZE_MB=$(lvs --noheadings --units m --nosuffix -o lv_size "$LV_PATH" 2>/dev/null \
                 | tr -d ' ' | cut -d. -f1)

    if [[ -z "$LV_SIZE_MB" ]]; then
        _fail "Could not read LV size for $LV_PATH"
    elif (( LV_SIZE_MB <= INITIAL_LV_SIZE_MB )); then
        _fail "LV is still ${LV_SIZE_MB} MiB (initial: ${INITIAL_LV_SIZE_MB} MiB). Hint: lvextend -l +100%FREE $LV_PATH"
    else
        # LV is larger — now confirm the filesystem was also resized
        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            FS_SIZE_MB=$(df -m "$MOUNT_POINT" 2>/dev/null | awk 'NR==2{print $2}')
        else
            # Fallback: read block count from superblock when not mounted
            FB=$(tune2fs -l "$LV_PATH" 2>/dev/null | awk '/^Block count:/{print $3}')
            BS=$(tune2fs -l "$LV_PATH" 2>/dev/null | awk '/^Block size:/{print $3}')
            FS_SIZE_MB=$(( FB * BS / 1024 / 1024 ))
        fi

        if (( FS_SIZE_MB > INITIAL_LV_SIZE_MB )); then
            _pass "LV extended to ${LV_SIZE_MB} MiB; filesystem resized to ~${FS_SIZE_MB} MiB"
        else
            _fail "LV is ${LV_SIZE_MB} MiB but filesystem is still ~${FS_SIZE_MB} MiB. Hint: resize2fs $LV_PATH"
        fi
    fi
fi
echo ""

# ── Task 5: Fix the broken fstab entry ───────────────────────────────────────

echo "[ Task 5 ] Fix the broken UUID in /etc/fstab"

CORRECT_UUID=$(blkid -o value -s UUID "/dev/$VG_NAME/$LV_NAME" 2>/dev/null || true)

if [[ -z "$CORRECT_UUID" ]]; then
    _fail "Could not determine UUID of /dev/$VG_NAME/$LV_NAME (is the LV active?)"
elif grep -q "UUID=$CORRECT_UUID" /etc/fstab; then
    _pass "/etc/fstab contains the correct UUID ($CORRECT_UUID)"
elif grep -q "00000000-0000-0000-0000-000000000000" /etc/fstab; then
    _fail "/etc/fstab still has the placeholder UUID. Correct UUID is: $CORRECT_UUID"
else
    _fail "/etc/fstab does not contain UUID=$CORRECT_UUID. Correct UUID is: $CORRECT_UUID"
fi
echo ""

# ── Final score ───────────────────────────────────────────────────────────────

TOTAL=$(( PASS + FAIL ))
echo "──────────────────────────────────────────────────"
echo "  Score: $PASS / $TOTAL tasks passed"
if (( PASS == TOTAL )); then
    echo "  All tasks complete — excellent work!"
fi
echo "──────────────────────────────────────────────────"
echo ""
