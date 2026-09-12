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

# BIOS / Firmware binary to embed into ROM
# (passed as argument: make run BIOS=/path/to/firmware.bin or FW=...)
FW_DEFAULT := $(if $(wildcard ../IPO_Firmware/build/firmware.bin),../IPO_Firmware/build/firmware.bin,$(BUILD)/stub_firmware.bin)
FW         ?= $(FW_DEFAULT)
BIOS       ?= $(FW)
FW_BIN     ?= $(BIOS)

# Target OS storage media (passed as argument: make run OS=/path/to/os.img)
OS         ?= ../build/IPO_OS.img
OS_IMAGE   ?= $(OS)
DISK1      ?= $(wildcard ../build/disk.img)
CDROM      ?= $(wildcard ../build/disk.iso)
MEM        ?= 8192

# Emulates booting specifically from storage media (IDE disk index 0)
QEMU_FLAGS := -M pc -m $(MEM) -bios $(RUN_ROM) \
              -drive format=raw,file=$(OS_IMAGE),if=ide,index=0

ifneq ($(DISK1),)
QEMU_FLAGS += -drive format=raw,file=$(DISK1),if=ide,index=1
endif

ifneq ($(CDROM),)
QEMU_FLAGS += -cdrom $(CDROM)
endif

QEMU_FLAGS += -serial stdio $(QEMU_EXTRA)
