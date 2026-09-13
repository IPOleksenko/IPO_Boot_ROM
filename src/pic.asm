; pic.asm — 8259A Programmable Interrupt Controller Initialization
; Configures master and slave PICs in cascade mode with standard PC vectors.
;
; Master PIC: IRQ 0-7  → INT 08h-0Fh  (ports 0x20/0x21)
; Slave PIC:  IRQ 8-15 → INT 70h-77h  (ports 0xA0/0xA1)

BITS 16

%include "contract.inc"

; =============================================================================
; pic_init — Initialize 8259A PICs in cascade mode
; =============================================================================
; ENTRY: Interrupts should be disabled (CLI).
; EXIT:  Both PICs programmed, all IRQs masked except IRQ2 (cascade).
;        All registers preserved.
;
; ICW (Initialization Command Word) sequence:
;   ICW1 → command port  (starts initialization, specifies edge/level, cascade)
;   ICW2 → data port     (interrupt vector base)
;   ICW3 → data port     (cascade identity / mask)
;   ICW4 → data port     (8086 mode, EOI mode)
; OCW1 → data port       (interrupt mask register)
; =============================================================================
pic_init:
    push    ax
    push    dx

    ; =========================================================================
    ; Master PIC (PIC1) — ports 0x20 (command) / 0x21 (data)
    ; =========================================================================

    ; --- ICW1: Initialization Command Word 1 ---
    ; Bit 4: 1 = ICW1 is being issued (required)
    ; Bit 3: 0 = Edge-triggered mode
    ; Bit 1: 0 = Cascade mode (slave on IRQ2)
    ; Bit 0: 1 = ICW4 needed
    ; Value: 0x11 = 0001_0001b
    mov     al, 0x11
    mov     dx, PIC1_CMD            ; Port 0x20
    out     dx, al

    ; --- ICW2: Interrupt Vector Base ---
    ; IRQ 0 → INT 08h, IRQ 1 → INT 09h, ... IRQ 7 → INT 0Fh
    ; Bits 7:3 = base vector (0x08 >> 3 = 1), Bits 2:0 = IRQ offset (set by HW)
    mov     al, 0x08
    mov     dx, PIC1_DATA           ; Port 0x21
    out     dx, al

    ; --- ICW3: Cascade Configuration (Master) ---
    ; Each bit indicates which IRQ line has a slave attached.
    ; Bit 2 = 1 → Slave PIC is connected on IRQ2
    ; Value: 0x04 = 0000_0100b
    mov     al, 0x04
    out     dx, al                  ; Port 0x21

    ; --- ICW4: Operating Mode ---
    ; Bit 0: 1 = 8086/8088 mode (vs MCS-80/85)
    ; Bit 1: 0 = Normal EOI (not auto-EOI)
    ; Value: 0x01
    mov     al, 0x01
    out     dx, al                  ; Port 0x21

    ; =========================================================================
    ; Slave PIC (PIC2) — ports 0xA0 (command) / 0xA1 (data)
    ; =========================================================================

    ; --- ICW1: Same as master ---
    ; Edge-triggered, cascade, ICW4 needed
    mov     al, 0x11
    mov     dx, PIC2_CMD            ; Port 0xA0
    out     dx, al

    ; --- ICW2: Interrupt Vector Base ---
    ; IRQ 8 → INT 70h, IRQ 9 → INT 71h, ... IRQ 15 → INT 77h
    mov     al, 0x70
    mov     dx, PIC2_DATA           ; Port 0xA1
    out     dx, al

    ; --- ICW3: Cascade Configuration (Slave) ---
    ; Bits 2:0 = Slave ID (which master IRQ line we're connected to)
    ; Value: 0x02 → connected to master's IRQ2
    mov     al, 0x02
    out     dx, al                  ; Port 0xA1

    ; --- ICW4: Operating Mode ---
    ; 8086 mode, normal EOI
    mov     al, 0x01
    out     dx, al                  ; Port 0xA1

    ; =========================================================================
    ; OCW1: Set Interrupt Mask Registers (IMR)
    ; =========================================================================
    ; Mask all IRQs initially for safe boot. Only unmask IRQ2 on master
    ; so slave PIC interrupts can cascade through.

    ; Master IMR: 0xFB = 1111_1011b → all masked EXCEPT IRQ2 (cascade)
    mov     al, 0xFB
    mov     dx, PIC1_DATA           ; Port 0x21
    out     dx, al

    ; Slave IMR: 0xFF = 1111_1111b → all masked
    mov     al, 0xFF
    mov     dx, PIC2_DATA           ; Port 0xA1
    out     dx, al

    pop     dx
    pop     ax
    ret
