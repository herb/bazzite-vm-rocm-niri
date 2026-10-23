#!/usr/bin/env bash

set -uo pipefail

interval="${1:-60}"
sleep_pid=""

stop_monitor() {
    if [[ -n "$sleep_pid" ]]; then
        kill "$sleep_pid" 2>/dev/null || true
    fi
    exit 0
}

trap stop_monitor TERM INT

sample() {
    {
        printf '\n=== build resource sample %s ===\n' "$(date -u +%FT%TZ)"
        awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ { print }' /proc/meminfo
        printf '%s\n' '--- swap devices ---'
        cat /proc/swaps
        printf '%s\n' '--- filesystem space ---'
        df -hP / /mnt
        printf '%s\n' '--- filesystem inodes ---'
        df -iP / /mnt
    }
}

while :; do
    sample
    sleep "$interval" &
    sleep_pid="$!"
    wait "$sleep_pid" || exit 0
    sleep_pid=""
done
