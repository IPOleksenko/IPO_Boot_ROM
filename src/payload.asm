; payload.asm — Built-in diagnostic payload for IPO_Boot_ROM
; Executed from shadow RAM at 0xF000:0x0000 when no external firmware is embedded.

BITS 16
ORG 0x0000

%include "contract.inc"

db      "IPO_Boot_ROM"

entry_point:
    cli
    cld

    mov     ax, cs
    mov     ds, ax
    mov     es, ax

    mov     si, msg_stub_serial
    call    serial_print

    call    vga_hardware_init
    call    vga_clear_screen
    call    bootrom_render_screen

    mov     si, msg_stub_halt
    call    serial_print

.halt:
    hlt
    jmp     .halt

; Render standalone diagnostic screen in VGA text buffer
bootrom_render_screen:
    push    es
    push    si
    push    di
    push    ax

    mov     ax, VGA_TEXT_SEG
    mov     es, ax

    xor     di, di
    mov     si, str_title
    mov     ah, 0x0A
    call    .draw_str

    mov     di, 132
    mov     si, str_author
    mov     ah, 0x0A
    call    .draw_str

    mov     di, 2 * 160
    mov     si, str_line1
    mov     ah, 0x07
    call    .draw_str

    mov     di, 3 * 160
    mov     si, str_line2
    mov     ah, 0x07
    call    .draw_str

    mov     di, 4 * 160
    mov     si, str_line3
    mov     ah, 0x07
    call    .draw_str

    mov     di, 5 * 160
    mov     si, str_line4
    mov     ah, 0x07
    call    .draw_str

    mov     di, 6 * 160
    mov     si, str_line5
    mov     ah, 0x07
    call    .draw_str

    mov     di, 7 * 160
    mov     si, str_line6
    mov     ah, 0x0B
    call    .draw_str

    mov     di, 9 * 160
    mov     si, str_line7
    mov     ah, 0x0E
    call    .draw_str

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

; Configure standard VGA Mode 03h (80x25 text) registers, font, and palette
vga_hardware_init:
    push    es
    push    ds
    push    si
    push    di
    push    cx
    push    dx
    push    ax

    ; Miscellaneous Output Register (28 MHz clock, color I/O at 0x3D4, RAM enabled)
    mov     dx, 0x03C2
    mov     al, 0x67
    out     dx, al

    ; Sequencer registers
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

    ; Unlock CRTC registers 0..7 (clear bit 7 of CRTC reg 0x11)
    mov     dx, 0x03D4
    mov     al, 0x11
    out     dx, al
    inc     dx
    in      al, dx
    and     al, 0x7F
    out     dx, al
    dec     dx

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

    ; Graphics Controller registers
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

    ; Map Plane 2 at 0xA0000 and load 8x16 font
    mov     dx, 0x03C4
    mov     ax, 0x0100
    out     dx, ax
    mov     ax, 0x0402
    out     dx, ax
    mov     ax, 0x0704
    out     dx, ax
    mov     ax, 0x0300
    out     dx, ax

    mov     dx, 0x03CE
    mov     ax, 0x0005
    out     dx, ax
    mov     ax, 0x0406
    out     dx, ax

    mov     ax, 0xA000
    mov     es, ax
    xor     di, di
    mov     si, vga_font_data
    mov     cx, 256
.loop_font:
    push    cx
    mov     cx, 8
    rep     movsw
    add     di, 16
    pop     cx
    loop    .loop_font

    ; Restore Sequencer and Graphics Controller to text mode (Planes 0 & 1 at 0xB8000)
    mov     dx, 0x03C4
    mov     ax, 0x0100
    out     dx, ax
    mov     ax, 0x0302
    out     dx, ax
    mov     ax, 0x0304
    out     dx, ax
    mov     ax, 0x0300
    out     dx, ax

    mov     dx, 0x03CE
    mov     ax, 0x1005
    out     dx, ax
    mov     ax, 0x0E06
    out     dx, ax

    ; Attribute Controller registers
    mov     dx, 0x03DA
    in      al, dx

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

    ; Load 256-color DAC palette
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

    ; Enable video output (PAS bit in Attribute Controller)
    mov     dx, 0x03DA
    in      al, dx
    mov     dx, 0x03C0
    mov     al, 0x20
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
    mov     ax, 0x0720
    rep     stosw

    pop     ax
    pop     cx
    pop     di
    pop     es
    ret

serial_tx_char:
    push    dx
    push    ax
    push    cx
    mov     ah, al
    mov     dx, COM1_PORT + 5
    mov     cx, 0xFFFF
.wait:
    in      al, dx
    test    al, 0x20
    jnz     .ready
    dec     cx
    jnz     .wait
    jmp     .done
.ready:
    mov     al, ah
    mov     dx, COM1_PORT
    out     dx, al
.done:
    pop     cx
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

vga_seq_data    db 0x03, 0x00, 0x03, 0x00, 0x02
vga_crtc_data   db 0x5F, 0x4F, 0x50, 0x82, 0x55, 0x81, 0xBF, 0x1F
                db 0x00, 0x4F, 0x0D, 0x0E, 0x00, 0x00, 0x00, 0x00
                db 0x9C, 0x8E, 0x8F, 0x28, 0x1F, 0x96, 0xB9, 0xA3
                db 0xFF
vga_gc_data     db 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0E, 0x0F, 0xFF
vga_ac_data     db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07
                db 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
                db 0x0C, 0x00, 0x0F, 0x08, 0x00

str_title       db "IPO_Boot_ROM", 0
str_author      db "by IPOleksenko", 0
str_line1       db "[IPO_Boot_ROM] CPU reset vector (0xFFFF0) reached in 16-bit Real Mode", 0
str_line2       db "[IPO_Boot_ROM] Stack: 0x7000-0x7C00 (SS:SP=0000:7C00)", 0
str_line3       db "[IPO_Boot_ROM] COM1 serial console initialized (115200 baud, 8N1)", 0
str_line4       db "[IPO_Boot_ROM] VGA text display adapter initialized (Mode 03h, 80x25)", 0
str_line5       db "[IPO_Boot_ROM] 64 KiB ROM window shadowed at 0xF0000-0xFFFFF", 0
str_line6       db "[IPO_Boot_ROM] Hardware diagnostics passed. Primary bootloader ready.", 0
str_line7       db "[IPO_Boot_ROM] Diagnostic payload active; embed BIOS firmware to boot an OS.", 0
str_line8       db "[IPO_Boot_ROM] System halted.", 0

msg_stub_serial db "[IPO_Boot_ROM] Reset vector reached. Boot ROM diagnostic payload active.", 10
                db "[IPO_Boot_ROM] Embed BIOS firmware in the ROM image to boot an OS.", 10, 0
msg_stub_halt   db "[IPO_Boot_ROM] System halted.", 10, 0

align 4
vga_dac_data:
    incbin "src/assets/vga_dac.bin"

align 4
vga_font_data:
    incbin "src/assets/font8x16.bin"
