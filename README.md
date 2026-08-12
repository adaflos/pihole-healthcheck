# healthcheck

Interactive top-style terminal dashboard for monitoring any Linux system. Supports **Pi-hole v6** monitoring out of the box, but works as a general-purpose system health tool on any distro.

![Bash](https://img.shields.io/badge/Bash-4+-green?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

## Features

- **Runs on any Linux distro** — auto-detects OS and displays a colored ASCII logo
- **Regular & Pi-hole modes** — system-only monitoring or full Pi-hole dashboard, auto-detected and toggleable at runtime
- **Flicker-free refresh** — redraws in-place like `top`/`btop`, no screen clearing (default: 1s)
- **ASCII analog clock** — lines-only clock overlay on the right side of the terminal
- **Keyboard controls** — toggle views, modes, and panels without restarting
- **Hardware monitoring** — CPU temperature, clock speed, throttling state, RAM usage
- **CPU info panel** — model, cores, load average, governor, frequency range, top processes
- **Storage health** — disk usage, read-only filesystem detection, SD card I/O errors
- **Pi-hole v6 engine** — FTL service status, memory footprint, DNS lookup latency
- **Network status** — local IP, interface detection, internet connectivity
- **Log auditing** — system errors, OOM kills, failed SSH logins, FTL events, live DNS traffic
- **Self-updating** — checks GitHub for new versions and installs with `-u`
- **Portable** — no hardcoded IPs or hostnames; Pi-specific checks skip gracefully on other hardware

## Supported Distros

Auto-detected via `/etc/os-release` with colored ASCII logos for:

Raspberry Pi OS, Debian, Ubuntu, Linux Mint, Pop!_OS, Arch, Manjaro, EndeavourOS, Fedora, CentOS, RHEL, Rocky, Alma, Alpine, Kali, Gentoo, Void, openSUSE/SLES — with a Tux penguin fallback for unrecognized distros.

## Quick Start

```bash
# Copy to your machine
scp healthcheck.sh user@<ip>:~/

# Make executable and run
chmod +x healthcheck.sh
./healthcheck.sh
```

## Install System-Wide

```bash
sudo cp healthcheck.sh /usr/local/bin/healthcheck
sudo chmod +x /usr/local/bin/healthcheck
```

After installing, run `healthcheck -u` anytime to update to the latest version from GitHub.

## Usage

```
healthcheck                     # Auto-detect mode (Pi-hole if available, system otherwise)
healthcheck -r                  # Regular mode (system-only, no Pi-hole checks)
healthcheck -p                  # Force Pi-hole mode
healthcheck -l                  # Log-only mode (minimal vitals + logs)
healthcheck -n 5                # Custom refresh interval (5 seconds)
healthcheck -1                  # One-shot mode (run once and exit)
healthcheck -u                  # Check for updates and install latest version
healthcheck -v                  # Print version
```

Flags can be combined: `healthcheck -r -l -n 3`

## Keyboard Controls

| Key | Action |
|-----|--------|
| `q` | Quit |
| `r` | Force immediate refresh |
| `l` | Toggle between full and log-only mode |
| `c` | Toggle CPU info panel |
| `p` | Toggle Pi-hole / regular mode |

## What It Monitors

### Always (Regular + Pi-hole mode)

| Section | Checks |
|---------|--------|
| **Hardware** | CPU temp, clock frequency, voltage/throttling flags, RAM usage, failed systemd units |
| **CPU Info** | Model, core count, load average, governor, frequency range, core voltage, top 5 processes (toggle with `c`) |
| **Storage** | Root disk usage, read-write verification, SD card I/O errors (dmesg) |
| **Network** | Default interface, local IP, public internet reachability |
| **Logs** | journalctl errors (1h), OOM kills, failed SSH logins |

### Pi-hole mode only

| Section | Checks |
|---------|--------|
| **Pi-hole Engine** | pihole-FTL service status & memory, DNS query latency via loopback |
| **Pi-hole Logs** | FTL log events (2h), live DNS query traffic |

## Requirements

- Bash 4+
- Standard Linux utilities (`free`, `df`, `systemctl`, `journalctl`, `ip`, `ping`, `dmesg`, `awk`)
- `curl` or `wget` (for self-update)
- `dig` (from `dnsutils`, optional — for DNS latency checks in Pi-hole mode)
- `vcgencmd` (Raspberry Pi only, optional — skipped if unavailable)

## License

MIT
