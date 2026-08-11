# pihole-healthcheck

Interactive top-style terminal dashboard for monitoring a **Raspberry Pi Zero 2 W** running **Pi-hole v6**.

![Bash](https://img.shields.io/badge/Bash-5.x-green?logo=gnubash&logoColor=white)
![Pi-hole](https://img.shields.io/badge/Pi--hole-v6-red?logo=pihole&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

## Features

- **Live auto-refresh** — runs like `top`, updating every 5 seconds (configurable)
- **Keyboard controls** — quit, force refresh, or toggle view mode without restarting
- **Hardware monitoring** — CPU temperature, clock speed, throttling state, RAM usage
- **Storage health** — disk usage, read-only filesystem detection, SD card I/O errors
- **Pi-hole v6 engine** — FTL service status, memory footprint, DNS lookup latency
- **Network status** — local IP, interface detection, internet connectivity
- **Log auditing** — system errors, FTL events, OOM kills, failed SSH logins, live DNS traffic
- **Portable** — no hardcoded IPs or hostnames; Pi-specific checks skip gracefully on other hardware
- **Self-updating** — checks GitHub for new versions and installs with a single flag

## Quick Start

```bash
# Copy to your Pi
scp healthcheck.sh pi@<your-pi-ip>:~/

# Make executable and run
ssh pi@<your-pi-ip>
chmod +x healthcheck.sh
./healthcheck.sh
```

## Usage

```
./healthcheck.sh                # Full interactive dashboard (refreshes every 5s)
./healthcheck.sh -l             # Log-only mode (minimal vitals + logs)
./healthcheck.sh -n 10          # Custom refresh interval (10 seconds)
./healthcheck.sh -1             # One-shot mode (run once and exit)
./healthcheck.sh -u             # Check for updates and install latest version
./healthcheck.sh -v             # Print version
```

## Install System-Wide

```bash
sudo cp healthcheck.sh /usr/local/bin/healthcheck
sudo chmod +x /usr/local/bin/healthcheck
```

After installing, run `healthcheck -u` anytime to update to the latest version from GitHub.

## Keyboard Controls

| Key | Action |
|-----|--------|
| `q` | Quit |
| `r` | Force immediate refresh |
| `l` | Toggle between full and log-only mode |
| `c` | Toggle CPU info panel (model, cores, governor, top processes) |

## What It Monitors

| Section | Checks |
|---------|--------|
| **Hardware** | CPU temp, clock frequency, voltage/throttling flags, RAM usage, failed systemd units |
| **Storage** | Root disk usage, read-write verification, SD card I/O errors (dmesg) |
| **Pi-hole** | pihole-FTL service status & memory, DNS query latency via loopback |
| **Network** | Default interface, local IP, public internet reachability |
| **Logs** | journalctl errors (1h), FTL events (2h), OOM kills, failed SSH logins, recent DNS queries |

## Requirements

- Bash 4+
- Standard Linux utilities (`free`, `df`, `systemctl`, `journalctl`, `ip`, `ping`, `dmesg`)
- `dig` (from `dnsutils`) for DNS latency checks
- `vcgencmd` (Raspberry Pi only, optional — skipped if unavailable)

## License

MIT
