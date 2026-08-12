#!/usr/bin/env bash

# ==============================================================================
# Unified System & Pi-hole Health Check Dashboard
# Interactive top-style mode with auto-refresh.
#
# Usage:
#   Full View:         ./healthcheck
#   Regular Mode:      ./healthcheck -r       (system-only, no Pi-hole)
#   Pi-hole Mode:      ./healthcheck -p       (force Pi-hole checks)
#   Log-Only Mode:     ./healthcheck -l
#   Custom Interval:   ./healthcheck -n 10    (refresh every 10 seconds)
#   One-Shot Mode:     ./healthcheck -1       (run once and exit)
#   Self-Update:       ./healthcheck -u
#
# Controls:
#   q / Ctrl-C   Quit
#   r            Force immediate refresh
#   l            Toggle log-only mode
#   c            Toggle CPU info panel
#   p            Toggle Pi-hole mode
# ==============================================================================

VERSION="1.2.1"
REPO_RAW="https://raw.githubusercontent.com/adaflos/pihole-healthcheck/master/healthcheck.sh"
INSTALL_PATH="/usr/local/bin/healthcheck"

# --- Color & Formatting Definitions (needed early for do_update) ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Defaults ---
LESS_MODE=false
REFRESH=1
ONESHOT=false
SHOW_CPU=false

# Auto-detect Pi-hole: default to pihole mode only if pihole-FTL exists
if command -v pihole &>/dev/null || systemctl list-unit-files pihole-FTL.service &>/dev/null; then
    PIHOLE_MODE=true
else
    PIHOLE_MODE=false
fi

# --- Self-Update ---
do_update() {
    echo -e "${BOLD}Checking for updates...${NC}"
    echo -e "  Installed version: ${CYAN}${VERSION}${NC}"

    local tmp
    tmp=$(mktemp) || { echo -e "  ${RED}Failed to create temp file.${NC}"; exit 1; }
    trap "rm -f '$tmp'" RETURN

    if command -v curl &>/dev/null; then
        curl -fsSL "$REPO_RAW" -o "$tmp" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp" "$REPO_RAW" 2>/dev/null
    else
        echo -e "  ${RED}Neither curl nor wget found. Cannot check for updates.${NC}"
        exit 1
    fi

    if [ ! -s "$tmp" ]; then
        echo -e "  ${RED}Failed to fetch remote script. Check your internet connection.${NC}"
        exit 1
    fi

    local remote_version
    remote_version=$(grep -m1 '^VERSION=' "$tmp" | cut -d'"' -f2)

    if [ -z "$remote_version" ]; then
        echo -e "  ${RED}Could not determine remote version.${NC}"
        exit 1
    fi

    echo -e "  Remote version:    ${CYAN}${remote_version}${NC}"

    local newer
    newer=$(printf '%s\n%s\n' "$VERSION" "$remote_version" | sort -V | tail -n1)

    if [ "$newer" = "$VERSION" ]; then
        echo -e "\n  ${GREEN}Already up to date.${NC}"
        exit 0
    fi

    echo -e "\n  ${YELLOW}New version available: ${remote_version}${NC}"
    echo -e "  Installing to ${BOLD}${INSTALL_PATH}${NC} ..."

    if [ -w "$(dirname "$INSTALL_PATH")" ]; then
        cp "$tmp" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
    else
        sudo cp "$tmp" "$INSTALL_PATH"
        sudo chmod +x "$INSTALL_PATH"
    fi

    echo -e "  ${GREEN}Updated to ${remote_version}!${NC}"
    exit 0
}

