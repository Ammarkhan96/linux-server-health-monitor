#!/usr/bin/env bash

set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MONITOR="$PROJECT_DIR/scripts/monitor.sh"
CONFIG="$PROJECT_DIR/config/monitor.conf"

TEMP_CONFIG="$(mktemp)"
cp "$CONFIG" "$TEMP_CONFIG"

cleanup() {
    cp "$TEMP_CONFIG" "$CONFIG"
    rm -f "$TEMP_CONFIG"
}
trap cleanup EXIT

echo "[TEST 1] Monitor runs and produces a report"

if bash "$MONITOR"; then
    echo "PASS: Monitor completed without threshold violations."
else
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
        echo "PASS: Monitor ran and detected threshold warnings."
    else
        echo "FAIL: Monitor exited with code $rc."
        exit 1
    fi
fi

TODAY="$(date '+%Y-%m-%d')"
REPORT="$PROJECT_DIR/reports/health-$TODAY.log"

if [[ ! -s "$REPORT" ]]; then
    echo "FAIL: Report file is missing or empty."
    exit 1
fi

for expected in "Linux Server Health Report" "CPU Usage" \
                "Memory Usage" "Disk Usage" "System Load"; do
    if ! grep -q "$expected" "$REPORT"; then
        echo "FAIL: Report is missing: $expected"
        exit 1
    fi
done

echo "PASS: Report contains all required metrics."

echo
echo "[TEST 2] Threshold warnings are detected"

# Set all percentage thresholds to zero for a controlled test.
sed -i \
    -e 's/^CPU_THRESHOLD=.*/CPU_THRESHOLD=0/' \
    -e 's/^MEMORY_THRESHOLD=.*/MEMORY_THRESHOLD=0/' \
    -e 's/^DISK_THRESHOLD=.*/DISK_THRESHOLD=0/' \
    -e 's/^LOAD_THRESHOLD=.*/LOAD_THRESHOLD=0/' \
    "$CONFIG"

set +e
bash "$MONITOR" >/dev/null
rc=$?
set -e

if [[ "$rc" -ne 1 ]]; then
    echo "FAIL: Expected exit code 1, received $rc."
    exit 1
fi

echo "PASS: Threshold violations return exit code 1."
echo "All tests passed."
