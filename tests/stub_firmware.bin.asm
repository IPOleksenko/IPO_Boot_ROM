; stub_firmware.bin.asm — Minimal test firmware payload for IPO_Boot_Rom testing
; Loaded into RAM at 0x0800:0x0000 (Physical 0x08000)
; Initializes VGA text mode 03h and displays the standalone Boot ROM screen.

BITS 16
ORG 0x0000

%include "contract.inc"

; =============================================================================
; Offset 0x0000: 4-byte Magic Signature
; =============================================================================
dd      FW_MAGIC                        ; 0x464F5049 ("IPOF")

; =============================================================================
; Offset 0x0004: Entry Point
; =============================================================================
entry_point:
    cli
    cld

    mov     ax, cs
    mov     ds, ax
    mov     es, ax

    ; 1. Print test marker to COM1 (0x3F8)
    mov     si, msg_stub_serial
    call    serial_print

    ; 2. Initialize VGA Hardware into Mode 03h (80x25 color text)
    call    vga_hardware_init

    ; 3. Clear VGA text buffer
    call    vga_clear_screen

    ; 4. Render Standalone Boot ROM Screen
    call    bootrom_render_screen

    ; 5. Print success marker to COM1
    mov     si, msg_stub_halt
    call    serial_print

    ; Exit QEMU quickly if isa-debug-exit device is active (automated tests)
    mov     dx, 0x501
    mov     ax, 0x0001
    out     dx, ax
    out     dx, al

.halt:
    hlt
    jmp     .halt

; =============================================================================
; VGA Render Routine
; =============================================================================
bootrom_render_screen:
    push    es
    push    si
    push    di
    push    ax

    mov     ax, VGA_TEXT_SEG
    mov     es, ax

    ; Row 0 Left (Col 0): "IPO_Boot_Rom" (attribute 0x0A: Light Green)
    xor     di, di
    mov     si, str_title
    mov     ah, 0x0A
    call    .draw_str

    ; Row 0 Right (Col 66): "by IPOleksenko" (attribute 0x0A)
    mov     di, 132
    mov     si, str_author
    mov     ah, 0x0A
    call    .draw_str

    ; Row 2 (Col 0): CPU reset vector
    mov     di, 2 * 160
    mov     si, str_line1
    mov     ah, 0x07
    call    .draw_str

    ; Row 3 (Col 0): Stack
    mov     di, 3 * 160
    mov     si, str_line2
    mov     ah, 0x07
    call    .draw_str

    ; Row 4 (Col 0): UART COM1
    mov     di, 4 * 160
    mov     si, str_line3
    mov     ah, 0x07
    call    .draw_str

    ; Row 5 (Col 0): VGA
    mov     di, 5 * 160
    mov     si, str_line4
    mov     ah, 0x07
    call    .draw_str

    ; Row 6 (Col 0): ROM mapping
    mov     di, 6 * 160
    mov     si, str_line5
    mov     ah, 0x07
    call    .draw_str

    ; Row 7 (Col 0): Hardware diagnostics
    mov     di, 7 * 160
    mov     si, str_line6
    mov     ah, 0x0B                        ; Light Cyan
    call    .draw_str

    ; Row 9 (Col 0): Standalone status
    mov     di, 9 * 160
    mov     si, str_line7
    mov     ah, 0x0E                        ; Yellow
    call    .draw_str

    ; Row 10 (Col 0): System halted
    mov     di, 10 * 160
    mov     si, str_line8
    mov     ah, 0x07
    call    .draw_str

    pop     ax
    pop     di
    pop     si
    pop     es
    ret

.draw_str:
    lodsb
    test    al, al
    jz      .draw_done
    stosw
    jmp     .draw_str
.draw_done:
    ret

