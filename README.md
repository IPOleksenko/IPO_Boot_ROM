# IPO_Boot_Rom

Independent bare-metal x86 Boot ROM (Reset Vector Initializer) for QEMU and PC-AT compatible machines.

---

## 📋 Architecture & Boot Flow

`IPO_Boot_Rom` serves as the root of trust and initial entry point for the bare-metal x86 boot process. It occupies the top of physical 32-bit address space (reset vector `0xFFFFFFF0`, aliased to `0xF000:0xFFF0` in real mode) within a 256 KB Flash ROM.

```text
CPU Hardware Reset (CS:IP = F000:FFF0)
  │
  ▼
Jump to Real-Mode ROM Base (jmp 0xF000:0xF800)
  │
  ▼
Low-Level Hardware Initialization
  ├─ Real Mode segments established (DS=ES=0x0000, CS=0xF000)
  ├─ System stack configured at 0x0000:0x7000
  ├─ COM1 UART Serial initialized (115200 baud, 8N1)
  └─ VGA text adapter configured (Mode 03h, 80x25 colour)
  │
  ▼
Payload Relocation (Contract 1 -> Contract 2)
  ├─ Copies 32 KB BIOS Firmware from ROM (0xF000:0000) to RAM (0x0800:0000)
  ├─ Validates 4-byte magic signature: 'IPOF' (0x464F5049)
  │
  ▼
Execution Handover (Contract 2)
  └─ Transfers control via: jmp 0x0800:0004
```

---

## 🛠️ Build Commands

```bash
# Compile Boot ROM binaries and construct ROM images
make

# Run automated headless verification tests in QEMU
make test

# Clean all build artifacts
make clean
```

---

## 🚀 Emulation & Running (`make run`)

`make run` supports fully standalone operation or integration with external BIOS Firmware and OS images without hardcoded dependencies:

### 1. Standalone Execution (No arguments)
Runs Boot ROM with internal diagnostics and hardware self-test:
```bash
make run
```

### 2. Single-Argument Invocations
* **With BIOS Firmware only:**
  ```bash
  make run BIOS=/home/ipoleksenko/Project/IPO_OS/IPO_Firmware/build/firmware.bin
  ```

* **With OS storage image only:**
  ```bash
  make run OS=/home/ipoleksenko/Project/IPO_OS/build/IPO_OS.img
  ```

### 3. Full Integration (BIOS + OS)
Embeds the specified BIOS Firmware into the ROM and attaches the target OS drive:
```bash
make run BIOS=/home/ipoleksenko/Project/IPO_OS/IPO_Firmware/build/firmware.bin OS=/home/ipoleksenko/Project/IPO_OS/build/IPO_OS.img
```

### 🔊 Audio Configuration
By default, QEMU connects the PC Speaker emulation to PulseAudio/PipeWire (`AUDIO=pa`). You can customize the audio driver:
```bash
make run AUDIO=alsa ...   # Use ALSA
make run AUDIO=sdl ...    # Use SDL audio
make run AUDIO=none ...   # Disable audio connection
```

---

## 📦 Generated Artifacts

| File | Size | Description |
| :--- | :--- | :--- |
| `build/bootrom.bin` | 262,144 B | Complete 256 KB ROM with internal diagnostic payload for standalone testing |
| `build/bootrom_template.bin` | 262,144 B | 256 KB ROM template with empty (0xFF) Firmware slot for external integration |
| `build/bootrom_run.bin` | 262,144 B | Dynamically generated ROM embedding the specified external BIOS Firmware |
| `build/init.bin` | ~600 B | Assembled early initialization code (mapped to `0xF000:0xF800`) |
| `build/reset.bin` | 16 B | Hardware reset vector code (mapped to `0xFFFF:0x0000` / `0xF000:0xFFF0`) |

---

## 📖 Specifications & Contracts

See [docs/CONTRACT.md](docs/CONTRACT.md) for complete technical specifications:
- **Contract 1**: Hardware Reset Vector State & Geometry
- **Contract 2**: Handover to `IPO_Firmware` (`CS:IP = 0x0800:0x0004`, magic `'IPOF'`)