# --- Parse Command Line Options ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--less)
            LESS_MODE=true
            shift
            ;;
        -n|--interval)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -n requires a numeric argument"
                exit 1
            fi
            REFRESH="$2"
            shift 2
            ;;
        -1|--once)
            ONESHOT=true
            shift
            ;;
        -r|--regular)
            PIHOLE_MODE=false
            shift
            ;;
        -p|--pihole)
            PIHOLE_MODE=true
            shift
            ;;
        -u|--update)
            do_update
            ;;
        -v|--version)
            echo "healthcheck v${VERSION}"
            exit 0
            ;;
        -h|--help)
            echo "Usage: healthcheck [-r|--regular] [-p|--pihole] [-l|--less] [-n SECONDS] [-1|--once] [-u|--update] [-v|--version]"
            echo ""
            echo "Modes:"
            echo "  -r, --regular     System-only mode (no Pi-hole checks)"
            echo "  -p, --pihole      Force Pi-hole mode (auto-detected by default)"
            echo "  -l, --less        Log-only mode (minimal vitals + logs)"
            echo "  -1, --once        Run once and exit (no interactive loop)"
            echo ""
            echo "Options:"
            echo "  -n, --interval N  Refresh every N seconds (default: 1)"
            echo "  -u, --update      Check for updates and install to ${INSTALL_PATH}"
            echo "  -v, --version     Show version and exit"
            echo ""
            echo "Controls:"
            echo "  q / Ctrl-C   Quit"
            echo "  r            Force immediate refresh"
            echo "  l            Toggle log-only mode"
            echo "  c            Toggle CPU info panel"
            echo "  p            Toggle Pi-hole mode"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- OS Detection & Logo ---
OS_ID="linux"
OS_NAME="Linux"
OS_COLOR="$YELLOW"

if [ -f /etc/os-release ]; then
    OS_ID=$(. /etc/os-release && echo "$ID")
    OS_NAME=$(. /etc/os-release && echo "$PRETTY_NAME")
fi

case "$OS_ID" in
    raspbian)                       OS_COLOR="$RED" ;;
    debian)                         OS_COLOR="$RED" ;;
    ubuntu|linuxmint|pop)           OS_COLOR="$YELLOW" ;;
    arch|archarm|manjaro|endeavouros) OS_COLOR="$CYAN" ;;
    fedora)                         OS_COLOR="$BLUE" ;;
    centos|rhel|rocky|alma)         OS_COLOR="$PURPLE" ;;
    alpine)                         OS_COLOR="$BLUE" ;;
    kali)                           OS_COLOR="$BLUE" ;;
    gentoo)                         OS_COLOR="$PURPLE" ;;
    void)                           OS_COLOR="$GREEN" ;;
    opensuse*|sles)                 OS_COLOR="$GREEN" ;;
esac

print_os_logo() {
    local lines=()
    case "$OS_ID" in
        raspbian)
            lines=(
                "   .~~.   .~~."
                "  '. \\ ' ' / .'"
                "   .~ .~~~. ~."
                "  : .~.'~'.~. :"
                " ~ (   ) (   ) ~"
                "( : '~'.~.'~' : )"
            )
            ;;
        debian|kali)
            lines=(
                "  _____"
                " /  __ \\"
                "|  /    |"
                "|  \\___-"
                "-_"
                "  --_"
            )
            ;;
        ubuntu|pop|linuxmint)
            lines=(
                "         _"
                "     ---(_)"
                " _/  ---  \\"
                "(_) |   |"
                " \\  --- _/"
                "     ---(_)"
            )
            ;;
        arch|archarm|manjaro|endeavouros)
            lines=(
                "      /\\"
                "     /  \\"
                "    /\\   \\"
                "   /  \\   \\"
                "  /   _\\   \\"
                " /___/  \\___\\"
            )
            ;;
        fedora)
            lines=(
                "      ____"
                "     /    \\"
                "    |  f  _|"
                "    |  |"
                "    |  |"
                "     \\_|"
            )
            ;;
        centos|rhel|rocky|alma)
            lines=(
                "  \\  |  /"
                "   \\ | /"
                "----***----"
                "   / | \\"
                "  /  |  \\"
            )
            ;;
        alpine)
            lines=(
                "   /\\ /\\"
                "  /  V  \\"
                " /      /"
                "/      /"
                "\\     /"
                " \\   /"
            )
            ;;
        gentoo)
            lines=(
                " _-----_"
                "(       \\"
                "\\    0   \\"
                " \\        )"
                " /      _/"
                "(     _-"
                "\\____-"
            )
            ;;
        void)
            lines=(
                "    _______"
                "   \\  ___  \\"
                "    \\ \\  \\ \\"
                "     \\ \\  \\ \\"
                "      \\_\\  \\_\\"
                "             "
            )
            ;;
        opensuse*|sles)
            lines=(
                "  _______"
                "__|   __ \\"
                "     / .\\ \\"
                "     \\__/ |"
                "   ______ |"
                "  /_____/-'"
            )
            ;;
        *)
            lines=(
                "    .---."
                "   /     \\"
                "   |O   O|"
                "   |  >  |"
                "  /|     |\\"
                "    '---'"
            )
            ;;
    esac

    local line
    for line in "${lines[@]}"; do
        printf '%b%s%b\n' "$OS_COLOR" "  $line" "$NC"
    done
    printf '%b  %s%b\n' "$BOLD" "$OS_NAME" "$NC"
    echo ""
}

