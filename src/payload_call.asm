; payload_call.asm — Copies Firmware from ROM to RAM, validates signature, and jumps
; Included by init.asm

payload_transfer_and_boot:
    ; -------------------------------------------------------------------------
    ; 1. Copy Firmware Payload: 0xF000:0x0000 (ROM) -> 0x0800:0x0000 (RAM)
    ; -------------------------------------------------------------------------
    mov     si, msg_copying
    call    serial_print
    call    vga_print

    cld
    mov     ax, FW_ROM_SEG
    mov     ds, ax
    xor     si, si                          ; DS:SI = 0xF000:0x0000

    mov     ax, FW_RAM_SEG
    mov     es, ax
    xor     di, di                          ; ES:DI = 0x0800:0x0000

    mov     cx, FW_COPY_WORDS               ; 16384 words = 32768 bytes
    rep     movsw

    ; Restore DS to BOOTROM_SEG so string messages are read from ROM
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    xor     ax, ax
    mov     es, ax

    ; -------------------------------------------------------------------------
    ; 2. Validate Firmware Magic Signature ("IPOF" at 0x0800:0x0000)
    ; -------------------------------------------------------------------------
    mov     ax, FW_RAM_SEG
    mov     es, ax
    mov     eax, [es:0]
    cmp     eax, FW_MAGIC
    je      .fw_valid

    ; Signature mismatch: print diagnostic and halt
    mov     si, msg_fw_invalid
    call    serial_print
    call    vga_print
    jmp     halt_system

.fw_valid:
    mov     si, msg_fw_ok
    call    serial_print
    call    vga_print

    ; -------------------------------------------------------------------------
    ; 3. Prepare Environment & Far Jump to Firmware
    ; -------------------------------------------------------------------------
    ; Contract 2:
    ;   CPU: 16-bit real mode
    ;   CS:IP = 0x0800:0x0000
    ;   SS:SP = 0x0000:0x7000
    ;   DS = 0x0000, ES = 0x0000
    ;   cli (interrupts disabled)
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, BOOT_STACK_PTR
    cli

    jmp     FW_RAM_SEG:FW_ENTRY_OFF
