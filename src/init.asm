; init.asm — Early hardware initialization for IPO_Boot_ROM
; Assembled at ORG 0x8000, executed in CS=0xF000 (physical 0xFFFF8000 / 0xF8000)

BITS 16
ORG 0x8000

%include "contract.inc"

global bootrom_init

bootrom_init:
    jmp     short .boot_start
    db      "IPO_Boot_ROM"
.boot_start:
    cli
    cld

    ; Route 0xF0000-0xFFFFF to physical Flash ROM in case of a warm reset
    ; where PAM0 was previously locked to Shadow RAM.
    mov     eax, 0x80000000
    mov     dx, PCI_CONFIG_ADDR
    out     dx, eax
    mov     dx, PCI_CONFIG_DATA
    in      eax, dx
    cmp     ax, 0xFFFF
    je      .pam_warm_reset_done
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

    ; Set up Cache-as-RAM (inline, no stack available before completion)
    %include "car.asm"

    ; Initialize COM1 serial port (115200 8N1) for early diagnostics
    call    serial_init

    ; Log CPU identity and probe Host Bridge + DRAM
    call    cpu_print_brand
    call    host_bridge_detect
    call    mrc_init

    ; Read detected hardware parameters from CAR before cache teardown
    mov     ax, CAR_STACK_SEG
    mov     es, ax
    mov     bx, [es:CAR_HOST_VID]
    mov     dx, [es:CAR_HOST_DID]
    mov     ecx, [es:CAR_TOTAL_RAM_BYTES]

    ; Tear down CAR and switch stack to initialized DRAM
    call    car_teardown

    ; Zero Scratch RAM (0x0000:0x0500 - 0x05FF) and store handoff parameters
    xor     ax, ax
    mov     es, ax
    mov     di, 0x0500
    mov     cx, 64
    xor     eax, eax
    cld
    rep     stosd

    mov     [es:SCRATCH_HOST_VID], bx
    mov     [es:SCRATCH_HOST_DID], dx
    mov     [es:SCRATCH_TOTAL_RAM], ecx

    ; Initialize 8259A PIC and 8254 PIT
    call    pic_init
    call    pit_init

    mov     si, msg_banner
    call    serial_print
    call    vga_print

    ; Shadow ROM to DRAM at 0xF0000, lock read-only, and jump to firmware
    %include "payload_call.asm"

halt_system:
    mov     si, msg_halted
    call    serial_print
    call    vga_print
.loop:
    hlt
    jmp     .loop

; COM1 Serial Driver (115200 baud, 8N1)
serial_init:
    push    ax
    push    dx

    ; Check UART presence via scratch register (0x3FF)
    mov     dx, COM1_PORT + 7
    mov     al, 0xA5
    out     dx, al
    in      al, dx
    cmp     al, 0xA5
    jne     .done

    mov     dx, COM1_PORT + 1
    xor     al, al
    out     dx, al                  ; Disable UART interrupts

    mov     dx, COM1_PORT + 3
    mov     al, 0x80
    out     dx, al                  ; Enable DLAB

    mov     dx, COM1_PORT + 0
    mov     al, 0x01
    out     dx, al                  ; Divisor latch low = 1 (115200 baud)

    mov     dx, COM1_PORT + 1
    xor     al, al
    out     dx, al                  ; Divisor latch high = 0

    mov     dx, COM1_PORT + 3
    mov     al, 0x03
    out     dx, al                  ; 8N1, disable DLAB

    mov     dx, COM1_PORT + 2
    mov     al, 0xC7
    out     dx, al                  ; Enable and clear FIFOs

    mov     dx, COM1_PORT + 4
    mov     al, 0x0B
    out     dx, al                  ; Assert DTR, RTS, OUT2

.done:
    pop     dx
    pop     ax
    ret

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

; Print AL as 2 hex digits to COM1
serial_print_hex8:
    push    ax
    push    bx
    mov     bl, al
    shr     al, 4
    call    .nibble
    mov     al, bl
    and     al, 0x0F
    call    .nibble
    pop     bx
    pop     ax
    ret
.nibble:
    add     al, '0'
    cmp     al, '9'
    jbe     .out
    add     al, 7
.out:
    call    serial_tx_char
    ret

