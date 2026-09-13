; chipset.asm — Chipset detection, PCI config space helpers, and PAM management
; Included by init.asm
;
; Supports:  Intel i440FX (82441FX PMC)  — QEMU -machine pc
;            Intel Q35 MCH               — QEMU -machine q35
;
; All routines preserve caller registers unless documented otherwise.

%include "contract.inc"

; =============================================================================
; PCI Configuration Space Helper Routines
; =============================================================================
;
; PCI config address format (written to port 0xCF8):
;   Bit 31      = Enable
;   Bits 23:16  = Bus number
;   Bits 15:11  = Device number
;   Bits 10:8   = Function number
;   Bits 7:2    = Register (dword-aligned)
;   Bits 1:0    = Must be 0
;
; To access individual bytes within a dword register:
;   1. Write (address & 0xFFFFFFFC) | 0x80000000 to port 0xCF8
;   2. Read/write port 0xCFC + (address & 3)
; =============================================================================

; -----------------------------------------------------------------------------
; pci_config_read8 — Read an 8-bit value from PCI configuration space
;
; Input:
;   EAX = PCI address (bus/dev/fn/reg encoded, bit 31 set or not)
;   CL  = byte offset within the dword (0–3)
;
; Output:
;   AL  = byte value read
;
; Clobbers: none (DX, upper EAX restored via stack)
; -----------------------------------------------------------------------------
pci_config_read8:
    push    edx
    push    eax

    ; Write dword-aligned address with enable bit to CONFIG_ADDRESS
    and     eax, 0xFFFFFFFC         ; Force dword alignment (clear bits 1:0)
    or      eax, 0x80000000         ; Set enable bit 31
    mov     dx, PCI_CONFIG_ADDR     ; 0x0CF8
    out     dx, eax

    pop     eax                     ; Restore original EAX (need CL for offset)

    ; Calculate byte port: 0xCFC + byte offset (CL)
    movzx   dx, cl                  ; DX = byte offset (0–3)
    add     dx, PCI_CONFIG_DATA     ; DX = 0x0CFC + offset
    in      al, dx                  ; Read the target byte

    pop     edx
    ret

; -----------------------------------------------------------------------------
; pci_config_write8 — Write an 8-bit value to PCI configuration space
;
; Input:
;   EAX = PCI address (bus/dev/fn/reg encoded)
;   CL  = byte offset within the dword (0–3)
;   CH  = value to write
;
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
pci_config_write8:
    push    edx
    push    eax

    ; Write dword-aligned address with enable bit to CONFIG_ADDRESS
    and     eax, 0xFFFFFFFC         ; Force dword alignment (clear bits 1:0)
    or      eax, 0x80000000         ; Set enable bit 31
    mov     dx, PCI_CONFIG_ADDR     ; 0x0CF8
    out     dx, eax

    pop     eax                     ; Restore original EAX

    ; Calculate byte port: 0xCFC + byte offset (CL)
    movzx   dx, cl                  ; DX = byte offset (0–3)
    add     dx, PCI_CONFIG_DATA     ; DX = 0x0CFC + offset
    mov     al, ch                  ; AL = value to write
    out     dx, al                  ; Write the target byte

    pop     edx
    ret

; -----------------------------------------------------------------------------
; pci_config_read16 — Read a 16-bit value from PCI configuration space
;
; Input:
;   EAX = PCI address (must be word-aligned, i.e. bit 0 = 0)
;
; Output:
;   AX  = word value read
;
; Clobbers: none
; -----------------------------------------------------------------------------
pci_config_read16:
    push    edx
    push    eax

    ; Write dword-aligned address with enable bit to CONFIG_ADDRESS
    ; Save original address bits 1:0 to determine word offset
    mov     edx, eax                ; Preserve original address in EDX
    and     eax, 0xFFFFFFFC         ; Force dword alignment
    or      eax, 0x80000000         ; Set enable bit 31
    push    edx                     ; Save original address for offset calc
    mov     dx, PCI_CONFIG_ADDR     ; 0x0CF8
    out     dx, eax

    pop     edx                     ; Restore original address
    and     edx, 0x03               ; Isolate byte offset (0 or 2 for words)
    add     dx, PCI_CONFIG_DATA     ; DX = 0x0CFC + offset
    in      ax, dx                  ; Read the target word

    ; Discard saved EAX (we return the new AX)
    add     esp, 4                  ; Pop the saved EAX without restoring it
    pop     edx
    ret

