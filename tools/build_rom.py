#!/usr/bin/env python3
"""Assemble a flashable boot ROM image.

Layout for FLASH_SIZE >= 128 KiB (e.g. 128 KiB, 256 KiB, 512 KiB, 1 MiB, 4 MiB, 16 MiB):
  - [0x00000000 .. romstage_size)     : 32-bit Flash-XIP romstage (phys 4 GiB - FLASH_SIZE)
  - [romstage_end .. fw_offset)       : Optional extended firmware (>56 KiB..64 KiB - 16 B)
  - [flash_size - 65536 .. -8192)     : 56 KiB firmware bank slot (0xF000:0000..0xDFFF)
  - [flash_size - 8192 .. -16)        : 8 KiB 16-bit bootblock init.bin (0xF000:0xE000..0xFFEF)
  - [flash_size - 16 .. flash_size)   : 16 B hardware reset vector reset.bin (0xFFFFFFF0)
"""

import argparse
import os
import struct
import sys


def parse_size(val):
    if isinstance(val, int):
        return val
    s = str(val).strip()
    if s.lower().startswith("0x"):
        return int(s, 16)

    s_upper = s.upper()
    multipliers = [
        ("GIB", 1024**3), ("MIB", 1024**2), ("KIB", 1024), ("B", 1),
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
    parser = argparse.ArgumentParser(description="Build IPO_Boot_ROM binary image")
    parser.add_argument("flash_size", help="Flash chip size (e.g. 128KiB, 256KiB, 4MiB)")
    parser.add_argument("fw_bin", help="Firmware payload binary")
    parser.add_argument("init_bin", help="16-bit Bootblock init.bin")
    parser.add_argument("reset_bin", help="16-byte x86 reset.bin")
    parser.add_argument("output_rom", help="Output bootrom.bin path")
    parser.add_argument("--romstage", default=None, help="Optional 32-bit Flash-XIP romstage.bin")
    args = parser.parse_args()

    try:
        flash_size = parse_size(args.flash_size)
    except Exception as e:
        print(f"ERROR: Invalid FLASH_SIZE '{args.flash_size}': {e}", file=sys.stderr)
        sys.exit(1)

    if flash_size < 131072 and args.romstage:
        print(f"ERROR: FLASH_SIZE must be >= 128KiB when 32-bit romstage is enabled, got {flash_size} B", file=sys.stderr)
        sys.exit(1)
    if flash_size < 65536:
        print(f"ERROR: FLASH_SIZE must be at least 64KiB, got {flash_size} B", file=sys.stderr)
        sys.exit(1)
    if flash_size % 16 != 0:
        print(f"ERROR: FLASH_SIZE ({flash_size}) must be 16-byte aligned!", file=sys.stderr)
        sys.exit(1)

    flash_phys_base = 0x100000000 - flash_size
    fw_offset = flash_size - 65536
    init_offset = flash_size - 8192
    reset_offset = flash_size - 16
    bank_fw_max = init_offset - fw_offset  # 56 KiB

    rom = bytearray(b"\xFF" * flash_size)

    # Place 32-bit Flash-XIP romstage at offset 0 (phys 4 GiB - flash_size)
    romstage_paddr = 0
    romstage_size = 0
    romstage_end = 0
    if args.romstage:
        if not os.path.isfile(args.romstage):
            print(f"ERROR: romstage binary '{args.romstage}' not found!", file=sys.stderr)
            sys.exit(1)
        with open(args.romstage, "rb") as f:
            rs_data = f.read()
        romstage_size = len(rs_data)
        if romstage_size > fw_offset:
            print(f"ERROR: romstage ({romstage_size} bytes) exceeds space below 0xFFFF0000 ({fw_offset} bytes)!", file=sys.stderr)
            sys.exit(1)
        rom[0:romstage_size] = rs_data
        romstage_paddr = flash_phys_base
        romstage_end = (romstage_size + 15) & ~15
        print(f"[build_rom] Embedding 32-bit romstage: {args.romstage} ({romstage_size} bytes) at phys 0x{romstage_paddr:08X}")

    # Place firmware payload (<=56 KiB in 0xF000 bank, or >56 KiB..64 KiB - 16 B staged)
    fw_ext_paddr = 0
    fw_ext_size = 0
    if args.fw_bin and os.path.isfile(args.fw_bin):
        with open(args.fw_bin, "rb") as f:
            fw_data = f.read()
        fw_size = len(fw_data)
        if fw_size > 65520:
            if fw_size >= 65536 and fw_data[fw_size - 65536 : fw_size - 65536 + 12] in (b"IPO_Firmware", b"IPO_Boot_ROM"):
                print(f"[build_rom] Extracting 56 KiB bank payload from full ROM image '{args.fw_bin}'...")
                fw_data = fw_data[fw_size - 65536 : fw_size - 8192]
                fw_size = len(fw_data)
            else:
                print(f"ERROR: Firmware '{args.fw_bin}' ({fw_size} B) exceeds 65520 B shadow limit!", file=sys.stderr)
                sys.exit(1)

        if fw_size <= bank_fw_max:
            rom[fw_offset:fw_offset + fw_size] = fw_data
            print(f"[build_rom] Embedding Firmware in bank: {args.fw_bin} ({fw_size} B) at offset 0x{fw_offset:08X}")
        else:
            if romstage_end + fw_size > fw_offset:
                print(f"ERROR: Not enough Flash space below 0xFFFF0000 for extended firmware ({fw_size} B)!", file=sys.stderr)
                sys.exit(1)
            rom[romstage_end:romstage_end + fw_size] = fw_data
            # Mirror magic header into the 0xF000 bank slot
            rom[fw_offset:fw_offset + 12] = fw_data[:12]
            fw_ext_paddr = flash_phys_base + romstage_end
            fw_ext_size = fw_size
            print(f"[build_rom] Embedding Extended Firmware (>56 KiB): {args.fw_bin} ({fw_size} B) at phys 0x{fw_ext_paddr:08X}")
    else:
        print(f"[build_rom] No Firmware binary provided; leaving bank slot as 0xFF")

    # Place 16-bit bootblock and patch IPORST01 descriptor
    if not os.path.isfile(args.init_bin):
        print(f"ERROR: Init binary '{args.init_bin}' not found!", file=sys.stderr)
        sys.exit(1)
    with open(args.init_bin, "rb") as f:
        init_data = bytearray(f.read())
    init_size = len(init_data)
    max_init_size = reset_offset - init_offset
    if init_size > max_init_size:
        print(f"ERROR: Bootblock init ({init_size} bytes) overflows 8 KiB slot (max {max_init_size} bytes)!", file=sys.stderr)
        sys.exit(1)

    hdr_idx = init_data.find(b"IPORST01")
    if hdr_idx < 0:
        print("ERROR: init.bin missing 'IPORST01' patch header!", file=sys.stderr)
        sys.exit(1)
    struct.pack_into("<IIII", init_data, hdr_idx + 8,
                     romstage_paddr, romstage_size, fw_ext_paddr, fw_ext_size)

    rom[init_offset:init_offset + init_size] = init_data
    print(f"[build_rom] Embedding Bootblock: {args.init_bin} ({init_size} bytes) at offset 0x{init_offset:08X}")

    # Place 16 B reset vector at the end of ROM
    if not os.path.isfile(args.reset_bin):
        print(f"ERROR: Reset binary '{args.reset_bin}' not found!", file=sys.stderr)
        sys.exit(1)
    with open(args.reset_bin, "rb") as f:
        reset_data = f.read()
    if len(reset_data) != 16:
        print(f"ERROR: reset.bin must be 16 bytes, got {len(reset_data)}!", file=sys.stderr)
        sys.exit(1)
    rom[reset_offset:reset_offset + 16] = reset_data
    print(f"[build_rom] Embedding Reset Vector: {args.reset_bin} (16 bytes) at offset 0x{reset_offset:08X}")

    os.makedirs(os.path.dirname(os.path.abspath(args.output_rom)), exist_ok=True)
    with open(args.output_rom, "wb") as f:
        f.write(rom)

    print(f"[build_rom] ROM generated: {args.output_rom} ({len(rom)} B / {len(rom)/1024:.1f} KiB)")


if __name__ == "__main__":
    main()
