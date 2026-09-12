# IPO_Boot_Rom

Independent bare-metal x86 Boot ROM (Reset Vector Initializer) for QEMU / PC-AT compatible machines.

## Architecture

- **Target Architecture**: x86 16-bit Real Mode
- **Reset Vector**: Placed at physical `0xFFFFFFF0` (file offset `0x3FFF0` in 256KB ROM).
- **Execution Flow**:
  1. CPU resets at `CS:IP = F000:FFF0`.
  2. Executes `jmp 0xF000:0xF800` to establish normal real-mode base `0xF0000`.
  3. Initializes segment registers, disables interrupts, configures stack at `0x0000:0x7000`.
  4. Initializes COM1 UART (`0x3F8`) and direct VGA text buffer (`0xB8000`).
  5. Copies up to 32 KB of the `IPO_Firmware` payload from ROM (`0xF000:0x0000`) into RAM (`0x0800:0x0000`).
  6. Validates the 4-byte signature `IPOF` (`0x464F5049`).
  7. Transfers control to `IPO_Firmware` via `jmp 0x0800:0x0004` under Contract 2.

## Build Commands

```bash
# Build ROM images
make

# Run automated verification test in QEMU
make test

# Clean artifacts
make clean
```

## Generated Artifacts

- `build/bootrom.bin`: Complete 256 KB ROM image including embedded stub firmware for isolated testing.
- `build/bootrom_template.bin`: 256 KB ROM image with an empty firmware payload slot (ready for integration with real `IPO_Firmware`).

## Documentation

See [docs/CONTRACT.md](docs/CONTRACT.md) for full interface, register states, and memory map specifications.