; =============================================================================
; VGA Mode 03h Hardware Initialization
; =============================================================================
vga_hardware_init:
    push    es
    push    ds
    push    si
    push    di
    push    cx
    push    dx
    push    ax

    ; 1. Misc Output Register (Port 0x3C2)
    mov     dx, 0x03C2
    mov     al, 0x67                        ; 28MHz, color mode (0x3D4), enable RAM
    out     dx, al

    ; 2. Sequencer Registers (Port 0x3C4 / 0x3C5)
    mov     dx, 0x03C4
    mov     si, vga_seq_data
    mov     cx, 5
    xor     ah, ah
.loop_seq:
    mov     al, ah
    out     dx, al
    inc     dx
    lodsb
    out     dx, al
    dec     dx
    inc     ah
    loop    .loop_seq

    ; 3. CRTC: Unlock CRTC registers 0..7 (clear bit 7 of reg 0x11)
    mov     dx, 0x03D4
    mov     al, 0x11
    out     dx, al
    inc     dx
    in      al, dx
    and     al, 0x7F
    out     dx, al
    dec     dx

    ; Write all 25 CRTC registers (Port 0x3D4 / 0x3D5)
    mov     si, vga_crtc_data
    mov     cx, 25
    xor     ah, ah
.loop_crtc:
    mov     al, ah
    out     dx, al
    inc     dx
    lodsb
    out     dx, al
    dec     dx
    inc     ah
    loop    .loop_crtc

    ; 4. Graphics Controller Registers (Port 0x3CE / 0x3CF)
    mov     dx, 0x03CE
    mov     si, vga_gc_data
    mov     cx, 9
    xor     ah, ah
.loop_gc:
    mov     al, ah
    out     dx, al
    inc     dx
    lodsb
    out     dx, al
    dec     dx
    inc     ah
    loop    .loop_gc

    ; 5. Load 8x16 Font into Plane 2 (0xA0000)
    mov     dx, 0x03C4
    mov     ax, 0x0100                      ; Synchronous reset
    out     dx, ax
    mov     ax, 0x0402                      ; Plane 2 write enable (bit 2)
    out     dx, ax
    mov     ax, 0x0704                      ; Sequential addressing
    out     dx, ax
    mov     ax, 0x0300                      ; Clear reset
    out     dx, ax

    mov     dx, 0x03CE
    mov     ax, 0x0005                      ; Write mode 0
    out     dx, ax
    mov     ax, 0x0406                      ; Map memory to 0xA0000 (64KB)
    out     dx, ax

    ; Copy 256 characters * 16 bytes into ES:DI (0xA000:0x0000)
    mov     ax, 0xA000
    mov     es, ax
    xor     di, di
    mov     si, vga_font_data
    mov     cx, 256
.loop_font:
    push    cx
    mov     cx, 8                           ; 8 words = 16 bytes
    rep     movsw
    add     di, 16                          ; Next character slot in 32-byte stride
    pop     cx
    loop    .loop_font

    ; Restore Sequencer to normal text mode (Planes 0 & 1, odd/even enabled)
    mov     dx, 0x03C4
    mov     ax, 0x0100
    out     dx, ax
    mov     ax, 0x0302                      ; Planes 0 & 1 enable
    out     dx, ax
    mov     ax, 0x0304                      ; Odd/even mode enable
    out     dx, ax
    mov     ax, 0x0300
    out     dx, ax

    ; Restore GC to normal text mode (0xB8000)
    mov     dx, 0x03CE
    mov     ax, 0x1005                      ; Odd/even mode
    out     dx, ax
    mov     ax, 0x0E06                      ; Map memory to 0xB8000
    out     dx, ax

    ; 6. Attribute Controller Registers (Port 0x3C0)
    mov     dx, 0x03DA
    in      al, dx                          ; Reset flip-flop

    mov     dx, 0x03C0
    mov     si, vga_ac_data
    mov     cx, 21
    xor     ah, ah
