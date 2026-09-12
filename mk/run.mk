# =============================================================================
#                 EMULATION / RUN TARGET
# =============================================================================

run: $(TARGET_ROM)
ifneq ($(OS_IMAGE),)
	@if [ ! -f "$(OS_IMAGE)" ]; then \
		echo "ERROR: OS storage media '$(OS_IMAGE)' not found!" >&2; \
		exit 1; \
	fi
endif
ifneq ($(FW_BIN),)
	@echo "================================================================="
	@echo "[IPO_Boot_Rom] Launching QEMU from hardware reset vector"
	@echo "[IPO_Boot_Rom] Embedded BIOS: $(FW_BIN)"
ifneq ($(OS_IMAGE),)
	@echo "[IPO_Boot_Rom] Booting OS from storage media: $(OS_IMAGE)"
endif
	@echo "================================================================="
else
	@echo "================================================================="
	@echo "[IPO_Boot_Rom] Launching QEMU with Boot ROM (standalone)"
	@echo "[IPO_Boot_Rom] Tip: To embed a BIOS and boot an OS, use:"
	@echo "[IPO_Boot_Rom]      make run BIOS=path/to/fw.bin [OS=path/to/os.img]"
	@echo "================================================================="
endif
	$(QEMU) $(QEMU_FLAGS)

.PHONY: run
