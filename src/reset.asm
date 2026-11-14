; reset.asm — x86 Reset Vector (16 bytes at physical 0xFFFFFFF0)

BITS 16
ORG 0xFFF0

%include "contract.inc"

reset_vector:
    jmp     BOOTROM_SEG:BOOTROM_INIT_OFF    ; 5 bytes: EA 00 80 00 F0

    db      '09/12/26'                      ; BIOS release date (8 bytes)
    db      0xFC                            ; PC-AT system model byte
    db      0x00                            ; Submodel byte
    db      0x00                            ; Checksum / padding byte

%if ($ - reset_vector) != 16
    %error "Reset vector must be exactly 16 bytes!"
%endif
