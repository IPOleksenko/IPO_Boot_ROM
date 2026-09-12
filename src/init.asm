; init.asm — Early initialization for IPO_Boot_Rom
; Assembled with ORG 0xF800, executed in CS=0xF000 (Physical 0xFF800 / 0xFFFFF800)

BITS 16
ORG 0xF800

%include "contract.inc"

global bootrom_init

bootrom_init:
    ; 1. Disable maskable interrupts immediately
    cli
    cld

    ; 2. Initialize segment registers for ROM execution
    ; CS is 0xF000. Set DS=0xF000 so strings/constants read from ROM
    mov     ax, BOOTROM_SEG
    mov     ds, ax

    ; 3. Setup temporary stack in conventional RAM (0x0000:0x7000)
    xor     ax, ax
    mov     ss, ax
    mov     sp, BOOT_STACK_PTR

    ; Reset VGA cursor offset tracker in scratch RAM (0x0000:0x0500)
    mov     es, ax
    mov     word [es:0x0500], 0

    ; 4. Initialize COM1 Serial Port for headless diagnostics
    call    serial_init

    ; 5. Print initial banner
    mov     si, msg_banner
    call    serial_print
    call    vga_print

    ; 6. Transfer control to payload handling
    %include "payload_call.asm"

halt_system:
    mov     si, msg_halted
    call    serial_print
    call    vga_print
.loop:
    hlt
    jmp     .loop

; =============================================================================
; Serial (COM1) Driver Routines (Direct Port I/O)
; =============================================================================
serial_init:
    push    dx
    push    ax

    ; Disable UART interrupts
    mov     dx, COM1_PORT + 1
    xor     al, al
    out     dx, al

    ; Enable DLAB (baud rate divisor)
    mov     dx, COM1_PORT + 3
    mov     al, 0x80
    out     dx, al

    ; Set divisor to 1 (115200 baud)
    mov     dx, COM1_PORT + 0
    mov     al, 0x01
    out     dx, al
    mov     dx, COM1_PORT + 1
    xor     al, al
    out     dx, al

    ; 8 bits, no parity, 1 stop bit (8N1), disable DLAB
    mov     dx, COM1_PORT + 3
    mov     al, 0x03
    out     dx, al

    ; Enable FIFO, clear TX/RX queues, 14-byte threshold
    mov     dx, COM1_PORT + 2
    mov     al, 0xC7
    out     dx, al

    ; Enable DTR, RTS, OUT2
    mov     dx, COM1_PORT + 4
    mov     al, 0x0B
    out     dx, al

    pop     ax
    pop     dx
    ret

serial_tx_char:
    push    dx
    push    ax
    mov     ah, al                  ; Save char to send

    mov     dx, COM1_PORT + 5       ; Line Status Register
.wait_empty:
    in      al, dx
    test    al, 0x20                ; Transmitter Holding Register Empty?
    jz      .wait_empty

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
    cmp     al, 10                  ; If newline (\n), send carriage return (\r) first
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
; Direct VGA Text Buffer (0xB800:0000) Output Routines
; =============================================================================
vga_print:
    push    es
    push    si
    push    di
    push    ax
    push    bx

    ; Read cursor offset from RAM 0x0000:0x0500
    xor     ax, ax
    mov     es, ax
    mov     di, [es:0x0500]

    ; Point ES to VGA text segment
    mov     ax, VGA_TEXT_SEG
    mov     es, ax

.loop:
    lodsb
    test    al, al
    jz      .done

    cmp     al, 10                  ; Newline
    je      .newline

    ; Write character + attribute (0x0F = white on black)
    mov     ah, 0x0F
    stosw
    jmp     .loop

.newline:
    ; Move DI to the start of the next 80-column line (160 bytes per row)
    mov     ax, di
    xor     dx, dx
    mov     bx, 160
    div     bx                      ; AX = current row
    inc     ax
    mul     bx
    mov     di, ax
    jmp     .loop

.done:
    ; Save updated DI back to scratch RAM 0x0000:0x0500
    xor     ax, ax
    mov     es, ax
    mov     [es:0x0500], di

    pop     bx
    pop     ax
    pop     di
    pop     si
    pop     es
    ret

; =============================================================================
; Data / Strings (Stored in ROM)
; =============================================================================
msg_banner      db "[IPO_Boot_Rom] Reset vector reached. Initializing system...", 10, 0
msg_copying     db "[IPO_Boot_Rom] Copying Firmware from ROM (0xF000:0000) to RAM (0x0800:0000)...", 10, 0
msg_fw_ok       db "[IPO_Boot_Rom] Firmware magic 'IPOF' validated. Jumping to 0x0800:0000...", 10, 0
msg_fw_invalid  db "[IPO_Boot_Rom] ERROR: Firmware magic header mismatch!", 10, 0
msg_halted      db "[IPO_Boot_Rom] System halted.", 10, 0
