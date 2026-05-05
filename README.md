# test-Labs

A collection of self-contained, hands-on Linux labs that simulate real-world sysadmin and security problems. Each lab uses only what is already on a standard Debian/Ubuntu VM — no extra hardware or cloud accounts required.

---

## Labs

| Lab | Topic | Tasks | Requires |
|-----|-------|-------|---------|
| [linux-hardening-lab](./linux-hardening-lab/) | Security hardening | 5 | sudo, ufw, openssh |
| [disk-storage-lab](./disk-storage-lab/) | LVM & disk management | 5 | sudo, lvm2, e2fsprogs |

---

## How Every Lab Works

Each lab follows the same three-script pattern:

```
<lab-name>/
├── README.md           ← scenario description and task list
├── setup.sh            ← creates the broken/incomplete environment
├── validate.sh         ← checks each task, prints PASS/FAIL + score
├── reset.sh            ← tears down and recreates the environment
└── solutions/
    └── solution-guide.md   ← full walkthrough (try first!)
```

```bash
# 1. Read the lab README to understand the scenario
# 2. Break the environment
sudo bash setup.sh

# 3. Work through the tasks
# 4. Check your progress at any time
sudo bash validate.sh

# 5. Reset if you want to start over
sudo bash reset.sh
```

> All setup/validate/reset scripts require root. Run them with `sudo bash <script>` or from a root shell. **Use a dedicated VM — setup scripts intentionally misconfigure the system.**

---

## Lab Summaries

### linux-hardening-lab

You inherit a server left in a dangerously insecure state. Five misconfigurations need to be found and fixed before an attacker exploits them.

| # | Problem |
|---|---------|
| 1 | Weak password (`123456`) on a user account |
| 2 | SSH configured to allow direct root login |
| 3 | A secrets file left world-readable and world-writable |
| 4 | Telnet service running and exposing plaintext credentials |
| 5 | UFW firewall disabled |

**Skills practiced:** `passwd`, `sshd_config`, `chmod`, `systemctl`, `ufw`

---

### disk-storage-lab

You take over a server where a storage volume was partially configured with LVM and left broken. Five storage problems need to be resolved.

| # | Problem |
|---|---------|
| 1 | Mount point permissions set to root-only (`700`) |
| 2 | Second disk attached but never formatted |
| 3 | Volume group not extended with the new disk |
| 4 | Logical volume and filesystem never grown to use the extra space |
| 5 | `/etc/fstab` entry has a wrong UUID that would break on reboot |

**Skills practiced:** `chmod`, `mkfs.ext4`, `pvcreate`, `vgextend`, `lvextend`, `resize2fs`, `blkid`, `/etc/fstab`

---

## Requirements

A Debian/Ubuntu VM with:

```bash
sudo apt install lvm2 e2fsprogs ufw openssh-server
```

Root or `sudo` access is required for all lab scripts.

---

## Recommended Setup

- **VirtualBox / VMware / QEMU** with a fresh Debian or Ubuntu install
- At least **1 GB RAM** and **5 GB disk** (labs use sparse loop-device images, not real partitions)
- Take a VM snapshot before running `setup.sh` so you can restore without reinstalling
