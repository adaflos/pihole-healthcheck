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
#   JSON Output:       ./healthcheck --json   (structured JSON payload)
#   No Color:          ./healthcheck -m       (plain output, no ANSI)
#   Self-Update:       ./healthcheck -u
#
# Controls:
#   q / Ctrl-C   Quit              d   Toggle Docker panel
#   r            Force refresh      n   Toggle Network diagnostics
#   l            Toggle log-only    s   Toggle Storage performance
#   c            Toggle CPU info    t   Toggle Thermal sensors
#   p            Toggle Pi-hole     a   Toggle Security audit
# ==============================================================================

VERSION="1.3.2"
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
SHOW_DOCKER=false
SHOW_NETWORK=false
SHOW_STORAGE_PERF=false
SHOW_THERMAL=false
SHOW_SECURITY=false
JSON_MODE=false
NO_COLOR=false
LOG_FILE=""
WEBHOOK_URL=""

# --- Thresholds ---
TEMP_LIMIT=75
RAM_LIMIT=85
DISK_LIMIT=90

# --- Throughput tracking (must persist between frames) ---
_prev_rx_bytes=0
_prev_tx_bytes=0
_prev_net_ts=0
_prev_read_sectors=0
_prev_write_sectors=0
_prev_disk_ts=0

# --- Auto-detect Pi-hole ---
if command -v pihole &>/dev/null || systemctl list-unit-files pihole-FTL.service &>/dev/null; then
    PIHOLE_MODE=true
else
    PIHOLE_MODE=false
fi

# --- Auto-detect container engine ---
CONTAINER_ENGINE=""
if command -v docker &>/dev/null && { [ -S /var/run/docker.sock ] || systemctl is-active --quiet docker 2>/dev/null; }; then
    CONTAINER_ENGINE="docker"
elif command -v podman &>/dev/null; then
    CONTAINER_ENGINE="podman"
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
        -m|--no-color)
            NO_COLOR=true
            shift
            ;;
        --json)
            JSON_MODE=true
            ONESHOT=true
            shift
            ;;
        --temp-limit)
            TEMP_LIMIT="$2"
            shift 2
            ;;
        --ram-limit)
            RAM_LIMIT="$2"
            shift 2
            ;;
        --disk-limit)
            DISK_LIMIT="$2"
            shift 2
            ;;
        --webhook)
            WEBHOOK_URL="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -u|--update)
            do_update
            ;;
        -v|--version)
            echo "healthcheck v${VERSION}"
            exit 0
            ;;
        -h|--help)
            cat <<'HELPEOF'
Usage: healthcheck [OPTIONS]

Modes:
  -r, --regular        System-only mode (no Pi-hole checks)
  -p, --pihole         Force Pi-hole mode (auto-detected by default)
  -l, --less           Log-only mode (minimal vitals + logs)
  -1, --once           Run once and exit (no interactive loop)
  --json               Output structured JSON and exit

Options:
  -n, --interval N     Refresh every N seconds (default: 1)
  -m, --no-color       Disable ANSI colors (for piping or plain terminals)
  --temp-limit N       CPU temp warning threshold in °C (default: 75)
  --ram-limit N        RAM usage warning threshold in % (default: 85)
  --disk-limit N       Disk usage warning threshold in % (default: 90)
  --webhook URL        Send alerts to webhook when thresholds are breached
  --log-file PATH      Append JSON snapshots to file on each refresh
  -u, --update         Check for updates and install latest version
  -v, --version        Show version and exit

Interactive Controls:
  q / Ctrl-C   Quit              d   Toggle Docker panel
  r            Force refresh      n   Toggle Network diagnostics
  l            Toggle log-only    s   Toggle Storage performance
  c            Toggle CPU info    t   Toggle Thermal sensors
  p            Toggle Pi-hole     a   Toggle Security audit
HELPEOF
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- Apply no-color mode ---
if [ "$NO_COLOR" = true ]; then
    GREEN="" YELLOW="" RED="" CYAN="" BLUE="" PURPLE="" BOLD="" DIM="" NC=""