# --- UI Helpers ---
print_header() {
    print_os_logo

    local mode_label
    if [ "$LESS_MODE" = true ]; then
        mode_label="${YELLOW}LOG-ONLY${NC}"
    else
        mode_label="${GREEN}FULL${NC}"
    fi

    if [ "$LESS_MODE" = true ]; then
        local log_title
        if [ "$PIHOLE_MODE" = true ]; then
            log_title="🍓 LIVE LOG & EVENT MONITOR (Pi-hole v6)"
        else
            log_title="📋 LIVE LOG & EVENT MONITOR"
        fi
        echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────────────┐${NC}"
        printf "${CYAN}│${NC} ${BOLD}${PURPLE}  %-43s${NC}              ${DIM}v%-12s${NC}${CYAN}│${NC}\n" "$log_title" "$VERSION"
        echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
        printf "${CYAN}│${NC} ${BOLD}Host:${NC} %-12s ${BOLD}Time:${NC} %-25s ${BOLD}Load:${NC} %-15s ${CYAN}│${NC}\n" \
            "$(hostname)" "$(date '+%Y-%m-%d %H:%M:%S')" "$(uptime | awk -F'load average:' '{print $2}' | xargs)"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
    else
        local dash_title
        if [ "$PIHOLE_MODE" = true ]; then
            dash_title="🍓 PI-HOLE v6 & SYSTEM DASHBOARD"
        else
            dash_title="🖥  SYSTEM HEALTH DASHBOARD"
        fi
        echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────────────┐${NC}"
        printf "${CYAN}│${NC} ${BOLD}${PURPLE}  %-43s${NC}              ${DIM}v%-12s${NC}${CYAN}│${NC}\n" "$dash_title" "$VERSION"
        echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
        printf "${CYAN}│${NC} ${BOLD}Host:${NC} %-12s ${BOLD}OS:${NC} %-18s ${BOLD}Uptime:${NC} %-17s ${CYAN}│${NC}\n" \
            "$(hostname)" "$(uname -s) $(uname -r | cut -d'-' -f1)" "$(uptime -p | sed 's/up //')"
        printf "${CYAN}│${NC} ${BOLD}Time:${NC} %-25s ${BOLD}Load:${NC} %-23s ${CYAN}│${NC}\n" \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$(uptime | awk -F'load average:' '{print $2}' | xargs)"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
    fi
    local pihole_label
    if [ "$PIHOLE_MODE" = true ]; then
        pihole_label="${PURPLE}PIHOLE${NC}"
    else
        pihole_label="${CYAN}SYSTEM${NC}"
    fi
    echo -e " ${DIM}View: ${NC}${mode_label}  ${DIM}│  Scope: ${NC}${pihole_label}  ${DIM}│  Refresh: ${NC}${REFRESH}s  ${DIM}│  ${NC}${BOLD}q${NC}${DIM}uit ${NC}${BOLD}r${NC}${DIM}efresh ${NC}${BOLD}l${NC}${DIM}og ${NC}${BOLD}c${NC}${DIM}pu ${NC}${BOLD}p${NC}${DIM}ihole${NC}"
    echo ""
}

print_section() {
    echo -e "${BOLD}${BLUE}▸ $1${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────────────${NC}"
}

print_status() {
    local label="$1"
    local status="$2"
    local detail="$3"

    case "$status" in
        OK)   printf "  [${GREEN}  OK  ${NC}] ${BOLD}%-22s${NC} : %b\n" "$label" "$detail" ;;
        WARN) printf "  [${YELLOW} WARN ${NC}] ${BOLD}%-22s${NC} : %b\n" "$label" "$detail" ;;
        FAIL) printf "  [${RED} FAIL ${NC}] ${BOLD}%-22s${NC} : %b\n" "$label" "$detail" ;;
    esac
}

