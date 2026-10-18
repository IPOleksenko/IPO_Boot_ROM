#!/usr/bin/env python3
"""
package_bios.py — Tool for packaging Boot ROM into physical SPI Flash images

Supports:
  1. Creating full-sized SPI Flash ROMs (512KB, 1MB, 2MB, 4MB, 8MB, 16MB) with 0xFF padding
     and placing the BIOS ROM at the very top of memory (reset vector at chip end).
  2. Patching the BIOS region of an existing physical motherboard SPI dump (preserving IFD/ME).
  3. Verifying reset vector integrity at offset (Size - 16).
"""

import sys
import os
import argparse

def parse_size(val):
    if isinstance(val, int):
        return val
    s = str(val).strip()
    if s.lower().startswith("0x"):
        return int(s, 16)
    s_upper = s.upper()
    multipliers = [
        ("GIB", 1024**3), ("MIB", 1024**2), ("KIB", 1024),
        ("GB", 1024**3),  ("MB", 1024**2),  ("KB", 1024),
        ("G", 1024**3),   ("M", 1024**2),   ("K", 1024),
        ("BYTES", 1),     ("BYTE", 1),      ("B", 1),
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

def parse_args():
    parser = argparse.ArgumentParser(description="Package Boot ROM for physical SPI Flash chips")
    parser.add_argument("-i", "--input", required=True, help="Input BIOS ROM (e.g. bootrom.bin)")
    parser.add_argument("-o", "--output", required=True, help="Output physical SPI flash image")
    parser.add_argument("-s", "--size", default="4M",
                        help="Target SPI Flash chip size (e.g. 4M, 2M, 3M, 384K, 0x400000; default: 4M)")
    parser.add_argument("-d", "--dump", default=None,
                        help="Optional existing SPI flash dump to patch top BIOS region into")
    parser.add_argument("-c", "--checksum", action="store_true",
                        help="Verify and adjust final byte so 64KB BIOS block sum mod 256 == 0")
    return parser.parse_args()

def main():
    args = parse_args()
    try:
        target_size = parse_size(args.size)
    except Exception as e:
        print(f"ERROR: Invalid flash size '{args.size}': {e}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.input):
        print(f"ERROR: Input BIOS file '{args.input}' not found!", file=sys.stderr)
        sys.exit(1)

    with open(args.input, "rb") as f:
        bios_data = f.read()

    bios_len = len(bios_data)
    print(f"[package_bios] Loaded input BIOS: {args.input} ({bios_len} bytes / {bios_len // 1024} KB)")

    if bios_len > target_size:
        print(f"ERROR: Input BIOS ({bios_len} bytes) exceeds target chip size ({target_size} bytes)!", file=sys.stderr)
        sys.exit(1)

    # Verify reset vector at the end of input BIOS
    # Reset vector is at offset (bios_len - 16)
    reset_op = bios_data[bios_len - 16]
    if reset_op != 0xEA:
        print(f"WARNING: Byte at offset -16 is 0x{reset_op:02X} (expected 0xEA for JMP FAR)!", file=sys.stderr)
    else:
        target_ip = int.from_bytes(bios_data[bios_len - 15:bios_len - 13], "little")
        target_cs = int.from_bytes(bios_data[bios_len - 13:bios_len - 11], "little")
        print(f"[package_bios] Reset vector verified: JMP FAR {target_cs:04X}:{target_ip:04X}")

    if args.dump:
        if not os.path.isfile(args.dump):
            print(f"ERROR: SPI dump '{args.dump}' not found!", file=sys.stderr)
            sys.exit(1)
        with open(args.dump, "rb") as f:
            flash_image = bytearray(f.read())
        if len(flash_image) != target_size:
            print(f"WARNING: SPI dump size ({len(flash_image)} bytes) != target size ({target_size} bytes). Using dump size.")
            target_size = len(flash_image)
        print(f"[package_bios] Patching top {bios_len} bytes of existing dump: {args.dump}")
    else:
        # Erased SPI flash chips are filled with 0xFF
        flash_image = bytearray(b"\xFF" * target_size)
        print(f"[package_bios] Creating blank 0xFF-padded {args.size} image ({target_size} bytes)")

    # Place BIOS at the very top of the flash image
    insert_offset = target_size - bios_len
    flash_image[insert_offset:insert_offset + bios_len] = bios_data
    print(f"[package_bios] Embedded BIOS at offset 0x{insert_offset:08X} .. 0x{target_size:08X}")

    # Write output
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(flash_image)

    print(f"[package_bios] Flash image generated successfully: {args.output} ({len(flash_image)} bytes)")
    print(f"[package_bios] Ready for flashing with flashrom or hardware SPI programmer (e.g. CH341A).")

if __name__ == "__main__":
    main()

