; 16-bit reset bootblock assembled at ORG 0xE000 (CS=0xF000, phys 0xFFFFE000/0xFE000).

BITS 16
ORG 0xE000

%include "contract.inc"

global bootrom_init

bootrom_init:
    jmp     short bootrom_boot_start
    db      "IPO_Boot_ROM"

    align 16
romstage_patch_hdr:
    db      "IPORST01"                  ; +0:  8 B marker patched by build_rom.py
    dd      0                           ; +8:  romstage physical base (32-bit XIP in flash)
    dd      0                           ; +12: romstage size (B)
    dd      0                           ; +16: extended firmware physical base (0 = in bank)
    dd      0                           ; +20: extended firmware size (B)

bootrom_boot_start:
    cli
    cld
    mov     ebp, edx                    ; Save reset signature in EBP[15:0]

    ; Map 0xF0000-0xFFFFF back to flash ROM on warm reset
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    cmp     ax, 0x8086
    jne     .pam_warm_reset_done
    shr     eax, 16
    cmp     ax, 0x2500
    jae     .pam_warm_reset_q35

    mov     eax, 0x80000058
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA + 1     ; PAM0 at 0x59
    in      al, dx
    and     al, 0xCF
    out     dx, al
    jmp     .pam_warm_reset_done

.pam_warm_reset_q35:
    mov     eax, 0x80000090
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA         ; PAM0 at 0x90
    in      al, dx
    and     al, 0xCF
    out     dx, al

.pam_warm_reset_done:
    mov     ax, BOOTROM_SEG
    mov     ds, ax

    ; Enable southbridge flash/Super I/O decode without RAM before accessing <0xFFFF0000
    mov     si, .after_lpc_early
    jmp     lpc_early_flash_decode
.after_lpc_early:

    ; Set up CAR (bypasses MTRR setup if CPUID or MTRR is absent)
    %include "car.asm"

    ; Probe 0x2E/0x4E Super I/O to enable COM1 (0x3F8) and PS/2 KBC
    call    superio_early_init

    ; Fill romstage_handoff_t at 0x7000:CAR_HANDOFF_OFF (0x00070040)
    mov     ax, CAR_STACK_SEG
    mov     es, ax
    mov     dword [es:CAR_HANDOFF_OFF + HO_OFF_MAGIC], HO_MAGIC_VAL
    mov     al, [es:CAR_HAS_CPUID]
    mov     [es:CAR_HANDOFF_OFF + HO_OFF_HAS_CPUID], al
    mov     al, [es:CAR_HAS_MTRR]
    mov     [es:CAR_HANDOFF_OFF + HO_OFF_HAS_MTRR], al
    mov     al, [es:CAR_CPU_VENDOR]
    mov     [es:CAR_HANDOFF_OFF + HO_OFF_CPU_VENDOR], al
    mov     al, [es:CAR_LPC_TYPE]
    mov     [es:CAR_HANDOFF_OFF + HO_OFF_LPC_TYPE], al
    mov     ax, [es:CAR_SUPERIO_PORT]
    mov     [es:CAR_HANDOFF_OFF + HO_OFF_SIO_PORT], ax
    mov     ax, [es:CAR_SUPERIO_ID]
    mov     [es:CAR_HANDOFF_OFF + HO_OFF_SIO_ID], ax
    mov     word [es:CAR_HANDOFF_OFF + HO_OFF_HOST_VID], 0
    mov     word [es:CAR_HANDOFF_OFF + HO_OFF_HOST_DID], 0
    mov     dword [es:CAR_HANDOFF_OFF + HO_OFF_RAM_MB], 0
    mov     dword [es:CAR_HANDOFF_OFF + HO_OFF_RAM_BYTES], 0
    mov     dword [es:CAR_HANDOFF_OFF + HO_OFF_DRAM_OK], 0
    mov     dword [es:CAR_HANDOFF_OFF + HO_OFF_SPD_DIMMS], 0
    mov     dword [es:CAR_HANDOFF_OFF + HO_OFF_MRC_FLAGS], 0

    ; Enter 32-bit flat protected mode for Flash-XIP romstage
    lgdt    [cs:boot_gdt_desc]
    mov     eax, cr0
    or      eax, 1
    mov     cr0, eax
    jmp     dword 0x0008:(0x000F0000 + .pm32_entry)

[BITS 32]
.pm32_entry:
    mov     ax, 0x0010
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     fs, ax
    mov     gs, ax
    mov     esp, CAR_STACK32_TOP

    mov     eax, [0x000F0000 + romstage_patch_hdr + 8]
    test    eax, eax
    jz      .skip_romstage
    push    dword CAR_HANDOFF_PADDR
    call    eax
    add     esp, 4
.skip_romstage:

    ; Stage extended firmware payload (> 56 KiB) from flash if present
    xor     ebx, ebx                    ; EBX = fw_ext_staged (0/1)
    mov     esi, [0x000F0000 + romstage_patch_hdr + 16]
    mov     ecx, [0x000F0000 + romstage_patch_hdr + 20]
    test    esi, esi
    jz      .no_ext_fw
    test    ecx, ecx
    jz      .no_ext_fw
    mov     edi, 0x00020000
    cld
    rep     movsb
    mov     ebx, 1
.no_ext_fw:

    ; Return to 16-bit Real Mode through 16-bit protected mode
    jmp     0x0018:.pm16_exit

