#!/usr/bin/env bash

set -uo pipefail

# Resolve the project directory regardless of the current working directory.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_FILE="$PROJECT_DIR/config/monitor.conf"
LOG_DIR="$PROJECT_DIR/logs"
REPORT_DIR="$PROJECT_DIR/reports"

mkdir -p "$LOG_DIR" "$REPORT_DIR"

LOG_FILE="$LOG_DIR/monitor.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
REPORT_FILE="$REPORT_DIR/health-$(date '+%Y-%m-%d').log"

# Send unexpected script errors to the execution log.
trap 'rc=$?; printf "[%s] ERROR: Script failed near line %s (exit %s)\n" \
  "$(date "+%Y-%m-%d %H:%M:%S")" "$LINENO" "$rc" >> "$LOG_FILE"' ERR

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "ERROR: Cannot read configuration: $CONFIG_FILE" >&2
    exit 2
fi

# This configuration file is maintained by the project owner.
# Do not source configuration files from untrusted locations.
source "$CONFIG_FILE"

for command_name in awk df free getconf sleep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $command_name" >&2
        exit 2
    fi
done

for threshold in "$CPU_THRESHOLD" "$MEMORY_THRESHOLD" "$DISK_THRESHOLD"; do
    if ! [[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
       ! awk -v n="$threshold" 'BEGIN { exit !(n >= 0 && n <= 100) }'; then
        echo "ERROR: CPU, memory and disk thresholds must be between 0 and 100." >&2
        exit 2
    fi
done

if ! [[ "$LOAD_THRESHOLD" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
   ! awk -v n="$LOAD_THRESHOLD" 'BEGIN { exit !(n >= 0) }'; then
    echo "ERROR: LOAD_THRESHOLD must be a non-negative number." >&2
    exit 2
fi

if ! [[ "$CPU_SAMPLE_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: CPU_SAMPLE_SECONDS must be a positive integer." >&2
    exit 2
fi

if [[ ! -d "$DISK_PATH" ]]; then
    echo "ERROR: DISK_PATH is not a directory: $DISK_PATH" >&2
    exit 2
fi

# Calculate CPU utilization from two samples of /proc/stat.
read_cpu_counters() {
    awk '/^cpu / {
        idle = $5 + $6
        total = 0
        for (i = 2; i <= NF; i++) total += $i
        print total, idle
        exit
    }' /proc/stat
}

read -r TOTAL1 IDLE1 < <(read_cpu_counters)
sleep "$CPU_SAMPLE_SECONDS"
read -r TOTAL2 IDLE2 < <(read_cpu_counters)

TOTAL_DELTA=$((TOTAL2 - TOTAL1))
IDLE_DELTA=$((IDLE2 - IDLE1))

if (( TOTAL_DELTA <= 0 )); then
    echo "ERROR: Could not calculate CPU utilization." >&2
    exit 2
fi

CPU_USAGE="$(awk -v total="$TOTAL_DELTA" -v idle="$IDLE_DELTA" \
    'BEGIN { printf "%.2f", 100 * (total - idle) / total }')"

# Calculate memory utilization using MemAvailable.
read -r TOTAL_MEM AVAILABLE_MEM < <(
    awk '
        /^MemTotal:/     { total = $2 }
        /^MemAvailable:/ { available = $2 }
        END {
            if (total > 0 && available >= 0) print total, available
            else exit 1
        }
    ' /proc/meminfo
) || {
    echo "ERROR: Could not read memory information." >&2
    exit 2
}

USED_MEM=$((TOTAL_MEM - AVAILABLE_MEM))
MEMORY_USAGE="$(awk -v used="$USED_MEM" -v total="$TOTAL_MEM" \
    'BEGIN { printf "%.2f", 100 * used / total }')"

# Check the selected filesystem.
DISK_USAGE="$(df -P "$DISK_PATH" | awk 'END {
    gsub(/%/, "", $5)
    print $5
}')"

if ! [[ "$DISK_USAGE" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not determine disk usage for $DISK_PATH." >&2
    exit 2
fi

# Get the 1-minute load average and number of CPU cores.
LOAD_AVERAGE="$(awk '{ print $1 }' /proc/loadavg)"
CPU_CORES="$(getconf _NPROCESSORS_ONLN)"

if [[ ! "$CPU_CORES" =~ ^[1-9][0-9]*$ ]]; then
    CPU_CORES=1
fi

STATUS="HEALTHY"
WARNINGS=()

check_threshold() {
    local metric_name="$1"
    local metric_value="$2"
    local threshold="$3"

    if awk -v value="$metric_value" -v limit="$threshold" \
        'BEGIN { exit !(value >= limit) }'; then
        STATUS="WARNING"
        WARNINGS+=("$metric_name is at or above its threshold ($threshold)")
    fi
}

check_threshold "CPU usage" "$CPU_USAGE" "$CPU_THRESHOLD"
check_threshold "Memory usage" "$MEMORY_USAGE" "$MEMORY_THRESHOLD"
check_threshold "Disk usage" "$DISK_USAGE" "$DISK_THRESHOLD"
check_threshold "1-minute load average" "$LOAD_AVERAGE" "$LOAD_THRESHOLD"

# Build the report.
{
    echo "=================================================="
    echo "Linux Server Health Report"
    echo "Timestamp      : $TIMESTAMP"
    echo "Hostname       : $(hostname)"
    echo "Status         : $STATUS"
    echo "=================================================="
    printf "CPU Usage      : %s%% (threshold: %s%%)\n" \
        "$CPU_USAGE" "$CPU_THRESHOLD"
    printf "Memory Usage   : %s%% (threshold: %s%%)\n" \
        "$MEMORY_USAGE" "$MEMORY_THRESHOLD"
    printf "Disk Usage     : %s%% on %s (threshold: %s%%)\n" \
        "$DISK_USAGE" "$DISK_PATH" "$DISK_THRESHOLD"
    printf "System Load    : %s (threshold: %s; CPUs: %s)\n" \
        "$LOAD_AVERAGE" "$LOAD_THRESHOLD" "$CPU_CORES"
    echo

    if (( ${#WARNINGS[@]} > 0 )); then
        echo "Warnings:"
        for warning in "${WARNINGS[@]}"; do
            printf "  - %s\n" "$warning"
        done
    else
        echo "No threshold violations detected."
    fi

    echo "=================================================="
    echo
} | tee -a "$LOG_FILE" "$REPORT_FILE"

# A warning returns exit code 1, so other automation can detect it.
if [[ "$STATUS" == "WARNING" ]]; then
    exit 1
fi

exit 0
