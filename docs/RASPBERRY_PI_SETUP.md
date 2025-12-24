# FlowForge Raspberry Pi Setup Guide

This guide walks you through setting up FlowForge on a Raspberry Pi from scratch. No prior Pi experience required!

## What You'll Get

After this setup:
- FlowForge server running 24/7 on your Pi
- Access from anywhere via Tailscale (secure VPN)
- Claude Code on iPhone can call FlowForge tools natively
- Web UI accessible from any browser
- Worktrees created on your Mac remotely

```
┌──────────────────────────────────────────────────────────────┐
│                    Your Network                               │
│                                                               │
│  ┌─────────────┐     Tailscale      ┌─────────────┐          │
│  │ Raspberry Pi│◄──────────────────►│    Mac      │          │
│  │ FlowForge   │                    │ (worktrees) │          │
│  │ Server:8081 │                    │             │          │
│  └─────────────┘                    └─────────────┘          │
│         ▲                                                     │
│         │ Tailscale                                          │
│         ▼                                                     │
│  ┌─────────────┐                                             │
│  │   iPhone    │                                             │
│  │ Claude Code │                                             │
│  └─────────────┘                                             │
└──────────────────────────────────────────────────────────────┘
```

---

## Part 1: Initial Pi Setup

### 1.1 Flash the SD Card

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on your Mac
2. Insert your SD card
3. Open Raspberry Pi Imager and click "Choose OS"
4. Select **Raspberry Pi OS (64-bit)** - the full desktop version is fine
5. Click "Choose Storage" and select your SD card
6. **Important**: Click the gear icon (⚙️) to configure:
   - Set hostname: `flowforge-pi` (or whatever you want)
   - Enable SSH: Yes, use password authentication
   - Set username: `pi` (or your preference)
   - Set password: (something secure!)
   - Configure WiFi: Enter your network name and password
   - Set locale/timezone
7. Click "Write" and wait for it to finish

### 1.2 First Boot

1. Insert SD card into Pi
2. Connect power
3. Wait 2-3 minutes for first boot
4. Find your Pi's IP address:
   - Check your router's admin page, or
   - On Mac: `ping flowforge-pi.local` (if you set hostname)

### 1.3 SSH Into Your Pi

From your Mac Terminal:

```bash
ssh pi@flowforge-pi.local
# Or use the IP address: ssh pi@192.168.x.x
```

Enter the password you set during imaging.

### 1.4 Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

This may take 5-10 minutes.

---

## Part 2: Install Tailscale

Tailscale creates a secure VPN between all your devices. No port forwarding needed!

### 2.1 Install on Pi

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 2.2 Connect to Tailscale

```bash
sudo tailscale up
```

