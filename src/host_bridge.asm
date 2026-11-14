; host_bridge.asm — PCI Configuration Space helpers, Host Bridge probe, and PAM control

%include "contract.inc"

; Read 8-bit PCI config register: EAX = PCI address, CL = byte offset (0..3) -> AL
pci_config_read8:
    push    edx
    push    eax

    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    pop     eax
    movzx   dx, cl
    add     dx, PCI_CONFIG_DATA
    in      al, dx

    pop     edx
    ret

; Write 8-bit PCI config register: EAX = PCI address, CL = byte offset (0..3), DL = value
pci_config_write8:
    push    eax
    push    edx

    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    push    edx
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    pop     eax
    movzx   dx, cl
    add     dx, PCI_CONFIG_DATA
    out     dx, al

    pop     edx
    pop     eax
    ret

; Read 16-bit PCI config register: EAX = word-aligned PCI address -> AX
pci_config_read16:
    push    edx
    push    eax

    mov     edx, eax
    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    push    edx
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    pop     edx
    and     edx, 0x03
    add     dx, PCI_CONFIG_DATA
    in      ax, dx

    add     sp, 4
    pop     edx
    ret

; Read 32-bit PCI config register: EAX = dword-aligned PCI address -> EAX
pci_config_read32:
    push    edx

    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    mov     dx, PCI_CONFIG_DATA
    in      eax, dx

    pop     edx
    ret

; Write 32-bit PCI config register: EAX = dword-aligned PCI address, ECX = value
pci_config_write32:
    push    edx
    push    eax

    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax

    mov     dx, PCI_CONFIG_DATA
    mov     eax, ecx
    out     dx, eax

    pop     eax
    pop     edx
    ret

; Probe PCI 0:0.0 and record Vendor/Device ID in CAR scratch space
host_bridge_detect:
    pushad
    push    ds
    push    es

    mov     ax, CAR_STACK_SEG
    mov     es, ax

    mov     eax, HOST_BRIDGE_PCI_ADDR
    call    pci_config_read32

    cmp     eax, 0xFFFFFFFF
    je      .not_found
    test    eax, eax
    jz      .not_found

    mov     [es:CAR_HOST_VID], ax
    mov     ebx, eax
    shr     ebx, 16
    mov     [es:CAR_HOST_DID], bx

    mov     si, msg_bridge_prefix
    call    serial_print

    mov     dx, [es:CAR_HOST_VID]
    call    serial_print_hex16

    mov     al, ':'
    call    serial_tx_char

    mov     dx, [es:CAR_HOST_DID]
    call    serial_print_hex16

    mov     si, msg_bridge_rev
    call    serial_print

    mov     eax, HOST_BRIDGE_PCI_ADDR | 0x08
    xor     cl, cl
    call    pci_config_read8
    call    serial_print_hex8

    mov     si, msg_bridge_suffix
    call    serial_print
    jmp     .done

.not_found:
    mov     word [es:CAR_HOST_VID], 0
    mov     word [es:CAR_HOST_DID], 0
    mov     si, msg_bridge_none
    call    serial_print

.done:
    pop     es
    pop     ds
    popad
    ret