; Print DX as 4 hex digits to COM1
serial_print_hex16:
    push    ax
    mov     al, dh
    call    serial_print_hex8
    mov     al, dl
    call    serial_print_hex8
    pop     ax
    ret

; Print EAX as unsigned decimal to COM1
serial_print_dec:
    pushad
    xor     ecx, ecx
    mov     ebx, 10
.div_loop:
    xor     edx, edx
    div     ebx
    push    dx
    inc     cx
    test    eax, eax
    jnz     .div_loop
.print_loop:
    pop     ax
    add     al, '0'
    call    serial_tx_char
    loop    .print_loop
    popad
    ret

; CPU Identification via CPUID
cpu_print_brand:
    pushad
    push    ds
    push    es

    mov     si, msg_cpu_prefix
    call    serial_print

    mov     eax, 0x80000000
    cpuid
    cmp     eax, 0x80000004
    jb      .fallback_vendor

    sub     sp, 48
    mov     bp, sp

    mov     eax, 0x80000002
    cpuid
    mov     [ss:bp + 0], eax
    mov     [ss:bp + 4], ebx
    mov     [ss:bp + 8], ecx
    mov     [ss:bp + 12], edx

    mov     eax, 0x80000003
    cpuid
    mov     [ss:bp + 16], eax
    mov     [ss:bp + 20], ebx
    mov     [ss:bp + 24], ecx
    mov     [ss:bp + 28], edx

    mov     eax, 0x80000004
    cpuid
    mov     [ss:bp + 32], eax
    mov     [ss:bp + 36], ebx
    mov     [ss:bp + 40], ecx
    mov     [ss:bp + 44], edx

    mov     si, bp
    mov     cx, 48
    xor     bl, bl
.print_loop:
    mov     al, [ss:si]
    inc     si
    test    al, al
    jz      .brand_done
    cmp     al, ' '
    jne     .emit_char
    test    bl, bl
    jz      .skip_space
.emit_char:
    mov     bl, 1
    call    serial_tx_char
.skip_space:
    loop    .print_loop

.brand_done:
    add     sp, 48
    jmp     .done

.fallback_vendor:
    xor     eax, eax
    cpuid
    push    ecx
    push    edx
    push    ebx
    mov     bp, sp
    mov     cx, 12
.vendor_loop:
    mov     al, [ss:bp]
    inc     bp
    call    serial_tx_char
    loop    .vendor_loop
    add     sp, 12

.done:
    mov     al, 13
    call    serial_tx_char
    mov     al, 10
    call    serial_tx_char
    pop     es
    pop     ds
    popad
    ret

; Direct VGA Text Buffer Output (0xB800:0000)
vga_print:
    push    es
    push    si
    push    di
    push    ax
    push    bx
    push    dx

    ; Only write to 0xB8000 if VGA hardware has RAM decode enabled (Misc Out bit 1)
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

%include "host_bridge.asm"
%include "smbus.asm"
%include "mrc.asm"
%include "pic.asm"
%include "pit.asm"

msg_cpu_prefix      db "[IPO_Boot_ROM] CPU: ", 0
msg_bridge_prefix   db "[IPO_Boot_ROM] Host Bridge: PCI ID [", 0
msg_bridge_rev      db "] Rev ", 0
msg_bridge_suffix   db 10, 0
msg_bridge_none     db "[IPO_Boot_ROM] Host Bridge: Not detected", 10, 0
msg_mem_prefix      db "[IPO_Boot_ROM] Memory: ", 0
msg_mem_suffix      db " MB", 10, 0
msg_banner          db "[IPO_Boot_ROM] Hardware initialized. Shadowing firmware...", 10, 0
msg_copying         db "[IPO_Boot_ROM] Shadowing ROM segment 0xF000 to DRAM...", 10, 0
msg_shadow_ok       db "[IPO_Boot_ROM] Shadow RAM locked (read-only). PAM verified.", 10, 0
msg_fw_ok           db "[IPO_Boot_ROM] Firmware magic validated. Jumping to 0xF000:000C", 10, 0
msg_fw_invalid      db "[IPO_Boot_ROM] ERROR: Firmware magic header mismatch!", 10, 0
msg_halted          db "[IPO_Boot_ROM] System halted.", 10, 0
magic_firmware      db "IPO_Firmware"
magic_bootrom       db "IPO_Boot_ROM"
