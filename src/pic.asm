; 8259A PIC init: remap IRQ 0-7 -> INT 08h-0Fh, IRQ 8-15 -> INT 70h-77h.

BITS 16

%include "contract.inc"

pic_init:
    push    ax
    push    dx

    ; Master PIC (0x20 / 0x21): ICW1..ICW4
    mov     al, 0x11
    mov     dx, PIC1_CMD
    out     dx, al

    mov     al, 0x08
    mov     dx, PIC1_DATA
    out     dx, al

    mov     al, 0x04
    out     dx, al

    mov     al, 0x01
    out     dx, al

    ; Slave PIC (0xA0 / 0xA1): ICW1..ICW4
    mov     al, 0x11
    mov     dx, PIC2_CMD
    out     dx, al

    mov     al, 0x70
    mov     dx, PIC2_DATA
    out     dx, al

    mov     al, 0x02
    out     dx, al

    mov     al, 0x01
    out     dx, al

    ; Mask all IRQs except cascade IRQ2 until IVT handlers are installed
    mov     al, 0xFB
    mov     dx, PIC1_DATA
    out     dx, al

    mov     al, 0xFF
    mov     dx, PIC2_DATA
    out     dx, al

    pop     dx
    pop     ax
    ret
