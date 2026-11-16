# IPO_Boot_ROM

Independent bare-metal x86 Boot ROM (Reset Vector Initializer) for PC-AT compatible machines and physical hardware.

---

## 📋 Architecture & Boot Flow

`IPO_Boot_ROM` serves as the initial entry point for the bare-metal x86 boot process. It executes directly from the CPU hardware reset vector (`0xFFFFFFF0`, mapped to `0xF000:0xFFF0` in real mode) in a configurable Flash image (`FLASH_SIZE`, `4 MiB` by default).

```text
CPU Hardware Reset (CS:IP = F000:FFF0, Phys: 0xFFFFFFF0)
  │
  ▼
Jump to 8 KiB Real-Mode Bootblock (jmp 0xF000:0xE000)
  │
  ▼
Low-Level Hardware Initialization
  ├─ Warm-reset guard: Clear Intel host-bridge PAM0 shadow bits to map Flash ROM
  ├─ Phase 1: Register-only Southbridge LPC Flash/IO decode (PIIX / ICH / PCH)
  ├─ Phase 2: Cache-as-RAM (CAR) setup (32 KiB at 0x70000-0x77FFF; Intel/AMD MTRR or clean pre-MTRR/pre-CPUID bypass)
  ├─ Phase 3: Early Super I/O COM1 (0x3F8) & PS/2 KBC init (Winbond/Nuvoton/Fintek, SMSC, ITE at 0x2E/0x4E)
  ├─ Phase 4: 32-bit Flash-XIP romstage (unconstrained by 16-bit Real Mode segment):
  │           COM1 UART (115200 8N1), CPU brand & CAR logging, Host Bridge probe (0:0.0),
  │           SMBus SPD / CMOS / Cold-Boot DRAM probe & i440FX/BX or Q35 MRC setup
  ├─ Phase 5: Copy optional extended firmware (>56 KiB..65,520 B) from Flash to 0x2000:0000; switch stack to DRAM 0x0000:0x7C00 & CAR teardown
  ├─ Phase 6: Scratch RAM init (0x0500-0x05FF), Cascaded PIC & PIT init
  ├─ Phase 7: Stage 64 KiB ROM to 0x2000:0000 DRAM and copy into Shadow DRAM (0xF000:0000) via 0x0000:0x0600 trampoline
  ├─ Phase 8: PAM Lock (write-protect 0xF0000-0xFFFFF as Read-Only) & validate magic at 0xF000:0x0000
  │
  ▼
Execution Handover
  └─ Transfers control (DS=ES=SS=0x0000, SP=0x7C00, cli) via: jmp 0xF000:0x000C
```

---

## ⚙️ Compilation Commands

### 📦 Install Dependencies
Install all necessary build tools and dependencies:
```bash
./install-dependencies.sh
```

### 🔨 Build Commands

```bash
# Compile Boot ROM binaries and construct ROM images
make

# Clean all build artifacts
make clean
```

---

## 🚀 Emulation & Testing (`make run`)

`make run` supports fully standalone operation or integration with external firmware payloads and storage media:

### 1. Standalone Execution (No arguments)
Runs `IPO_Boot_ROM` with its built-in diagnostic payload. This payload halts after displaying diagnostics; embed a compatible BIOS firmware payload with `FIRMWARE=...` to boot an OS:
```bash
make run
```

### 2. Running with an External Firmware Binary
Embeds a firmware payload (`<= 56 KiB` in the `0xF000` bank, or `> 56 KiB .. 65,520 B` staged via Flash) and transfers control to it:
```bash
make run FIRMWARE=path/to/firmware.bin
```

### 3. Running with an Attached Storage Disk
Attaches a raw disk image as primary IDE master (`0x80`):
```bash
make run OS=path/to/disk.img
```

### 4. Running with Firmware and Storage Media
Embeds the firmware binary and attaches the storage media:
```bash
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img
```

### 5. Selecting Storage Interface (`DRIVE_TYPE`) and Machine Options
You can choose the virtual storage bus controller and hardware profile for testing:
```bash
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=ide   # Default: Legacy IDE/PATA
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=ahci  # SATA AHCI
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=nvme  # PCIe NVMe SSD
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=usb   # USB Flash Drive (EHCI BOT)
```