draw_progress_bar() {
    local pct=$1
    local width=18
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""

    local color=$GREEN
    if [ "$pct" -ge 80 ]; then color=$YELLOW; fi
    if [ "$pct" -ge 90 ]; then color=$RED; fi

    bar+="${color}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    bar+="${NC}${DIM}"
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="${NC}"

    echo -e "[${bar}] ${pct}%"
}

# --- 1. Hardware & Thermal Engine ---
check_hardware() {
    print_section "HARDWARE & THERMAL METRICS"

    if command -v vcgencmd &>/dev/null; then
        temp_raw=$(vcgencmd measure_temp | awk -F'=' '{print $2}' | tr -d "'C")
        temp_int=${temp_raw%.*}
        freq_raw=$(vcgencmd measure_clock arm | awk -F'=' '{print $2}')
        freq_raw=${freq_raw:-0}
        freq_mhz=$(( freq_raw / 1000000 ))

        if [ "$temp_int" -lt 68 ]; then
            print_status "CPU Temp" "OK" "${temp_raw}°C (${freq_mhz} MHz)"
        elif [ "$temp_int" -lt 78 ]; then
            print_status "CPU Temp" "WARN" "${temp_raw}°C (${freq_mhz} MHz - High)"
        else
            print_status "CPU Temp" "FAIL" "${temp_raw}°C (${freq_mhz} MHz - Critical Throttle)"
        fi

        throttled=$(vcgencmd get_throttled | awk -F'=' '{print $2}')
        if [ "$throttled" == "0x0" ]; then
            print_status "Power & Throttling" "OK" "Clean (No voltage drops or throttling)"
        else
            print_status "Power & Throttling" "WARN" "Flag: ${throttled} (Check power supply)"
        fi
    fi

    ram_total=$(free -m | awk '/^Mem:/{print $2}')
    ram_used=$(free -m | awk '/^Mem:/{print $3}')
    ram_pct=$(( ram_used * 100 / ram_total ))
    ram_bar=$(draw_progress_bar "$ram_pct")

    if [ "$ram_pct" -lt 80 ]; then
        print_status "RAM Usage" "OK" "${ram_used}MB / ${ram_total}MB ${ram_bar}"
    else
        print_status "RAM Usage" "WARN" "${ram_used}MB / ${ram_total}MB ${ram_bar} (High Memory Pressure)"
    fi

    failed_units=$(systemctl --failed --no-legend | wc -l)
    if [ "$failed_units" -eq 0 ]; then
        print_status "Systemd Health" "OK" "0 failed system units"
    else
        failed_names=$(systemctl --failed --no-legend | awk '{print $1}' | tr '\n' ' ')
        print_status "Systemd Health" "FAIL" "${failed_units} failed unit(s): ${failed_names}"
    fi
    echo ""
}

# --- 1b. CPU Info Panel (toggled with 'c') ---
check_cpu_info() {
    print_section "CPU INFORMATION"

    if [ -f /proc/cpuinfo ]; then
        local model cores
        model=$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)
        model=${model:-$(grep -m1 'Model' /proc/cpuinfo | cut -d':' -f2 | xargs)}
        cores=$(grep -c '^processor' /proc/cpuinfo)
        print_status "CPU Model" "OK" "${model:-Unknown}"
        print_status "CPU Cores" "OK" "${cores}"
    fi

    if [ -f /proc/loadavg ]; then
        local load1 load5 load15 procs
        read -r load1 load5 load15 procs _ < /proc/loadavg
        print_status "Load Average" "OK" "${load1} / ${load5} / ${load15}  (1/5/15 min)"
        print_status "Processes" "OK" "${procs}"
    fi

    if command -v vcgencmd &>/dev/null; then
        local volts governor
        volts=$(vcgencmd measure_volts core 2>/dev/null | awk -F'=' '{print $2}')
        [ -n "$volts" ] && print_status "Core Voltage" "OK" "${volts}"

        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
            print_status "CPU Governor" "OK" "${governor}"
        fi

        local freq_min freq_max
        [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq ] && \
            freq_min=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq) / 1000 ))
        [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ] && \
            freq_max=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) / 1000 ))
        [ -n "$freq_min" ] && [ -n "$freq_max" ] && \
            print_status "Freq Range" "OK" "${freq_min} - ${freq_max} MHz"
    else
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            local governor
            governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
            print_status "CPU Governor" "OK" "${governor}"
        fi
    fi

    local top_procs
    top_procs=$(ps -eo pid,pcpu,comm --sort=-pcpu --no-headers | head -n 5)
    if [ -n "$top_procs" ]; then
        print_status "Top Processes (CPU)" "OK" ""
        echo "$top_procs" | while read -r line; do
            echo -e "      ${DIM}${line}${NC}"
        done
    fi
    echo ""
}

