#!/bin/bash

STATE_FILE="/tmp/cpu_limit_state"

CPU_PATH="/sys/devices/system/cpu"

enable_limit() {
    echo "== Enabling CPU limiter =="

    # save current governor + max freq (for restore)
    mkdir -p /tmp/cpu_limit_backup

    for cpu in $CPU_PATH/cpu[0-9]*; do
        [ -d "$cpu/cpufreq" ] || continue

        cpu_name=$(basename "$cpu")

        # backup governor
        if [ -f "$cpu/cpufreq/scaling_governor" ]; then
            cat "$cpu/cpufreq/scaling_governor" > /tmp/cpu_limit_backup/${cpu_name}_gov
        fi

        # backup max freq
        if [ -f "$cpu/cpufreq/scaling_max_freq" ]; then
            cat "$cpu/cpufreq/scaling_max_freq" > /tmp/cpu_limit_backup/${cpu_name}_max
        fi

        # set powersave
        echo powersave | sudo tee "$cpu/cpufreq/scaling_governor" > /dev/null

        # set min freq as max
        MIN=$(cat "$cpu/cpufreq/cpuinfo_min_freq")
        echo $MIN | sudo tee "$cpu/cpufreq/scaling_max_freq" > /dev/null
    done

    # disable turbo (intel)
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
    fi

    # disable extra cores (optional safety)
    for cpu in $CPU_PATH/cpu[1-9]*; do
        [ -f "$cpu/online" ] && echo 0 | sudo tee "$cpu/online" > /dev/null
    done

    echo "enabled" > "$STATE_FILE"
    echo "== CPU limiter ENABLED =="
}

disable_limit() {
    echo "== Restoring CPU settings =="

    for file in /tmp/cpu_limit_backup/*_gov; do
        cpu_name=$(basename "$file" _gov)
        [ -f "$CPU_PATH/$cpu_name/cpufreq/scaling_governor" ] && \
            cat "$file" | sudo tee "$CPU_PATH/$cpu_name/cpufreq/scaling_governor" > /dev/null
    done

    for file in /tmp/cpu_limit_backup/*_max; do
        cpu_name=$(basename "$file" _max)
        [ -f "$CPU_PATH/$cpu_name/cpufreq/scaling_max_freq" ] && \
            cat "$file" | sudo tee "$CPU_PATH/$cpu_name/cpufreq/scaling_max_freq" > /dev/null
    done

    # re-enable cores
    for cpu in $CPU_PATH/cpu[1-9]*; do
        [ -f "$cpu/online" ] && echo 1 | sudo tee "$cpu/online" > /dev/null
    done

    # re-enable turbo (if exists)
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
    fi

    rm -f "$STATE_FILE"
    rm -rf /tmp/cpu_limit_backup

    echo "== CPU limiter DISABLED (restored) =="
}

status() {
    if [ -f "$STATE_FILE" ]; then
        echo "CPU limiter: ENABLED"
    else
        echo "CPU limiter: DISABLED"
    fi
}

case "$1" in
    on)
        enable_limit
        ;;
    off)
        disable_limit
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {on|off|status}"
        ;;
esac
