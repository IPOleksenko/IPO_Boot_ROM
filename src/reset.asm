; reset.asm — x86 Reset Vector (exactly 16 bytes)
; Located at physical address 0xFFFFFFF0 (offset 262128 / 0x3FFF0 in 256KB ROM).
;
; On x86 CPU reset:
;   CS selector = 0xF000, hidden base = 0xFFFF0000, IP = 0xFFF0
;   First instruction executed is at 0xFFFF0000 + 0xFFF0 = 0xFFFFFFF0.
;
; The far jump resets the hidden base of CS to 0xF000 * 16 = 0x000F0000,
; enabling normal 16-bit real mode execution in the 1MB address space.

BITS 16
ORG 0xFFF0

%include "contract.inc"

reset_vector:
    jmp     BOOTROM_SEG:BOOTROM_INIT_OFF    ; 5 bytes: EA 00 F8 00 F0

    ; BIOS date string (8 bytes: MM/DD/YY) + system model byte + padding
    db      '09/12/26'                      ; 8 bytes
    db      0xFC                            ; System model byte (PC-AT)
    db      0x00                            ; Checksum / padding byte

    ; Verify that reset vector is exactly 16 bytes
    times 16 - ($ - reset_vector) db 0x90
