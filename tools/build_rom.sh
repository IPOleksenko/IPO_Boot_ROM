#!/usr/bin/env python3
"""
build_rom.sh — Constructs a single fixed-size Boot ROM binary for physical hardware and emulation.
Supports any standard or non-standard flash chip sizes (64K, 128K, 256K, 384K, 512K, 1M, 1.5M, 2M, 3M, 4M, 5M, 8M, 12M, 16M, hex, bytes, etc.).
"""

import sys
import os

def parse_size(val):
    """
    Parses any flash size string (standard or non-standard) into byte count.
    Supports:
      - Units: B, K, KB, KiB, M, MB, MiB, G, GB, GiB (case-insensitive)
      - Non-power-of-two / non-standard sizes: 384K, 768K, 3M, 5M, 12M, etc.
      - Decimals / floats: 1.5M, 2.5MB, 0.5M, etc.
      - Hexadecimal: 0x400000, 0x100000, 0x80000, 0x10000, etc.
      - Plain integers: 4194304, 262144, 65536, etc.
    """
    if isinstance(val, int):
        return val
    s = str(val).strip()
    if s.lower().startswith("0x"):
        return int(s, 16)

    s_upper = s.upper()
    multipliers = [
        ("GIB", 1024**3),
        ("MIB", 1024**2),
        ("KIB", 1024),
        ("GB", 1024**3),
        ("MB", 1024**2),
        ("KB", 1024),
        ("G", 1024**3),
        ("M", 1024**2),
        ("K", 1024),
        ("BYTES", 1),
        ("BYTE", 1),
        ("B", 1),
    ]
    for suffix, mult in multipliers:
        if s_upper.endswith(suffix):
            num_part = s_upper[:-len(suffix)].strip()
            if "." in num_part:
                return int(float(num_part) * mult)
            return int(num_part) * mult

    if "." in s:
        return int(float(s))
    return int(s)

def main():
    if len(sys.argv) < 6:
        print(f"Usage: {sys.argv[0]} <FLASH_SIZE> <FW_BIN> <INIT_BIN> <RESET_BIN> <OUTPUT_ROM>", file=sys.stderr)
        sys.exit(1)

    flash_size_str = sys.argv[1]
    fw_bin = sys.argv[2]
    init_bin = sys.argv[3]
    reset_bin = sys.argv[4]
    output_rom = sys.argv[5]

    try:
        flash_size = parse_size(flash_size_str)
    except Exception as e:
        print(f"ERROR: Invalid FLASH_SIZE '{flash_size_str}': {e}", file=sys.stderr)
        sys.exit(1)

    if flash_size < 65536:
        print(f"ERROR: FLASH_SIZE must be at least 64K (65536 bytes) to accommodate firmware payload and bootrom init, got {flash_size}", file=sys.stderr)
        sys.exit(1)

    if flash_size % 16 != 0:
        print(f"ERROR: FLASH_SIZE ({flash_size}) must be aligned to at least 16 bytes (x86 reset vector requirement)!", file=sys.stderr)
        sys.exit(1)

    # Offsets relative to the end of the ROM image:
    fw_offset = flash_size - 65536
    init_offset = flash_size - 32768
    reset_offset = flash_size - 16

    rom = bytearray(b"\xFF" * flash_size)

    # 1. Embed Firmware payload (up to 32 KB)
    if fw_bin and os.path.isfile(fw_bin):
        with open(fw_bin, "rb") as f:
            fw_data = f.read()
        fw_size = len(fw_data)
        if fw_size > 32768:
            print(f"ERROR: Firmware payload '{fw_bin}' ({fw_size} bytes) exceeds 32 KB slot!", file=sys.stderr)
            sys.exit(1)
        rom[fw_offset:fw_offset + fw_size] = fw_data
        print(f"[build_rom] Embedding Firmware: {fw_bin} ({fw_size} bytes) at offset 0x{fw_offset:08X}")
    else:
        print(f"[build_rom] No Firmware binary provided; leaving slot at offset 0x{fw_offset:08X} as 0xFF")

    # 2. Embed Boot_ROM init code
    if not os.path.isfile(init_bin):
        print(f"ERROR: Init binary '{init_bin}' not found!", file=sys.stderr)
        sys.exit(1)
    with open(init_bin, "rb") as f:
        init_data = f.read()
    init_size = len(init_data)
    max_init_size = reset_offset - init_offset
    if init_size > max_init_size:
        print(f"ERROR: Boot_ROM init ({init_size} bytes) overflows into Reset Vector (max {max_init_size} bytes)!", file=sys.stderr)
        sys.exit(1)
    rom[init_offset:init_offset + init_size] = init_data
    print(f"[build_rom] Embedding Boot_ROM init: {init_bin} ({init_size} bytes) at offset 0x{init_offset:08X}")

    # 3. Embed Reset Vector (must be exactly 16 bytes)
    if not os.path.isfile(reset_bin):
        print(f"ERROR: Reset binary '{reset_bin}' not found!", file=sys.stderr)
        sys.exit(1)
    with open(reset_bin, "rb") as f:
        reset_data = f.read()
    reset_size = len(reset_data)
    if reset_size != 16:
        print(f"ERROR: reset.bin must be exactly 16 bytes, got {reset_size} bytes!", file=sys.stderr)
        sys.exit(1)
    if reset_data[0] != 0xEA:
        print(f"WARNING: Reset vector byte 0 is 0x{reset_data[0]:02X} (expected 0xEA for JMP FAR)!", file=sys.stderr)
    rom[reset_offset:reset_offset + 16] = reset_data
    print(f"[build_rom] Embedding Reset Vector: {reset_bin} (16 bytes) at offset 0x{reset_offset:08X}")

    # 4. Write output ROM
    os.makedirs(os.path.dirname(os.path.abspath(output_rom)), exist_ok=True)
    with open(output_rom, "wb") as f:
        f.write(rom)

    print(f"[build_rom] ROM successfully generated: {output_rom} ({len(rom)} bytes / {len(rom)/1024:.1f} KB / {len(rom)/(1024*1024):.2f} MB)")
    print(f"[build_rom] Ready for physical flashrom programmer or QEMU emulation.")

if __name__ == "__main__":
    main()
