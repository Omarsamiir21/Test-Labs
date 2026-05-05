# Test Labs - Technical Lab Portfolio

A collection of hands-on technical labs built to demonstrate skills in Linux administration, storage management, and infrastructure monitoring. Each lab simulates a real-world scenario using only standard tools available on a Debian/Ubuntu system — no cloud accounts or extra hardware required.

---

## Labs

### linux-hardening-lab

Deploys a misconfigured Linux system with 5 deliberate security issues. The learner identifies and fixes each one; an automated validation script checks their work and reports a score.

**Skills demonstrated:** Security auditing, SSH hardening, firewall configuration, file permissions, service management

**How to run:**
```bash
cd linux-hardening-lab
sudo bash setup.sh      # deploy the misconfigured environment
sudo bash validate.sh   # check progress (run anytime)
sudo bash reset.sh      # start over
```

> Use a dedicated VM. `setup.sh` intentionally misconfigures the system.

---

### disk-storage-lab

Simulates real-world storage problems using LVM and loop devices. The learner extends volumes, fixes a broken `fstab` entry, and formats and mounts an unformatted disk.

**Skills demonstrated:** LVM management (`pvcreate`, `vgextend`, `lvextend`), filesystem operations (`mkfs.ext4`, `resize2fs`), `fstab` configuration, `blkid`, mount management

**How to run:**
```bash
cd disk-storage-lab
sudo bash setup.sh      # create the broken storage environment
sudo bash validate.sh   # check progress (run anytime)
sudo bash reset.sh      # start over
```

---

### vm-dashboard

A live VM health monitoring dashboard. `agent.sh` runs on any Linux machine and reports CPU, RAM, disk usage, and service status to a central Flask server. Results are displayed in a dark-themed web UI that auto-refreshes.

**Skills demonstrated:** Bash scripting, Python/Flask web development, system metrics collection, HTTP API design, multi-host monitoring

**How to run:**
```bash
cd vm-dashboard

# Start the Flask server
pip install flask
python3 server.py

# On each machine to monitor (separate terminal or remote host)
bash agent.sh
```

Open `http://localhost:5000` in your browser to view the dashboard.

---

## Tools & Technologies

| Category | Technologies |
|----------|-------------|
| Scripting | Bash |
| Web / API | Python, Flask |
| Storage | LVM, loop devices, ext4 |
| Linux Admin | systemctl, ufw, sshd, fstab, file permissions |
| Version Control | Git |

---

## Requirements

A Debian/Ubuntu VM with:

```bash
sudo apt install lvm2 e2fsprogs ufw openssh-server python3-pip
```

Root or `sudo` access is required for all lab setup and validation scripts. It is recommended to run labs inside a VM snapshot so you can restore cleanly without reinstalling.
