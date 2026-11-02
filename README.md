# IPO_Boot_ROM

Independent bare-metal x86 Boot ROM (Reset Vector Initializer) for PC-AT compatible machines and physical hardware.

---

## 📋 Architecture & Boot Flow

`IPO_Boot_ROM` serves as the initial entry point for the bare-metal x86 boot process. It executes directly from the CPU hardware reset vector (`0xFFFFFFF0`, mapped to `0xF000:0xFFF0` in real mode) in a configurable Flash image (`FLASH_SIZE`, 4 MiB by default).

```text
CPU Hardware Reset (CS:IP = F000:FFF0, Phys: 0xFFFFFFF0)
  │
  ▼
Jump to Real-Mode ROM Base (jmp 0xF000:0x8000)
  │
  ▼
Low-Level Hardware Initialization
  ├─ Phase 1: Cache-as-RAM (CAR) setup via MTRRs (stack at 0x7000:0x8000)
  ├─ Phase 2: Host Chipset Detection via PCI probe
  ├─ Phase 3: Memory Reference Code (MRC) DRAM controller training
  ├─ Phase 4: CAR teardown, system stack relocated to DRAM (range 0x7000-0x7C00, SP=0x7C00)
  ├─ Phase 5: Cascaded 8259A PIC & 8254 PIT (18.2 Hz) timer configuration
  ├─ Phase 6: COM1 UART Serial initialization (115200 baud, 8N1)
  ├─ Phase 7: PAM Shadow RAM copy (64 KB ROM -> DRAM at 0xF000:0000)
  ├─ Phase 8: PAM Lock: write-protect 0xF0000-0xFFFFF as Read-Only
  └─ Phase 9: Validate 4-byte firmware magic: 'IPO' (0x004F5049)
  │
  ▼
Execution Handover (Contract 2)
  └─ Transfers control via: jmp 0xF000:0004 (Shadow RAM)
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
Embeds a firmware payload at the start of the final 64 KiB ROM window (`FLASH_SIZE - 0x10000`, mapped to `0xF000:0000`) and transfers control to it:
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

### 5. Selecting Storage Interface (`DRIVE_TYPE`)
You can choose the virtual storage bus controller for testing:
```bash
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=ide   # Default: Legacy IDE/PATA
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=ahci  # Modern SATA AHCI
make run FIRMWARE=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=usb   # USB 2.0 Flash Drive (EHCI BOT)
```

### 6. Packaging for Physical Hardware & SPI Flash
`make` generates a single unified binary `build/bootrom.bin` ready for physical hardware. Both standard and arbitrary non-standard sizes are supported:
```bash
# Default build generates a 4 MiB flash image ready for physical SPI flash chips:
make

# Standard and non-standard sizes supported:
make FLASH_SIZE=256K      # 256 KiB parallel flash
make FLASH_SIZE=64K       # Minimal 64 KiB ROM
make FLASH_SIZE=384K      # Non-standard 384 KiB size
make FLASH_SIZE=1.5M      # Decimal size suffix (1.5 MiB = 1536 KiB)
make FLASH_SIZE=3M        # Non-power-of-two (3 MiB)
make FLASH_SIZE=4M        # Standard 4 MiB SPI Flash (default)
make FLASH_SIZE=8M        # 8 MiB SPI Flash
make FLASH_SIZE=16M       # 16 MiB SPI Flash
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
| `build/bootrom.bin` | Configurable (`FLASH_SIZE`, default 4 MiB / 4,194,304 B) | Single unified ROM image ready for physical SPI flash programming (`flashrom`) and QEMU emulation |

---

## ROM Layout

The build places each region relative to the end of the configured ROM image. For a `FLASH_SIZE` of `N` bytes, the payload starts at `N - 0x10000`, init code at `N - 0x8000`, and the reset vector at `N - 0x10`. Thus the file offsets below are examples for `FLASH_SIZE=256K`; the default `FLASH_SIZE=4M` uses offsets `0x3F0000`, `0x3F8000`, and `0x3FFFF0`, respectively.

| File Offset (`FLASH_SIZE=256K`) | Linear Phys (4G Alias) | Real-Mode Alias | Component / Content |
| :--- | :--- | :--- | :--- |
| `0x30000` | `0xFFFF0000` | `0xF000:0x0000` | **Firmware Payload Slot** (up to 32 KiB, begins with magic `'IPO'`) |
| `0x38000` | `0xFFFF8000` | `0xF000:0x8000` | **Boot_ROM Init Code** (`init.asm`, CAR, MRC, PIC, PIT, chipset probe) |
| `0x3FFF0` | `0xFFFFFFF0` | `0xF000:0xFFF0` | **Hardware Reset Vector** (16 bytes: `jmp 0xF000:0x8000`) |

---

## 🗺️ Physical Memory Map & Handover Contract