.loop_ac:
    mov     al, ah
    out     dx, al
    lodsb
    out     dx, al
    inc     ah
    loop    .loop_ac

    ; 7. Initialize DAC Palette (256 standard VGA colors)
    mov     dx, 0x03C8
    xor     al, al
    out     dx, al
    inc     dx
    mov     si, vga_dac_data
    mov     cx, 256 * 3
.loop_dac:
    lodsb
    out     dx, al
    loop    .loop_dac

    ; 8. Enable Video Output (PAS bit in Attribute Controller)
    mov     dx, 0x03DA
    in      al, dx
    mov     dx, 0x03C0
    mov     al, 0x20                        ; Bit 5 = 1 (Enable Video / PAS)
    out     dx, al

    pop     ax
    pop     dx
    pop     cx
    pop     di
    pop     si
    pop     ds
    pop     es
    ret

vga_clear_screen:
    push    es
    push    di
    push    cx
    push    ax

    mov     ax, VGA_TEXT_SEG
    mov     es, ax
    xor     di, di
    mov     cx, 80 * 25
    mov     ax, 0x0720                      ; Space (0x20) with attribute 0x07
    rep     stosw

    pop     ax
    pop     cx
    pop     di
    pop     es
    ret

; =============================================================================
; Serial Print Routines
; =============================================================================
serial_tx_char:
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

serial_print:
    push    si
    push    ax
.loop:
    lodsb
    test    al, al
    jz      .done
    cmp     al, 10
    jne     .send
    push    ax
    mov     al, 13
    call    serial_tx_char
    pop     ax
.send:
    call    serial_tx_char
    jmp     .loop
.done:
    pop     ax
    pop     si
    ret

; =============================================================================
; VGA Mode 03h Tables & Assets
; =============================================================================
vga_seq_data    db 0x03, 0x00, 0x03, 0x00, 0x02
vga_crtc_data   db 0x5F, 0x4F, 0x50, 0x82, 0x55, 0x81, 0xBF, 0x1F
                db 0x00, 0x4F, 0x0D, 0x0E, 0x00, 0x00, 0x00, 0x00
                db 0x9C, 0x8E, 0x8F, 0x28, 0x1F, 0x96, 0xB9, 0xA3
                db 0xFF
vga_gc_data     db 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0E, 0x0F, 0xFF
vga_ac_data     db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07
                db 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
                db 0x0C, 0x00, 0x0F, 0x08, 0x00

str_title       db "IPO_Boot_Rom", 0
str_author      db "by IPOleksenko", 0
str_line1       db "[IPO_Boot_Rom] CPU reset vector (0xFFFF0) reached in 16-bit Real Mode", 0
str_line2       db "[IPO_Boot_Rom] System stack allocated at 0x0000:0x7000", 0
str_line3       db "[IPO_Boot_Rom] COM1 serial console initialized (115200 baud, 8N1)", 0
str_line4       db "[IPO_Boot_Rom] VGA text display adapter initialized (Mode 03h, 80x25)", 0
str_line5       db "[IPO_Boot_Rom] ROM mapping verified (0xF0000 - 0xFFFFF, 256 KB Flash)", 0
str_line6       db "[IPO_Boot_Rom] Hardware diagnostics passed. Primary bootloader ready.", 0
str_line7       db "[IPO_Boot_Rom] Standalone mode: waiting for external BIOS Firmware payload...", 0
str_line8       db "[IPO_Boot_Rom] System halted.", 0

msg_stub_serial db "[IPO_Boot_Rom] Reset vector reached. IPO_Firmware reached! Hardware diagnostics passed.", 10
                db "[IPO_Boot_Rom] Standalone mode: waiting for external BIOS Firmware payload...", 10, 0
msg_stub_halt   db "[IPO_Boot_Rom] System halted.", 10, 0

align 4
vga_dac_data:
    incbin "tests/vga_dac.bin"

align 4
vga_font_data:
    incbin "tests/font8x16.bin"
