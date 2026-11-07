#!/usr/bin/env bash
set -Eeuo pipefail

# Store the log beside this script, regardless of the caller's working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/health_log.txt"

read_cpu_counters() {
    awk '/^cpu / {
        total = 0
        for (i = 2; i <= NF; i++) total += $i
        idle = $5 + $6
        print total, idle
        exit
    }' /proc/stat
}

read -r cpu_total_before cpu_idle_before < <(read_cpu_counters)
sleep 1
read -r cpu_total_after cpu_idle_after < <(read_cpu_counters)

total_delta=$((cpu_total_after - cpu_total_before))
idle_delta=$((cpu_idle_after - cpu_idle_before))

if (( total_delta > 0 )); then
    cpu_usage=$(awk -v total="$total_delta" -v idle="$idle_delta" \
        'BEGIN { printf "%.1f", (total-idle)*100/total }')
else
    cpu_usage="N/A"
fi

memory_usage=$(awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { available = $2 }
    END {
        if (total > 0) printf "%.1f", (total-available)*100/total
        else print "N/A"
    }
' /proc/meminfo)

disk_usage=$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"

entry="[$timestamp] CPU: ${cpu_usage}% | Memory: ${memory_usage}% | Disk: ${disk_usage}%"
printf '%s\n' "$entry" | tee -a "$LOG_FILE"

if [[ "$disk_usage" =~ ^[0-9]+$ ]] && (( disk_usage > 80 )); then
    warning="[WARNING] Disk space high!"
    printf '%s\n' "$warning" | tee -a "$LOG_FILE"
fi