# --- 2. Storage & Filesystem Health ---
check_storage() {
    print_section "STORAGE & FILESYSTEM MOUNTS"

    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    disk_usage=${disk_usage:-0}
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    disk_bar=$(draw_progress_bar "$disk_usage")

    if [ "$disk_usage" -lt 80 ]; then
        print_status "Total Root Space (/)" "OK" "${disk_free} free ${disk_bar}"
    else
        print_status "Total Root Space (/)" "WARN" "${disk_free} free ${disk_bar}"
    fi

    if touch /tmp/ro_test_check &>/dev/null; then
        rm -f /tmp/ro_test_check
        print_status "Filesystem Access" "OK" "Read-Write mode verified"
    else
        print_status "Filesystem Access" "FAIL" "${RED}${BOLD}READ-ONLY MODE DETECTED!${NC}"
    fi

    if dmesg -l err,crit 2>/dev/null | grep -iqE 'mmc|sd|ext4'; then
        print_status "SD Card Health" "FAIL" "Kernel logged I/O errors in dmesg"
    else
        print_status "SD Card Health" "OK" "No SD card I/O errors"
    fi
    echo ""
}

# --- 3. Pi-hole v6 Engine & Web API ---
check_pihole_v6() {
    print_section "PI-HOLE v6 ENGINE & SERVICES"

    if systemctl is-active --quiet pihole-FTL; then
        ftl_mem=$(ps aux | grep '[p]ihole-FTL' | awk '{sum+=$6} END{print sum+0}')
        ftl_mem_mb=$(( ftl_mem / 1024 ))
        print_status "pihole-FTL Engine" "OK" "Active (${ftl_mem_mb}MB RAM usage)"
    else
        print_status "pihole-FTL Engine" "FAIL" "Service is down or crashed"
    fi

    if command -v dig &>/dev/null; then
        qtime=$(dig @127.0.0.1 google.com +time=2 +tries=1 | awk '/Query time:/ {print $4}')
        if [ -n "$qtime" ]; then
            print_status "DNS Lookup Speed" "OK" "${qtime} ms (Local loopback)"
        else
            print_status "DNS Lookup Speed" "FAIL" "Query timed out"
        fi
    fi
    echo ""
}

# --- 4. Network & Security Details ---
check_network_security() {
    print_section "NETWORK CONFIGURATION & SECURITY"

    main_iface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -n "$main_iface" ]; then
        local_ip=$(ip -4 addr show "$main_iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -n1)
        print_status "Local IP Address" "OK" "${local_ip:-Unknown} on ${main_iface}"
    fi

    if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        print_status "Public Internet" "OK" "Connected"
    else
        print_status "Public Internet" "FAIL" "Unreachable"
    fi
    echo ""
}

# --- 5. Logs & System Audit (Live Stream) ---
check_logs() {
    print_section "LOGS & SYSTEM AUDIT STREAM"

    recent_errors=$(journalctl -p 0..3 --since "1 hour ago" --no-pager -n 5 2>/dev/null | grep -v "vc4-drm" | tail -n 5)
    if [ -n "$recent_errors" ]; then
        print_status "System Errors (1h)" "WARN" "Errors detected:"
        echo "$recent_errors" | while read -r line; do
            echo -e "      ${DIM}${line}${NC}"
        done
    else
        print_status "System Errors (1h)" "OK" "No critical errors"
    fi

    if [ "$PIHOLE_MODE" = true ]; then
        ftl_logs=$(journalctl -u pihole-FTL -p 0..4 --since "2 hours ago" --no-pager -n 5 2>/dev/null | tail -n 5)
        if [ -n "$ftl_logs" ]; then
            print_status "FTL Log Events (2h)" "WARN" "Recent entries:"
            echo "$ftl_logs" | while read -r line; do
                echo -e "      ${DIM}${line}${NC}"
            done
        else
            print_status "FTL Log Events (2h)" "OK" "Clean (No events in last 2h)"
        fi
    fi

    if dmesg 2>/dev/null | grep -iqE "Out of memory|Killed process"; then
        oom_target=$(dmesg | grep -iE "Killed process" | tail -n 1 | awk -F'Killed process' '{print $2}')
        print_status "OOM Killer Events" "FAIL" "Process killed:${oom_target}"
    else
        print_status "OOM Killer Events" "OK" "No kernel process kills recorded"
    fi

    failed_ssh=$(journalctl -u ssh --since "today" 2>/dev/null | grep -c "Failed password")
    if [ "$failed_ssh" -gt 0 ]; then
        print_status "Failed SSH Logins" "WARN" "${failed_ssh} failed attempt(s) today"
    else
        print_status "Failed SSH Logins" "OK" "0 failed attempts today"
    fi

    if [ "$PIHOLE_MODE" = true ] && [ -f /var/log/pihole/pihole.log ]; then
        last_queries=$(tail -n 5 /var/log/pihole/pihole.log 2>/dev/null | grep -E 'query|reply')
        if [ -n "$last_queries" ]; then
            print_status "Live DNS Traffic" "OK" "Recent queries:"
            echo "$last_queries" | while read -r line; do
                echo -e "      ${DIM}${line}${NC}"
            done
        fi
    fi
    echo ""
}