[BITS 16]
.pm16_exit:
    mov     ax, 0x0020
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     fs, ax
    mov     gs, ax

    mov     eax, cr0
    and     eax, ~1
    mov     cr0, eax
    jmp     BOOTROM_SEG:.back_real16

.back_real16:
    ; Hold staged flag in SI and read CAR handoff fields before teardown
    mov     si, bx

    mov     ax, CAR_STACK_SEG
    mov     ds, ax
    mov     bx, [CAR_HANDOFF_OFF + HO_OFF_HOST_VID]
    mov     dx, [CAR_HANDOFF_OFF + HO_OFF_HOST_DID]
    mov     ecx, [CAR_HANDOFF_OFF + HO_OFF_RAM_BYTES]
    mov     al, [CAR_HANDOFF_OFF + HO_OFF_HAS_MTRR]

    ; Switch stack to DRAM (0x0000:0x7C00) before tearing down CAR MTRRs
    xor     di, di
    mov     ss, di
    xor     esp, esp
    mov     sp, BOOT_STACK_PTR

    push    bx
    push    dx
    push    ecx
    push    si
    call    car_teardown_dram
    pop     si
    pop     ecx
    pop     dx
    pop     bx

    mov     ax, BOOTROM_SEG
    mov     ds, ax

    ; Clear scratch RAM (0x0000:0x0500-0x05FF) and write handoff fields
    xor     ax, ax
    mov     es, ax
    mov     di, 0x0500
    push    cx
    mov     cx, 64
    xor     eax, eax
    cld
    rep     stosd
    pop     cx

    mov     [es:SCRATCH_HOST_VID], bx
    mov     [es:SCRATCH_HOST_DID], dx
    mov     [es:SCRATCH_TOTAL_RAM], ecx

    call    pic_init
    call    pit_init

    ; Print banner and shadow firmware (BX = fw_ext_staged)
    push    si
    mov     si, msg_banner
    call    serial_print
    call    vga_print
    pop     bx

    %include "payload_call.asm"

halt_system:
    mov     si, msg_halted
    call    serial_print
    call    vga_print
.loop:
    hlt
    jmp     .loop

; 16-bit Real Mode COM1 output
serial_tx_char:
    push    dx
    push    ax
    push    cx
    mov     ah, al
    mov     dx, COM1_PORT + 5
    mov     cx, 0xFFFF
.wait_empty:
    in      al, dx
    test    al, 0x20
    jnz     .send_byte
    dec     cx
    jnz     .wait_empty
    jmp     .tx_done
.send_byte:
    mov     al, ah
    mov     dx, COM1_PORT
    out     dx, al
.tx_done:
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

; VGA text buffer output (0xB800:0000)
vga_print:
    push    es
    push    si
    push    di
    push    ax
    push    bx
    push    dx

    mov     dx, 0x03CC
    in      al, dx
    cmp     al, 0xFF
    je      .no_vga
    test    al, 0x02
    jz      .no_vga

    xor     ax, ax
    mov     es, ax
    mov     di, [es:0x0500]

    mov     ax, VGA_TEXT_SEG
    mov     es, ax

.loop:
    lodsb
    test    al, al
    jz      .done
    cmp     al, 10
    je      .newline
    mov     ah, 0x0F
    stosw
    jmp     .loop

.newline:
    mov     ax, di
    xor     dx, dx
    mov     bx, 160
    div     bx
    inc     ax
    mul     bx
    mov     di, ax
    jmp     .loop

.done:
    xor     ax, ax
    mov     es, ax
    mov     [es:0x0500], di

.no_vga:
    pop     dx
    pop     bx
    pop     ax
    pop     di
    pop     si
    pop     es
    ret

%include "lpc_early.asm"
%include "pic.asm"
%include "pit.asm"

align 8
boot_gdt:
    dq 0x0000000000000000               ; 0x00: null
    dq 0x00CF9A000000FFFF               ; 0x08: 32-bit code (base=0, limit=4 GiB)
    dq 0x00CF92000000FFFF               ; 0x10: 32-bit data (base=0, limit=4 GiB)
    dq 0x00009A0F0000FFFF               ; 0x18: 16-bit code (base=0x000F0000, limit=64 KiB)
    dq 0x000092000000FFFF               ; 0x20: 16-bit data (base=0, limit=64 KiB)
boot_gdt_end:

boot_gdt_desc:
    dw (boot_gdt_end - boot_gdt - 1)
    dd (0x000F0000 + boot_gdt)

msg_banner          db "[IPO_Boot_ROM] Hardware initialized. Shadowing firmware...", 10, 0
msg_copying         db "[IPO_Boot_ROM] Shadowing ROM segment 0xF000 to DRAM...", 10, 0
msg_shadow_ok       db "[IPO_Boot_ROM] Shadow RAM locked (read-only). PAM verified.", 10, 0
msg_fw_ok           db "[IPO_Boot_ROM] Firmware magic validated. Jumping to 0xF000:000C", 10, 0
msg_fw_invalid      db "[IPO_Boot_ROM] ERROR: Firmware magic header mismatch!", 10, 0
msg_halted          db "[IPO_Boot_ROM] System halted.", 10, 0
magic_firmware      db "IPO_Firmware"
magic_bootrom       db "IPO_Boot_ROM"
