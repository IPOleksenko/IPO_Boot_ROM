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
INIT_OFFSET := 260096  # 0x3F800 (mapped to 0xFFFFF800 / alias 0xF000:0xF800)

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

# BIOS / Firmware binary to embed into ROM (optional: make run BIOS=/path/to/firmware.bin)
BIOS     ?=
FW       ?= $(BIOS)
FIRMWARE ?= $(FW)
FW_BIN   ?= $(FIRMWARE)

ifeq ($(FW_BIN),1)
FW_BIN := ../IPO_Firmware/build/firmware.bin
else ifeq ($(FW_BIN),default)
FW_BIN := ../IPO_Firmware/build/firmware.bin
endif

# Target OS storage media (optional: make run OS=/path/to/disk.img)
OS       ?=
OS_IMAGE ?= $(OS)
MEM      ?= 8192

# Determine active ROM for emulation:
# If BIOS/Firmware is provided, build RUN_ROM; otherwise run standalone BOOTROM_BIN
ifeq ($(FW_BIN),)
TARGET_ROM := $(BOOTROM_BIN)
else
TARGET_ROM := $(RUN_ROM)
endif

# Base QEMU flags for running Boot ROM
QEMU_FLAGS := -M pc -m $(MEM) -bios $(TARGET_ROM) -serial stdio

# Audio configuration for PC Speaker (matching IPO_OS)
AUDIO ?= pa
ifneq ($(AUDIO),none)
QEMU_FLAGS += -audiodev $(AUDIO),id=pa -machine pcspk-audiodev=pa
endif

# If an OS storage media image is supplied, attach it as primary IDE master (disk 0x80)
ifneq ($(OS_IMAGE),)
QEMU_FLAGS += -drive format=raw,file=$(OS_IMAGE),if=ide,index=0
# Optional secondary disk (e.g. IPO_OS disk pool)
DISK ?=
ifneq ($(DISK),)
QEMU_FLAGS += -drive format=raw,file=$(DISK),if=ide,index=1
else ifneq ($(wildcard $(dir $(OS_IMAGE))disk.img),)
QEMU_FLAGS += -drive format=raw,file=$(dir $(OS_IMAGE))disk.img,if=ide,index=1
else ifneq ($(wildcard $(dir $(OS_IMAGE))../build/disk.img),)
QEMU_FLAGS += -drive format=raw,file=$(dir $(OS_IMAGE))../build/disk.img,if=ide,index=1
endif
endif

QEMU_FLAGS += $(QEMU_EXTRA)
