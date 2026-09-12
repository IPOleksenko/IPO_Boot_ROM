# =============================================================================
# IPO_Boot_Rom Makefile — Independent Reset Vector Boot ROM Build System
# =============================================================================

ASM         := nasm
BUILD       := build

# 256 KB ROM parameters
ROMSIZE     := 262144
FW_OFFSET   := 196608  # 0x30000 (mapped to 0xFFFF0000 / alias 0xF000:0x0000)
INIT_OFFSET := 260096  # 0x3F800 (mapped to 0xFFFFF800 / alias 0xF000:0xF800)

ASM_FLAGS   := -f bin -Iinclude -Isrc

.DEFAULT_GOAL := all

all: $(BUILD)/bootrom.bin $(BUILD)/bootrom_template.bin

$(BUILD)/init.bin: src/init.asm src/payload_call.asm include/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) src/init.asm -o $@

$(BUILD)/reset.bin: src/reset.asm include/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) src/reset.asm -o $@

$(BUILD)/stub_firmware.bin: tests/stub_firmware.bin.asm include/contract.inc
	@mkdir -p $(BUILD)
	$(ASM) $(ASM_FLAGS) tests/stub_firmware.bin.asm -o $@

# Standalone testable ROM: Boot_Rom + embedded Stub Firmware
$(BUILD)/bootrom.bin: $(BUILD)/init.bin $(BUILD)/reset.bin $(BUILD)/stub_firmware.bin tools/build_rom.sh
	tools/build_rom.sh $(ROMSIZE) $(FW_OFFSET) $(BUILD)/stub_firmware.bin $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

# Template ROM: Boot_Rom with empty (0xFF) Firmware slot (for external integration)
$(BUILD)/bootrom_template.bin: $(BUILD)/init.bin $(BUILD)/reset.bin tools/build_rom.sh
	tools/build_rom.sh $(ROMSIZE) $(FW_OFFSET) "" $(INIT_OFFSET) $(BUILD)/init.bin $(BUILD)/reset.bin $@

test: $(BUILD)/bootrom.bin
	tests/run_qemu_test.sh $<

clean:
	rm -rf $(BUILD)

.PHONY: all test clean
