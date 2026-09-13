; payload_call.asm — Shadows ROM to DRAM, validates firmware, and jumps
; Included by init.asm (Phase 4)
;
; Shadow ROM process:
;   1. Open PAM for writes to 0xF0000-0xFFFFF (reads still from ROM)
;   2. Copy 64KB from ROM to DRAM at same address range
;   3. Lock PAM to read-only (reads from DRAM shadow, writes blocked)
;   4. Validate firmware magic signature at 0xF000:0x0000
;   5. Jump to firmware at 0xF000:0x0004
;
; NOTE: After step 3, all code execution switches seamlessly to DRAM shadow
;       because the CPU's instruction fetches now read from DRAM instead of ROM.
;       The DRAM shadow contains an identical copy, so execution continues
;       uninterrupted.

shadow_and_boot:
    ; -------------------------------------------------------------------------
    ; 1. Open PAM: enable DRAM writes to 0xF0000-0xFFFFF
    ;    Reads still go to ROM, writes go to DRAM
    ; -------------------------------------------------------------------------
    mov     si, msg_copying
    call    serial_print
    call    vga_print

    call    pam_open_write

    ; -------------------------------------------------------------------------
    ; 2. Copy 64KB from ROM (read path) to DRAM (write path) at 0xF0000
    ;    PAM state: RE=0 (reads → ROM), WE=1 (writes → DRAM)
    ;    So DS:SI reads from ROM, ES:DI writes to DRAM, same address range!
    ; -------------------------------------------------------------------------
    cld
    mov     ax, BOOTROM_SEG                 ; 0xF000
    mov     ds, ax
    mov     es, ax
    xor     si, si                          ; DS:SI = 0xF000:0x0000 (read from ROM)
    xor     di, di                          ; ES:DI = 0xF000:0x0000 (write to DRAM)
    mov     cx, FW_COPY_WORDS               ; 32768 words = 64 KB
    rep     movsw

    ; Restore DS to our code segment (now in DRAM, but same content)
    mov     ax, BOOTROM_SEG
    mov     ds, ax

    ; -------------------------------------------------------------------------
    ; 3. Lock PAM: reads from DRAM shadow, writes blocked
    ;    After this call, ALL instruction fetches from 0xF0000-0xFFFFF
    ;    come from DRAM. Since we just copied ROM → DRAM, execution continues
    ;    seamlessly from the DRAM copy.
    ; -------------------------------------------------------------------------
    call    pam_lock_readonly

    mov     si, msg_shadow_ok
    call    serial_print
    call    vga_print

    ; -------------------------------------------------------------------------
    ; 4. Validate Firmware Magic Signature ("IPOF" at 0xF000:0x0000)
    ;    Now reading from DRAM shadow (which is a copy of ROM)
    ; -------------------------------------------------------------------------
    mov     ax, FW_SHADOW_SEG
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
    ; 5. Prepare Environment & Far Jump to Firmware in Shadow RAM
    ; -------------------------------------------------------------------------
    ; Contract 2 (Hardware Mode):
    ;   CPU: 16-bit real mode
    ;   CS:IP = 0xF000:0x0004
    ;   SS:SP = 0x0000:0x7000
    ;   DS = 0x0000, ES = 0x0000
    ;   cli (interrupts disabled)
    ;   Shadow RAM 0xF0000-0xFFFFF is read-only (PAM locked)
    ;   PIC initialized (all IRQs masked except cascade)
    ;   PIT initialized (18.2 Hz system timer)
    ;   DRAM is fully initialized and available
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, BOOT_STACK_PTR
    cli

    jmp     FW_SHADOW_SEG:FW_ENTRY_OFF