fi

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
    echo -e " ${DIM}View: ${NC}${mode_label}  ${DIM}│  Scope: ${NC}${pihole_label}  ${DIM}│  Refresh: ${NC}${REFRESH}s  ${DIM}│  ${NC}${BOLD}q${NC}${DIM}uit ${NC}${BOLD}r${NC}${DIM}efresh ${NC}${BOLD}l${NC}${DIM}og ${NC}${BOLD}c${NC}${DIM}pu ${NC}${BOLD}p${NC}${DIM}ihole ${NC}${BOLD}d${NC}${DIM}ocker ${NC}${BOLD}n${NC}${DIM}et ${NC}${BOLD}s${NC}${DIM}tor ${NC}${BOLD}t${NC}${DIM}herm ${NC}${BOLD}a${NC}${DIM}udit${NC}"
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
    if [ "$pct" -gt 50 ]; then color=$YELLOW; fi
    if [ "$pct" -gt 75 ]; then color=$RED; fi

    bar+="${color}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    bar+="${NC}${DIM}"
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="${NC}"

    echo -e "[${bar}] ${pct}%"
}

# ==============================================================================
# CHECK FUNCTIONS
# ==============================================================================

# --- 1. Hardware & Thermal Engine ---
check_hardware() {
    print_section "HARDWARE & THERMAL METRICS"

    if command -v vcgencmd &>/dev/null; then
        temp_raw=$(vcgencmd measure_temp | awk -F'=' '{print $2}' | tr -d "'C")
        temp_int=${temp_raw%.*}
        freq_raw=$(vcgencmd measure_clock arm | awk -F'=' '{print $2}')
        freq_raw=${freq_raw:-0}
        freq_mhz=$(( freq_raw / 1000000 ))

        if [ "$temp_int" -lt "$TEMP_LIMIT" ]; then
            print_status "CPU Temp" "OK" "${temp_raw}°C (${freq_mhz} MHz)"
        elif [ "$temp_int" -lt $(( TEMP_LIMIT + 10 )) ]; then
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
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp_raw=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
        temp_int=${temp_raw%.*}
        if [ "$temp_int" -lt "$TEMP_LIMIT" ]; then
            print_status "CPU Temp" "OK" "${temp_raw}°C"
        elif [ "$temp_int" -lt $(( TEMP_LIMIT + 10 )) ]; then
            print_status "CPU Temp" "WARN" "${temp_raw}°C (High)"
        else
            print_status "CPU Temp" "FAIL" "${temp_raw}°C (Critical)"
        fi
    fi

    ram_total=$(free -m | awk '/^Mem:/{print $2}')
    ram_used=$(free -m | awk '/^Mem:/{print $3}')
    ram_total=${ram_total:-1}
    ram_pct=$(( ram_used * 100 / ram_total ))
    ram_bar=$(draw_progress_bar "$ram_pct")

    if [ "$ram_pct" -lt "$RAM_LIMIT" ]; then
        print_status "RAM Usage" "OK" "${ram_used}MB / ${ram_total}MB ${ram_bar}"
    else
        print_status "RAM Usage" "WARN" "${ram_used}MB / ${ram_total}MB ${ram_bar} (High Memory Pressure)"
    fi

    failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
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

    while IFS= read -r line; do
        local mount dev size used avail pct
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')
        pct=${pct:-0}

        local bar status
        bar=$(draw_progress_bar "$pct")
        if [ "$pct" -lt "$DISK_LIMIT" ]; then
            status="OK"
        else
            status="WARN"
        fi
        print_status "${mount}" "$status" "${avail} free / ${size} ${bar}  ${DIM}(${dev})${NC}"
    done < <(df -h -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1')

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

# --- 2b. Storage Performance (toggled with 's') ---
check_storage_performance() {
    print_section "STORAGE PERFORMANCE & ARRAYS"

    # I/O Wait
    if [ -f /proc/stat ]; then
        local cpu_line iowait_val
        cpu_line=$(head -1 /proc/stat)
        iowait_val=$(echo "$cpu_line" | awk '{total=0; for(i=2;i<=NF;i++) total+=$i; if(total>0) printf "%.1f", $7*100/total; else print "0"}')
        local iow_int=${iowait_val%.*}
        if [ "${iow_int:-0}" -lt 5 ]; then
            print_status "I/O Wait" "OK" "${iowait_val}%"
        elif [ "${iow_int:-0}" -lt 20 ]; then
            print_status "I/O Wait" "WARN" "${iowait_val}% (Disk bottleneck possible)"
        else
            print_status "I/O Wait" "FAIL" "${iowait_val}% (High disk latency)"
        fi
    fi

    # Live Disk Throughput
    if [ -f /proc/diskstats ]; then
        local root_dev
        root_dev=$(df / | awk 'NR==2 {print $1}' | sed 's|/dev/||; s|[0-9]*$||; s|p$||')
        if [ -n "$root_dev" ]; then
            local read_sectors write_sectors now_ts
            read_sectors=$(awk -v dev="$root_dev" '$3==dev {print $6}' /proc/diskstats 2>/dev/null)
            write_sectors=$(awk -v dev="$root_dev" '$3==dev {print $10}' /proc/diskstats 2>/dev/null)
            now_ts=$(date +%s)

            read_sectors=${read_sectors:-0}
            write_sectors=${write_sectors:-0}

            if [ "$_prev_disk_ts" -gt 0 ] && [ "$now_ts" -gt "$_prev_disk_ts" ]; then
                local dt=$(( now_ts - _prev_disk_ts ))
                local dr=$(( (read_sectors - _prev_read_sectors) * 512 / 1024 / dt ))
                local dw=$(( (write_sectors - _prev_write_sectors) * 512 / 1024 / dt ))
                print_status "Disk Read" "OK" "${dr} KB/s"
                print_status "Disk Write" "OK" "${dw} KB/s"
            else
                print_status "Disk Throughput" "OK" "Measuring..."
            fi
        fi
    fi

    # S.M.A.R.T. Health (single smartctl call per drive, cached output)
    if command -v smartctl &>/dev/null; then
        local smart_devs
        smart_devs=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' | head -3)
        for dev in $smart_devs; do
            local smart_out
            smart_out=$(timeout 3 smartctl -H "/dev/$dev" 2>/dev/null)
            if [ -n "$smart_out" ]; then
                local smart_health
                smart_health=$(echo "$smart_out" | grep -i 'overall-health\|SMART Health Status' | awk -F: '{print $2}' | xargs)
                if [ -n "$smart_health" ]; then
                    if echo "$smart_health" | grep -iq 'passed\|ok'; then
                        print_status "S.M.A.R.T. ($dev)" "OK" "$smart_health"
                    else
                        print_status "S.M.A.R.T. ($dev)" "FAIL" "$smart_health"
                    fi
                fi
            fi
        done
    fi

    # RAID / ZFS / Btrfs
    if [ -f /proc/mdstat ]; then
        local md_status
        md_status=$(grep -c '\[.*_.*\]' /proc/mdstat 2>/dev/null)
        if [ "${md_status:-0}" -gt 0 ]; then
            print_status "MD RAID" "FAIL" "Degraded array detected"
        elif grep -q '^md' /proc/mdstat 2>/dev/null; then
            print_status "MD RAID" "OK" "All arrays healthy"
        fi
    fi

    if command -v zpool &>/dev/null; then
        local zpool_health
        zpool_health=$(zpool status -x 2>/dev/null)
        if echo "$zpool_health" | grep -q "all pools are healthy"; then
            print_status "ZFS Pools" "OK" "All pools healthy"
        elif [ -n "$zpool_health" ]; then
            print_status "ZFS Pools" "FAIL" "Degraded or faulted pool"
        fi
    fi

    if command -v btrfs &>/dev/null; then
        local btrfs_errs
        btrfs_errs=$(btrfs device stats / 2>/dev/null | awk '{sum+=$NF} END{print sum+0}')
        if [ "${btrfs_errs:-0}" -eq 0 ]; then
            print_status "Btrfs Health" "OK" "No device errors"
        else
            print_status "Btrfs Health" "WARN" "${btrfs_errs} error(s) detected"
        fi
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
        qtime=$(dig @127.0.0.1 google.com +time=1 +tries=1 | awk '/Query time:/ {print $4}')
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

    if ping -c 1 -W 1 1.1.1.1 &>/dev/null; then
        print_status "Public Internet" "OK" "Connected"
    else
        print_status "Public Internet" "FAIL" "Unreachable"
    fi
    echo ""
}

# --- 4b. Network Diagnostics (toggled with 'n') ---
check_network_diagnostics() {
    print_section "NETWORK & PORT DIAGNOSTICS"

    # Active Connections Summary
    if command -v ss &>/dev/null; then
        local estab listen tw
        estab=$(ss -t state established 2>/dev/null | tail -n +2 | wc -l)
        listen=$(ss -tln 2>/dev/null | tail -n +2 | wc -l)
        tw=$(ss -t state time-wait 2>/dev/null | tail -n +2 | wc -l)
        print_status "TCP Connections" "OK" "ESTAB: ${estab}  LISTEN: ${listen}  TIME_WAIT: ${tw}"

        # Port Listener Audit
        local listeners
        listeners=$(ss -tulpn 2>/dev/null | awk 'NR>1 {
            split($5, a, ":");
            port = a[length(a)];
            proc = $7;
            gsub(/.*"/, "", proc); gsub(/".*/, "", proc);
            if (port+0 > 0) printf "      %-8s %s\n", port, proc
        }' | sort -t' ' -k1 -n | head -8)
        if [ -n "$listeners" ]; then
            print_status "Listening Ports" "OK" "Top listeners:"
            echo -e "${DIM}${listeners}${NC}"
        fi
    fi

    # DNS Latency Matrix (parallel queries)
    if command -v dig &>/dev/null; then
        local dns_tmp
        dns_tmp=$(mktemp -d 2>/dev/null || mktemp -d -t hc_dns)

        dig @1.1.1.1 example.com +time=1 +tries=1 2>/dev/null | awk '/Query time:/ {print $4}' > "$dns_tmp/cf" &
        dig @8.8.8.8 example.com +time=1 +tries=1 2>/dev/null | awk '/Query time:/ {print $4}' > "$dns_tmp/go" &
        if [ "$PIHOLE_MODE" = true ]; then
            dig @127.0.0.1 example.com +time=1 +tries=1 2>/dev/null | awk '/Query time:/ {print $4}' > "$dns_tmp/ph" &
        fi
        wait

        local dns_results=""
        local cf_ms go_ms ph_ms
        cf_ms=$(cat "$dns_tmp/cf" 2>/dev/null); cf_ms=${cf_ms:-timeout}
        go_ms=$(cat "$dns_tmp/go" 2>/dev/null); go_ms=${go_ms:-timeout}
        dns_results="Cloudflare: ${cf_ms}ms  Google: ${go_ms}ms"
        if [ "$PIHOLE_MODE" = true ]; then
            ph_ms=$(cat "$dns_tmp/ph" 2>/dev/null); ph_ms=${ph_ms:-timeout}
            dns_results+="  Pi-hole: ${ph_ms}ms"
        fi
        rm -rf "$dns_tmp"
        print_status "DNS Latency" "OK" "$dns_results"
    fi

    # Live Network Throughput
    if [ -n "$main_iface" ] && [ -f /proc/net/dev ]; then
        local rx_bytes tx_bytes now_ts
        read -r rx_bytes tx_bytes <<< "$(awk -v iface="$main_iface" '$0 ~ iface":" {gsub(/.*:/, "", $0); print $1, $9}' /proc/net/dev)"
        now_ts=$(date +%s)

        rx_bytes=${rx_bytes:-0}
        tx_bytes=${tx_bytes:-0}

        if [ "$_prev_net_ts" -gt 0 ] && [ "$now_ts" -gt "$_prev_net_ts" ]; then
            local dt=$(( now_ts - _prev_net_ts ))
            local rx_rate=$(( (rx_bytes - _prev_rx_bytes) / 1024 / dt ))
            local tx_rate=$(( (tx_bytes - _prev_tx_bytes) / 1024 / dt ))

            local rx_unit="KB/s" tx_unit="KB/s"
            if [ "$rx_rate" -gt 1024 ]; then
                rx_rate=$(( rx_rate / 1024 ))
                rx_unit="MB/s"
            fi
            if [ "$tx_rate" -gt 1024 ]; then
                tx_rate=$(( tx_rate / 1024 ))
                tx_unit="MB/s"
            fi
            print_status "RX Throughput" "OK" "${rx_rate} ${rx_unit} (${main_iface})"
            print_status "TX Throughput" "OK" "${tx_rate} ${tx_unit} (${main_iface})"
        else
            print_status "Net Throughput" "OK" "Measuring..."
        fi
    fi
    echo ""
}

# --- 5. Docker / Container Health (toggled with 'd') ---
check_docker() {
    print_section "DOCKER & CONTAINER HEALTH"

    if [ -z "$CONTAINER_ENGINE" ]; then
        print_status "Container Engine" "WARN" "No Docker or Podman detected"
        echo ""
        return
    fi

    print_status "Container Engine" "OK" "${CONTAINER_ENGINE}"

    local running stopped unhealthy
    running=$($CONTAINER_ENGINE ps -q 2>/dev/null | wc -l)
    stopped=$($CONTAINER_ENGINE ps -aq --filter "status=exited" 2>/dev/null | wc -l)
    unhealthy=$($CONTAINER_ENGINE ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)

    local status="OK"
    [ "$unhealthy" -gt 0 ] && status="WARN"
    print_status "Containers" "$status" "Running: ${running}  Stopped: ${stopped}  Unhealthy: ${unhealthy}"

    # Restart loops
    local restarting
    restarting=$($CONTAINER_ENGINE ps --filter "status=restarting" --format '{{.Names}}' 2>/dev/null | head -3)
    if [ -n "$restarting" ]; then
        print_status "Restart Loops" "FAIL" "$(echo "$restarting" | tr '\n' ' ')"
    fi

    # Top 3 by memory (uses ps-based check, avoids slow docker stats)
    if [ "$running" -gt 0 ]; then
        local top_containers
        top_containers=$($CONTAINER_ENGINE ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | head -5)
        if [ -n "$top_containers" ]; then
            print_status "Running Containers" "OK" ""
            echo "$top_containers" | while IFS=$'\t' read -r name status; do
                printf "      ${DIM}%-25s %s${NC}\n" "$name" "$status"
            done
        fi
    fi
    echo ""
}

# --- 6. Thermal & Hardware Sensors (toggled with 't') ---
check_thermal_expanded() {
    print_section "THERMAL & HARDWARE SENSORS"

    # Drive Temperatures
    if command -v smartctl &>/dev/null; then
        local smart_devs
        smart_devs=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' | head -4)
        for dev in $smart_devs; do
            local drive_temp smart_out
            smart_out=$(timeout 3 smartctl -A "/dev/$dev" 2>/dev/null)
            drive_temp=$(echo "$smart_out" | awk '/Temperature_Celsius|Airflow_Temperature/ {print $10}' | head -1)
            if [ -z "$drive_temp" ]; then
                drive_temp=$(echo "$smart_out" | awk '/Temperature:/ {print $2}' | head -1)
            fi
            if [ -n "$drive_temp" ] && [ "$drive_temp" -gt 0 ] 2>/dev/null; then
                local dstat="OK"
                [ "$drive_temp" -gt 50 ] && dstat="WARN"
                [ "$drive_temp" -gt 60 ] && dstat="FAIL"
                print_status "Drive Temp ($dev)" "$dstat" "${drive_temp}°C"
            fi
        done
    fi

    # Fan Speeds
    if command -v sensors &>/dev/null; then
        local fans
        fans=$(sensors 2>/dev/null | grep -i 'fan' | grep -oP '\d+ RPM' | head -4)
        if [ -n "$fans" ]; then
            local i=1
            echo "$fans" | while read -r rpm; do
                print_status "Fan $i" "OK" "$rpm"
                i=$((i+1))
            done
        fi
    fi

    # Power / UPS / Battery
    if [ -d /sys/class/power_supply ]; then
        for ps_path in /sys/class/power_supply/*/; do
            local ps_name ps_type ps_status
            ps_name=$(basename "$ps_path")
            ps_type=$(cat "$ps_path/type" 2>/dev/null)
            ps_status=$(cat "$ps_path/status" 2>/dev/null)

            if [ "$ps_type" = "Battery" ]; then
                local capacity
                capacity=$(cat "$ps_path/capacity" 2>/dev/null)
                if [ -n "$capacity" ]; then
                    local bstat="OK"
                    [ "$capacity" -lt 20 ] && bstat="WARN"
                    [ "$capacity" -lt 5 ] && bstat="FAIL"
                    local bbar
                    bbar=$(draw_progress_bar "$capacity")
                    print_status "Battery ($ps_name)" "$bstat" "${ps_status} ${bbar}"
                fi
            fi
        done
    fi

    if command -v upsc &>/dev/null; then
        local ups_name
        ups_name=$(upsc -l 2>/dev/null | head -1)
        if [ -n "$ups_name" ]; then
            local ups_status ups_charge ups_runtime
            ups_status=$(upsc "$ups_name" ups.status 2>/dev/null)
            ups_charge=$(upsc "$ups_name" battery.charge 2>/dev/null)
            ups_runtime=$(upsc "$ups_name" battery.runtime 2>/dev/null)

            local ustat="OK"
            [ "$ups_status" != "OL" ] && ustat="WARN"
            print_status "UPS ($ups_name)" "$ustat" "Status: ${ups_status:-Unknown}"
            [ -n "$ups_charge" ] && print_status "UPS Battery" "OK" "${ups_charge}%  Runtime: ${ups_runtime:-?}s"
        fi
    fi
    echo ""
}

# --- 7. Security & System Audit (toggled with 'a') ---
check_security_audit() {
    print_section "SECURITY & SYSTEM AUDIT"

    # Firewall Status
    if command -v ufw &>/dev/null; then
        local ufw_out
        ufw_out=$(ufw status 2>/dev/null)
        if echo "$ufw_out" | head -1 | grep -qi "active"; then
            local rule_count
            rule_count=$(echo "$ufw_out" | grep -c "ALLOW\|DENY\|REJECT")
            print_status "Firewall (ufw)" "OK" "Active (${rule_count} rules)"
        else
            print_status "Firewall (ufw)" "WARN" "Inactive"
        fi
    elif command -v nft &>/dev/null; then
        local nft_rules
        nft_rules=$(nft list ruleset 2>/dev/null | grep -c "rule")
        if [ "${nft_rules:-0}" -gt 0 ]; then
            print_status "Firewall (nftables)" "OK" "${nft_rules} rules loaded"
        else
            print_status "Firewall (nftables)" "WARN" "No rules loaded"
        fi
    elif command -v iptables &>/dev/null; then
        local ipt_rules
        ipt_rules=$(iptables -L -n 2>/dev/null | grep -c "^[A-Z]")
        print_status "Firewall (iptables)" "OK" "${ipt_rules:-0} chain(s)"
    else
        print_status "Firewall" "WARN" "No firewall detected"
    fi

    # Fail2ban (single status call)
    if command -v fail2ban-client &>/dev/null; then
        local f2b_output jails
        f2b_output=$(fail2ban-client status 2>/dev/null)
        if [ -n "$f2b_output" ]; then
            jails=$(echo "$f2b_output" | grep "Number of jail" | awk '{print $NF}')
            print_status "Fail2ban" "OK" "${jails:-0} active jail(s)"
        fi
    fi

    # Pending Updates (uses cached file when available, avoids slow apt/dnf queries)
    if [ -f /var/lib/update-notifier/updates-available ]; then
        local updates
        updates=$(grep -oP '\d+(?= packages? can be updated)' /var/lib/update-notifier/updates-available 2>/dev/null | head -1)
        if [ "${updates:-0}" -gt 0 ]; then
            print_status "Pending Updates" "WARN" "${updates} package(s) upgradable"
        else
            print_status "Pending Updates" "OK" "System up to date"
        fi
    elif [ -f /var/lib/pacman/db.lck ] || command -v pacman &>/dev/null; then
        if command -v checkupdates &>/dev/null; then
            local updates
            updates=$(checkupdates 2>/dev/null | wc -l)
            if [ "${updates:-0}" -gt 0 ]; then
                print_status "Pending Updates" "WARN" "${updates} package(s) available"
            else
                print_status "Pending Updates" "OK" "System up to date"
            fi
        fi
    fi

    # Active User Sessions
    local active_users
    active_users=$(who 2>/dev/null | wc -l)
    if [ "${active_users:-0}" -gt 0 ]; then
        local user_list
        user_list=$(who 2>/dev/null | awk '{printf "%s(%s) ", $1, $5}' | xargs)
        print_status "Active Sessions" "OK" "${active_users} user(s): ${user_list}"
    else
        print_status "Active Sessions" "OK" "No active sessions"
    fi

    # Reboot required check (instant file check, no slow needrestart)
    if [ -f /var/run/reboot-required ]; then
        print_status "Reboot Required" "WARN" "System restart needed"
    fi
    echo ""
}

# --- 8. Logs & System Audit (Live Stream) ---
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

# ==============================================================================
# ASCII ANALOG CLOCK
# ==============================================================================

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

        for (i = 0; i < 120; i++) {
            a = i / 120.0 * 2 * pi - pi / 2
            px = int(cx + rx * cos(a) + 0.5)
            py = int(cy + ry * sin(a) + 0.5)
            if (px >= 0 && px < W && py >= 0 && py < H && t[py,px] == 0) {
                g[py,px] = "."; t[py,px] = 1
            }
        }

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

        ma = min / 60.0 * 2 * pi - pi / 2
        mch = lch(cos(ma), sin(ma))
        for (s = 0.1; s <= 0.82; s += 0.01) {
            mx = int(cx + rx * s * cos(ma) + 0.5)
            my = int(cy + ry * s * sin(ma) + 0.5)
            if (mx >= 0 && mx < W && my >= 0 && my < H)
                if (t[my,mx] <= 1) { g[my,mx] = mch; t[my,mx] = 5 }
        }

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
    [ "$NO_COLOR" = true ] && return

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

# ==============================================================================
# JSON OUTPUT
# ==============================================================================

output_json() {
    local hostname
    hostname=$(hostname)
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    local ram_total ram_used ram_pct
    ram_total=$(free -m | awk '/^Mem:/{print $2}')
    ram_used=$(free -m | awk '/^Mem:/{print $3}')
    ram_total=${ram_total:-1}
    ram_pct=$(( ram_used * 100 / ram_total ))

    local disk_usage disk_free
    disk_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    disk_usage=${disk_usage:-0}
    disk_free=$(df -h / | awk 'NR==2 {print $4}')

    local cpu_temp="null"
    if command -v vcgencmd &>/dev/null; then
        cpu_temp=$(vcgencmd measure_temp | awk -F'=' '{print $2}' | tr -d "'C")
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        cpu_temp=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
    fi

    local load1 load5 load15
    if [ -f /proc/loadavg ]; then
        read -r load1 load5 load15 _ _ < /proc/loadavg
    fi

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)

    local main_iface local_ip
    main_iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n1)
    local_ip=$(ip -4 addr show "$main_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

    local pihole_active="false"
    systemctl is-active --quiet pihole-FTL 2>/dev/null && pihole_active="true"

    local docker_running=0
    if [ -n "$CONTAINER_ENGINE" ]; then
        docker_running=$($CONTAINER_ENGINE ps -q 2>/dev/null | wc -l)
    fi

    cat <<ENDJSON
{
  "version": "${VERSION}",
  "hostname": "${hostname}",
  "timestamp": "${timestamp}",
  "hardware": {
    "cpu_temp_c": ${cpu_temp},
    "ram_total_mb": ${ram_total},
    "ram_used_mb": ${ram_used},
    "ram_percent": ${ram_pct},
    "load_1m": ${load1:-0},
    "load_5m": ${load5:-0},
    "load_15m": ${load15:-0},
    "failed_systemd_units": ${failed_units}
  },
  "storage": {
    "root_usage_percent": ${disk_usage},
    "root_free": "${disk_free}"
  },
  "network": {
    "interface": "${main_iface}",
    "local_ip": "${local_ip}"
  },
  "pihole": {
    "active": ${pihole_active}
  },
  "containers": {
    "engine": "${CONTAINER_ENGINE:-none}",
    "running": ${docker_running}
  }
}
ENDJSON
}

# ==============================================================================
# WEBHOOK ALERTS
# ==============================================================================

check_webhook_alerts() {
    [ -z "$WEBHOOK_URL" ] && return

    local alerts=""

    local ram_pct
    ram_pct=$(free | awk '/^Mem:/{total=$2; used=$3; if(total>0) printf "%d", used*100/total; else print "0"}')
    if [ "$ram_pct" -gt "$RAM_LIMIT" ]; then
        alerts+="RAM usage at ${ram_pct}% (limit: ${RAM_LIMIT}%)\\n"
    fi

    local disk_pct
    disk_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    disk_pct=${disk_pct:-0}
    if [ "$disk_pct" -gt "$DISK_LIMIT" ]; then
        alerts+="Disk usage at ${disk_pct}% (limit: ${DISK_LIMIT}%)\\n"
    fi

    if command -v vcgencmd &>/dev/null; then
        local temp
        temp=$(vcgencmd measure_temp | awk -F'=' '{print $2}' | tr -d "'C")
        local temp_int=${temp%.*}
        if [ "${temp_int:-0}" -gt "$TEMP_LIMIT" ]; then
            alerts+="CPU temp at ${temp}°C (limit: ${TEMP_LIMIT}°C)\\n"
        fi
    fi

    if ! touch /tmp/ro_test_check &>/dev/null; then
        alerts+="CRITICAL: Filesystem is READ-ONLY\\n"
    else
        rm -f /tmp/ro_test_check
    fi

    if [ -n "$alerts" ]; then
        local payload
        payload=$(printf '{"text":"⚠️ healthcheck alert on %s:\\n%s","content":"⚠️ healthcheck alert on %s:\\n%s"}' \
            "$(hostname)" "$alerts" "$(hostname)" "$alerts")
        if command -v curl &>/dev/null; then
            curl -s -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" &>/dev/null &
        elif command -v wget &>/dev/null; then
            wget -qO- --post-data="$payload" --header="Content-Type: application/json" "$WEBHOOK_URL" &>/dev/null &
        fi
    fi
}

# ==============================================================================
# THROUGHPUT STATE UPDATE (must run outside subshell)
# ==============================================================================

update_throughput_state() {
    local main_iface
    main_iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n1)

    # Network throughput state
    if [ -n "$main_iface" ] && [ -f /proc/net/dev ]; then
        local rx tx
        read -r rx tx <<< "$(awk -v iface="$main_iface" '$0 ~ iface":" {gsub(/.*:/, "", $0); print $1, $9}' /proc/net/dev)"
        _prev_rx_bytes=${rx:-0}
        _prev_tx_bytes=${tx:-0}
        _prev_net_ts=$(date +%s)
    fi

    # Disk throughput state
    if [ -f /proc/diskstats ]; then
        local root_dev
        root_dev=$(df / | awk 'NR==2 {print $1}' | sed 's|/dev/||; s|[0-9]*$||; s|p$||')
        if [ -n "$root_dev" ]; then
            local rs ws
            rs=$(awk -v dev="$root_dev" '$3==dev {print $6}' /proc/diskstats 2>/dev/null)
            ws=$(awk -v dev="$root_dev" '$3==dev {print $10}' /proc/diskstats 2>/dev/null)
            _prev_read_sectors=${rs:-0}
            _prev_write_sectors=${ws:-0}
            _prev_disk_ts=$(date +%s)
        fi
    fi
}

# ==============================================================================
# RENDER
# ==============================================================================

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
            [ "$SHOW_THERMAL" = true ] && check_thermal_expanded
            [ "$PIHOLE_MODE" = true ] && check_pihole_v6
            check_logs
        else
            check_hardware
            [ "$SHOW_CPU" = true ] && check_cpu_info
            [ "$SHOW_THERMAL" = true ] && check_thermal_expanded
            check_storage
            [ "$SHOW_STORAGE_PERF" = true ] && check_storage_performance
            [ "$PIHOLE_MODE" = true ] && check_pihole_v6
            check_network_security
            [ "$SHOW_NETWORK" = true ] && check_network_diagnostics
            [ "$SHOW_DOCKER" = true ] && check_docker
            [ "$SHOW_SECURITY" = true ] && check_security_audit
            check_logs
        fi
    )

    tput cup 0 0 2>/dev/null
    echo -e "$buffer"
    tput ed 2>/dev/null
    draw_clock_overlay

    # Update throughput state after display (outside subshell)
    update_throughput_state

    # Log to file if configured
    if [ -n "$LOG_FILE" ]; then
        output_json >> "$LOG_FILE" 2>/dev/null
    fi

    # Check webhook alerts
    check_webhook_alerts
}

# ==============================================================================
# JSON MODE
# ==============================================================================

if [ "$JSON_MODE" = true ]; then
    output_json
    exit 0
fi

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
                    LESS_MODE=$( [ "$LESS_MODE" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                c|C)
                    SHOW_CPU=$( [ "$SHOW_CPU" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                p|P)
                    PIHOLE_MODE=$( [ "$PIHOLE_MODE" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                d|D)
                    SHOW_DOCKER=$( [ "$SHOW_DOCKER" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                n|N)
                    SHOW_NETWORK=$( [ "$SHOW_NETWORK" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                s|S)
                    SHOW_STORAGE_PERF=$( [ "$SHOW_STORAGE_PERF" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                t|T)
                    SHOW_THERMAL=$( [ "$SHOW_THERMAL" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
                a|A)
                    SHOW_SECURITY=$( [ "$SHOW_SECURITY" = true ] && echo false || echo true )
                    clear
                    break
                    ;;
            esac
        fi
        countdown=$(( countdown - 1 ))
    done
done
