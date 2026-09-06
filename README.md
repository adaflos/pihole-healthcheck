# healthcheck

Interactive top-style terminal dashboard for monitoring any Linux system. Supports **Pi-hole v6** monitoring out of the box, but works as a general-purpose system health tool on any distro.

![Bash](https://img.shields.io/badge/Bash-4+-green?logo=gnubash&logoColor=white)
![Version](https://img.shields.io/badge/Version-1.10.0-orange)
![License](https://img.shields.io/badge/License-MIT-blue)

## Screenshots

### System Mode
![System Health Dashboard](screenshot_system.png)

### Pi-hole Mode
![Pi-hole Dashboard](screenshot_pihole.png)

## Features

- **Hourly package-update check** — refreshes the package index in the background (apt, dnf, pacman, zypper, apk), reports how many packages are upgradable, and pushes kernel and security updates into Needs Attention
- **Needs Attention roll-up** — every warning and failure across all checks is gathered into one block at the top, with a count; you see what is wrong without reading the whole screen
- **Dense layout** — sections are a heading plus a hairline rule rather than a box, which is two rows lighter each; panels are placed into whichever column has room rather than a fixed side, across up to three columns on wide terminals (≥192 cols), two at ≥128, one below that
- **Fits the screen** — the layout searches for a configuration that fits: shorter list sections, then dropping the OS logo
- **Fully adaptive layout** — header box, panels, and progress bars all resize to the terminal; nothing wraps or misaligns at any width
- **Runs on any Linux distro** — auto-detects OS and displays a colored ASCII logo
- **Regular & Pi-hole modes** — system-only monitoring or full Pi-hole dashboard, auto-detected and toggleable at runtime
- **Flicker-free refresh** — the frame is painted with absolute cursor addressing in a single write, so it never scrolls, never tears, and the header is never lost (default: 1s)
- **Cached probes** — expensive checks (docker, smartctl, ss, dig, journalctl) carry a TTL instead of re-running every second, keeping CPU use low
- **Live CPU utilisation** — true CPU%, computed from `/proc/stat` jiffy deltas between frames
- **Vitals strip** — CPU, memory and swap as live gauges in the header, so the numbers that move every second are always in the same place
- **Active-panel hotkey legend** — enabled panels light up green in the key hints
- **Keyboard controls** — toggle views, modes, and panels without restarting
- **Hardware monitoring** — CPU temperature, clock speed, throttling state, RAM usage
- **CPU info panel** — model, cores, load average, governor, frequency range, top processes
- **Network diagnostics** — active connections, listening ports, DNS latency matrix, live RX/TX throughput
- **Docker & container health** — auto-detects Docker/Podman, shows running/stopped/unhealthy counts, top containers by CPU/memory, restart loop detection
- **Storage performance** — I/O wait times, live disk throughput, S.M.A.R.T. drive health, RAID/ZFS/Btrfs array status
- **Thermal & sensor expansion** — drive temperatures, fan speeds, battery/UPS monitoring
- **Security audit** — firewall status (ufw/nftables/iptables), Fail2ban jails, active SSH sessions, reboot-required checks
- **Pi-hole v6 engine** — FTL service status, memory footprint, DNS lookup latency
- **Log auditing** — system errors, OOM kills, failed SSH logins, FTL events, live DNS traffic
- **JSON output** — structured JSON payload for Home Assistant, Prometheus, or custom tooling
- **Webhook alerts** — Discord, Slack, or generic webhook notifications when thresholds are breached
- **Snapshot logging** — append JSON snapshots to a log file on each refresh cycle
- **Custom thresholds** — configurable CPU temp, RAM, and disk warning levels via CLI flags
- **No-color mode** — disable ANSI codes for piping to files or plain terminals
- **Self-updating** — checks GitHub for new versions and installs with `-u`
- **Portable** — no hardcoded IPs or hostnames; optional checks skip gracefully if tools are missing

## Supported Distros

Auto-detected via `/etc/os-release` with colored ASCII logos for:

Raspberry Pi OS, Debian, Ubuntu, Linux Mint, Pop!_OS, Arch, Manjaro, EndeavourOS, Fedora, CentOS, RHEL, Rocky, Alma, Alpine, Kali, Gentoo, Void, openSUSE/SLES — with a Tux penguin fallback for unrecognized distros.

## Install

Install to your `PATH` in one line:

```bash
curl -fsSL https://raw.githubusercontent.com/adaflos/healthcheck/master/healthcheck.sh | sudo tee /usr/local/bin/healthcheck >/dev/null && sudo chmod +x /usr/local/bin/healthcheck
```

Then run it from anywhere:

```bash
healthcheck
```

Prefer to read the script before running it as root? Download it first:

```bash
curl -fsSL -O https://raw.githubusercontent.com/adaflos/healthcheck/master/healthcheck.sh
less healthcheck.sh
sudo install -m 755 healthcheck.sh /usr/local/bin/healthcheck
```

### Run without installing

```bash
curl -fsSL -O https://raw.githubusercontent.com/adaflos/healthcheck/master/healthcheck.sh
chmod +x healthcheck.sh
./healthcheck.sh
```

### Keeping it current

```bash
healthcheck -u
```

Checks GitHub and installs the newer version if there is one. It queries the API rather than the raw file, so a release is picked up immediately instead of waiting out the CDN cache.

## Usage

```
healthcheck                     # Auto-detect mode (Pi-hole if available, system otherwise)
healthcheck -r                  # Regular mode (system-only, no Pi-hole checks)
healthcheck -p                  # Force Pi-hole mode
healthcheck -l                  # Log-only mode (minimal vitals + logs)
healthcheck -n 5                # Custom refresh interval (5 seconds)
healthcheck -1                  # One-shot mode (run once and exit)
healthcheck --json              # Output structured JSON and exit
healthcheck -m                  # No-color mode (plain text, no ANSI)
healthcheck --no-update-check   # Skip the package index refresh entirely
healthcheck --update-interval 30 # Refresh the package index every 30 min (default: 60)
healthcheck -u                  # Check for updates and install latest version
healthcheck -v                  # Print version
```

### Custom Thresholds

```
healthcheck --temp-limit 70     # CPU temp warning at 70°C (default: 75)
healthcheck --ram-limit 90      # RAM warning at 90% (default: 85)
healthcheck --disk-limit 85     # Disk warning at 85% (default: 90)
```

### Webhook Alerts

```
healthcheck --webhook https://discord.com/api/webhooks/...
healthcheck --webhook https://hooks.slack.com/services/...
```

Sends a JSON POST with `text` and `content` fields when RAM, disk, temperature, or filesystem thresholds are breached.

### Snapshot Logging

```
healthcheck --log-file /var/log/healthcheck.log
```

Appends a JSON snapshot on each refresh cycle for later analysis.

Flags can be combined: `healthcheck -r -l -n 3 --ram-limit 90 --webhook https://...`

## Keyboard Controls

| Key | Action |
|-----|--------|
| `q` | Quit |
| `l` | Toggle between full and log-only mode |
| `c` | Toggle CPU info panel |
| `p` | Toggle Pi-hole / regular mode |
| `d` | Toggle Docker / container panel |
| `n` | Toggle network diagnostics panel |
| `s` | Toggle storage performance panel |
| `t` | Toggle thermal / sensor panel |
| `a` | Toggle security audit panel |

## What It Monitors

### Always (Regular + Pi-hole mode)

| Section | Checks |
|---------|--------|
| **Hardware** | CPU temp, clock frequency, live CPU utilisation %, memory & swap gauges, voltage/throttling flags, failed systemd units |
| **CPU Info** | Model, core count, load average, governor, frequency range, core voltage, top 5 processes (toggle with `c`) |
| **Storage** | Root disk usage, read-write verification, SD card I/O errors (dmesg) |
| **Network** | Default interface, local IP, public internet reachability |
| **Logs** | journalctl errors (1h), OOM kills, failed SSH logins |
| **Package Updates** | Upgradable package count, kernel/security updates flagged, age of the last index refresh |

### Toggle panels

| Section | Key | Checks |
|---------|-----|--------|
| **Network Diagnostics** | `n` | TCP connection summary (ESTAB/LISTEN/TIME_WAIT), listening port audit, DNS latency matrix (Cloudflare, Google, Pi-hole), live RX/TX throughput per interface |
| **Docker / Containers** | `d` | Engine detection (Docker/Podman), running/stopped/unhealthy counts, restart loop detection, top 3 containers by CPU & memory |
| **Storage Performance** | `s` | I/O wait percentage, live disk read/write throughput, S.M.A.R.T. drive health, MD RAID / ZFS pool / Btrfs array status |
| **Thermal & Sensors** | `t` | Drive temperatures (SATA/NVMe via smartctl), fan speeds (lm-sensors), battery status, UPS monitoring (NUT/upsc) |
| **Security Audit** | `a` | Firewall status (ufw/nftables/iptables), Fail2ban jails & banned IPs, pending package updates, active user sessions, kernel restart status |

### Pi-hole mode only

| Section | Checks |
|---------|--------|
| **Pi-hole Engine** | pihole-FTL service status & memory, DNS query latency via loopback |
| **Pi-hole Logs** | FTL log events (2h), live DNS query traffic |

## Status Indicators

| Icon | Meaning |
|------|---------|
| `●` green | Healthy |
| `▲` yellow | Warning — attention advised |
| `✖` red | Failure — action needed |

Progress bars change color based on usage:
- **Green** — 0-50%
- **Yellow** — 51-75%
- **Red** — 76-100%

Bars widen on roomy terminals and shrink on narrow ones, so the layout stays readable from ~50 columns upward.

## JSON Output

The `--json` flag outputs a structured payload suitable for ingestion by Home Assistant, Prometheus, or custom logging agents:

```bash
healthcheck --json | jq .
```

```json
{
  "version": "1.3.0",
  "hostname": "pizero2",
  "timestamp": "2026-08-12T22:00:00+00:00",
  "hardware": {
    "cpu_temp_c": 56.9,
    "ram_total_mb": 463,
    "ram_used_mb": 254,
    "ram_percent": 54,
    "load_1m": 0.83,
    "load_5m": 0.75,
    "load_15m": 0.49,
    "failed_systemd_units": 0
  },
  "storage": {
    "root_usage_percent": 6,
    "root_free": "106G"
  },
  "network": {
    "interface": "eth0",
    "local_ip": "192.168.1.200",
    "public_internet": true
  },
  "pihole": { "active": true },
  "containers": { "engine": "docker", "running": 3 }
}
```

## Package Updates

The dashboard refreshes the package index in the background once an hour and reports what is pending.

| Manager | Refresh | Needs root? |
|---------|---------|-------------|
| `apt` | `apt-get update` | yes |
| `dnf` | `dnf makecache` | yes |
| `pacman` | `checkupdates` | **no** — syncs to its own temp database |
| `zypper` | `zypper refresh` | yes |
| `apk` | `apk update` | yes |

The refresh runs detached, so it never blocks a frame, and it uses `sudo -n` — which fails rather than prompting. Without passwordless sudo the refresh is skipped and the count is read from the existing cache instead, labelled `cache only, no root`.

Counting upgradable packages never needs root, so the numbers stay useful either way. On Debian/Ubuntu the count comes from a simulated `dist-upgrade` rather than `upgrade`, because a new kernel arrives as a *new* package that plain `upgrade` holds back and would otherwise never report.

Updates matching kernel or core-security names — `linux-image*`, `kernel*`, `systemd`, `libc6`/`glibc`, `openssl`/`libssl*`, `openssh`, `sudo` — are raised into **Needs Attention**.

The hourly timer is stored in `~/.cache/healthcheck/`, so restarting the dashboard does not trigger a fresh index refresh each time.

## Requirements

- Bash 4+
- Standard Linux utilities (`free`, `df`, `systemctl`, `journalctl`, `ip`, `ping`, `dmesg`, `awk`, `ss`)
- `curl` or `wget` (for self-update and webhooks)
- `dig` (from `dnsutils`, optional — for DNS latency checks)
- `vcgencmd` (Raspberry Pi only, optional — skipped if unavailable)
- `smartctl` (optional — for S.M.A.R.T. and drive temperature monitoring)
- `sensors` (from `lm-sensors`, optional — for fan speed monitoring)
- `docker` or `podman` (optional — for container health panel)
- `fail2ban-client` (optional — for Fail2ban integration)
- `upsc` (from `nut`, optional — for UPS monitoring)

## License

MIT