; -----------------------------------------------------------------------------
; pci_config_read32 / pci_read_dword — Read a 32-bit value from PCI configuration space
;
; Input:
;   EAX = PCI address (should be dword-aligned)
;
; Output:
;   EAX = dword value read
;
; Clobbers: none
; -----------------------------------------------------------------------------
pci_read_dword:
pci_config_read32:
    push    edx

    ; Write dword-aligned address with enable bit to CONFIG_ADDRESS
    and     eax, 0xFFFFFFFC         ; Force dword alignment
    or      eax, 0x80000000         ; Set enable bit 31
    mov     dx, PCI_CONFIG_ADDR     ; 0x0CF8
    out     dx, eax

    ; Read full dword from CONFIG_DATA
    mov     dx, PCI_CONFIG_DATA     ; 0x0CFC
    in      eax, dx                 ; Read 32-bit value

    pop     edx
    ret

; -----------------------------------------------------------------------------
; pci_config_write32 / pci_write_dword — Write a 32-bit value to PCI config space
;
; Input:
;   EAX = PCI address (should be dword-aligned)
;   ECX = 32-bit value to write
;
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
pci_write_dword:
pci_config_write32:
    push    edx
    push    eax

    ; Write dword-aligned address with enable bit to CONFIG_ADDRESS
    and     eax, 0xFFFFFFFC         ; Force dword alignment
    or      eax, 0x80000000         ; Set enable bit 31
    mov     dx, PCI_CONFIG_ADDR     ; 0x0CF8
    out     dx, eax

    ; Write full dword to CONFIG_DATA
    mov     dx, PCI_CONFIG_DATA     ; 0x0CFC
    mov     eax, ecx
    out     dx, eax                 ; Write 32-bit value

    pop     eax
    pop     edx
    ret

; =============================================================================
; Chipset Detection
; =============================================================================

; -----------------------------------------------------------------------------
; chipset_detect — Identify the host bridge chipset at PCI 0:0.0
;
; Reads the Vendor ID and Device ID from PCI Bus 0, Device 0, Function 0.
; Sets [detected_chipset] to CHIPSET_I440FX, CHIPSET_Q35, or CHIPSET_UNKNOWN.
;
; Input:  none
; Output: [detected_chipset] updated
; Clobbers: none (all registers preserved)
; -----------------------------------------------------------------------------
chipset_detect:
    push    eax
    push    cx

    ; ------------------------------------------------------------------
    ; Step 1: Read Device ID (register 0x02, 16-bit) from PCI 0:0.0
    ;         Vendor ID is at 0x00 but both chipsets share VID 0x8086,
    ;         so we identify by Device ID alone.
    ; ------------------------------------------------------------------
    mov     eax, I440FX_PCI_ADDR    ; 0x80000000 — Bus 0, Dev 0, Fn 0
    or      eax, 0x00               ; Register 0x00 (contains VID:DID dword)
    call    pci_config_read32       ; EAX = [DID(31:16) | VID(15:0)]
    shr     eax, 16                 ; AX = Device ID

    ; ------------------------------------------------------------------
    ; Step 2: Match against known Device IDs
    ; ------------------------------------------------------------------
    cmp     ax, I440FX_DID          ; 0x1237 — Intel i440FX
    je      .found_i440fx

    cmp     ax, Q35_DID             ; 0x29C0 — Intel Q35 MCH
    je      .found_q35

    ; Unknown chipset
    mov     byte [detected_chipset], CHIPSET_UNKNOWN
    jmp     .detect_done

.found_i440fx:
    mov     byte [detected_chipset], CHIPSET_I440FX
    jmp     .detect_done

.found_q35:
    mov     byte [detected_chipset], CHIPSET_Q35

.detect_done:
    pop     cx
    pop     eax
    ret

; =============================================================================
; PAM (Programmable Attribute Map) Register Management
; =============================================================================
;
; PAM0 controls the BIOS area 0xF0000–0xFFFFF.
; Bits [5:4] of the PAM register select the routing mode:
;   00 = Disabled  — reads and writes go to PCI/ROM
;   01 = RE        — reads from DRAM (shadow), writes to PCI/ROM
;   10 = WE        — reads from PCI/ROM, writes to DRAM
;   11 = RE+WE     — reads and writes go to DRAM
;
; For ROM-to-DRAM shadowing:
;   1. pam_open_write:   set bits [5:4] = 10 (WE) — reads ROM, writes DRAM
;   2. (caller copies ROM content to shadow RAM)
;   3. pam_lock_readonly: set bits [5:4] = 01 (RE) — reads DRAM, writes blocked

