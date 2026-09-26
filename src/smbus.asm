; smbus.asm — SMBus/I2C Driver for Intel ICH9 SMBus Controller
; Included by init.asm — depends on PCI helpers from chipset.asm
;
; The ICH9 SMBus controller sits at PCI 0:1F.3 (address 0x8000FB00).
; It provides an I/O-mapped host interface for SMBus/I2C byte-level
; transactions, used primarily to read SPD EEPROM data from DIMM modules.
;
; Subroutines:
;   smbus_init       — Configure BAR, enable host controller & I/O space
;   smbus_read_byte  — Read one byte via SMBus Byte Data protocol
;
; Depends on (from chipset.asm):
;   pci_read_dword   — Read 32-bit PCI config register (EAX = PCI addr)
;   pci_write_dword  — Write 32-bit PCI config register (EAX = PCI addr, ECX = data)

BITS 16

%include "contract.inc"

; =============================================================================
; smbus_init — Initialize the ICH9 SMBus Controller
; =============================================================================
;
; Steps:
;   1. Read the SMBus I/O Base Address Register (PCI reg 0x20)
;   2. Enable the SMBus Host Controller (PCI reg 0x40, bit 0)
;   3. Enable I/O Space access in PCI Command register (reg 0x04, bit 0)
;
; Inputs:  None
; Outputs: None (smbus_base_port is set)
; Clobbers: None (all registers preserved)
; =============================================================================
smbus_init:
    push    eax
    push    ecx
    push    dx
    push    es
    push    bx

    mov     bx, CAR_STACK_SEG
    mov     es, bx
    mov     word [es:CAR_SMBUS_BASE], 0

    ; -----------------------------------------------------------------
    ; 1. Check if ICH9 SMBus is present (PCI 0:1F.3)
    ; -----------------------------------------------------------------
    mov     eax, ICH9_SMBUS_PCI_ADDR
    call    pci_read_dword          ; EAX = [DID | VID]
    cmp     ax, 0xFFFF
    je      .check_piix4
    test    ax, ax
    jz      .check_piix4

    ; Found ICH9 SMBus! Read SMBus BAR (reg 0x20)
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_BAR
    call    pci_read_dword
    and     ax, 0xFFFE              ; Mask off bit 0 (I/O space indicator)
    test    ax, ax
    jnz     .ich9_have_bar
    ; Assign default I/O base 0x0400 if unassigned
    mov     ecx, 0x00000401
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_BAR
    call    pci_write_dword
    mov     ax, 0x0400
.ich9_have_bar:
    mov     [es:CAR_SMBUS_BASE], ax

    ; Enable SMBus Host Controller (PCI reg 0x40 bit 0)
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_HOSTC
    call    pci_read_dword
    or      al, 0x01
    mov     ecx, eax
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_HOSTC
    call    pci_write_dword

    ; Enable I/O Space in PCI Command Register (reg 0x04 bit 0)
    mov     eax, ICH9_SMBUS_PCI_ADDR | 0x04
    call    pci_read_dword
    or      al, 0x01
    mov     ecx, eax
    mov     eax, ICH9_SMBUS_PCI_ADDR | 0x04
    call    pci_write_dword
    jmp     .init_done

.check_piix4:
    ; -----------------------------------------------------------------
    ; 2. Check if PIIX4 SMBus is present (PCI 0:7.3, i440FX/440BX boards)
    ; -----------------------------------------------------------------
    mov     eax, PIIX4_SMBUS_PCI_ADDR
    call    pci_read_dword          ; EAX = [DID | VID]
    cmp     ax, 0xFFFF
    je      .init_done
    test    ax, ax
    jz      .init_done

    ; Found PIIX4 SMBus! Read Base Address from reg 0x90
    mov     eax, PIIX4_SMBUS_PCI_ADDR | PIIX4_SMBUS_BAR
    call    pci_read_dword
    and     ax, 0xFFF0
    test    ax, ax
    jnz     .piix4_have_bar
    ; Assign default I/O base 0x1000 if unassigned
    mov     ecx, 0x00001001
    mov     eax, PIIX4_SMBUS_PCI_ADDR | PIIX4_SMBUS_BAR
    call    pci_write_dword
    mov     ax, 0x1000