### Memory Map (Conventional 1 MB Space)
| Memory Range | Physical Address | Usage / Component |
| :--- | :--- | :--- |
| `0x0000:0x0000` | `0x00000000` | Interrupt Vector Table (IVT, 1024 B) |
| `0x0040:0x0000` | `0x00000400` | BIOS Data Area (BDA, 256 B) |
| `0x0000:0x0500` | `0x00000500` | Scratch RAM (Registry, peripheral flags, E820 buffer) |
| `0x0000:0x7000` | `0x00007000` | Boot stack range `0x7000-0x7C00` in DRAM; initial `SP=0x7C00`, grows downward |
| `0x0000:0x7C00` | `0x00007C00` | MBR Load Buffer (512 B boot sector target) |
| `0x9FC0:0x0000` | `0x0009FC00` | Extended BIOS Data Area (EBDA) & ACPI 1.0 tables |
| `0xB800:0x0000` | `0x000B8000` | VGA Framebuffer (Mode 03h, 80x25 16-color text) |
| `0x7000:0x0000` | `0x00070000` | Cache-as-RAM (CAR) temporary stack/data (32 KB, pre-DRAM phase) |
| `0xF000:0x0000` | `0x000F0000` | Shadow RAM (64 KB write-protected DRAM mirror of ROM) |

### Contract 2: Handover to Firmware Payload
At the completion of Boot ROM initialization, control is transferred to the firmware:
- **CPU Mode:** 16-bit Real Mode
- **Entry Point (`CS:IP`):** `0xF000:0x0004` (in write-protected Shadow RAM)
- **Signature (`0xF000:0x0000`):** Must contain `'I', 'P', 'O'` (`0x004F5049`)
- **Segments (`DS, ES`):** `0x0000`
- **Stack (`SS:SP`):** `0x0000:0x7C00` (stack range `0x7000-0x7C00`, below MBR buffer)
- **Interrupts (`IF`):** `0` (`cli`, disabled until IVT is registered by firmware)
- **Hardware State:** Host chipset detected, DRAM trained and active via MRC, PIC/PIT initialized, PAM0 locked Read-Only.

---

## ⚡ Physical Hardware & Flashing Guide

### Flashing with `flashrom`
> [!CAUTION]
> **Always dump and verify two identical backups before flashing physical hardware!**
> Set `PROGRAMMER` to the programmer interface supported by your hardware.
> ```bash
> flashrom -p "$PROGRAMMER" -r backup1.bin
> flashrom -p "$PROGRAMMER" -r backup2.bin
> cmp backup1.bin backup2.bin || echo "Flash read unstable! Check clamp and wiring!"
> ```

```bash
# Build ROM image (default 4MB, or specify FLASH_SIZE):
make FLASH_SIZE=4M

# Write to physical flash using a supported programmer:
flashrom -p "$PROGRAMMER" -w build/bootrom.bin
```

---

## 🚦 POST Diagnostic Port 0x80 Codes

A standard 2-digit LPC/PCI POST card connected to port `0x80` reports boot progress:

| Hex Code | Checkpoint / Milestone | Status |
| :---: | :--- | :---: |
| `0x10` | CPU Reset Vector reached (`0xFFFFFFF0`) | Progress |
| `0x11` | Entered Boot_ROM initialization code (`0xF000:0x8000`) | Progress |
| `0x12` | MTRR Cache-as-RAM (CAR) setup started | Progress |
| `0x13` | CAR stack operational at `0x7000:0x8000` (NEM enabled) | Progress |
| `0x14` | PCI chipset probing started | Progress |
| `0x15` | Supported chipset detected | Progress |
| `0x16` | Memory Reference Code (MRC) DRAM training started | Progress |
| `0x17` | DRAM sanity pattern test passed (`0x55AA55AA` / `0xAA55AA55`) | Progress |
| `0x18` | CAR teardown complete (`wbinvd`, MTRRs restored, stack in DRAM) | Progress |
| `0x19` | Cascaded 8259 PIC and 8254 PIT (18.2 Hz) initialized | Progress |
| `0x1A` | COM1 UART initialized (115200 baud, 8N1) | Progress |
| `0x1B` | ROM copied to DRAM Shadow RAM (`0xF0000..0xFFFFF`) | Progress |
| `0x1C` | PAM locked read-only (`RE=1, WE=0`) | Progress |
| `0x1D` | Firmware header magic (`'IPO'`) validated | Progress |
| `0x1E` | Far jump to Firmware payload (`0xF000:0x0004`) | Progress |
| `0x1F` | Warning: SMBus SPD read failed, fallback to CMOS/default RAM geometry | Warning |
| **`0x2E`** | **ERROR:** CPU lacks MTRR support or CAR configuration failed | **Error** |
| **`0x3E`** | **ERROR:** Unsupported chipset / unknown PCI Host Bridge ID | **Error** |
| **`0x4E`** | **ERROR:** DRAM memory pattern test failed | **Error** |
| **`0x7E`** | **ERROR:** Firmware signature mismatch (`'IPO'` expected) | **Error** |

## 🧑‍💻 Authors

- [IPOleksenko](https://github.com/IPOleksenko) (owner) — Developer and creator of the idea.


# 📜 License

This project is licensed under the [MIT License][license].

[license]: ./LICENSE