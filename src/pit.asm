; pit.asm — 8254 Programmable Interval Timer initialization
; Channel 0: System timer (~18.2 Hz), Channel 1: DRAM refresh (~66.3 kHz)

BITS 16

%include "contract.inc"

pit_init:
    push    ax
    push    dx

    ; Channel 0: Mode 2 (Rate Generator), 16-bit binary, divisor 0xFFFF (~18.2 Hz)
    mov     al, 0x34
    mov     dx, PIT_CMD
    out     dx, al

    mov     ax, PIT_DIVIDER
    mov     dx, PIT_CH0
    out     dx, al
    mov     al, ah
    out     dx, al

    ; Channel 1: Mode 2 (Rate Generator), LSB only, divisor 18 (~15 us DRAM refresh)
    mov     al, 0x54
    mov     dx, PIT_CMD
    out     dx, al

    mov     al, 0x12
    mov     dx, PIT_CH1
    out     dx, al

    pop     dx
    pop     ax
    ret
