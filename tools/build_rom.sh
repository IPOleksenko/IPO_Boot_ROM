#!/usr/bin/env bash
# build_rom.sh — Constructs a fixed-size ROM binary (256KB) for IPO_Boot_ROM
#
# Arguments:
#   $1 = ROMSIZE       (e.g., 262144)
#   $2 = FW_OFFSET     (e.g., 196608 = 0x30000)
#   $3 = FW_BIN        (path to firmware binary, optional)
#   $4 = INIT_OFFSET   (e.g., 261120 = 0x3F800)
#   $5 = INIT_BIN      (path to init.bin)
#   $6 = RESET_BIN     (path to reset.bin)
#   $7 = OUTPUT_ROM    (path to output file)

set -euo pipefail

ROMSIZE="${1:-262144}"
FW_OFFSET="${2:-196608}"
FW_BIN="${3:-}"
INIT_OFFSET="${4:-260096}"
INIT_BIN="${5}"
RESET_BIN="${6}"
OUTPUT_ROM="${7}"

mkdir -p "$(dirname "$OUTPUT_ROM")"

# 1. Initialize full ROM image filled with 0xFF (flash erased state)
python3 -c "import sys; sys.stdout.buffer.write(b'\xFF' * $ROMSIZE)" > "$OUTPUT_ROM"

# 2. Embed Firmware payload at FW_OFFSET (if provided)
if [ -n "$FW_BIN" ] && [ -f "$FW_BIN" ]; then
    fw_size=$(stat -c %s "$FW_BIN")
    echo "[build_rom] Embedding Firmware: $FW_BIN ($fw_size bytes) at offset $FW_OFFSET (0x$(printf '%X' $FW_OFFSET))"
    dd if="$FW_BIN" of="$OUTPUT_ROM" bs=1 seek="$FW_OFFSET" conv=notrunc status=none
else
    echo "[build_rom] No Firmware binary provided; leaving slot at offset $FW_OFFSET as 0xFF"
fi

# 3. Embed Boot_ROM init code at INIT_OFFSET
init_size=$(stat -c %s "$INIT_BIN")
echo "[build_rom] Embedding Boot_ROM init: $INIT_BIN ($init_size bytes) at offset $INIT_OFFSET (0x$(printf '%X' $INIT_OFFSET))"
dd if="$INIT_BIN" of="$OUTPUT_ROM" bs=1 seek="$INIT_OFFSET" conv=notrunc status=none

# 4. Embed Reset Vector (last 16 bytes of ROM)
RESET_OFFSET=$(( ROMSIZE - 16 ))
reset_size=$(stat -c %s "$RESET_BIN")
if [ "$reset_size" -ne 16 ]; then
    echo "ERROR: reset.bin must be exactly 16 bytes, got $reset_size bytes!" >&2
    exit 1
fi
echo "[build_rom] Embedding Reset Vector: $RESET_BIN (16 bytes) at offset $RESET_OFFSET (0x$(printf '%X' $RESET_OFFSET))"
dd if="$RESET_BIN" of="$OUTPUT_ROM" bs=1 seek="$RESET_OFFSET" conv=notrunc status=none

# 5. Verify final ROM size
final_size=$(stat -c %s "$OUTPUT_ROM")
if [ "$final_size" -ne "$ROMSIZE" ]; then
    echo "ERROR: Final ROM size mismatch! Expected $ROMSIZE, got $final_size" >&2
    exit 1
fi

echo "[build_rom] ROM successfully generated: $OUTPUT_ROM ($final_size bytes)"
