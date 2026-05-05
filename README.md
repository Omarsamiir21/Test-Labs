# VM Health Dashboard

A lightweight real-time dashboard for monitoring multiple Linux VMs.
The server runs on your WSL instance; a small bash agent runs on each VM.

---

## Architecture

```
VM 1 ──agent.sh──┐
VM 2 ──agent.sh──┤──POST /api/report──► server.py (Flask, WSL)
VM 3 ──agent.sh──┘                            │
                                        data/HOSTNAME.json
                                              │
                                    Browser ◄─┘ GET /dashboard
```

---

## 1. Start the server (on WSL)

### Install dependencies

```bash
pip install flask
```

### Run the server

```bash
cd ~/vm-dashboard
python server.py
```

The server listens on **all interfaces** (`0.0.0.0:5000`).
Open the dashboard in your browser: **http://localhost:5000/dashboard**

To keep the server running after you close the terminal, use `nohup`:

```bash
nohup python server.py &> server.log &
```

---

## 2. Find your WSL IP address

From inside WSL:

```bash
hostname -I | awk '{print $1}'
```

From Windows (PowerShell):

```powershell
wsl hostname -I
```

The IP usually looks like `172.x.x.x`. Note it — you'll need it for the agents.

> **Tip:** WSL's IP changes on reboot. For a stable address, configure a static IP
> in `/etc/wsl.conf` or use Windows' `wsl --set-default-version` features.

---

## 3. Run agent.sh on a VM

### Copy the agent to the target VM

```bash
scp ~/vm-dashboard/agent.sh user@VM_IP:/opt/agent.sh
```

Or paste the contents manually and save as `/opt/agent.sh`.

### Make it executable

```bash
chmod +x /opt/agent.sh
```

### Test it manually

Replace `WSL_IP` with the IP from step 2:

```bash
/opt/agent.sh http://WSL_IP:5000/api/report
```

You should see output like:
```
[14:32:01] Reported metrics for webserver-01 → http://172.18.0.1:5000/api/report (HTTP 200)
```
And a new card should appear on the dashboard within seconds.

### Run automatically every 30 seconds (cron)

```bash
crontab -e
```

Add this line (replace `WSL_IP`):

```cron
* * * * * /opt/agent.sh http://WSL_IP:5000/api/report >> /var/log/vm-agent.log 2>&1
* * * * * sleep 30 && /opt/agent.sh http://WSL_IP:5000/api/report >> /var/log/vm-agent.log 2>&1
```

The two cron lines together fire the script at 0s and 30s of every minute,
giving a ~30-second reporting interval.

---

## API reference

| Endpoint         | Method | Description                          |
|------------------|--------|--------------------------------------|
| `/dashboard`     | GET    | Serves the HTML dashboard            |
| `/`              | GET    | Alias for `/dashboard`               |
| `/api/report`    | POST   | Accepts JSON metric payload from agent |
| `/api/vms`       | GET    | Returns all VM data + online summary |

### POST /api/report payload example

```json
{
  "hostname":      "webserver-01",
  "ip":            "10.0.0.5",
  "os":            "Ubuntu 22.04.3 LTS",
  "cpu_pct":       23.4,
  "ram_used_mb":   1024,
  "ram_total_mb":  4096,
  "ram_pct":       25.0,
  "disk_used_mb":  8192,
  "disk_total_mb": 51200,
  "disk_pct":      16,
  "uptime":        "3d 4h 12m",
  "services":      ["ssh", "nginx", "cron"],
  "timestamp":     "2025-01-15T14:32:00Z"
}
```

---

## Offline detection

A VM is marked **offline** if its last report was more than **60 seconds** ago.
Its card turns dim and shows an orange "offline" badge.
Data is preserved until the file is deleted from `data/`.

---

## File layout

```
vm-dashboard/
├── server.py       # Flask API + dashboard route
├── dashboard.html  # Dark-theme live UI
├── agent.sh        # Metric collector (runs on each VM)
├── data/           # Per-VM JSON files (auto-created by server)
└── README.md       # This file
```
