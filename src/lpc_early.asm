; Early southbridge flash/I/O decode and Super I/O COM1/KBC setup.
; Preserves EBP during register-only execution before CAR stack setup.

BITS 16

; Stackless PCI CF8/CFC dword read: EAX = addr -> EAX (clobbers DX)
lpc_pci_read32_nostack:
    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    ret

; Stackless PCI CF8/CFC dword write: EAX = addr, ECX = val (clobbers DX)
lpc_pci_write32_nostack:
    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    mov     eax, ecx
    out     dx, eax
    ret

; Stackless decode routine; SI holds return offset
lpc_early_flash_decode:
    ; BL = detected bridge type (0=none, 1=legacy ISA, 2=LPC)
    xor     ebx, ebx

    ; Probe PCIe/LPC southbridge at Bus 0, Dev 31, Fn 0 (0x8000F800)
    mov     eax, LPC_ICH_PCI_ADDR
    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    cmp     ax, 0x8086
    jne     .check_piix

    shr     eax, 16
    cmp     ax, 0x2400
    jb      .check_piix

    mov     bl, 2                       ; LPC bridge found

    ; Program LPC_IO_DEC (0x80: COMA=3F8, COMB=2F8) + LPC_EN (0x82: COMA/B, KBC, MC, CNF1/2)
    mov     eax, LPC_ICH_PCI_ADDR | 0x80
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    and     eax, 0xFFFFFF00             ; COMA_DEC[2:0] = 000 (0x3F8)
    or      eax, 0x34030010             ; LPC_EN bits 0,1,10,12,13 + COMB=0x2F8
    mov     dx, PCI_CONFIG_ADDR
    mov     ecx, eax
    mov     eax, LPC_ICH_PCI_ADDR | 0x80
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    mov     eax, ecx
    out     dx, eax

    ; Enable flash decode ranges (BIOS_DEC_EN1 at 0xD8, low 16 bits = 0xFFFF)
    mov     eax, LPC_ICH_PCI_ADDR | 0xD8
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    or      eax, 0x0000FFFF
    mov     ecx, eax
    mov     eax, LPC_ICH_PCI_ADDR | 0xD8
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    mov     eax, ecx
    out     dx, eax
    jmp     .lpc_done

.check_piix:
    ; Probe legacy PCI-ISA southbridge at 0:1.0 or 0:7.0
    mov     eax, LPC_PIIX_PCI_ADDR1
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    cmp     ax, 0x8086
    je      .piix_found_dev1

    mov     eax, LPC_PIIX_PCI_ADDR7
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    cmp     ax, 0x8086
    jne     .lpc_done
    mov     edi, LPC_PIIX_PCI_ADDR7
    jmp     .piix_setup

.piix_found_dev1:
    mov     edi, LPC_PIIX_PCI_ADDR1

.piix_setup:
    shr     eax, 16
    cmp     ax, 0x122E
    je      .piix_ok
    cmp     ax, 0x7000
    je      .piix_ok
    cmp     ax, 0x7110
    jne     .lpc_done
.piix_ok:
    mov     bl, 1
    ; XBCS (0x4E): enable extended flash decode (bits 6-7) and KBC (bit 2)
    mov     eax, edi
    or      eax, 0x4C
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    or      eax, 0x00C40000
    mov     ecx, eax
    mov     eax, edi
    or      eax, 0x4C
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    mov     eax, ecx
    out     dx, eax

.lpc_done:
    jmp     si

; Early Super I/O init (requires CAR stack).
; Probes 0x2E and 0x4E across standard PnP unlock sequences to enable COM1 and KBC.
; Saves CAR_SUPERIO_PORT and CAR_SUPERIO_ID in CAR scratch.
sio_read_reg:
    ; DX = base port (0x2E or 0x4E), AL = index -> returns AL
    out     dx, al
    inc     dx
    in      al, dx
    dec     dx
    ret

sio_write_reg:
    ; DX = base port, AH = index, AL = value
    push    ax
    mov     al, ah
    out     dx, al
    pop     ax
    inc     dx
    out     dx, al
    dec     dx
    ret