; -----------------------------------------------------------------------------
; pam_open_write — Open PAM0 for writes (reads from ROM, writes to DRAM)
;
; This enables the shadowing copy phase: CPU reads ROM at 0xF0000,
; CPU writes land in DRAM at 0xF0000.
;
; Input:  [detected_chipset] must be set (call chipset_detect first)
; Output: PAM0 register updated on the host bridge
; Clobbers: none
; -----------------------------------------------------------------------------
pam_open_write:
    push    eax
    push    cx

    ; Determine which PAM register offset to use
    cmp     byte [detected_chipset], CHIPSET_Q35
    je      .pam_wr_q35

    ; ----- i440FX path (or unknown — default to i440FX PAM) -----
    ; PAM0 register is at offset 0x59 on PCI 0:0.0
    mov     eax, I440FX_PCI_ADDR    ; 0x80000000
    or      eax, I440FX_PAM0        ; OR in register offset 0x59
    mov     cl, (I440FX_PAM0 & 0x03) ; Byte offset within dword = 0x59 & 3 = 1
    jmp     .pam_wr_do

.pam_wr_q35:
    ; PAM0 register is at offset 0x90 on PCI 0:0.0
    mov     eax, Q35_PCI_ADDR       ; 0x80000000
    or      eax, Q35_PAM0           ; OR in register offset 0x90
    mov     cl, (Q35_PAM0 & 0x03)   ; Byte offset within dword = 0x90 & 3 = 0

.pam_wr_do:
    ; Read current PAM0 value
    call    pci_config_read8        ; AL = current PAM0 value

    ; Mask out bits [5:4], then set to WE (0x20)
    ; WE = bit 5 set, bit 4 clear → reads from ROM, writes to DRAM
    and     al, ~PAM_RW             ; Clear bits [5:4] (mask = ~0x30 = 0xCF)
    or      al, PAM_WE              ; Set bit 5 (WE = 0x20)
    mov     ch, al                  ; CH = new value to write

    ; Write updated PAM0 value back
    call    pci_config_write8

    pop     cx
    pop     eax
    ret

; -----------------------------------------------------------------------------
; pam_lock_readonly — Lock PAM0 to read-only (reads from DRAM shadow)
;
; After shadowing is complete, this locks the region so:
;   - Reads come from DRAM (the shadow copy)
;   - Writes are blocked (go to PCI, effectively discarded)
;
; Input:  [detected_chipset] must be set
; Output: PAM0 register updated on the host bridge
; Clobbers: none
; -----------------------------------------------------------------------------
pam_lock_readonly:
    push    eax
    push    cx

    ; Determine which PAM register offset to use
    cmp     byte [detected_chipset], CHIPSET_Q35
    je      .pam_ro_q35

    ; ----- i440FX path -----
    mov     eax, I440FX_PCI_ADDR
    or      eax, I440FX_PAM0
    mov     cl, (I440FX_PAM0 & 0x03) ; Byte offset = 1
    jmp     .pam_ro_do

.pam_ro_q35:
    ; ----- Q35 path -----
    mov     eax, Q35_PCI_ADDR
    or      eax, Q35_PAM0
    mov     cl, (Q35_PAM0 & 0x03)   ; Byte offset = 0

.pam_ro_do:
    ; Read current PAM0 value
    call    pci_config_read8        ; AL = current PAM0 value

    ; Mask out bits [5:4], then set to RE (0x10)
    ; RE = bit 4 set, bit 5 clear → reads from DRAM shadow, writes blocked
    and     al, ~PAM_RW             ; Clear bits [5:4] (mask = 0xCF)
    or      al, PAM_RE              ; Set bit 4 (RE = 0x10)
    mov     ch, al                  ; CH = new value to write

    ; Write updated PAM0 value back
    call    pci_config_write8

    pop     cx
    pop     eax
    ret

; =============================================================================
; Data Section
; =============================================================================

align 4
detected_chipset    db CHIPSET_UNKNOWN  ; Set by chipset_detect
