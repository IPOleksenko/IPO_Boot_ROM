; 8254 PIT init: ch0 system tick (~18.2 Hz), ch1 DRAM refresh (~66.3 kHz).

BITS 16

%include "contract.inc"

pit_init:
    push    ax
    push    dx

    ; Ch0: mode 2 rate generator, divisor 0xFFFF (~18.2 Hz)
    mov     al, 0x34
    mov     dx, PIT_CMD
    out     dx, al

    mov     ax, PIT_DIVIDER
    mov     dx, PIT_CH0
    out     dx, al
    mov     al, ah
    out     dx, al

    ; Ch1: mode 2 rate generator, LSB only, divisor 18 (~15 us refresh)
    mov     al, 0x54
    mov     dx, PIT_CMD
    out     dx, al

    mov     al, 0x12
    mov     dx, PIT_CH1
    out     dx, al

    pop     dx
    pop     ax
    ret
