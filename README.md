# IPO_Boot_ROM

Independent bare-metal x86 Boot ROM (Reset Vector Initializer) for PC-AT compatible machines and physical hardware.

---

## 📋 Architecture & Boot Flow

`IPO_Boot_ROM` serves as the initial entry point for the bare-metal x86 boot process. It executes directly from the CPU hardware reset vector (`0xFFFFFFF0`, mapped to `0xF000:0xFFF0` in real mode) within a 256 KB Flash ROM.

```text
CPU Hardware Reset (CS:IP = F000:FFF0, Phys: 0xFFFFFFF0)
  │
  ▼
Jump to Real-Mode ROM Base (jmp 0xF000:0x8000)
  │
  ▼
Low-Level Hardware Initialization
  ├─ Phase 1: Cache-as-RAM (CAR) setup via MTRRs (stack at 0x7000:0x8000)
  ├─ Phase 2: Host Chipset Detection (i440FX vs Q35 via PCI probe)
  ├─ Phase 3: Memory Reference Code (MRC) DRAM controller training
  ├─ Phase 4: CAR teardown, system stack relocated to DRAM (0x0000:0x7000)
  ├─ Phase 5: Cascaded 8259A PIC & 8254 PIT (18.2 Hz) timer configuration
  ├─ Phase 6: COM1 UART Serial initialization (115200 baud, 8N1)
  ├─ Phase 7: PAM Shadow RAM copy (64 KB ROM -> DRAM at 0xF000:0000)
  ├─ Phase 8: PAM Lock: write-protect 0xF0000-0xFFFFF as Read-Only
  └─ Phase 9: Validate 4-byte firmware magic: 'IPOF' (0x464F5049)
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

# Run automated headless verification tests
make test

# Clean all build artifacts
make clean
```

---

## 🚀 Emulation & Testing (`make run`)

`make run` supports fully standalone operation or integration with external firmware payloads and storage media:

### 1. Standalone Execution (No arguments)
Runs `IPO_Boot_ROM` in isolation with internal diagnostics and hardware self-test:
```bash
make run
```

### 2. Running with an External Firmware Binary
Embeds a firmware binary at offset `0x30000` (`0xF000:0000`) and transfers control to it:
```bash
make run BIOS=path/to/firmware.bin
```

### 3. Running with an Attached Storage Disk
Attaches a raw disk image as primary IDE master (`0x80`):
```bash
make run OS=path/to/disk.img
```

### 4. Running with Firmware and Storage Media
Embeds the firmware binary and attaches the storage media:
```bash
make run BIOS=path/to/firmware.bin OS=path/to/disk.img
```

### 5. Selecting Storage Interface (`DRIVE_TYPE`)
You can choose the virtual storage bus controller for testing:
```bash
make run BIOS=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=ide   # Default: Legacy IDE/PATA
make run BIOS=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=ahci  # Modern SATA AHCI
make run BIOS=path/to/firmware.bin OS=path/to/disk.img DRIVE_TYPE=usb   # USB 2.0 Flash Drive (EHCI BOT)
```

