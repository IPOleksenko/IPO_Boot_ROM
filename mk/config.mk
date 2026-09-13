# =============================================================================
#                     TOOLS
# =============================================================================

ASM     := nasm
QEMU    := qemu-system-i386

# =============================================================================
#                 PROJECT DIRECTORIES
# =============================================================================

SRC     := src
BUILD   := build
INC     := include
TOOLS   := tools
TESTS   := tests

# =============================================================================
#                 ROM GEOMETRY (256 KB)
# =============================================================================

ROMSIZE     := 262144
FW_OFFSET   := 196608  # 0x30000 (mapped to 0xFFFF0000 / alias 0xF000:0x0000)
INIT_OFFSET := 229376  # 0x38000 (mapped to 0xFFFF8000 / alias 0xF000:0x8000)
                        # Expanded from 0x3F800 to accommodate hardware init code
                        # (CAR, MRC, PIC, PIT, chipset, shadow ROM routines)

# =============================================================================
#                 OUTPUT ARTIFACTS
# =============================================================================

BOOTROM_BIN  := $(BUILD)/bootrom.bin
BOOTROM_TMPL := $(BUILD)/bootrom_template.bin
RUN_ROM      := $(BUILD)/bootrom_run.bin

# =============================================================================
#                 FLAGS
# =============================================================================

ASM_FLAGS := -f bin -I$(INC) -I$(SRC)

# =============================================================================
#                 EMULATION RUN ARGUMENTS
# =============================================================================

# Firmware binary to embed into ROM (optional: make run BIOS=/path/to/firmware.bin)
BIOS     ?=
FW       ?= $(BIOS)
FIRMWARE ?= $(FW)
FW_BIN   ?= $(FIRMWARE)

# Target OS storage media (optional: make run OS=/path/to/disk.img)
OS       ?=
OS_IMAGE ?= $(OS)
MEM      ?= 8192

# Determine active ROM for emulation:
# If Firmware is provided, build RUN_ROM; otherwise run standalone BOOTROM_BIN
ifeq ($(FW_BIN),)
TARGET_ROM := $(BOOTROM_BIN)
else
TARGET_ROM := $(RUN_ROM)
endif

# QEMU machine type (default: pc = i440FX; use MACHINE=q35 for Q35)
MACHINE ?= pc

# Base QEMU flags for running Boot ROM
QEMU_FLAGS := -M $(MACHINE) -m $(MEM) -bios $(TARGET_ROM) -serial stdio

# Audio configuration for PC Speaker
AUDIO ?= pa
ifneq ($(AUDIO),none)
QEMU_FLAGS += -audiodev $(AUDIO),id=pa -machine pcspk-audiodev=pa
endif

# If an OS storage media image is supplied, attach it according to DRIVE_TYPE (ide, ahci, or usb)
ifneq ($(OS_IMAGE),)
DRIVE_TYPE ?= ide
ifeq ($(DRIVE_TYPE),ahci)
QEMU_FLAGS += -device ahci,id=ahci -device ide-hd,drive=sata_disk,bus=ahci.0 -drive id=sata_disk,file=$(OS_IMAGE),format=raw,if=none
else ifeq ($(DRIVE_TYPE),usb)
QEMU_FLAGS += -device usb-ehci,id=ehci -device usb-storage,bus=ehci.0,drive=usb_disk -drive id=usb_disk,file=$(OS_IMAGE),format=raw,if=none
else
QEMU_FLAGS += -drive format=raw,file=$(OS_IMAGE),if=ide,index=0
# Optional secondary disk
DISK ?=
ifneq ($(DISK),)
QEMU_FLAGS += -drive format=raw,file=$(DISK),if=ide,index=1
else ifneq ($(wildcard $(dir $(OS_IMAGE))disk.img),)
QEMU_FLAGS += -drive format=raw,file=$(dir $(OS_IMAGE))disk.img,if=ide,index=1
endif
endif
endif

QEMU_FLAGS += $(QEMU_EXTRA)
