# Solution Guide

Work through the lab on your own before reading this. Each fix below is
explained with the command, the reasoning behind it, and what to verify
afterwards.

---

## Issue 1 — Weak password for `labuser`

### What was wrong

`labuser` was created with the password `123456`. This appears in every
standard wordlist and would be cracked instantly by any brute-force tool.

### Fix

```bash
sudo passwd labuser
```

Enter a strong password when prompted (12+ characters, mixed case, digits,
symbols). The validator checks that the stored hash no longer matches `123456`.

### Going further

Password auth on service accounts is better replaced with SSH key auth
entirely. Lock the password and add an authorized key instead:

```bash
sudo passwd -l labuser                         # lock password login
sudo mkdir -p /home/labuser/.ssh
sudo chmod 700 /home/labuser/.ssh
# paste the user's public key:
sudo tee /home/labuser/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAA... user@host
EOF
sudo chmod 600 /home/labuser/.ssh/authorized_keys
sudo chown -R labuser:labuser /home/labuser/.ssh
```

---

## Issue 2 — SSH root login enabled

### What was wrong

`PermitRootLogin yes` in `/etc/ssh/sshd_config` allows an attacker to
authenticate directly as root over SSH. A successful brute-force or
credential-stuffing attempt immediately yields full system control with no
intermediate step.

### Fix

Open `/etc/ssh/sshd_config` in a text editor:

```bash
sudo nano /etc/ssh/sshd_config
```

Find the line:

```
PermitRootLogin yes
```

Change it to:

```
PermitRootLogin no
```

Save the file, then reload the SSH daemon to apply the change:

```bash
sudo systemctl reload ssh       # Debian/Ubuntu
# or
sudo systemctl reload sshd      # RHEL/Fedora
```

### Verify

```bash
sudo sshd -T | grep permitrootlogin
```

Should output `permitrootlogin no`.

### Going further

`PermitRootLogin prohibit-password` is a middle ground: root can log in with
an SSH key but not a password. The strictest option is `no` — require admins
to log in as a normal user and then `sudo`.

---

## Issue 3 — World-writable secrets file

### What was wrong

`/etc/lab-secrets.txt` had permissions `777`, meaning every user on the system
— and every process running as any user — could read credentials or overwrite
the file with malicious content.

### Fix

```bash
sudo chmod 600 /etc/lab-secrets.txt
sudo chown root:root /etc/lab-secrets.txt
```

`600` means: owner (root) can read and write; group and others have no access.

### Verify

```bash
stat /etc/lab-secrets.txt
```

Look for `Access: (0600/-rw-------)`.

### Going further

- Secrets should ideally not live in plain-text flat files at all. Use a
  secrets manager (HashiCorp Vault, AWS Secrets Manager, `pass`, etc.).
- Audit for other over-permissioned sensitive files:
  ```bash
  find /etc -maxdepth 1 -type f -perm /o+r 2>/dev/null
  ```

---

## Issue 4 — Telnet service running

### What was wrong

Telnet transmits all data — including usernames and passwords — as plain text.
Anyone with access to the network path between client and server can capture
credentials with a packet sniffer. SSH replaced telnet in the late 1990s and
telnet should never run on a modern system.

### Fix — systemd socket unit (most common on modern systems)

```bash
sudo systemctl disable --now telnet.socket
```

### Fix — inetd / xinetd

If the system uses `inetd`, comment out the telnet line in `/etc/inetd.conf`:

```bash
sudo sed -i '/^\s*telnet/s/^/#/' /etc/inetd.conf
sudo systemctl restart inetd
```

If `xinetd` is in use, disable the service file:

```bash
sudo systemctl disable --now xinetd
# or edit /etc/xinetd.d/telnet and set: disable = yes
```

### Optionally remove the package

```bash
sudo apt-get purge telnetd inetutils-telnetd 2>/dev/null || true
```

### Verify

```bash
ss -tlnp | grep ':23'
```

Should return no output.

---

## Issue 5 — UFW firewall disabled

### What was wrong

`ufw disable` turned off all firewall filtering. Every port on the machine was
reachable from the network with no restriction, regardless of whether a
service should be publicly accessible.

### Fix

First, make sure the SSH rule exists so you don't lock yourself out:

```bash
sudo ufw allow OpenSSH
```

Then enable the firewall:

```bash
sudo ufw enable
```

Confirm with:

```bash
sudo ufw status verbose
```

### Recommended baseline ruleset

```bash
sudo ufw default deny incoming    # block all inbound by default
sudo ufw default allow outgoing   # allow all outbound by default
sudo ufw allow OpenSSH            # allow SSH (adjust port if non-standard)
sudo ufw enable
```

Add further `allow` rules only for services that should be reachable from the
network (e.g., `sudo ufw allow 80/tcp` for a web server).

### Going further

- `ufw logging on` enables firewall logging to `/var/log/ufw.log`.
- For a finer-grained policy, restrict SSH to specific source IPs:
  ```bash
  sudo ufw allow from 192.168.1.0/24 to any port 22
  ```

---

## Summary Table

| # | Issue | Quick Fix |
|---|-------|-----------|
| 1 | Weak password | `sudo passwd labuser` |
| 2 | SSH root login | Set `PermitRootLogin no` in `sshd_config`, reload sshd |
| 3 | World-writable secrets file | `sudo chmod 600 /etc/lab-secrets.txt` |
| 4 | Telnet running | `sudo systemctl disable --now telnet.socket` |
| 5 | Firewall disabled | `sudo ufw allow OpenSSH && sudo ufw enable` |

Run `sudo bash validate.sh` to confirm all 5 checks pass.
