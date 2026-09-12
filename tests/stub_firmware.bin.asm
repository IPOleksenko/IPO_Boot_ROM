; stub_firmware.bin.asm — Minimal test firmware payload for IPO_Boot_Rom testing
; Loaded into RAM at 0x0800:0x0000 (Physical 0x08000)

BITS 16
ORG 0x0000

%include "contract.inc"

; Offset 0x0000: 4-byte Magic Signature
dd      FW_MAGIC                        ; 0x464F5049 ("IPOF")

; Offset 0x0004: Entry Point
entry_point:
    cli
    mov     ax, cs
    mov     ds, ax

    ; Print test marker to COM1 (0x3F8)
    mov     si, msg_stub
.serial_loop:
    lodsb
    test    al, al
    jz      .serial_done
    cmp     al, 10
    jne     .send_char
    push    ax
    mov     al, 13
    call    serial_tx
    pop     ax
.send_char:
    call    serial_tx
    jmp     .serial_loop

.serial_done:
    ; Also write to VGA buffer directly
    mov     ax, VGA_TEXT_SEG
    mov     es, ax
    ; Line 4 in VGA (offset 160 * 4 = 640)
    mov     di, 640
    mov     si, msg_stub
.vga_loop:
    lodsb
    test    al, al
    jz      .halt
    cmp     al, 10
    je      .halt
    mov     ah, 0x0A                    ; Light green on black
    stosw
    jmp     .vga_loop

.halt:
    ; Exit QEMU quickly if isa-debug-exit device is active
    mov     dx, 0x501
    mov     ax, 0x0001
    out     dx, ax
    out     dx, al

    hlt
    jmp     .halt

serial_tx:
    push    dx
    push    ax
    mov     ah, al
    mov     dx, COM1_PORT + 5
.wait:
    in      al, dx
    test    al, 0x20
    jz      .wait
    mov     al, ah
    mov     dx, COM1_PORT
    out     dx, al
    pop     ax
    pop     dx
    ret

msg_stub db "[IPO_Firmware] IPO_Firmware reached! Stub firmware test PASSED.", 10, 0

; Pad to 512 bytes for a clean sector-sized binary
times 512 - ($ - $$) db 0
