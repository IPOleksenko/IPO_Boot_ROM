# Boot ROM image rules

# Physical XIP base address (4 GiB - FLASH_SIZE) for 32-bit romstage
ROMSTAGE_BASE := $(shell python3 -c "import sys; sys.path.insert(0, '$(TOOLS)'); import build_rom; print(hex(0x100000000 - build_rom.parse_size('$(FLASH_SIZE)')))")

# Bootblock sources included by init.asm
INIT_SRCS := $(SRC)/init.asm \
             $(SRC)/payload_call.asm \
             $(SRC)/lpc_early.asm \
             $(SRC)/car.asm \
             $(SRC)/pic.asm \
             $(SRC)/pit.asm \
             $(INC)/contract.inc

bootrom: $(BOOTROM_BIN)

$(BIN)/init.bin: $(INIT_SRCS)
	@mkdir -p $(BIN)
	$(ASM) $(ASM_FLAGS) $(SRC)/init.asm -o $@

$(BIN)/reset.bin: $(SRC)/reset.asm $(INC)/contract.inc
	@mkdir -p $(BIN)
	$(ASM) $(ASM_FLAGS) $(SRC)/reset.asm -o $@

$(BIN)/payload.bin: $(SRC)/payload.asm $(INC)/contract.inc $(SRC)/assets/vga_dac.bin $(SRC)/assets/font8x16.bin
	@mkdir -p $(BIN)
	$(ASM) $(ASM_FLAGS) $(SRC)/payload.asm -o $@

# 32-bit Flash-XIP romstage objects
$(BIN)/romstage_entry.o: $(SRC)/romstage_entry.asm
	@mkdir -p $(BIN)
	$(ASM) $(ASM_ELF_FLAGS) $< -o $@

$(BIN)/romstage.o: $(SRC)/romstage.c $(SRC)/romstage_hw.h
	@mkdir -p $(BIN)
	$(CC) $(ROMSTAGE_CFLAGS) -std=gnu11 -c $< -o $@

$(BIN)/romstage_mrc.o: $(SRC)/romstage_mrc.c $(SRC)/romstage_hw.h
	@mkdir -p $(BIN)
	$(CC) $(ROMSTAGE_CFLAGS) -std=gnu11 -c $< -o $@

$(BIN)/romstage.elf: $(BIN)/romstage_entry.o $(BIN)/romstage.o $(BIN)/romstage_mrc.o $(SRC)/romstage.ld
	$(LD) -m elf_i386 --oformat elf32-i386 -T $(SRC)/romstage.ld --defsym ROMSTAGE_BASE=$(ROMSTAGE_BASE) -nostdlib -o $@ $(BIN)/romstage_entry.o $(BIN)/romstage.o $(BIN)/romstage_mrc.o

$(BIN)/romstage.bin: $(BIN)/romstage.elf
	$(OBJCOPY) -O binary $< $@
	@if [ $$(size $< | awk 'NR==2 {print $$2 + $$3}') -ne 0 ]; then \
		echo "ERROR: romstage has non-zero .data/.bss (must be pure Flash-XIP)!" >&2; \
		size $<; \
		exit 1; \
	fi

# Rebuild when FLASH_SIZE changes
CONFIG_STAMP := $(BIN)/.size_$(FLASH_SIZE)
$(CONFIG_STAMP):
	@mkdir -p $(BIN)
	@rm -f $(BIN)/.size_*
	@touch $@

# Rebuild when firmware payload changes
FW_PAYLOAD := $(if $(FIRMWARE),$(FIRMWARE),$(BIN)/payload.bin)
FW_STAMP := $(BIN)/.fw_$(subst /,-,$(subst .,-,$(FW_PAYLOAD)))
$(FW_STAMP):
	@mkdir -p $(BIN)
	@rm -f $(BIN)/.fw_*
	@touch $@

# Final flash image
$(BOOTROM_BIN): $(BIN)/init.bin $(BIN)/reset.bin $(BIN)/romstage.bin $(TOOLS)/build_rom.py $(CONFIG_STAMP) $(FW_STAMP) $(FW_PAYLOAD)
	@mkdir -p $(BUILD)
	@if [ ! -f "$(FW_PAYLOAD)" ]; then \
		echo "ERROR: Firmware payload '$(FW_PAYLOAD)' not found!" >&2; \
		exit 1; \
	fi; \
	python3 $(TOOLS)/build_rom.py "$(FLASH_SIZE)" "$(FW_PAYLOAD)" $(BIN)/init.bin $(BIN)/reset.bin $@ --romstage $(BIN)/romstage.bin

.PHONY: bootrom
