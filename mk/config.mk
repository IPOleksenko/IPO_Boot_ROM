# Toolchain and emulator binaries

ASM     := nasm
CC      := gcc
LD      := ld
OBJCOPY := objcopy
QEMU    := qemu-system-i386

# Flash chip geometry (default 4 MiB SPI flash; 256 KiB for parallel EEPROM)
FLASH_SIZE  ?= 4MiB

# Project directories

SRC     := src
BUILD   := build
BIN     := $(BUILD)/.bin
INC     := include
TOOLS   := tools

# Output image

BOOTROM_BIN := $(BUILD)/bootrom.bin
TARGET_ROM  := $(BOOTROM_BIN)

# Compiler and assembler flags

ASM_FLAGS := -f bin -I$(INC) -I$(SRC)
ASM_ELF_FLAGS := -f elf32 -I$(INC) -I$(SRC)
ROMSTAGE_CFLAGS := -m32 -march=i386 -mtune=generic -mno-sse -mno-mmx -Os \
	-ffreestanding -fno-pic -fno-pie -fno-builtin -nostdlib -nostartfiles \
	-fno-asynchronous-unwind-tables -fno-unwind-tables -Wall -Wextra -I$(SRC)

# Emulator arguments

# Optional external firmware binary (FIRMWARE=/path/to/fw.bin)
FIRMWARE ?=

# Optional OS disk image (OS=/path/to/disk.img)
OS       ?=
CPU      ?= pentium3
MEM      ?= 512

# Machine profile (default: pc for legacy host bridge, or PCIe host bridge)
MACHINE ?= pc

# Base emulator flags
QEMU_FLAGS := -M $(MACHINE) -cpu $(CPU) -m $(MEM) -bios $(TARGET_ROM) -serial stdio

# PC speaker audio backend
AUDIO ?= pa
ifneq ($(AUDIO),none)
QEMU_FLAGS += -audiodev $(AUDIO),id=pa -machine pcspk-audiodev=pa
endif

# Attach OS disk image using DRIVE_TYPE (ide, ahci, nvme, or usb)
ifneq ($(OS),)
DRIVE_TYPE ?= ide
ifeq ($(DRIVE_TYPE),ahci)
QEMU_FLAGS += -device ahci,id=ahci -device ide-hd,drive=sata_disk,bus=ahci.0 -drive id=sata_disk,file=$(OS),format=raw,if=none
else ifeq ($(DRIVE_TYPE),nvme)
QEMU_FLAGS += -drive file=$(OS),format=raw,if=none,id=nvme_disk -device nvme,serial=IPO1234,drive=nvme_disk
else ifeq ($(DRIVE_TYPE),usb)
QEMU_FLAGS += -device usb-ehci,id=ehci -device usb-storage,bus=ehci.0,drive=usb_disk -drive id=usb_disk,file=$(OS),format=raw,if=none
else
QEMU_FLAGS += -drive format=raw,file=$(OS),if=ide,index=0
# Optional secondary disk
DISK ?=
ifneq ($(DISK),)
QEMU_FLAGS += -drive format=raw,file=$(DISK),if=ide,index=1
else ifneq ($(wildcard $(dir $(OS))disks/disk.img),)
QEMU_FLAGS += -drive format=raw,file=$(dir $(OS))disks/disk.img,if=ide,index=1
else ifneq ($(wildcard $(dir $(OS))disk.img),)
QEMU_FLAGS += -drive format=raw,file=$(dir $(OS))disk.img,if=ide,index=1
endif
endif
endif

QEMU_FLAGS += $(QEMU_EXTRA)
