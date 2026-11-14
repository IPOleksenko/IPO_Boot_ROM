; payload_call.asm — Shadows 64 KB ROM to DRAM, verifies Firmware header, and jumps

SHADOW_STAGE_SEG    equ 0x2000      ; Temporary DRAM buffer (0x20000-0x2FFFF)
SHADOW_TRAMP_SEG    equ 0x0000
SHADOW_TRAMP_OFF    equ 0x0600      ; Low-RAM trampoline outside 0xF0000-0xFFFFF

shadow_and_boot:
    mov     si, msg_copying
    call    serial_print
    call    vga_print

    ; Copy 64 KB Flash ROM window (0xF000:0000) to staging DRAM while ROM is mapped readable.
    ; Changing PAM0 while still fetching from 0xF0000 would pull active code out from under EIP.
    cld
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    mov     ax, SHADOW_STAGE_SEG
    mov     es, ax
    xor     si, si
    xor     di, di
    mov     cx, FW_COPY_WORDS
    rep     movsw

    ; Copy position-independent trampoline into low conventional DRAM (0x0000:0x0600)
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
    ; Select i440FX PAM0 (0x59) or Q35/MCH PAM0 (0x90) from Scratch Host DID
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
    ; Set PAM0 Read+Write DRAM (PAM_RW), preserving reserved lower nibble
    mov     eax, esi
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, bp
    in      al, dx
    and     al, 0x0F
    mov     bl, al
    or      al, PAM_RW
    out     dx, al

    ; Copy 64 KB from staging DRAM (0x2000:0000) into Shadow DRAM (0xF000:0000)
    cld
    mov     ax, SHADOW_STAGE_SEG
    mov     ds, ax
    mov     ax, FW_SHADOW_SEG
    mov     es, ax
    xor     si, si
    xor     di, di
    mov     cx, FW_COPY_WORDS
    rep     movsw

    ; Lock Shadow DRAM read-only (PAM_RE: reads -> DRAM, writes blocked)
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

    ; Validate 12-byte magic ("IPO_Firmware" or "IPO_Boot_ROM") at 0xF000:0x0000
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
