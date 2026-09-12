#!/usr/bin/env bash
# run_qemu_test.sh — Automated test runner for IPO_Boot_ROM in QEMU
#
# Arguments:
#   $1 = Path to ROM binary (e.g., build/bootrom.bin)

set -euo pipefail

ROM="${1:-build/bootrom.bin}"
EXPECTED="Firmware payload entry reached"
TIMEOUT_SECS=5

if [ ! -f "$ROM" ]; then
    echo "ERROR: ROM file '$ROM' does not exist!" >&2
    exit 1
fi

echo "[test] Launching QEMU with -bios $ROM..."

LOGFILE=$(mktemp)
timeout -s KILL 3s qemu-system-i386 \
    -M pc \
    -bios "$ROM" \
    -display none \
    -serial stdio \
    -device isa-debug-exit,iobase=0x501,iosize=2 \
    -no-reboot \
    -no-shutdown < /dev/null > "$LOGFILE" 2>&1 || true

OUTPUT=$(cat "$LOGFILE")
rm -f "$LOGFILE"

echo "────────────────────────────────────────"
echo "QEMU Serial Output:"
echo "$OUTPUT"
echo "────────────────────────────────────────"

if echo "$OUTPUT" | grep -Fq "$EXPECTED"; then
    echo "✅ PASS: Boot_ROM -> Firmware handoff verified successfully!"
    exit 0
else
    echo "❌ FAIL: Expected marker '$EXPECTED' was not found in output!" >&2
    exit 1
fi
