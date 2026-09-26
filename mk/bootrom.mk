# =============================================================================
#                 BOOT ROM BUILD RULES
# =============================================================================

# All source files that init.asm %includes
INIT_SRCS := $(SRC)/init.asm \
             $(SRC)/payload_call.asm \
             $(SRC)/car.asm \
             $(SRC)/chipset.asm \
             $(SRC)/mrc_440fx.asm \
             $(SRC)/smbus.asm \
             $(SRC)/mrc_q35.asm \
             $(SRC)/pic.asm \
             $(SRC)/pit.asm \
             $(INC)/contract.inc

bootrom: $(BOOTROM_BIN) $(BOOTROM_TMPL)

$(BUILD)/init.bin: $(INIT_SRCS)
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) $(SRC)/init.asm -o $@

$(BUILD)/reset.bin: $(SRC)/reset.asm $(INC)/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) $(SRC)/reset.asm -o $@

$(BUILD)/stub_firmware.bin: $(TESTS)/stub_firmware.bin.asm $(INC)/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) $(TESTS)/stub_firmware.bin.asm -o $@

# Standalone testable ROM: Boot_ROM + embedded internal stub payload
$(BOOTROM_BIN): $(BUILD)/init.bin $(BUILD)/reset.bin $(BUILD)/stub_firmware.bin $(TOOLS)/build_rom.sh
	$(TOOLS)/build_rom.sh $(ROMSIZE) $(FW_OFFSET) $(BUILD)/stub_firmware.bin $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

# Template ROM: Boot_ROM with empty (0xFF) Firmware slot (for external integration)
$(BOOTROM_TMPL): $(BUILD)/init.bin $(BUILD)/reset.bin $(TOOLS)/build_rom.sh
	$(TOOLS)/build_rom.sh $(ROMSIZE) $(FW_OFFSET) "" $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

# Run ROM: Builds complete ROM embedding the specified BIOS/Firmware
$(RUN_ROM): $(BUILD)/init.bin $(BUILD)/reset.bin $(TOOLS)/build_rom.sh $(FW_BIN)
	@fw_target="$(FW_BIN)"; \
	if [ ! -f "$$fw_target" ]; then \
		echo "ERROR: Firmware binary '$$fw_target' not found!" >&2; \
		echo "Usage: make run BIOS=/path/to/firmware.bin [OS=/path/to/disk.img]" >&2; \
		exit 1; \
	fi; \
	$(TOOLS)/build_rom.sh $(ROMSIZE) $(FW_OFFSET) "$$fw_target" $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

test: $(BOOTROM_BIN)
	$(TESTS)/run_qemu_test.sh $<

SPI_FLASH_BIN := $(BUILD)/spi_flash.bin
FLASH_SIZE    ?= 4M

spi-flash: $(SPI_FLASH_BIN)

$(SPI_FLASH_BIN): $(BOOTROM_BIN) $(TOOLS)/package_bios.py
	python3 $(TOOLS)/package_bios.py -i $(BOOTROM_BIN) -o $@ -s $(FLASH_SIZE)

.PHONY: bootrom test spi-flash
