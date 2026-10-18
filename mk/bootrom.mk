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

bootrom: $(BOOTROM_BIN)

$(OBJ)/init.bin: $(INIT_SRCS)
	@mkdir -p $(OBJ)
	$(ASM) $(ASM_FLAGS) $(SRC)/init.asm -o $@

$(OBJ)/reset.bin: $(SRC)/reset.asm $(INC)/contract.inc
	@mkdir -p $(OBJ)
	$(ASM) $(ASM_FLAGS) $(SRC)/reset.asm -o $@

$(OBJ)/payload.bin: $(SRC)/payload.asm $(INC)/contract.inc $(SRC)/assets/vga_dac.bin $(SRC)/assets/font8x16.bin
	@mkdir -p $(OBJ)
	$(ASM) $(ASM_FLAGS) $(SRC)/payload.asm -o $@

# Track FLASH_SIZE configuration to auto-rebuild if size changes
CONFIG_STAMP := $(OBJ)/.size_$(FLASH_SIZE)
$(CONFIG_STAMP):
	@mkdir -p $(OBJ)
	@rm -f $(OBJ)/.size_*
	@touch $@

# Track firmware target configuration to auto-rebuild if payload changes
FW_PAYLOAD := $(if $(FW_BIN),$(FW_BIN),$(OBJ)/payload.bin)
FW_STAMP := $(OBJ)/.fw_$(subst /,-,$(subst .,-,$(FW_PAYLOAD)))
$(FW_STAMP):
	@mkdir -p $(OBJ)
	@rm -f $(OBJ)/.fw_*
	@touch $@

# Single unified Boot ROM binary for physical hardware and emulation
$(BOOTROM_BIN): $(OBJ)/init.bin $(OBJ)/reset.bin $(TOOLS)/build_rom.sh $(CONFIG_STAMP) $(FW_STAMP) $(FW_PAYLOAD)
	@mkdir -p $(BUILD)
	@if [ ! -f "$(FW_PAYLOAD)" ]; then \
		echo "ERROR: Firmware payload '$(FW_PAYLOAD)' not found!" >&2; \
		exit 1; \
	fi; \
	$(TOOLS)/build_rom.sh "$(FLASH_SIZE)" "$(FW_PAYLOAD)" $(OBJ)/init.bin $(OBJ)/reset.bin $@

# Alias for backwards compatibility
spi-flash: $(BOOTROM_BIN)

.PHONY: bootrom spi-flash
