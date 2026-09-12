# =============================================================================
#                 EMULATION / RUN TARGET
# =============================================================================

run: $(RUN_ROM)
	@if [ ! -f "$(OS_IMAGE)" ]; then \
		echo "ERROR: OS storage media '$(OS_IMAGE)' not found!" >&2; \
		echo "Usage: make run BIOS=/path/to/firmware.bin OS=/path/to/disk.img" >&2; \
		exit 1; \
	fi
	@echo "================================================================="
	@echo "[IPO_Boot_Rom] Launching QEMU from hardware reset vector"
	@echo "[IPO_Boot_Rom] Embedded BIOS: $(FW_BIN)"
	@echo "[IPO_Boot_Rom] Booting OS from storage media: $(OS_IMAGE)"
	@echo "================================================================="
	$(QEMU) $(QEMU_FLAGS)

.PHONY: run
