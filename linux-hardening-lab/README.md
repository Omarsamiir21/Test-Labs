# Linux Hardening Lab

## Scenario

You have inherited a Linux server that was set up in a hurry. The previous
administrator cut corners everywhere: weak passwords, insecure remote-access
services, and a switched-off firewall. Your job is to find and fix each
misconfiguration before an attacker does.

There are **5 issues** to correct. Run `validate.sh` at any time to see your
current score.

---

## Prerequisites

- A Debian/Ubuntu-based Linux system (VM recommended)
- Root or `sudo` access
- Basic familiarity with the terminal

---

## Getting Started

### 1. Set up the broken environment

```bash
sudo bash setup.sh
```

This script intentionally misconfigures the system. **Do not run it on a
production machine.**

### 2. Find and fix the 5 issues

Work through each task below. Use any tools available to you: man pages,
`systemctl`, `chmod`, `passwd`, etc.

### 3. Check your work

```bash
sudo bash validate.sh
```

Each check reports **PASS** or **FAIL** with a hint if something still needs
attention. Aim for 5/5.

### 4. Reset for the next learner

```bash
sudo bash reset.sh
```

---

## The 5 Tasks

### Task 1 — Change the weak password for `labuser`

The account `labuser` was created with the password `123456`, which appears in
every leaked-credential list on the internet. Change it to something strong.

**Hints:**
- `passwd labuser`
- A strong password uses 12+ characters and mixes letters, digits, and symbols.
- Even better: lock password auth entirely and require SSH keys.

---

### Task 2 — Disable SSH root login

The SSH daemon is configured to allow direct root login, meaning an attacker
who guesses or brute-forces the root password has full control immediately.

**Hints:**
- The SSH daemon config lives at `/etc/ssh/sshd_config`.
- Look for the `PermitRootLogin` directive.
- After editing, reload the daemon so the change takes effect.

---

### Task 3 — Fix permissions on `/etc/lab-secrets.txt`

A file containing credentials has been created world-readable and
world-writable (mode `777`). Any user — and any process running as any user —
can read or overwrite it.

**Hints:**
- `stat /etc/lab-secrets.txt` shows current permissions.
- `chmod` is the tool you need.
- Files containing secrets should typically be owned by root and readable only
  by root (`600`) or by a specific service account.

---

### Task 4 — Disable the telnet service

Telnet transmits everything — including passwords — in plain text. It was
superseded by SSH decades ago. The service should not be running.

**Hints:**
- `ss -tlnp` lists services listening on TCP ports. Port 23 is telnet.
- `systemctl` can disable socket-activated units.
- If the system uses `inetd`, check `/etc/inetd.conf`.

---

### Task 5 — Enable the UFW firewall

The firewall has been disabled, leaving all ports exposed. Enable it with a
safe default policy so only the traffic you explicitly allow can reach the
machine.

**Hints:**
- `ufw status` shows whether the firewall is active.
- Before enabling, make sure you allow SSH so you don't lock yourself out.
- `ufw enable` activates the firewall.

---

## Validating Your Work

```bash
sudo bash validate.sh
```

Example output when all tasks are complete:

```
=== Linux Hardening Lab — Validation ===

Check 1: Weak password for 'labuser'
  [PASS] labuser does not use password '123456'
Check 2: SSH PermitRootLogin
  [PASS] PermitRootLogin is not 'yes'
Check 3: /etc/lab-secrets.txt permissions
  [PASS] /etc/lab-secrets.txt is not world-readable/writable
Check 4: Telnet service
  [PASS] Telnet service is not running on port 23
Check 5: UFW firewall status
  [PASS] UFW firewall is active

─────────────────────────────────────
  Score: 5 / 5 checks passed
─────────────────────────────────────
  All checks passed — well done!
```

---

## File Layout

```
linux-hardening-lab/
├── README.md          ← You are here
├── setup.sh           ← Introduces the 5 misconfigurations
├── reset.sh           ← Restores the broken state for the next learner
├── validate.sh        ← Checks each issue and reports PASS/FAIL
└── solutions/
    └── solution-guide.md   ← Step-by-step fixes (read after attempting)
```

---

## Safety Note

Run this lab **only inside a dedicated VM or container** — never on a system
you care about. `setup.sh` deliberately weakens security in ways that are
dangerous on a real machine.