sio_probe_and_enable_port:
    ; Input:  DX = index port (0x2E or 0x4E)
    ; Output: CF=0 with AX=chip ID if found, CF=1 otherwise
    push    bx
    push    cx

    ; Unlock key 1 (0x87, 0x87)
    mov     al, 0x87
    out     dx, al
    out     dx, al

    mov     al, 0x20
    call    sio_read_reg
    mov     bh, al
    mov     al, 0x21
    call    sio_read_reg
    mov     bl, al
    cmp     bx, 0xFFFF
    je      .try_smsc
    test    bx, bx
    jz      .try_smsc

    ; Type 1 Super I/O: UART1=LDN 2, KBC=LDN 5
    mov     cl, 2
    mov     ch, 5
    jmp     .enable_devices

.try_smsc:
    mov     al, 0xAA
    out     dx, al
    ; Unlock key 2 (0x55)
    mov     al, 0x55
    out     dx, al
    mov     al, 0x20
    call    sio_read_reg
    mov     bh, al
    mov     al, 0x21
    call    sio_read_reg
    mov     bl, al
    cmp     bx, 0xFFFF
    je      .try_ite
    test    bx, bx
    jz      .try_ite

    ; Type 2 Super I/O: UART1=LDN 4, KBC=LDN 7
    mov     cl, 4
    mov     ch, 7
    jmp     .enable_devices

.try_ite:
    mov     al, 0xAA
    out     dx, al
    ; Unlock key 3 (0x87, 0x01, 0x55, plus 0x55 on 0x2E or 0xAA on 0x4E)
    mov     al, 0x87
    out     dx, al
    mov     al, 0x01
    out     dx, al
    mov     al, 0x55
    out     dx, al
    cmp     dx, 0x2E
    je      .ite_2e
    mov     al, 0xAA
.ite_2e:
    out     dx, al

    mov     al, 0x20
    call    sio_read_reg
    mov     bh, al
    mov     al, 0x21
    call    sio_read_reg
    mov     bl, al
    cmp     bx, 0xFFFF
    je      .not_found
    test    bx, bx
    jz      .not_found

    ; Type 3 Super I/O: UART1=LDN 1, KBC=LDN 5
    mov     cl, 1
    mov     ch, 5

    ; Enable UART1 at 0x03F8, IRQ 4
.enable_devices:
    mov     ah, 0x07
    mov     al, cl
    call    sio_write_reg
    mov     ah, 0x60
    mov     al, 0x03
    call    sio_write_reg
    mov     ah, 0x61
    mov     al, 0xF8
    call    sio_write_reg
    mov     ah, 0x70
    mov     al, 0x04
    call    sio_write_reg
    mov     ah, 0x30
    mov     al, 0x01
    call    sio_write_reg

    ; Enable PS/2 KBC
    mov     ah, 0x07
    mov     al, ch
    call    sio_write_reg
    mov     ah, 0x30
    mov     al, 0x01
    call    sio_write_reg

    ; Exit PnP config mode (type 1/2 use 0xAA; type 3 with CL==1 also needs reg 0x02=0x02)
    mov     al, 0xAA
    out     dx, al
    mov     ah, 0x02
    mov     al, 0x02
    cmp     cl, 1
    jne     .exit_done
    mov     al, 0x87
    out     dx, al
    mov     al, 0x01
    out     dx, al
    mov     al, 0x55
    out     dx, al
    cmp     dx, 0x2E
    je      .ite_re2e
    mov     al, 0xAA
.ite_re2e:
    out     dx, al
    mov     ah, 0x02
    mov     al, 0x02
    call    sio_write_reg
.exit_done:
    mov     ax, bx
    clc
    pop     cx
    pop     bx
    ret

.not_found:
    mov     al, 0xAA
    out     dx, al
    xor     ax, ax
    stc
    pop     cx
    pop     bx
    ret

superio_early_init:
    push    ax
    push    dx
    push    es

    mov     ax, CAR_STACK_SEG
    mov     es, ax
    mov     word [es:CAR_SUPERIO_PORT], 0
    mov     word [es:CAR_SUPERIO_ID], 0xFFFF

    mov     dx, 0x002E
    call    sio_probe_and_enable_port
    jnc     .sio_found

    mov     dx, 0x004E
    call    sio_probe_and_enable_port
    jc      .sio_done

.sio_found:
    mov     [es:CAR_SUPERIO_PORT], dx
    mov     [es:CAR_SUPERIO_ID], ax

.sio_done:
    pop     es
    pop     dx
    pop     ax
    ret