# --- ASCII Analog Clock ---
generate_clock() {
    date '+%H %M %S' | awk '
    function lch(dx, dy,    adx, ady, vdy) {
        adx = (dx >= 0) ? dx : -dx
        ady = (dy >= 0) ? dy : -dy
        vdy = ady * 2
        if (vdy < adx * 0.4) return "-"
        if (adx < vdy * 0.4) return "|"
        if ((dx > 0 && dy > 0) || (dx < 0 && dy < 0)) return "\\"
        return "/"
    }
    {
        hour = ($1 + 0) % 12
        min = $2 + 0
        sec = $3 + 0

        W = 31; H = 21
        cx = 15; cy = 9
        rx = 14; ry = 7
        pi = atan2(0, -1)

        for (y = 0; y < H; y++)
            for (x = 0; x < W; x++) {
                g[y,x] = " "; t[y,x] = 0
            }

        # Circle outline
        for (i = 0; i < 120; i++) {
            a = i / 120.0 * 2 * pi - pi / 2
            px = int(cx + rx * cos(a) + 0.5)
            py = int(cy + ry * sin(a) + 0.5)
            if (px >= 0 && px < W && py >= 0 && py < H && t[py,px] == 0) {
                g[py,px] = "."; t[py,px] = 1
            }
        }

        # Tick marks at hour positions (lines only, no numbers)
        for (i = 1; i <= 12; i++) {
            a = i / 12.0 * 2 * pi - pi / 2
            ca = cos(a); sa = sin(a)
            ch = lch(ca, sa)

            ox = int(cx + rx * ca + 0.5)
            oy = int(cy + ry * sa + 0.5)
            g[oy,ox] = ch; t[oy,ox] = 2

            ix = int(cx + rx * 0.88 * ca + 0.5)
            iy = int(cy + ry * 0.88 * sa + 0.5)
            if (ix != ox || iy != oy) { g[iy,ix] = ch; t[iy,ix] = 2 }

            if (i == 12 || i == 3 || i == 6 || i == 9) {
                mx = int(cx + rx * 0.78 * ca + 0.5)
                my = int(cy + ry * 0.78 * sa + 0.5)
                g[my,mx] = ch; t[my,mx] = 3
                nx = int(cx + rx * 0.72 * ca + 0.5)
                ny = int(cy + ry * 0.72 * sa + 0.5)
                if (nx != mx || ny != my) { g[ny,nx] = ch; t[ny,nx] = 3 }
            }
        }

        g[cy,cx] = "+"; t[cy,cx] = 6

        # Minute hand
        ma = min / 60.0 * 2 * pi - pi / 2
        mch = lch(cos(ma), sin(ma))
        for (s = 0.1; s <= 0.82; s += 0.01) {
            mx = int(cx + rx * s * cos(ma) + 0.5)
            my = int(cy + ry * s * sin(ma) + 0.5)
            if (mx >= 0 && mx < W && my >= 0 && my < H)
                if (t[my,mx] <= 1) { g[my,mx] = mch; t[my,mx] = 5 }
        }

        # Hour hand (overwrites minute)
        ha = (hour + min / 60.0) / 12.0 * 2 * pi - pi / 2
        hch = lch(cos(ha), sin(ha))
        for (s = 0.1; s <= 0.52; s += 0.01) {
            hx = int(cx + rx * s * cos(ha) + 0.5)
            hy = int(cy + ry * s * sin(ha) + 0.5)
            if (hx >= 0 && hx < W && hy >= 0 && hy < H)
                if (t[hy,hx] <= 1 || t[hy,hx] == 5) { g[hy,hx] = hch; t[hy,hx] = 4 }
        }

        dim = "\033[2m"; bold = "\033[1m"
        cyan = "\033[0;36m"; yel = "\033[1;33m"; nc = "\033[0m"

        for (y = 0; y < H; y++) {
            line = ""
            for (x = 0; x < W; x++) {
                c = g[y,x]; tp = t[y,x]
                if      (tp == 1) line = line dim c nc
                else if (tp == 2) line = line bold c nc
                else if (tp == 3) line = line bold c nc
                else if (tp == 4) line = line yel c nc
                else if (tp == 5) line = line cyan c nc
                else if (tp == 6) line = line bold c nc
                else              line = line c
            }
            print line
        }
        printf "           %s%02d:%02d:%02d%s\n", bold, ($1+0), min, sec, nc
    }'
}

