# =============================================================================
#                 EMULATION / RUN TARGET
# =============================================================================

run: $(TARGET_ROM)
ifneq ($(OS),)
	@if [ ! -f "$(OS)" ]; then \
		echo "ERROR: OS storage media '$(OS)' not found!" >&2; \
		exit 1; \
	fi
endif
ifneq ($(FIRMWARE),)
	@echo "================================================================="
	@echo "[IPO_Boot_ROM] Launching QEMU from hardware reset vector"
	@echo "[IPO_Boot_ROM] Embedded Firmware: $(FIRMWARE)"
ifneq ($(OS),)
	@echo "[IPO_Boot_ROM] Booting OS from storage media: $(OS)"
endif
	@echo "================================================================="
else
	@echo "================================================================="
	@echo "[IPO_Boot_ROM] Launching QEMU with Boot ROM (standalone)"
	@echo "[IPO_Boot_ROM] Tip: To embed a firmware payload and boot an OS, use:"
	@echo "[IPO_Boot_ROM]      make run FIRMWARE=path/to/fw.bin [OS=path/to/os.img]"
	@echo "================================================================="
endif
	$(QEMU) $(QEMU_FLAGS)

.PHONY: run