Additional `make run` variables supported in `mk/config.mk`:
- `MACHINE=<type>` (QEMU machine profile configured in `mk/config.mk`)
- `CPU=<model>` and `MEM=<MiB>` (default memory `512` MiB)
- `DISK=path/to/secondary.img` (optional secondary IDE disk for `DRIVE_TYPE=ide`; also auto-detects `disks/disk.img` or `disk.img` next to `OS`)
- `QEMU_EXTRA="..."` (extra arguments passed directly to `qemu-system-i386`)

### 6. Packaging for Physical Hardware & SPI Flash
`make` generates a single unified binary `build/bootrom.bin` ready for physical hardware. Standard IEC suffixes (`GiB`, `MiB`, `KiB`, `B`) and hexadecimal byte counts are supported:
```bash
# Default build generates a 4 MiB flash image ready for physical SPI flash chips:
make

# Standard and non-standard sizes supported:
make FLASH_SIZE=256KiB    # 256 KiB parallel flash
make FLASH_SIZE=128KiB    # Minimal 128 KiB ROM with 32-bit romstage
make FLASH_SIZE=384KiB    # Non-standard 384 KiB size
make FLASH_SIZE=1.5MiB    # Decimal size suffix (1.5 MiB = 1536 KiB)
make FLASH_SIZE=3MiB      # Non-power-of-two (3 MiB)
make FLASH_SIZE=4MiB      # Standard 4 MiB SPI Flash (default)
make FLASH_SIZE=8MiB      # 8 MiB SPI Flash
make FLASH_SIZE=16MiB     # 16 MiB SPI Flash
make FLASH_SIZE=0x400000  # Hexadecimal byte notation
```

### 🔊 Audio Configuration
By default, the emulator connects the PC Speaker emulation to PulseAudio/PipeWire (`AUDIO=pa`). You can customize or disable the audio driver:
```bash
make run AUDIO=alsa ...   # Use ALSA
make run AUDIO=sdl ...    # Use SDL audio
make run AUDIO=none ...   # Disable audio connection
```

---

## 📦 Generated Artifacts

| File | Size | Description |
| :--- | :--- | :--- |
| `build/bootrom.bin` | Configurable (`FLASH_SIZE`, min `128 KiB` with `romstage`, default `4 MiB` / `4,194,304 B`) | Single unified ROM image ready for physical SPI flash programming and QEMU emulation |
| `build/.bin/romstage.bin` | Flash-XIP (zero `.data`/`.bss`) | 32-bit hardware/MRC initializer mapped at `4 GiB - FLASH_SIZE` |
| `build/.bin/init.bin` | `<= 8 KiB` (`8,176 B` before reset vector) | Compact 16-bit early-init bootblock (`init.asm`, `lpc_early.asm`, `car.asm`, `pic.asm`, `pit.asm`) |
| `build/.bin/payload.bin` | `<= 56 KiB` in bank (`<= 65,520 B` extended) | Built-in standalone diagnostic payload (`payload.asm`, magic `"IPO_Boot_ROM"`) |
| `build/.bin/reset.bin` | `16 B` | Assembled x86 Reset Vector (`reset.asm`) |

---

## ROM Layout

The build places `romstage.bin` at offset `0` (`4 GiB - FLASH_SIZE`) and anchors the top 64 KiB window relative to the end of `FLASH_SIZE`. For example, with `FLASH_SIZE=256KiB` (`0x40000 B`):

| File Offset (`FLASH_SIZE=256KiB`) | Linear Phys (4 GiB Alias) | Real-Mode Alias | Component / Content |
| :--- | :--- | :--- | :--- |
| `0x00000` | `0xFFFC0000` | — | **32-bit Flash-XIP `romstage.bin`** (plus optional extended firmware `>56 KiB`) |
| `0x30000` | `0xFFFF0000` | `0xF000:0x0000` | **Firmware Payload Bank Slot** (`56 KiB`; begins with `"IPO_Firmware"` or `"IPO_Boot_ROM"`, entry at `+0x0C`) |
| `0x3E000` | `0xFFFFE000` | `0xF000:0xE000` | **Compact Bootblock (`init.bin`)** (`8 KiB - 16 B`) |
| `0x3FFF0` | `0xFFFFFFF0` | `0xF000:0xFFF0` | **Hardware Reset Vector** (`16 B`: `jmp 0xF000:0xE000`) |

