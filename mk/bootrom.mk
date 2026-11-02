# =============================================================================
#                 BOOT ROM BUILD RULES
# =============================================================================

# All source files that init.asm %includes
INIT_SRCS := $(SRC)/init.asm \
             $(SRC)/payload_call.asm \
             $(SRC)/car.asm \
             $(SRC)/host_bridge.asm \
             $(SRC)/mrc.asm \
             $(SRC)/smbus.asm \
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

# Track FLASH_SIZE configuration to auto-rebuild if size changes
CONFIG_STAMP := $(BIN)/.size_$(FLASH_SIZE)
$(CONFIG_STAMP):
	@mkdir -p $(BIN)
	@rm -f $(BIN)/.size_*
	@touch $@

# Track firmware target configuration to auto-rebuild if payload changes
FW_PAYLOAD := $(if $(FIRMWARE),$(FIRMWARE),$(BIN)/payload.bin)
FW_STAMP := $(BIN)/.fw_$(subst /,-,$(subst .,-,$(FW_PAYLOAD)))
$(FW_STAMP):
	@mkdir -p $(BIN)
	@rm -f $(BIN)/.fw_*
	@touch $@

# Single unified Boot ROM binary for physical hardware and emulation
$(BOOTROM_BIN): $(BIN)/init.bin $(BIN)/reset.bin $(TOOLS)/build_rom.sh $(CONFIG_STAMP) $(FW_STAMP) $(FW_PAYLOAD)
	@mkdir -p $(BUILD)
	@if [ ! -f "$(FW_PAYLOAD)" ]; then \
		echo "ERROR: Firmware payload '$(FW_PAYLOAD)' not found!" >&2; \
		exit 1; \
	fi; \
	$(TOOLS)/build_rom.sh "$(FLASH_SIZE)" "$(FW_PAYLOAD)" $(BIN)/init.bin $(BIN)/reset.bin $@

# Alias for backwards compatibility
spi-flash: $(BOOTROM_BIN)

.PHONY: bootrom spi-flash
