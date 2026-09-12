# IPO_Boot_ROM Contract & Architecture Specification

## 1. Overview
`IPO_Boot_ROM` is an independent, bare-metal x86 Boot ROM that serves as the root of the system boot chain. It executes immediately from the CPU hardware reset vector without requiring any BIOS, firmware, or prior initialization.

```
+-------------------------------------------------------------+
| x86 Hardware Reset (CS:IP = F000:FFF0, Phys: 0xFFFFFFF0)    |
+-------------------------------------------------------------+
                              |
                              v jmp far 0xF000:0xF800
+-------------------------------------------------------------+
| IPO_Boot_ROM (ROM segment 0xF000, offset 0xF800)           |
| - cli, flat segments, stack setup (SS:SP = 0x0000:0x7000)   |
| - COM1 (0x3F8) serial initialization                        |
| - Direct VGA (0xB8000) text output                          |
| - Copies 32KB Firmware payload from 0xF000:0000 -> 0x0800:0 |
| - Validates 4-byte magic signature 'IPOF' (0x464F5049)     |
| - Far jump to Firmware: jmp 0x0800:0x0004                   |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
| Firmware Payload (RAM segment 0x0800, offset 0x0004)        |
+-------------------------------------------------------------+
```

## 2. ROM Layout (256 KB)

| File Offset | Linear Phys (High Alias) | Real-Mode Alias | Component / Content |
| :--- | :--- | :--- | :--- |
| `0x00000` | `0xFFFC0000` | — | Unused padding (`0xFF`) |
| `0x30000` | `0xFFFF0000` | `0xF000:0x0000` | **Firmware Payload Slot** (up to 32 KB) |
| `0x3F800` | `0xFFFFF800` | `0xF000:0xF800` | **Boot_ROM Init Code** (`init.asm`) |
| `0x3FFF0` | `0xFFFFFFF0` | `0xF000:0xFFF0` | **Reset Vector** (16 bytes, `jmp 0xF000:0xF800`) |

## 3. Reset Vector Mechanics
On x86 CPUs, after reset:
- `CS` selector has the visible value `0xF000`, but hidden base descriptor is `0xFFFF0000`.
- `IP` = `0xFFF0`.
- First instruction executed is at `0xFFFF0000 + 0xFFF0 = 0xFFFFFFF0` (file offset `ROMSIZE - 16`).

The reset vector executes:
```nasm
jmp 0xF000:0xF800
```
This far jump reloads `CS` with base `0x000F0000`, allowing normal 16-bit real-mode execution within the conventional 1 MB memory address space.

## 4. Contract 2: Handover to Firmware Payload

| Register / Resource | Value at Handover | Notes |
| :--- | :--- | :--- |
| **CPU Mode** | 16-bit Real Mode | Standard real mode |
| **CS:IP** | `0x0800:0x0004` | Firmware entry point (immediately after 4-byte magic) |
| **Magic Header** | `0x0800:0x0000` | Must contain `'I', 'P', 'O', 'F'` (`0x464F5049`) |
| **DS, ES** | `0x0000` | Conventional base segment |
| **SS:SP** | `0x0000:0x7000` | Safe stack growing downward; does not collide with IVT/BDA (`0x000-0x4FF`) or MBR (`0x7C00-0x7DFF`) |
| **Interrupt Flag (IF)** | `0` (`cli`) | Interrupts disabled until Firmware sets up IVT |
| **RAM Firmware Image** | `0x0800:0x0000` - `0x0800:0x7FFF` | 32 KB payload copied from ROM `0xF000:0x0000` |

## 5. Verification & Testing
- `make`: Compiles `build/bootrom.bin` (standalone test image with embedded stub firmware) and `build/bootrom_template.bin` (image with empty firmware slot for system integration).
- `make test`: Executes QEMU headless with `-bios build/bootrom.bin -display none -serial stdio` and verifies that the firmware stub receives control and logs to COM1.