.piix4_have_bar:
    mov     [es:CAR_SMBUS_BASE], ax

    ; Enable PIIX4 Host Controller (PCI reg 0xD2: bit 0 = Host Enable, bit 1 = I/O Enable)
    mov     eax, PIIX4_SMBUS_PCI_ADDR | PIIX4_SMBUS_HOSTC
    call    pci_read_dword
    or      al, 0x03
    mov     ecx, eax
    mov     eax, PIIX4_SMBUS_PCI_ADDR | PIIX4_SMBUS_HOSTC
    call    pci_write_dword

    ; Enable PCI I/O space in Command Register (reg 0x04 bit 0)
    mov     eax, PIIX4_SMBUS_PCI_ADDR | 0x04
    call    pci_read_dword
    or      al, 0x01
    mov     ecx, eax
    mov     eax, PIIX4_SMBUS_PCI_ADDR | 0x04
    call    pci_write_dword

.init_done:
    pop     bx
    pop     es
    pop     dx
    pop     ecx
    pop     eax
    ret

; =============================================================================
; smbus_read_byte — Read a Single Byte via SMBus Byte Data Protocol
; =============================================================================
;
; Uses the ICH9 SMBus host interface to perform a Byte Data Read transaction.
; The SMBus Byte Data protocol sends a command byte (register offset) to the
; slave and reads back a single data byte.
;
; Inputs:
;   BL = Slave address (7-bit, e.g., 0x50 for DIMM0 SPD)
;   BH = Command/offset byte (register to read from slave)
;
; Outputs:
;   AL = Data byte read from slave
;   CF = 0 on success
;   CF = 1 on error (device error, bus failed, or timeout)
;
; Clobbers: None except AL and flags
; =============================================================================
smbus_read_byte:
    push    cx
    push    dx
    push    es
    push    di

    mov     di, CAR_STACK_SEG
    mov     es, di

    ; -----------------------------------------------------------------
    ; Step 1: Load SMBus I/O base address
    ; -----------------------------------------------------------------
    mov     dx, [es:CAR_SMBUS_BASE]
    test    dx, dx                  ; Sanity check: base must be non-zero
    jz      .error

    ; -----------------------------------------------------------------
    ; Step 2: Clear all host status bits
    ;   Write 0xFF to SMBUS_HST_STS (base+0) to clear any pending status.
    ; -----------------------------------------------------------------
    mov     al, 0xFF
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 3: Set slave address with read bit
    ;   SMBUS_XMIT_SLVA (base+4): bits [7:1] = slave addr, bit 0 = R/W
    ; -----------------------------------------------------------------
    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_XMIT_SLVA     ; DX = base + 4
    mov     al, bl                  ; AL = 7-bit slave address
    shl     al, 1                   ; Shift address into bits [7:1]
    or      al, 0x01                ; Set bit 0 = Read direction
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 4: Set command byte (register offset to read)
    ;   SMBUS_HST_CMD (base+3)
    ; -----------------------------------------------------------------
    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_HST_CMD       ; DX = base + 3
    mov     al, bh                  ; AL = command/offset byte
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 5: Start the SMBus transaction
    ; -----------------------------------------------------------------
    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_HST_CNT       ; DX = base + 2
    mov     al, SMBUS_CNT_START | SMBUS_CNT_BYTE_DATA  ; 0x48
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 6: Poll for transaction completion
    ; -----------------------------------------------------------------
    mov     dx, [es:CAR_SMBUS_BASE] ; DX = base + 0 (SMBUS_HST_STS)
    mov     cx, 0xFFFF              ; Timeout counter

.poll_loop:
    in      al, dx                  ; Read Host Status register

    ; Check if bus error occurred
    test    al, SMBUS_STS_ERROR     ; Bit 2: Device Error
    jnz     .error
    test    al, SMBUS_STS_FAILED    ; Bit 4: Failed
    jnz     .error

    ; Check if transaction completed successfully
    test    al, SMBUS_STS_INTR      ; Bit 1: Interrupt (completion)
    jnz     .read_data              ; Transaction complete — read result

    dec     cx
    jnz     .poll_loop
    jmp     .error

    ; -----------------------------------------------------------------
    ; Step 7: Read the data byte
    ; -----------------------------------------------------------------
.read_data:
    mov     dx, [es:CAR_SMBUS_BASE]
    add     dx, SMBUS_HST_D0        ; DX = base + 5
    in      al, dx                  ; AL = data byte from slave

    ; -----------------------------------------------------------------
    ; Step 8: Clear host status for next transaction
    ; -----------------------------------------------------------------
    push    ax                      ; Preserve data byte in AL
    mov     dx, [es:CAR_SMBUS_BASE] ; DX = base + 0
    mov     al, 0xFF
    out     dx, al
    pop     ax                      ; Restore data byte

    clc
    jmp     .done

.error:
    mov     dx, [es:CAR_SMBUS_BASE]
    mov     al, 0xFF
    out     dx, al
    stc

.done:
    pop     di
    pop     es
    pop     dx
    pop     cx
    ret
