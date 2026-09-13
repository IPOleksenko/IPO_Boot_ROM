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

    ; -----------------------------------------------------------------
    ; Step 1: Read SMBus BAR from PCI config register 0x20
    ;   PCI address = ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_BAR
    ;   BAR format: bits [15:5] = I/O base, bit 0 = I/O indicator
    ; -----------------------------------------------------------------
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_BAR
    call    pci_read_dword          ; EAX = BAR value
    and     ax, 0xFFFE              ; Mask off bit 0 (I/O space indicator)
    mov     [smbus_base_port], ax   ; Store the I/O base address

    ; -----------------------------------------------------------------
    ; Step 2: Enable SMBus Host Controller
    ;   PCI reg 0x40 (ICH9_SMBUS_HOSTC), bit 0 = SMBus Host Enable
    ;   Read-modify-write: set bit 0
    ; -----------------------------------------------------------------
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_HOSTC
    call    pci_read_dword          ; EAX = Host Configuration
    or      al, 0x01                ; Set bit 0: SMBus Host Enable
    mov     ecx, eax                ; ECX = modified value
    mov     eax, ICH9_SMBUS_PCI_ADDR | ICH9_SMBUS_HOSTC
    call    pci_write_dword         ; Write back

    ; -----------------------------------------------------------------
    ; Step 3: Enable I/O Space in PCI Command Register
    ;   PCI reg 0x04, bit 0 = I/O Space Enable
    ;   Read-modify-write: set bit 0
    ; -----------------------------------------------------------------
    mov     eax, ICH9_SMBUS_PCI_ADDR | 0x04
    call    pci_read_dword          ; EAX = PCI Command/Status
    or      al, 0x01                ; Set bit 0: I/O Space Enable
    mov     ecx, eax                ; ECX = modified value
    mov     eax, ICH9_SMBUS_PCI_ADDR | 0x04
    call    pci_write_dword         ; Write back

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

    ; -----------------------------------------------------------------
    ; Step 1: Load SMBus I/O base address
    ; -----------------------------------------------------------------
    mov     dx, [smbus_base_port]
    test    dx, dx                  ; Sanity check: base must be non-zero
    jz      .error

    ; -----------------------------------------------------------------
    ; Step 2: Clear all host status bits
    ;   Write 0xFF to SMBUS_HST_STS (base+0) to clear any pending status.
    ;   Status bits are Write-1-to-Clear (W1C).
    ; -----------------------------------------------------------------
    ; DX already points to base+0 (SMBUS_HST_STS)
    mov     al, 0xFF
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 3: Set slave address with read bit
    ;   SMBUS_XMIT_SLVA (base+4): bits [7:1] = slave addr, bit 0 = R/W
    ;   For read: (slave_addr << 1) | 1
    ; -----------------------------------------------------------------
    lea     dx, [edx + SMBUS_XMIT_SLVA - SMBUS_HST_STS]
                                    ; DX = base + 4
    mov     al, bl                  ; AL = 7-bit slave address
    shl     al, 1                   ; Shift address into bits [7:1]
    or      al, 0x01                ; Set bit 0 = Read direction
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 4: Set command byte (register offset to read)
    ;   SMBUS_HST_CMD (base+3)
    ; -----------------------------------------------------------------
    mov     dx, [smbus_base_port]
    add     dx, SMBUS_HST_CMD       ; DX = base + 3
    mov     al, bh                  ; AL = command/offset byte
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 5: Start the SMBus transaction
    ;   SMBUS_HST_CNT (base+2): write START | BYTE_DATA
    ;   START     = 0x40 (bit 6: start transaction)
    ;   BYTE_DATA = 0x08 (bits [4:2] = 010b: Byte Data protocol)
    ;   Combined  = 0x48
    ; -----------------------------------------------------------------
    mov     dx, [smbus_base_port]
    add     dx, SMBUS_HST_CNT       ; DX = base + 2
    mov     al, SMBUS_CNT_START | SMBUS_CNT_BYTE_DATA  ; 0x48
    out     dx, al

    ; -----------------------------------------------------------------
    ; Step 6: Poll for transaction completion
    ;   Read SMBUS_HST_STS (base+0) in a loop:
    ;     - Wait until BUSY (bit 0) clears
    ;     - Check ERROR (bit 2) or FAILED (bit 4) → error
    ;     - Check INTR (bit 1) → success
    ;   Timeout after 0xFFFF iterations to prevent infinite hang.
    ; -----------------------------------------------------------------
    mov     dx, [smbus_base_port]   ; DX = base + 0 (SMBUS_HST_STS)
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

    ; Still busy — decrement timeout and retry
    dec     cx
    jnz     .poll_loop

    ; Timeout: fell through without completion
    jmp     .error

    ; -----------------------------------------------------------------
    ; Step 7: Read the data byte
    ;   SMBUS_HST_D0 (base+5) holds the received byte
    ; -----------------------------------------------------------------
.read_data:
    mov     dx, [smbus_base_port]
    add     dx, SMBUS_HST_D0        ; DX = base + 5
    in      al, dx                  ; AL = data byte from slave

    ; -----------------------------------------------------------------
    ; Step 8: Clear host status for next transaction
    ;   Write 0xFF to SMBUS_HST_STS (base+0) — W1C all bits
    ; -----------------------------------------------------------------
    push    ax                      ; Preserve data byte in AL
    mov     dx, [smbus_base_port]   ; DX = base + 0
    mov     al, 0xFF
    out     dx, al
    pop     ax                      ; Restore data byte

    ; Success — clear carry flag
    clc
    jmp     .done

.error:
    ; Clear host status even on error (clean up for next attempt)
    mov     dx, [smbus_base_port]
    mov     al, 0xFF
    out     dx, al

    ; Set carry flag to indicate error
    stc

.done:
    pop     dx
    pop     cx
    ret

; =============================================================================
; Data Section
; =============================================================================

align 2
smbus_base_port     dw 0            ; SMBus I/O base address (from PCI BAR)