### 6. Packaging for Physical SPI Flash
Build a full-sized flash image ready for a physical SPI programmer:
```bash
# Build full-sized SPI Flash image (e.g. 4MB, 8MB, 16MB) padded with 0xFF:
make spi-flash FLASH_SIZE=4M
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
| `build/bootrom.bin` | 262,144 B | Complete 256 KB ROM image with internal diagnostic payload for standalone testing |
| `build/bootrom_template.bin` | 262,144 B | 256 KB ROM template with empty (0xFF) firmware slot ready for external payloads |
| `build/bootrom_run.bin` | 262,144 B | Dynamically generated ROM embedding the specified external firmware |
| `build/init.bin` | ~600 B | Assembled early initialization code (mapped to `0xF000:0xF800`) |
| `build/reset.bin` | 16 B | Hardware reset vector code (mapped to `0xFFFF:0x0000` / `0xF000:0xFFF0`) |

---

##  ROM Layout (256 KB)

| File Offset | Linear Phys (4G Alias) | Real-Mode Alias | Component / Content |
| :--- | :--- | :--- | :--- |
| `0x00000` | `0xFFFC0000` | — | Unused padding (`0xFF`) |
| `0x30000` | `0xFFFF0000` | `0xF000:0x0000` | **Firmware Payload Slot** (up to 32 KB, begins with magic `'IPOF'`) |
| `0x38000` | `0xFFFF8000` | `0xF000:0x8000` | **Boot_ROM Init Code** (`init.asm`, CAR, MRC, PIC, PIT, Chipset probe) |
| `0x3FFF0` | `0xFFFFFFF0` | `0xF000:0xFFF0` | **Hardware Reset Vector** (16 bytes: `jmp 0xF000:0x8000`) |

---

## 🗺️ Physical Memory Map & Handover Contract

### Memory Map (Conventional 1 MB Space)
| Memory Range | Physical Address | Usage / Component |
| :--- | :--- | :--- |
| `0x0000:0x0000` | `0x00000000` | Interrupt Vector Table (IVT, 1024 B) |
| `0x0040:0x0000` | `0x00000400` | BIOS Data Area (BDA, 256 B) |
| `0x0000:0x0500` | `0x00000500` | Scratch RAM (Registry, peripheral flags, E820 buffer) |
| `0x0000:0x7000` | `0x00007000` | Boot Stack in physical DRAM (top at `0x0000:0x7C00`, grows downward) |
| `0x0000:0x7C00` | `0x00007C00` | MBR Load Buffer (512 B boot sector target) |
| `0x9FC0:0x0000` | `0x0009FC00` | Extended BIOS Data Area (EBDA) & ACPI 1.0 tables |
| `0xB800:0x0000` | `0x000B8000` | VGA Framebuffer (Mode 03h, 80x25 16-color text) |
| `0x7000:0x0000` | `0x00070000` | Cache-as-RAM (CAR) temporary stack/data (32 KB, pre-DRAM phase) |
| `0xF000:0x0000` | `0x000F0000` | Shadow RAM (64 KB write-protected DRAM mirror of ROM) |

### Contract 2: Handover to Firmware Payload
At the completion of Boot ROM initialization, control is transferred to the firmware:
- **CPU Mode:** 16-bit Real Mode
- **Entry Point (`CS:IP`):** `0xF000:0x0004` (in write-protected Shadow RAM)
- **Signature (`0xF000:0x0000`):** Must contain `'I', 'P', 'O', 'F'` (`0x464F5049`)
- **Segments (`DS, ES`):** `0x0000`
- **Stack (`SS:SP`):** `0x0000:0x7000` (safe DRAM stack below MBR buffer)
- **Interrupts (`IF`):** `0` (`cli`, disabled until IVT is registered by firmware)
- **Hardware State:** Host chipset detected, DRAM trained and active via MRC, PIC/PIT initialized, PAM0 locked Read-Only.

---

## ⚡ Physical Hardware & Flashing Guide

### Hardware Compatibility Matrix
| Platform / Generation | Supported | Notes & Requirements |
| :--- | :---: | :--- |
| **Intel i440FX + PIIX3/PIIX4** (Pentium II / III) | **YES** | Native support. Complete SDRAM MRC sequence (`mrc_440fx.asm`) & PAM (`0x59..0x5F`). |
| **Intel Q35 + ICH9** (Core 2 / LGA 775) | **YES** | Native support. PAM (`0x90..0x96`), PCI enumeration, SMBus SPD probing. |
| **Modern Intel (Core i 1st–14th gen)** | **NO** | Integrated Memory Controller (IMC) requires Intel FSP; Intel Boot Guard blocks unsigned flash. |
| **Modern AMD (Zen 1–5)** | **NO** | Boot handled by AMD PSP (Platform Security Processor) before x86 reset vector release. |

### Flashing with `flashrom`
> [!CAUTION]
> **Always dump and verify two identical backups before flashing physical hardware!**
> ```bash
> flashrom -p ch341a_spi -r backup1.bin
> flashrom -p ch341a_spi -r backup2.bin
> cmp backup1.bin backup2.bin || echo "Flash read unstable! Check clamp and wiring!"
> ```

```bash
# Build full SPI flash image padded to chip size (e.g. 4MB / 8MB):
make spi-flash BIOS=path/to/firmware.bin FLASH_SIZE=4M

# Write to physical SPI Flash via CH341A external programmer:
flashrom -p ch341a_spi -w build/spi_flash.bin

# Or write via Raspberry Pi SPI header:
flashrom -p linux_spi:dev=/dev/spidev0.0,spispeed=16000 -w build/spi_flash.bin
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
| `0x15` | Chipset detected (i440FX `0x1237` or Q35 `0x29C0`) | Progress |
| `0x16` | Memory Reference Code (MRC) DRAM training started | Progress |
| `0x17` | DRAM sanity pattern test passed (`0x55AA55AA` / `0xAA55AA55`) | Progress |
| `0x18` | CAR teardown complete (`wbinvd`, MTRRs restored, stack in DRAM) | Progress |
| `0x19` | Cascaded 8259 PIC and 8254 PIT (18.2 Hz) initialized | Progress |
| `0x1A` | COM1 UART initialized (115200 baud, 8N1) | Progress |
| `0x1B` | ROM copied to DRAM Shadow RAM (`0xF0000..0xFFFFF`) | Progress |
| `0x1C` | PAM locked read-only (`RE=1, WE=0`) | Progress |
| `0x1D` | Firmware header magic (`'IPOF'`) validated | Progress |
| `0x1E` | Far jump to Firmware payload (`0xF000:0x0004`) | Progress |
| `0x1F` | Warning: SMBus SPD read failed, fallback to CMOS/default RAM geometry | Warning |
| **`0x2E`** | **ERROR:** CPU lacks MTRR support or CAR configuration failed | **Error** |
| **`0x3E`** | **ERROR:** Unsupported chipset / unknown PCI Host Bridge ID | **Error** |
| **`0x4E`** | **ERROR:** DRAM memory pattern test failed | **Error** |
| **`0x7E`** | **ERROR:** Firmware signature mismatch (`'IPOF'` expected) | **Error** |

## 🧑‍💻 Authors

- [IPOleksenko](https://github.com/IPOleksenko) (owner) — Developer and creator of the idea.


# 📜 License

This project is licensed under the [MIT License][license].

[license]: ./LICENSE