---

## 🗺️ Physical Memory Map & Handover Contract

### Memory Map (Conventional 1 MiB Space)
| Memory Range | Physical Address | Usage / Component |
| :--- | :--- | :--- |
| `0x0000:0x0500` | `0x00000500` | Scratch RAM (`0x0500-0x05FF` zeroed; stores Host VID `0x0508`, Host DID `0x050A`, RAM bytes `0x0514`, VGA cursor `0x0500`) |
| `0x0000:0x0600` | `0x00000600` | Low-RAM position-independent trampoline used during PAM0 shadow copy |
| `0x0000:0x7000` | `0x00007000` | Post-DRAM boot stack range in DRAM; initial `SP=0x7C00`, grows downward |
| `0x2000:0x0000` | `0x00020000` | Temporary `64 KiB` staging DRAM buffer used while copying ROM to Shadow RAM |
| `0x7000:0x0000` | `0x00070000` | Cache-as-RAM (CAR) temporary stack/scratch (`0x70000-0x77FFF`, `32 KiB`, pre-DRAM phase, initial `SP=0x8000`) |
| `0xB800:0x0000` | `0x000B8000` | VGA Text Buffer (used for Boot ROM messages when VGA RAM decode is enabled) |
| `0xF000:0x0000` | `0x000F0000` | Shadow RAM (`64 KiB` write-protected DRAM mirror of top `64 KiB` ROM bank) |

### Handover to Firmware Payload
At the completion of Boot ROM initialization, control is transferred to the payload in Shadow RAM:
- **CPU Mode:** 16-bit Real Mode
- **Entry Point (`CS:IP`):** `0xF000:0x000C` (in write-protected Shadow RAM)
- **Signature (`0xF000:0x0000`):** Must match 12 ASCII bytes `"IPO_Firmware"` or `"IPO_Boot_ROM"`
- **Segments (`DS, ES, SS`):** `0x0000`
- **Stack (`SS:SP`):** `0x0000:0x7C00` (grows downward)
- **Interrupts (`IF`):** `0` (`cli`, disabled until IVT is registered by firmware)
- **Hardware State:** Host bridge detected (`0x0508`/`0x050A`), DRAM initialized via MRC (`0x0514`), MTRRs set on MTRR-capable CPUs (DRAM `0x00000000-0xDFFFFFFF` WB, MMIO `0xE0000000-0xFFFFFFFF` UC), COM1/PIC/PIT initialized, PAM0 locked Read-Only (`PAM_RE`).

---

## 🚦 POST Diagnostic Port 0x80 Codes

`IPO_Boot_ROM` writes the following checkpoints to diagnostic port `0x80` (`POST_PORT` in `include/contract.inc`):

| Hex Code | Symbol / Checkpoint | Status |
| :---: | :--- | :---: |
| `0x12` | `POST_CAR_START` — MTRR Cache-as-RAM (CAR) setup and cache-line warmup started (`car.asm`) | Progress |
| `0x13` | `POST_CAR_OK` — CAR stack/scratch operational at `0x7000:0x8000` (`car.asm`) | Progress |
| `0x15` | `POST_ROMSTAGE_START` — 32-bit Flash-XIP `romstage` entered (`romstage.c`) | Progress |
| `0x16` | `POST_ROMSTAGE_OK` — 32-bit `romstage` hardware & MRC initialization complete (`romstage.c`) | Progress |
| `0x1F` | `POST_WARN_SPD_FAIL` — SMBus SPD read returned `0 MiB`; falling back to CMOS (`0x34/0x35`, `0x17/0x18`), cold-boot DRAM probe, or `64 MiB` default (`romstage_mrc.c`) | Warning |
| `0x2E` | `POST_NOMTRR_BYPASS` — Info: CPU lacks `CPUID` or MTRR (`CPUID.1:EDX[12] = 0`); CAR MSR setup cleanly bypassed without halting (`car.asm`) | Info |

## 🧑‍💻 Authors

- [IPOleksenko](https://github.com/IPOleksenko) (owner) — Developer and creator of the idea.


# 📜 License

This project is licensed under the [MIT License][license].

[license]: ./LICENSE
