#!/usr/bin/env python3
"""
package_bios.py — Tool for packaging IPO_OS BIOS ROM into physical SPI Flash images

Supports:
  1. Creating full-sized SPI Flash ROMs (512KB, 1MB, 2MB, 4MB, 8MB, 16MB) with 0xFF padding
     and placing the BIOS ROM at the very top of memory (reset vector at chip end).
  2. Patching the BIOS region of an existing physical motherboard SPI dump (preserving IFD/ME).
  3. Verifying reset vector integrity at offset (Size - 16).
"""

import sys
import os
import argparse

VALID_FLASH_SIZES = {
    "256K": 256 * 1024,
    "512K": 512 * 1024,
    "1M":   1024 * 1024,
    "2M":   2 * 1024 * 1024,
    "4M":   4 * 1024 * 1024,
    "8M":   8 * 1024 * 1024,
    "16M":  16 * 1024 * 1024
}

def parse_args():
    parser = argparse.ArgumentParser(description="Package IPO_OS BIOS for physical SPI Flash chips")
    parser.add_argument("-i", "--input", required=True, help="Input 256KB BIOS ROM (e.g. full_bios.bin)")
    parser.add_argument("-o", "--output", required=True, help="Output physical SPI flash image")
    parser.add_argument("-s", "--size", default="4M", choices=list(VALID_FLASH_SIZES.keys()),
                        help="Target SPI Flash chip size (default: 4M)")
    parser.add_argument("-d", "--dump", default=None,
                        help="Optional existing SPI flash dump to patch top BIOS region into")
    return parser.parse_args()

def main():
    args = parse_args()
    target_size = VALID_FLASH_SIZES[args.size]

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

