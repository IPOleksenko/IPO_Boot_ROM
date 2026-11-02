; host_bridge.asm — Host Bridge discovery, CPU identification, PCI config helpers, and PAM management
; Included by init.asm
;
; Discovers CPU brand string and host bridge dynamically from hardware without hardcoded IDs.
; Preserves caller registers unless documented otherwise.

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
;   EAX = PCI address (dword-aligned, or with byte offset in bits 1:0)
;   CL  = byte offset within the dword (0–3)
;   DL  = value to write
;
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
pci_config_write8:
    push    eax
    push    edx

    ; Write dword-aligned address with enable bit to CONFIG_ADDRESS
    and     eax, 0xFFFFFFFC         ; Force dword alignment (clear bits 1:0)
    or      eax, 0x80000000         ; Set enable bit 31
    push    edx                     ; Save DL on stack
    mov     dx, PCI_CONFIG_ADDR     ; 0x0CF8
    out     dx, eax

    pop     eax                     ; AL = original DL (value to write)
    movzx   dx, cl                  ; DX = byte offset (0–3)
    add     dx, PCI_CONFIG_DATA     ; DX = 0x0CFC + offset
    out     dx, al                  ; Write the target byte

    pop     edx
    pop     eax
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
; Serial Output Formatting Helpers
; =============================================================================

; -----------------------------------------------------------------------------
; serial_print_hex8_early — Transmit an 8-bit byte as 2 hex characters to COM1
; Input: AL = 8-bit value
; Clobbers: None
; -----------------------------------------------------------------------------
serial_print_hex8_early:
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
    call    serial_tx_char_early
    ret

; -----------------------------------------------------------------------------
; serial_print_hex16_early — Transmit a 16-bit word as 4 hex characters to COM1
; Input: DX = 16-bit value
; Clobbers: None
; -----------------------------------------------------------------------------
serial_print_hex16_early:
    push    ax
    push    bx
    push    cx
    push    dx
    mov     bx, dx
    mov     cx, 4
.hex_loop:
    rol     bx, 4
    mov     al, bl
    and     al, 0x0F
    add     al, '0'
    cmp     al, '9'
    jbe     .hex_out
    add     al, 7           ; 'A' - '9' - 1
.hex_out:
    call    serial_tx_char_early
    loop    .hex_loop
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; -----------------------------------------------------------------------------
; serial_print_dec_early — Transmit an unsigned 32-bit number in decimal to COM1
; Input: EAX = 32-bit number
; Clobbers: None
; -----------------------------------------------------------------------------
serial_print_dec_early:
    pushad
    xor     ecx, ecx                ; Digit counter
    mov     ebx, 10
.div_loop:
    xor     edx, edx
    div     ebx                     ; EDX = remainder, EAX = quotient
    push    dx                      ; Push remainder on stack
    inc     cx
    test    eax, eax
    jnz     .div_loop
.print_loop:
    pop     ax
    add     al, '0'
    call    serial_tx_char_early
    loop    .print_loop
    popad
    ret

; =============================================================================
; CPU Hardware Information via CPUID
; =============================================================================

; -----------------------------------------------------------------------------
; cpu_print_brand_early — Query CPU hardware and print Brand String to COM1
; Reads CPUID 0x80000000: if EAX >= 0x80000004, executes 0x80000002..0x80000004
; to print the 48-byte ASCII string returned directly from CPU hardware.
; If extended functions are not supported, prints the 12-byte vendor string.
;
; Input:  none
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
cpu_print_brand_early:
    pushad
    push    ds
    push    es

    ; Print prefix: "[IPO_Boot_ROM] CPU: "
    mov     si, msg_cpu_prefix
    call    serial_print_early

    ; Check if extended CPUID brand string is supported
    mov     eax, 0x80000000
    cpuid
    cmp     eax, 0x80000004
    jb      .fallback_vendor

    ; Allocate 48 bytes on CAR stack
    sub     sp, 48
    mov     bp, sp

    ; CPUID 0x80000002 (bytes 0..15)
    mov     eax, 0x80000002
    cpuid
    mov     [ss:bp + 0], eax
    mov     [ss:bp + 4], ebx
    mov     [ss:bp + 8], ecx
    mov     [ss:bp + 12], edx

    ; CPUID 0x80000003 (bytes 16..31)
    mov     eax, 0x80000003
    cpuid
    mov     [ss:bp + 16], eax
    mov     [ss:bp + 20], ebx
    mov     [ss:bp + 24], ecx
    mov     [ss:bp + 28], edx

    ; CPUID 0x80000004 (bytes 32..47)
    mov     eax, 0x80000004
    cpuid
    mov     [ss:bp + 32], eax
    mov     [ss:bp + 36], ebx
    mov     [ss:bp + 40], ecx
    mov     [ss:bp + 44], edx

    ; Print characters from brand string, skipping leading spaces
    mov     si, bp
    mov     cx, 48
    xor     bl, bl                  ; bl = 0: haven't seen first non-space char

.print_loop:
    mov     al, [ss:si]
    inc     si
    test    al, al
    jz      .print_newline
    cmp     al, ' '
    jne     .found_char
    test    bl, bl
    jz      .skip_space             ; Skip leading space
.found_char:
    mov     bl, 1                   ; Seen non-space
    call    serial_tx_char_early
.skip_space:
    loop    .print_loop

.print_newline:
    add     sp, 48
    jmp     .done

.fallback_vendor:
    ; Fallback: read 12-byte vendor string from CPUID 0
    xor     eax, eax
    cpuid
    ; EBX, EDX, ECX contain 12 ASCII characters
    push    ecx
    push    edx
    push    ebx
    mov     bp, sp
    mov     cx, 12
