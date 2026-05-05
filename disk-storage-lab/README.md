# Linux Disk & Storage Lab

A hands-on lab that simulates real-world Linux storage problems using **loop devices** — no spare partitions or physical disks required.

---

## Scenario

You have been handed a Linux server by a departing sysadmin. They partially set up a data volume using LVM but left things in a broken state:

- A shared directory is mounted but **nobody except root can write to it**.
- A second raw disk is attached but **was never formatted or added to the volume group**.
- The volume group has room to grow, but the **logical volume was never extended**.
- There is an `/etc/fstab` entry for the mount, but it contains a **wrong UUID** and would fail on reboot.

Your job is to fix all five problems.

---

## Requirements

| Package | Purpose |
|---------|---------|
| `lvm2` | LVM tools (`pvcreate`, `vgcreate`, `lvcreate`, …) |
| `e2fsprogs` | `mkfs.ext4`, `resize2fs`, `tune2fs` |
| `util-linux` | `losetup`, `blkid`, `mount` |

Install on Debian/Ubuntu: `sudo apt install lvm2 e2fsprogs`

---

## Quick Start

```bash
# 1. Create the broken environment (requires root)
sudo bash setup.sh

# 2. Work through the five tasks described below

# 3. Validate your progress at any time
sudo bash validate.sh

# 4. Reset to a clean broken state if you want to start over
sudo bash reset.sh
```

---

## Your Five Tasks

After running `setup.sh`, the terminal output shows the exact loop device names (e.g. `/dev/loop8`, `/dev/loop9`). Use those values wherever you see `<LOOP2>` below.

### Task 1 — Fix mount permissions

The directory `/mnt/labdata` is mounted but only root can write to it.  
**Goal:** make it writable by all users.

Hints:
- `ls -ld /mnt/labdata` — check current permissions
- `chmod` changes file/directory permissions

---

### Task 2 — Format the second loop device

The second loop device (`<LOOP2>`) is raw and unformatted.  
**Goal:** create an ext4 filesystem on it.

Hints:
- `sudo blkid <LOOP2>` — check current filesystem type
- `mkfs.ext4` creates an ext4 filesystem on a block device

---

### Task 3 — Add the second loop device to the volume group

The volume group `labvg` only contains the first disk.  
**Goal:** add `<LOOP2>` as a new physical volume and extend the volume group.

Hints:
- `sudo pvs` / `sudo vgs` — list current PVs and VGs
- `pvcreate` initialises a block device as an LVM physical volume
- `vgextend` adds a physical volume to an existing volume group

---

### Task 4 — Extend the logical volume and resize the filesystem

After adding the new PV the volume group has free space, but the logical volume and filesystem are still the original size.  
**Goal:** extend the logical volume to use all available free space, then grow the filesystem to match.

Hints:
- `sudo lvdisplay` / `sudo lvs` — show LV details and current size
- `lvextend -l +100%FREE /dev/labvg/lablv` — extend to use all free PE
- `resize2fs /dev/labvg/lablv` — grow an ext4 filesystem to fill its LV
- *Order matters:* extend the LV first, resize the filesystem second.

---

### Task 5 — Fix the broken fstab entry

`/etc/fstab` contains a placeholder UUID `00000000-0000-0000-0000-000000000000` that would prevent the system from mounting the volume at boot.  
**Goal:** replace it with the real UUID of `/dev/labvg/lablv`.

Hints:
- `sudo blkid /dev/labvg/lablv` — retrieve the actual UUID
- Edit `/etc/fstab` with `sudo nano /etc/fstab` (or any editor)
- `sudo mount -a` — test that fstab is valid (should produce no errors)

---

## Checking Your Work

```bash
sudo bash validate.sh
```

Each task prints `[PASS]` or `[FAIL]` with a short hint. A final score is shown at the end.

---

## Files

```
disk-storage-lab/
├── README.md           ← this file
├── setup.sh            ← creates the broken environment
├── validate.sh         ← checks all five tasks
├── reset.sh            ← tears down and recreates the lab
└── solutions/
    └── solution-guide.md   ← full solution (try before peeking!)
```

Lab state is stored in `/var/lib/disk-storage-lab/` (disk images + state file).

---

## Tips

- All lab scripts require root. Prefix with `sudo bash` or run in a root shell.
- `sudo lsblk` and `sudo lvs` are your friends for orientation.
- If a command asks *"Really INITIALIZE? [y/n]"* answer `y`.
- When you are completely stuck, the `solutions/solution-guide.md` has every command.