This will print a URL. Open it in a browser to authenticate with your Tailscale account.
(Create one at https://tailscale.com if you don't have one - it's free!)

### 2.3 Get Your Pi's Tailscale Name

```bash
tailscale status
```

Note your Pi's Tailscale hostname (e.g., `flowforge-pi`). You'll access it as `flowforge-pi.tailnet` or similar.

### 2.4 Install Tailscale on Mac and iPhone

- **Mac**: Download from https://tailscale.com/download or `brew install tailscale`
- **iPhone**: Download "Tailscale" from App Store

Sign in to the same Tailscale account on all devices.

---

## Part 3: Install FlowForge

### 3.1 Install Python 3.11+

Raspberry Pi OS should have Python 3.11+ already:

```bash
python3 --version
# Should show Python 3.11.x or higher
```

If not:
```bash
sudo apt install python3.11 python3.11-venv python3-pip -y
```

### 3.2 Clone FlowForge

```bash
cd ~
git clone https://github.com/YOUR_USERNAME/FlowForge.git flowforge
cd flowforge
```

Or if you're copying from your Mac:
```bash
# On your Mac:
scp -r ~/Projects/Active/FlowForge pi@flowforge-pi.local:~/flowforge
```

### 3.3 Create Virtual Environment

```bash
cd ~/flowforge
python3 -m venv venv
source venv/bin/activate
```

### 3.4 Install FlowForge with Server Dependencies

```bash
pip install -e ".[server]"
```

### 3.5 Test It Works

```bash
forge --version
# Should show: FlowForge v0.1.0
```

---

## Part 4: Configure SSH to Mac

The Pi needs to create git worktrees on your Mac. We'll set up passwordless SSH.

### 4.1 Generate SSH Key on Pi

```bash
ssh-keygen -t ed25519 -C "flowforge-pi"
# Press Enter for all prompts (no passphrase needed)
```

### 4.2 Copy Key to Mac

First, find your Mac's Tailscale hostname:
```bash
# On your Mac
tailscale status
# Note the name, e.g., "brians-macbook-pro"
```

Then from the Pi:
```bash
ssh-copy-id your-username@brians-macbook-pro
# Enter your Mac password when prompted
```

### 4.3 Test Connection

```bash
ssh your-username@brians-macbook-pro "echo 'Connection works!'"
# Should print "Connection works!" without asking for password
```

---

## Part 5: Create Systemd Service

This makes FlowForge start automatically when the Pi boots.

### 5.1 Create Service File

```bash
sudo nano /etc/systemd/system/flowforge.service
```

Paste this (edit the paths and usernames):

```ini
[Unit]
Description=FlowForge Development Orchestrator
After=network.target tailscaled.service

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/flowforge
Environment="PATH=/home/pi/flowforge/venv/bin:/usr/local/bin:/usr/bin"
Environment="FLOWFORGE_PROJECTS_PATH=/Users/YOUR_MAC_USERNAME/Projects/Active"
Environment="FLOWFORGE_MAC_HOST=YOUR_MAC_TAILSCALE_HOSTNAME"
Environment="FLOWFORGE_MAC_USER=YOUR_MAC_USERNAME"
Environment="FLOWFORGE_PORT=8081"
ExecStart=/home/pi/flowforge/venv/bin/python -m flowforge.server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Replace these values:**
- `YOUR_MAC_USERNAME` → your Mac username (e.g., `Brian`)
- `YOUR_MAC_TAILSCALE_HOSTNAME` → your Mac's Tailscale name (e.g., `brians-macbook-pro`)

Save with `Ctrl+O`, then `Enter`, then `Ctrl+X` to exit.

### 5.2 Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable flowforge
sudo systemctl start flowforge
```

### 5.3 Check Status

```bash
sudo systemctl status flowforge
```

Should show "active (running)".

### 5.4 View Logs

```bash
sudo journalctl -u flowforge -f
# Press Ctrl+C to stop following
```

---

## Part 6: Test Everything

### 6.1 Test Web UI

From any device on your Tailscale network, open a browser to:

```
http://flowforge-pi:8081/
```

You should see the FlowForge web UI!

### 6.2 Test API

```bash
curl http://flowforge-pi:8081/health
# Should return: {"status":"healthy",...}

curl http://flowforge-pi:8081/api/projects
# Should list your FlowForge-initialized projects
```

### 6.3 Test MCP Tools

```bash
curl http://flowforge-pi:8081/mcp/tools
# Should list all available tools
```

---

## Part 7: Configure Claude Code on iPhone

### 7.1 Open Claude Code Settings

1. Open Claude app on iPhone
2. Go to Settings → Claude Code → MCP Servers

### 7.2 Add FlowForge Server

Add a new Remote MCP Server:
- **Name**: FlowForge
- **URL**: `http://flowforge-pi:8081`
  (Use your Pi's Tailscale hostname)

### 7.3 Test It!

In Claude Code on iPhone, try:

> "List all projects in FlowForge"

Claude should call the `flowforge_list_projects` tool and show your projects!

---

## Troubleshooting

### Pi Not Reachable

```bash
# On Pi, check Tailscale is running:
tailscale status

# Restart if needed:
sudo systemctl restart tailscaled
```

### FlowForge Server Not Starting

```bash
# Check logs:
sudo journalctl -u flowforge -n 50

# Try running manually to see errors:
cd ~/flowforge
source venv/bin/activate
FLOWFORGE_PROJECTS_PATH=/Users/YOUR_USERNAME/Projects/Active forge-server
```

### SSH to Mac Failing

```bash
# Test connection:
ssh -v YOUR_USERNAME@YOUR_MAC_TAILSCALE_HOSTNAME

# Check if key was copied:
cat ~/.ssh/id_ed25519.pub
# This should match an entry in your Mac's ~/.ssh/authorized_keys
```

### Projects Not Found

Make sure the `FLOWFORGE_PROJECTS_PATH` in the systemd service points to the correct directory on your Mac, and that those projects have been initialized with `forge init`.

---

## Quick Reference

| What | Command/URL |
|------|-------------|
| SSH to Pi | `ssh pi@flowforge-pi` |
| Pi Web UI | `http://flowforge-pi:8081/` |
| Check server status | `sudo systemctl status flowforge` |
| View server logs | `sudo journalctl -u flowforge -f` |
| Restart server | `sudo systemctl restart flowforge` |
| Stop server | `sudo systemctl stop flowforge` |

---

## What's Next?

Once everything is running:

1. **From Mac**: Use `forge` CLI or the web UI
2. **From iPhone**: Use Claude Code with natural language
   - "Start the login-feature on MyApp"
   - "What features are in progress on AirFit?"
   - "Check if any features are ready to merge"
3. **From Browser**: Use the web UI at `http://flowforge-pi:8081/`

Happy building! 🔨