draw_clock_overlay() {
    local cols
    cols=$(tput cols 2>/dev/null) || cols=80
    local clock_width=31
    local start_col=$((cols - clock_width - 2))
    local start_row=1

    if [ "$start_col" -lt 50 ]; then
        return
    fi

    local clock_output
    clock_output=$(generate_clock)

    local row=$start_row
    while IFS= read -r line; do
        tput cup "$row" "$start_col" 2>/dev/null
        echo -e "$line"
        row=$((row + 1))
    done <<< "$clock_output"
}

# --- Render one full frame into a buffer, then paint in-place ---
PREV_COLS=0

render_frame() {
    local current_cols
    current_cols=$(tput cols 2>/dev/null) || current_cols=80
    if [ "$current_cols" -ne "$PREV_COLS" ]; then
        clear
        PREV_COLS=$current_cols
    fi

    local buffer
    buffer=$(
        print_header

        if [ "$LESS_MODE" = true ]; then
            check_hardware
            [ "$SHOW_CPU" = true ] && check_cpu_info
            [ "$PIHOLE_MODE" = true ] && check_pihole_v6
            check_logs
        else
            check_hardware
            [ "$SHOW_CPU" = true ] && check_cpu_info
            check_storage
            [ "$PIHOLE_MODE" = true ] && check_pihole_v6
            check_network_security
            check_logs
        fi
    )

    tput cup 0 0 2>/dev/null
    echo -e "$buffer"
    tput ed 2>/dev/null
    draw_clock_overlay
}

# --- One-shot mode ---
if [ "$ONESHOT" = true ]; then
    clear
    render_frame
    exit 0
fi

# --- Interactive loop ---
tput civis 2>/dev/null

# Use alternate screen buffer so the original terminal is restored on exit
tput smcup 2>/dev/null
clear
ALTSCREEN=true

cleanup() {
    tput cnorm 2>/dev/null
    [ "$ALTSCREEN" = true ] && tput rmcup 2>/dev/null
    stty echo 2>/dev/null
    echo -e "\n${DIM}Dashboard stopped.${NC}"
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    render_frame

    countdown=$REFRESH
    while [ "$countdown" -gt 0 ]; do
        if read -rsn1 -t 1 key 2>/dev/null; then
            case "$key" in
                q|Q)
                    exit 0
                    ;;
                r|R)
                    break
                    ;;
                l|L)
                    if [ "$LESS_MODE" = true ]; then
                        LESS_MODE=false
                    else
                        LESS_MODE=true
                    fi
                    clear
                    break
                    ;;
                c|C)
                    if [ "$SHOW_CPU" = true ]; then
                        SHOW_CPU=false
                    else
                        SHOW_CPU=true
                    fi
                    clear
                    break
                    ;;
                p|P)
                    if [ "$PIHOLE_MODE" = true ]; then
                        PIHOLE_MODE=false
                    else
                        PIHOLE_MODE=true
                    fi
                    clear
                    break
                    ;;
            esac
        fi
        countdown=$(( countdown - 1 ))
    done
done
