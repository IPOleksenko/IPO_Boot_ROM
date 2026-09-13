; pit.asm — 8254 Programmable Interval Timer Initialization
; Configures PIT channels for system timer and DRAM refresh.
;
; Channel 0: System timer — Mode 2 (Rate Generator), ~18.2 Hz
; Channel 1: DRAM refresh  — Mode 2 (Rate Generator), divisor 18

BITS 16

%include "contract.inc"

; =============================================================================
; pit_init — Initialize 8254 PIT Channels 0 and 1
; =============================================================================
; ENTRY: No prerequisites.
; EXIT:  Channel 0 running at ~18.2 Hz (divider 0xFFFF).
;        Channel 1 running with standard DRAM refresh divisor (18).
;        All registers preserved.
;
; PIT Command Register (port 0x43) format:
;   Bits 7:6 — Channel select (00=Ch0, 01=Ch1, 10=Ch2, 11=Read-Back)
;   Bits 5:4 — Access mode (00=Latch, 01=LSB, 10=MSB, 11=LSB/MSB)
;   Bits 3:1 — Operating mode (000=0, 001=1, 010=2, 011=3, 100=4, 101=5)
;   Bit  0   — BCD/Binary (0=16-bit binary, 1=BCD)
; =============================================================================
pit_init:
    push    ax
    push    dx

    ; =========================================================================
    ; Channel 0 — System Timer (IRQ 0)
    ; =========================================================================
    ; Command byte: 0x34
    ;   Bits 7:6 = 00  → Channel 0
    ;   Bits 5:4 = 11  → Access LSB then MSB
    ;   Bits 3:1 = 010 → Mode 2 (Rate Generator: periodic square wave)
    ;   Bit  0   = 0   → 16-bit binary counting
    ;
    ; Divisor: PIT_DIVIDER = 0xFFFF = 65535
    ; Frequency: 1,193,182 / 65535 ≈ 18.2065 Hz (~54.925 ms period)
    ; This matches the standard PC BIOS tick rate.

    mov     al, 0x34                ; Channel 0, LSB/MSB, Mode 2, Binary
    mov     dx, PIT_CMD             ; Port 0x43 — Mode/Command register
    out     dx, al

    ; Write 16-bit divisor to Channel 0 data port (LSB first, then MSB)
    mov     ax, PIT_DIVIDER         ; AX = 0xFFFF
    mov     dx, PIT_CH0             ; Port 0x40 — Channel 0 data
    out     dx, al                  ; Write low byte (0xFF)
    mov     al, ah                  ; AL = high byte
    out     dx, al                  ; Write high byte (0xFF)

    ; =========================================================================
    ; Channel 1 — DRAM Refresh Timer (DMA Channel 0)
    ; =========================================================================
    ; Command byte: 0x54
    ;   Bits 7:6 = 01  → Channel 1
    ;   Bits 5:4 = 01  → Access LSB only
    ;   Bits 3:1 = 010 → Mode 2 (Rate Generator)
    ;   Bit  0   = 0   → 16-bit binary counting
    ;
    ; Divisor: 18 (0x12)
    ; Frequency: 1,193,182 / 18 ≈ 66,288 Hz (~15.09 µs period)
    ; This is the standard PC DRAM refresh rate — one refresh request
    ; approximately every 15 µs, ensuring all DRAM rows are refreshed
    ; within the required 2 ms window (128 rows × 15.09 µs ≈ 1.93 ms).

    mov     al, 0x54                ; Channel 1, LSB only, Mode 2, Binary
    mov     dx, PIT_CMD             ; Port 0x43
    out     dx, al

    mov     al, 0x12                ; Divisor = 18 (0x12)
    mov     dx, PIT_CH1             ; Port 0x41 — Channel 1 data
    out     dx, al                  ; Write low byte only (LSB access mode)

    pop     dx
    pop     ax
    ret
