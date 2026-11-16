; Shadow firmware into 0xF0000-0xFFFFF DRAM, validate header, and jump.
; Input: BX = 1 if >56 KiB payload is already staged at 0x2000:0000,
;        BX = 0 to copy the 56 KiB bank from 0xF000:0000..0xDFFF.

SHADOW_STAGE_SEG    equ 0x2000      ; Staging buffer (0x20000-0x2FFFF)
SHADOW_TRAMP_SEG    equ 0x0000
SHADOW_TRAMP_OFF    equ 0x0600      ; Low-RAM trampoline outside 0xF0000-0xFFFFF

shadow_and_boot:
    push    bx
    mov     si, msg_copying
    call    serial_print
    call    vga_print
    pop     bx

    test    bx, bx
    jnz     .stage_ready

    ; Zero upper 8 KiB of staging buffer (0xF000:0xE000..0xFFFF)
    cld
    mov     ax, SHADOW_STAGE_SEG
    mov     es, ax
    mov     di, 0xE000
    mov     cx, 4096
    xor     ax, ax
    rep     stosw

    ; Copy 56 KiB firmware bank (0xF000:0000..0xDFFF) to staging DRAM
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    mov     ax, SHADOW_STAGE_SEG
    mov     es, ax
    xor     si, si
    xor     di, di
    mov     cx, FW_BANK_COPY_WORDS
    rep     movsw

.stage_ready:
    ; Relocate trampoline below 0xF0000 before switching PAM0
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    xor     ax, ax
    mov     es, ax
    mov     si, shadow_trampoline
    mov     di, SHADOW_TRAMP_OFF
    mov     cx, shadow_trampoline_end - shadow_trampoline
    rep     movsb

    xor     ax, ax
    mov     ds, ax
    jmp     SHADOW_TRAMP_SEG:SHADOW_TRAMP_OFF

shadow_trampoline:
    ; Program PAM0 only on supported 0x8086 host bridges
    mov     ax, [SCRATCH_HOST_VID]
    cmp     ax, 0x8086
    jne     .enter_shadow
    mov     ax, [SCRATCH_HOST_DID]
    test    ax, ax
    jz      .enter_shadow
    cmp     ax, 0x2500
    jae     .q35_pam

    mov     esi, HOST_BRIDGE_PCI_ADDR + (HOST_PAM0_STD & 0xFC)
    mov     bp, PCI_CONFIG_DATA + (HOST_PAM0_STD & 0x03)
    jmp     short .enable_rw

.q35_pam:
    mov     esi, HOST_BRIDGE_PCI_ADDR + (HOST_PAM0_EXT & 0xFC)
    mov     bp, PCI_CONFIG_DATA + (HOST_PAM0_EXT & 0x03)

.enable_rw:
    ; Enable DRAM read/write in PAM0 while preserving low nibble
    mov     eax, esi
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, bp
    in      al, dx
    and     al, 0x0F
    mov     bl, al
    or      al, PAM_RW
    out     dx, al

    ; Copy 64 KiB minus 16 B reset vector into shadow DRAM (0xF000:0000)
    cld
    mov     ax, SHADOW_STAGE_SEG
    mov     ds, ax
    mov     ax, FW_SHADOW_SEG
    mov     es, ax
    xor     si, si
    xor     di, di
    mov     cx, FW_COPY_WORDS - 8
    rep     movsw

    ; Lock shadow DRAM read-only (PAM_RE)
    mov     eax, esi
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, bp
    mov     al, bl
    or      al, PAM_RE
    out     dx, al

.enter_shadow:
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    jmp     BOOTROM_SEG:shadow_resume
shadow_trampoline_end:

shadow_resume:
    mov     si, msg_shadow_ok
    call    serial_print
    call    vga_print

    ; Check 12 B firmware magic signature at 0xF000:0x0000
    mov     ax, FW_SHADOW_SEG
    mov     es, ax
    cld
    mov     si, magic_firmware
    xor     di, di
    mov     cx, 12
    repe    cmpsb
    je      shadow_fw_valid

    mov     si, magic_bootrom
    xor     di, di
    mov     cx, 12
    repe    cmpsb
    je      shadow_fw_valid

    mov     si, msg_fw_invalid
    call    serial_print
    call    vga_print
    jmp     halt_system

shadow_fw_valid:
    mov     si, msg_fw_ok
    call    serial_print
    call    vga_print

    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    xor     esp, esp
    mov     sp, BOOT_STACK_PTR
    cli

    jmp     FW_SHADOW_SEG:FW_ENTRY_OFF
