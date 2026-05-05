# Solution Guide

> **Try the tasks yourself before reading this.**  
> Run `sudo bash validate.sh` to check progress without spoilers.

---

## Finding Your Loop Devices

After running `setup.sh` you need to know which loop devices were created.  
The setup output tells you directly, but you can also query at any time:

```bash
sudo losetup -l
# or
sudo lsblk | grep loop
```

In all commands below, substitute your actual device names for `<LOOP1>` and `<LOOP2>`.

---

## Task 1 — Fix mount permissions on /mnt/labdata

**Problem:** `/mnt/labdata` was created with `chmod 700` (root-only).

**Check current state:**
```bash
ls -ld /mnt/labdata
# drwx------ 3 root root 1024 ...  ← only root can enter or write
```

**Fix:**
```bash
sudo chmod 777 /mnt/labdata
```

Alternatively, `1777` adds the sticky bit (prevents users deleting each other's files — good practice on shared directories):
```bash
sudo chmod 1777 /mnt/labdata
```

**Verify:**
```bash
ls -ld /mnt/labdata
# drwxrwxrwx  or  drwxrwxrwt  (sticky bit variant)
```

---

## Task 2 — Format the second loop device with ext4

**Problem:** `<LOOP2>` is a raw block device with no filesystem.

**Check current state:**
```bash
sudo blkid <LOOP2>
# (no output — no filesystem signature)

sudo file -s <LOOP2>
# /dev/loop9: data   ← just raw bytes
```

**Fix:**
```bash
sudo mkfs.ext4 <LOOP2>
```

**Verify:**
```bash
sudo blkid <LOOP2>
# /dev/loop9: UUID="..." TYPE="ext4"
```

---

## Task 3 — Add the second loop device to the volume group

**Problem:** `<LOOP2>` is formatted but not part of `labvg`.

**Check current state:**
```bash
sudo pvs
# Only <LOOP1> is listed

sudo vgdisplay labvg
# "Alloc PE / Size" equals total — no free space from disk2
```

**Fix — two commands:**

```bash
# Step 1: Initialise LOOP2 as an LVM physical volume
#   pvcreate will warn that ext4 data exists — answer 'y' to proceed
sudo pvcreate <LOOP2>

# Step 2: Add the new PV to the volume group
sudo vgextend labvg <LOOP2>
```

**Verify:**
```bash
sudo pvs
# Both <LOOP1> and <LOOP2> now appear under VG labvg

sudo vgs labvg
# VFree shows ~50 MiB of new free space
```

---

## Task 4 — Extend the logical volume and resize the filesystem

**Problem:** `labvg` now has free space but `/dev/labvg/lablv` is still 60 MiB.

**Check current state:**
```bash
sudo lvs /dev/labvg/lablv
# LSize shows 60.00m

df -h /mnt/labdata
# Size shows ~56 MiB
```

**Fix — two commands (order matters):**

```bash
# Step 1: Grow the logical volume to consume all free physical extents
sudo lvextend -l +100%FREE /dev/labvg/lablv

# Step 2: Grow the ext4 filesystem to fill the enlarged LV
#   resize2fs works on a live (mounted) ext4 filesystem
sudo resize2fs /dev/labvg/lablv
```

> **Why two steps?**  
> `lvextend` increases the block-device size at the LVM layer.  
> `resize2fs` tells the filesystem about the extra blocks.  
> Skipping step 2 leaves the filesystem unaware of the new space.

**Verify:**
```bash
sudo lvs /dev/labvg/lablv
# LSize now shows ~110 MiB (60 MB original + ~50 MB from disk2)

df -h /mnt/labdata
# Size reflects the new, larger filesystem
```

---

## Task 5 — Fix the broken fstab entry

**Problem:** `/etc/fstab` contains a placeholder UUID that does not match any real device.

**Check current state:**
```bash
grep -A1 'disk-storage-lab' /etc/fstab
# UUID=00000000-0000-0000-0000-000000000000  /mnt/labdata  ext4  defaults  0  2
```

**Step 1 — Get the real UUID:**
```bash
sudo blkid -o value -s UUID /dev/labvg/lablv
# Example output: a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

**Step 2 — Edit fstab:**
```bash
sudo nano /etc/fstab
```

Find the line with `00000000-0000-0000-0000-000000000000` and replace the UUID with the value from step 1. The corrected line should look like:

```
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /mnt/labdata  ext4  defaults  0  2
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).

**Step 3 — Test without rebooting:**
```bash
sudo mount -a
# No output = success.  An error means the UUID or path is still wrong.
```

**Verify:**
```bash
grep labdata /etc/fstab
# Should show the real UUID, not 00000000-...
```

---

## One-Shot: All Five Fixes

```bash
# Task 1
sudo chmod 777 /mnt/labdata

# Task 2
sudo mkfs.ext4 <LOOP2>

# Task 3
sudo pvcreate <LOOP2>
sudo vgextend labvg <LOOP2>

# Task 4
sudo lvextend -l +100%FREE /dev/labvg/lablv
sudo resize2fs /dev/labvg/lablv

# Task 5 — get UUID first, then edit fstab
REAL_UUID=$(sudo blkid -o value -s UUID /dev/labvg/lablv)
sudo sed -i "s/00000000-0000-0000-0000-000000000000/$REAL_UUID/" /etc/fstab
sudo mount -a
```

Then run `sudo bash validate.sh` — all five tasks should show `[PASS]`.

---

## Key Concepts Covered

| Concept | Commands used |
|---------|--------------|
| Loop devices (virtual block devices) | `losetup` |
| Filesystem creation | `mkfs.ext4` |
| LVM physical volumes | `pvcreate`, `pvs` |
| LVM volume groups | `vgcreate`, `vgextend`, `vgs` |
| LVM logical volumes | `lvcreate`, `lvextend`, `lvs` |
| Online filesystem resize | `resize2fs` |
| Persistent mounts | `/etc/fstab`, `blkid`, `mount -a` |
| File permissions | `chmod`, `ls -ld`, `stat` |
