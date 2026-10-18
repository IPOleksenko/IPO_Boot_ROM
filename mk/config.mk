# =============================================================================
#                     TOOLS
# =============================================================================

ASM     := nasm
QEMU    := qemu-system-i386

# =============================================================================
#                 TARGET FLASH CHIP GEOMETRY
# =============================================================================

# Physical SPI flash chip size (default: 4M for physical SPI flash like W25Q32;
# use FLASH_SIZE=256K for vintage 256KB parallel flash / PLCC32 EEPROM)
FLASH_SIZE  ?= 4M

# =============================================================================
#                 PROJECT DIRECTORIES
# =============================================================================

SRC     := src
BUILD   := build
OBJ     := $(BUILD)/.obj
INC     := include
TOOLS   := tools

# =============================================================================
#                 OUTPUT ARTIFACT (Single unified ROM binary)
# =============================================================================

BOOTROM_BIN := $(BUILD)/bootrom.bin
TARGET_ROM  := $(BOOTROM_BIN)

# =============================================================================
#                 FLAGS
# =============================================================================

ASM_FLAGS := -f bin -I$(INC) -I$(SRC)

# =============================================================================
#                 EMULATION RUN ARGUMENTS
# =============================================================================

# Firmware binary to embed into ROM (optional: make run FIRMWARE=/path/to/firmware.bin)
FIRMWARE ?=
FW       ?= $(FIRMWARE)
BIOS     ?= $(FW)
FW_BIN   ?= $(BIOS)

# Target OS storage media (optional: make run OS=/path/to/disk.img)
OS       ?=
OS_IMAGE ?= $(OS)
CPU      ?= pentium3
MEM      ?= 512

# QEMU machine type (default: pc = i440FX; use MACHINE=q35 for Q35)
MACHINE ?= pc

# Base QEMU flags for running Boot ROM
QEMU_FLAGS := -M $(MACHINE) -cpu $(CPU) -m $(MEM) -bios $(TARGET_ROM) -serial stdio

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
