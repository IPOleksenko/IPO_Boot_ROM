# =============================================================================
# IPO_Boot_Rom — Reset Vector Boot ROM
# =============================================================================

.DEFAULT_GOAL := all

include mk/config.mk
include mk/bootrom.mk
include mk/run.mk
include mk/clean.mk

all: bootrom

.PHONY: all bootrom run test clean