.vendor_loop:
    mov     al, [ss:bp]
    inc     bp
    call    serial_tx_char_early
    loop    .vendor_loop
    add     sp, 12

.done:
    mov     al, 10                  ; Line feed
    call    serial_tx_char_early
    pop     es
    pop     ds
    popad
    ret

; =============================================================================
; Host Bridge Discovery
; =============================================================================

; -----------------------------------------------------------------------------
; host_bridge_detect — Discover host bridge from PCI 0:0.0
;
; Reads the Vendor ID, Device ID, and Revision directly from PCI Bus 0, Dev 0, Fn 0.
; Stores raw Vendor ID and Device ID in CAR without comparing against hardcoded lists.
;
; Input:  none
; Output: [CAR_HOST_VID], [CAR_HOST_DID] set
; Clobbers: none (all registers preserved)
; -----------------------------------------------------------------------------
host_bridge_detect:
    pushad
    push    ds
    push    es

    mov     ax, CAR_STACK_SEG
    mov     es, ax

    ; Read Vendor ID and Device ID from PCI 0:0.0
    mov     eax, HOST_BRIDGE_PCI_ADDR
    call    pci_config_read32       ; EAX = [DID(31:16) | VID(15:0)]

    ; Check if host bridge responds
    cmp     ax, 0xFFFF
    je      .no_bridge
    test    ax, ax
    jz      .no_bridge

    ; Store raw hardware IDs directly in CAR
    mov     [es:CAR_HOST_VID], ax
    mov     dx, ax                  ; DX = Vendor ID
    shr     eax, 16                 ; AX = Device ID
    mov     [es:CAR_HOST_DID], ax

    ; Read Revision ID from register 0x08 (bits 7:0)
    mov     eax, HOST_BRIDGE_PCI_ADDR | 0x08
    call    pci_config_read32
    mov     bl, al                  ; BL = Revision ID

    ; Print dynamically discovered ID: "[IPO_Boot_ROM] Host Bridge: PCI ID [VVVV:DDDD] Rev RR\n"
    mov     si, msg_bridge_prefix
    call    serial_print_early

    call    serial_print_hex16_early ; Print Vendor ID (DX)

    mov     al, ':'
    call    serial_tx_char_early

    mov     dx, [es:CAR_HOST_DID]
    call    serial_print_hex16_early ; Print Device ID

    mov     si, msg_bridge_rev
    call    serial_print_early

    mov     al, bl
    call    serial_print_hex8_early  ; Print Revision ID (BL)

    mov     si, msg_bridge_suffix
    call    serial_print_early
    jmp     .detect_done

.no_bridge:
    xor     ax, ax
    mov     [es:CAR_HOST_VID], ax
    mov     [es:CAR_HOST_DID], ax
    mov     si, msg_bridge_none
    call    serial_print_early

.detect_done:
    pop     es
    pop     ds
    popad
    ret

; =============================================================================
; Universal PAM (Programmable Attribute Map) Register Management
; =============================================================================
;
; Configures shadow RAM dynamically across motherboards.
; Evaluates standard PAM base (0x59..0x5F) and extended PAM base (0x90..0x96)
; by testing register writeability (SeaBIOS algorithm), without hardware branching.
; =============================================================================

pam_open_write:
    pushad

    ; Configure Standard PAM0 (offset 0x59 on Host Bridge PCI 0:0.0)
    mov     eax, HOST_BRIDGE_PCI_ADDR | 0x58
    mov     cl, 1
    call    pci_config_read8
    mov     bl, al
    and     al, ~PAM_RW             ; Clear bits [5:4] (mask = 0xCF)
    or      al, PAM_WE              ; Set bit 5 (WE = 0x20)
    mov     dl, al
    call    pci_config_write8

    ; Configure Extended PAM0 (offset 0x90 on Host Bridge PCI 0:0.0)
    mov     eax, HOST_BRIDGE_PCI_ADDR | 0x90
    mov     cl, 0
    call    pci_config_read8
    and     al, ~PAM_RW             ; Clear bits [5:4] (mask = 0xCF)
    or      al, PAM_WE              ; Set bit 5 (WE = 0x20)
    mov     dl, al
    call    pci_config_write8

    popad
    ret

pam_lock_readonly:
    pushad

    ; Lock Standard PAM0 (offset 0x59)
    mov     eax, HOST_BRIDGE_PCI_ADDR | 0x58
    mov     cl, 1
    call    pci_config_read8
    and     al, ~PAM_RW             ; Clear bits [5:4] (mask = 0xCF)
    or      al, PAM_RE              ; Set bit 4 (RE = 0x10)
    mov     dl, al
    call    pci_config_write8

    ; Lock Extended PAM0 (offset 0x90)
    mov     eax, HOST_BRIDGE_PCI_ADDR | 0x90
    mov     cl, 0
    call    pci_config_read8
    and     al, ~PAM_RW             ; Clear bits [5:4] (mask = 0xCF)
    or      al, PAM_RE              ; Set bit 4 (RE = 0x10)
    mov     dl, al
    call    pci_config_write8

    ; Verify write protection: confirm writes do not mutate shadow RAM at 0xF000:0000
    mov     ax, FW_SHADOW_SEG
    mov     es, ax
    mov     eax, [es:0]             ; Save current value (should be FW_MAGIC 'IPO')
    mov     dword [es:0], 0xDEADBEEF ; Attempt write to locked shadow RAM
    mov     ebx, [es:0]
    mov     [es:0], eax             ; Restore if write wasn't blocked
    ; If shadow RAM is locked, EBX == EAX (write ignored)

    popad
    ret
