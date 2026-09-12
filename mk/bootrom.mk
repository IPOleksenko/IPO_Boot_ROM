# =============================================================================
#                 BOOT ROM BUILD RULES
# =============================================================================

bootrom: $(BOOTROM_BIN) $(BOOTROM_TMPL)

$(BUILD)/init.bin: $(SRC)/init.asm $(SRC)/payload_call.asm $(INC)/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) $(SRC)/init.asm -o $@

$(BUILD)/reset.bin: $(SRC)/reset.asm $(INC)/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) $(SRC)/reset.asm -o $@

$(BUILD)/stub_firmware.bin: $(TESTS)/stub_firmware.bin.asm $(INC)/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) $(TESTS)/stub_firmware.bin.asm -o $@

# Standalone testable ROM: Boot_Rom + embedded internal stub payload
$(BOOTROM_BIN): $(BUILD)/init.bin $(BUILD)/reset.bin $(BUILD)/stub_firmware.bin $(TOOLS)/build_rom.sh
	$(TOOLS)/build_rom.sh $(ROMSIZE) $(FW_OFFSET) $(BUILD)/stub_firmware.bin $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

# Template ROM: Boot_Rom with empty (0xFF) Firmware slot (for external integration)
$(BOOTROM_TMPL): $(BUILD)/init.bin $(BUILD)/reset.bin $(TOOLS)/build_rom.sh
	$(TOOLS)/build_rom.sh $(ROMSIZE) $(FW_OFFSET) "" $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

# Run ROM: Builds complete ROM embedding the specified BIOS/Firmware
$(RUN_ROM): $(BUILD)/init.bin $(BUILD)/reset.bin $(TOOLS)/build_rom.sh
	@fw_target="$(FW_BIN)"; \
	if [ ! -f "$$fw_target" ]; then \
		if [ "$$fw_target" = "../IPO_Firmware/build/firmware.bin" ] && [ -d "../IPO_Firmware" ]; then \
			echo "[IPO_Boot_Rom] Building IPO_Firmware..."; \
			$(MAKE) -C ../IPO_Firmware firmware || exit 1; \
		fi; \
	fi; \
	if [ ! -f "$$fw_target" ]; then \
		echo "ERROR: Firmware binary '$$fw_target' not found!" >&2; \
		echo "Usage: make run BIOS=/path/to/firmware.bin [OS=/path/to/disk.img]" >&2; \
		exit 1; \
	fi; \
	$(TOOLS)/build_rom.sh $(ROMSIZE) $(FW_OFFSET) "$$fw_target" $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

test: $(BOOTROM_BIN)
	$(TESTS)/run_qemu_test.sh $<

.PHONY: bootrom test
