# IPO_Boot_ROM Contract & Architecture Specification

## 1. Overview
`IPO_Boot_ROM` is an independent, bare-metal x86 Boot ROM that serves as the root of the system boot chain. It executes immediately from the CPU hardware reset vector without requiring any BIOS, firmware, or prior initialization.

It supports physical x86 motherboards (Intel i440FX and Q35 chipsets) as well as QEMU emulation.

```
+-------------------------------------------------------------+
| x86 Hardware Reset (CS:IP = F000:FFF0, Phys: 0xFFFFFFF0)    |
+-------------------------------------------------------------+
                              |
                              v jmp far 0xF000:0x8000
+-------------------------------------------------------------+
| IPO_Boot_ROM (ROM segment 0xF000, offset 0x8000)           |
| Phase 1: Cache-as-RAM (CAR) setup via MTRRs (no DRAM yet)   |
| Phase 2: Chipset Detection (i440FX vs Q35 via PCI probe)    |
| Phase 3: Memory Reference Code (MRC) DRAM controller init   |
| Phase 4: CAR teardown, system stack to DRAM (0x0000:0x7000) |
| Phase 5: 8259A PIC cascade init & 8254 PIT (18.2 Hz) timer  |
| Phase 6: COM1 (0x3F8) serial initialization                 |
| Phase 7: Shadow ROM: copy 64KB ROM -> DRAM via PAM          |
| Phase 8: PAM Lock: write-protect 0xF0000-0xFFFFF as Read-Only|
| Phase 9: Validate 4-byte magic 'IPOF' (0x464F5049)          |
| Phase 10: Far jump to Firmware: jmp 0xF000:0x0004           |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
| Firmware Payload (Shadow RAM segment 0xF000, offset 0x0004) |
+-------------------------------------------------------------+
```

## 2. ROM Layout (256 KB)

| File Offset | Linear Phys (High Alias) | Real-Mode Alias | Component / Content |
| :--- | :--- | :--- | :--- |
| `0x00000` | `0xFFFC0000` | — | Unused padding (`0xFF`) |
| `0x30000` | `0xFFFF0000` | `0xF000:0x0000` | **Firmware Payload Slot** (up to 32 KB) |
| `0x38000` | `0xFFFF8000` | `0xF000:0x8000` | **Boot_ROM Init Code** (`init.asm`, CAR, MRC, PIC, PIT, Chipset) |
| `0x3FFF0` | `0xFFFFFFF0` | `0xF000:0xFFF0` | **Reset Vector** (16 bytes, `jmp 0xF000:0x8000`) |

## 3. Reset Vector Mechanics
On x86 CPUs, after reset:
- `CS` selector has the visible value `0xF000`, but hidden base descriptor is `0xFFFF0000`.
- `IP` = `0xFFF0`.
- First instruction executed is at `0xFFFF0000 + 0xFFF0 = 0xFFFFFFF0` (file offset `ROMSIZE - 16`).

The reset vector executes:
```nasm
jmp 0xF000:0x8000
```
On both Intel i440FX and Q35 chipsets, PAM registers default to `0x00` at power-on reset, which routes read requests for `0xF0000–0xFFFFF` directly to SPI/ROM flash. This far jump reloads `CS` with base `0x000F0000`, allowing normal 16-bit real-mode execution within the conventional 1 MB memory address space while fetching directly from ROM.

## 4. Hardware Initialization Pipeline

1. **Cache-as-RAM (CAR):** Prior to memory controller initialization, physical DRAM cannot store data. The Boot ROM programs CPU MTRRs (`MSR 0x200`/`0x201`/`0x2FF`) to configure a 32 KB write-back cache region at `0x70000–0x77FFF`, providing an early stack (`SS:SP = 0x7000:0x8000`) entirely within CPU L1/L2 cache without evicting to DRAM.
2. **Chipset Detection:** Probes PCI configuration space at `0:0.0` (ports `0x0CF8`/`0x0CFC`) to detect Device ID:
   - `0x1237`: Intel i440FX (82441FX PMC)
   - `0x29C0`: Intel Q35 MCH
3. **Memory Reference Code (MRC):**
   - **i440FX:** Configures DRAM timing (`DRAMT` 0x68), DRAM row boundary registers (`DRB0`–`DRB7` 0x60–0x67), page size (`RPS` 0x74), and SDRAM controller command sequence (`SDRAMC` 0x76).
   - **Q35:** Initializes ICH9 SMBus controller (`PCI 0:1F.3`), probes DIMM SPD EEPROMs over I2C, calculates module capacities, and programs Q35 memory registers (`DRC` 0x7C, `TOM` 0xA0, `TOLUD` 0xB0).
4. **CAR Teardown:** Flushes cache with `wbinvd`, restores normal MTRR caching, and relocates stack to working DRAM at `0x0000:0x7000`.
5. **Interrupt & Timer Initialization:**
   - **PIC 8259A:** Initialized in cascade mode. Master mapped to `INT 08h–0Fh`, Slave mapped to `INT 70h–77h`. IRQs masked except IRQ2 cascade.
   - **PIT 8254:** Channel 0 configured in Mode 2 (Rate Generator) at 18.2 Hz (divisor `0xFFFF`). Channel 1 configured for DRAM refresh.
6. **Shadow RAM & PAM Protection:**
   - Opens PAM0 bits [5:4] to enable writes to DRAM while reads come from ROM.
   - Copies full 64 KB from ROM `0xF000:0x0000` to DRAM at `0xF000:0x0000`.
   - Locks PAM0 bits [5:4] to Read-Only (`RE=1, WE=0`). All subsequent instruction fetches come from high-speed DRAM shadow, while writes are protected from OS corruption.

## 5. Contract 2: Handover to Firmware Payload (Shadow RAM Mode)

| Register / Resource | Value at Handover | Notes |
| :--- | :--- | :--- |
| **CPU Mode** | 16-bit Real Mode | Standard real mode |
| **CS:IP** | `0xF000:0x0004` | Firmware entry point in Shadow RAM (after 4-byte magic) |
| **Magic Header** | `0xF000:0x0000` | Must contain `'I', 'P', 'O', 'F'` (`0x464F5049`) |
| **DS, ES** | `0x0000` | Conventional base segment |
| **SS:SP** | `0x0000:0x7000` | Safe stack in DRAM; does not collide with IVT/BDA (`0x000-0x4FF`) or MBR (`0x7C00-0x7DFF`) |
| **Interrupt Flag (IF)** | `0` (`cli`) | Interrupts disabled until Firmware sets up IVT |
| **Shadow RAM State** | `0xF0000–0xFFFFF` | Read-only DRAM shadow protected by PAM registers |
| **DRAM State** | Operational | Memory controller trained and fully active |
| **PIC / PIT State** | Operational | Cascaded PIC and 18.2 Hz system timer ready |

## 6. Verification & Testing
- `make`: Compiles `build/bootrom.bin` (standalone test image with embedded stub firmware) and `build/bootrom_template.bin` (image with empty firmware slot for system integration).
- `make test`: Executes QEMU headless with `-bios build/bootrom.bin -display none -serial stdio` and verifies that the firmware stub receives control and logs to COM1.
