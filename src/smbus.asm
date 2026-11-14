; smbus.asm — PCI SMBus Host Controller initialization and Byte Data reads

BITS 16

%include "contract.inc"

SMBUS_DEFAULT_IO_BASE equ 0x0500

smbus_init:
    push    eax
    push    ecx
    push    dx
    push    es
    push    bx

    mov     ax, CAR_STACK_SEG
    mov     es, ax
    mov     word [es:CAR_SMBUS_BASE], 0

    ; Check primary SMBus location (Bus 0, Dev 31, Fn 3 — ICH family)
    mov     eax, SMBUS_PCI_ADDR_PRI
    call    pci_config_read32
    cmp     eax, 0xFFFFFFFF
    je      .check_secondary
    test    eax, eax
    jz      .check_secondary

    mov     eax, SMBUS_PCI_ADDR_PRI | SMBUS_BAR_PRI
    call    pci_config_read32
    and     ax, 0xFFF0
    test    ax, ax
    jnz     .pri_have_bar

    mov     eax, SMBUS_PCI_ADDR_PRI | SMBUS_BAR_PRI
    mov     ecx, SMBUS_DEFAULT_IO_BASE | 0x01
    call    pci_config_write32
    mov     ax, SMBUS_DEFAULT_IO_BASE

.pri_have_bar:
    mov     [es:CAR_SMBUS_BASE], ax

    mov     eax, SMBUS_PCI_ADDR_PRI + (SMBUS_HOSTC_PRI & 0xFC)
    mov     cl, SMBUS_HOSTC_PRI & 0x03
    mov     dl, 0x01
    call    pci_config_write8

    mov     eax, SMBUS_PCI_ADDR_PRI | 0x04
    call    pci_config_read32
    or      al, 0x01
    mov     ecx, eax
    mov     eax, SMBUS_PCI_ADDR_PRI | 0x04
    call    pci_config_write32
    jmp     .init_done

.check_secondary:
    ; Check secondary SMBus location (Bus 0, Dev 7, Fn 3 — PIIX4 family)
    mov     eax, SMBUS_PCI_ADDR_SEC
    call    pci_config_read32
    cmp     eax, 0xFFFFFFFF
    je      .init_done
    test    eax, eax
    jz      .init_done

    mov     eax, SMBUS_PCI_ADDR_SEC | SMBUS_BAR_SEC
    call    pci_config_read32
    and     ax, 0xFFF0
    test    ax, ax
    jnz     .sec_have_bar

    mov     eax, SMBUS_PCI_ADDR_SEC | SMBUS_BAR_SEC
    mov     ecx, SMBUS_DEFAULT_IO_BASE | 0x01
    call    pci_config_write32
    mov     ax, SMBUS_DEFAULT_IO_BASE

.sec_have_bar:
    mov     [es:CAR_SMBUS_BASE], ax

    mov     eax, SMBUS_PCI_ADDR_SEC + (SMBUS_HOSTC_SEC & 0xFC)
    mov     cl, SMBUS_HOSTC_SEC & 0x03
    mov     dl, 0x01
    call    pci_config_write8

    mov     eax, SMBUS_PCI_ADDR_SEC | 0x04
    call    pci_config_read32
    or      al, 0x01
    mov     ecx, eax
    mov     eax, SMBUS_PCI_ADDR_SEC | 0x04
    call    pci_config_write32

.init_done:
    pop     bx
    pop     es
    pop     dx
    pop     ecx
    pop     eax
    ret

; Read a byte from an SMBus slave: BL = 7-bit slave addr, BH = register offset -> AL (CF=0 ok, CF=1 err)
smbus_read_byte:
    push    cx
    push    dx
    push    es
    push    di

    mov     di, CAR_STACK_SEG
    mov     es, di

    mov     dx, [es:CAR_SMBUS_BASE]
    test    dx, dx
    jz      .error

    mov     al, 0xFF
    out     dx, al

    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_XMIT_SLVA
    mov     al, bl
    shl     al, 1
    or      al, 0x01
    out     dx, al

    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_HST_CMD
    mov     al, bh
    out     dx, al

    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_HST_CNT
    mov     al, SMBUS_CNT_START | SMBUS_CNT_BYTE_DATA
    out     dx, al

    mov     dx, [es:CAR_SMBUS_BASE]
    mov     cx, 0xFFFF

.poll_loop:
    in      al, dx
    test    al, SMBUS_STS_ERROR | SMBUS_STS_FAILED
    jnz     .error
    test    al, SMBUS_STS_INTR
    jnz     .read_data
    dec     cx
    jnz     .poll_loop
    jmp     .error

.read_data:
    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_HST_D0
    in      al, dx

    push    ax
    mov     dx, [es:CAR_SMBUS_BASE]
    mov     al, 0xFF
    out     dx, al
    pop     ax

    clc
    jmp     .done

.error:
    mov     dx, [es:CAR_SMBUS_BASE]
    test    dx, dx
    jz      .error_no_base
    mov     al, 0xFF
    out     dx, al
.error_no_base:
    stc

.done:
    pop     di
    pop     es
    pop     dx
    pop     cx
    ret
