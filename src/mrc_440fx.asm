; mrc_440fx.asm — Memory Reference Code (MRC) for Intel i440FX (82441FX PMC)
; Included by init.asm
;
; Configures the SDRAM memory controller so that DRAM is functional.
; The i440FX PMC lives at PCI Bus 0, Dev 0, Fn 0 (address 0x80000000).
;
; Dependencies (defined in chipset.asm, linked before this file):
;   pci_config_read8   — EAX=PCI addr (dword-aligned), CL=byte offset → AL
;   pci_config_write8  — EAX=PCI addr (dword-aligned), CL=byte offset, DL=value
;   pci_config_read16  — EAX=PCI addr → AX
;   pci_config_read32  — EAX=PCI addr → EAX
;   pci_config_write16 — EAX=PCI addr, value in DX

BITS 16

%include "contract.inc"

; =============================================================================
; SDRAM Controller Register Values
; =============================================================================

; DRAMT (reg 0x68) — DRAM Timing Register
;   Bit [4]  : 1 = SDRAM mode (vs EDO)
;   Bits[3:2]: 00 = CAS Latency 3 (conservative)
;   Bits[1:0]: 00 = 0 wait states for MA
DRAMT_SDRAM_CL3     equ 0x10

; SDRAMC (reg 0x76) — SDRAM Control Register Command Encodings
;   These values are written to SDRAMC to issue commands to DIMMs.
;   The actual command is sent when the CPU performs a read from DRAM.
SDRAMC_DISABLED     equ 0x00        ; SDRAM controller disabled / normal prep
SDRAMC_NOP          equ 0x08        ; NOP Command Enable
SDRAMC_PRECHARGE    equ 0x10        ; All Banks Precharge
SDRAMC_CBR_REFRESH  equ 0x18        ; CBR (CAS Before RAS) Auto-Refresh
SDRAMC_MRS          equ 0x20        ; Mode Register Set
SDRAMC_NORMAL       equ 0x00        ; Normal SDRAM Operation

; Mode Register Set address encoding for CAS Latency 3:
;   The SDRAM mode register is programmed by a read from an address
;   that encodes the mode bits. For CL=3: A[6:4] = 011 → address bit pattern.
;   In practice, a read from a low address (e.g., 0x00000000) after writing
;   SDRAMC_MRS with CL=3 encoded in DRAMT is sufficient on i440FX.
MRS_CL3_ADDR        equ 0x00000030  ; CL=3 encoded in A[6:4]

; Default memory size (8 MB units) — fallback if CMOS detection fails
MRC_DEFAULT_8MB     equ 0x08        ; 8 × 8 MB = 64 MB

; CMOS extended memory registers (above 16 MB, in 64 KB units)
;   Register 0x34 = low byte, 0x35 = high byte
CMOS_EXT2_MEM_LO    equ 0x34
CMOS_EXT2_MEM_HI    equ 0x35

; CMOS base extended memory (1 MB–16 MB, in 1 KB units)
;   Register 0x17 = low byte, 0x18 = high byte
CMOS_EXT_MEM_LO     equ 0x17
CMOS_EXT_MEM_HI     equ 0x18

; =============================================================================
; mrc_init_440fx — Initialize SDRAM controller on i440FX
; =============================================================================
; Inputs:  None (chipset must be at PCI 0:0.0)
; Outputs: [mrc_total_ram_bytes] = detected RAM in bytes
; Clobbers: None (all registers preserved)
; =============================================================================

mrc_init_440fx:
    pushad
    push    ds
    push    es

    ; -------------------------------------------------------------------------
    ; Step 1: Set DRAM Timing (DRAMT, register 0x68)
    ;         SDRAM mode, CAS Latency = 3, 0 MA wait states
    ; -------------------------------------------------------------------------
    mov     eax, I440FX_PCI_ADDR            ; 0x80000000 — Bus 0, Dev 0, Fn 0
    mov     cl, I440FX_DRAMT & 0x03         ; Byte offset within dword
    add     eax, I440FX_DRAMT & 0xFC        ; Dword-aligned PCI address
    mov     dl, DRAMT_SDRAM_CL3             ; 0x10: SDRAM, CL=3, 0ws
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 2: Disable SDRAM controller (SDRAMC, register 0x76)
    ;         Must be disabled before programming DRBs
    ; -------------------------------------------------------------------------
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_DISABLED             ; 0x00: controller off
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 3: Detect memory size via CMOS registers
    ;         CMOS 0x34/0x35 = memory above 16 MB in 64 KB units
    ;         CMOS 0x17/0x18 = memory between 1–16 MB in 1 KB units
    ;         Total = 1 MB (base) + ext_1to16 + ext_above16
    ; -------------------------------------------------------------------------
    call    mrc_detect_ram_size
    ; Returns: EBX = total RAM in bytes, ECX = total RAM in 8 MB units

    ; Save detected memory size
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    mov     [mrc_total_ram_bytes], ebx

    ; -------------------------------------------------------------------------
    ; Step 4: Program DRB Registers (0x60–0x67)
    ;         DRBn = cumulative DRAM boundary in 8 MB units
    ;         We put all memory in row 0, remaining rows repeat same boundary
    ; -------------------------------------------------------------------------
    ; ECX = total 8 MB units (from detection)
    ; DRB0 = ECX, DRB1..DRB7 = ECX (no additional rows)
    mov     esi, 0                          ; Row counter (0–7)
.program_drb:
    mov     eax, I440FX_PCI_ADDR
    lea     edx, [esi + I440FX_DRB0]        ; Register = 0x60 + row
    push    ecx
    mov     cl, dl
    and     cl, 0x03                        ; Byte offset within dword
    and     edx, 0xFC                       ; Dword-align
    add     eax, edx
    pop     ecx
    mov     dl, cl                          ; DRBn value = total 8MB units
    call    pci_config_write8

    inc     esi
    cmp     esi, 8
    jb      .program_drb

    ; -------------------------------------------------------------------------
    ; Step 5: Configure Row Page Size (RPS, register 0x74)
    ;         0x00 = 1 KB page size for all rows (safe default)
    ; -------------------------------------------------------------------------
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_RPS & 0x03
    add     eax, I440FX_RPS & 0xFC
    mov     dl, 0x00
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 6: Configure Paging Policy (PGPOL, register 0x78)
    ;         0x00 = standard paging policy
    ; -------------------------------------------------------------------------
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_PGPOL & 0x03
    add     eax, I440FX_PGPOL & 0xFC
    mov     dl, 0x00
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 7: SDRAM Initialization Sequence
    ;         The i440FX requires a specific command sequence to bring
    ;         SDRAM DIMMs online. Each command is issued by:
    ;           1. Writing the command code to SDRAMC (reg 0x76)
    ;           2. Performing a dummy read from DRAM (triggers command on bus)
    ;         QEMU ignores these commands but accepts the register writes.
    ;         Real hardware requires exact sequencing per JEDEC spec.
    ; -------------------------------------------------------------------------

    ; --- 7a: NOP Command ---
    ;     Stabilizes the SDRAM clock after power-up
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_NOP                  ; 0x08
    call    pci_config_write8

    ; Issue NOP: dummy read from address 0x00000000
    xor     ax, ax
    mov     es, ax
    mov     al, [es:0x0000]                 ; Triggers NOP on DRAM bus

    ; --- 7b: All Banks Precharge ---
    ;     Precharges all SDRAM banks simultaneously
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_PRECHARGE            ; 0x10
    call    pci_config_write8

    mov     al, [es:0x0000]                 ; Triggers All Banks Precharge

    ; --- 7c: CBR Auto-Refresh (×8) ---
    ;     JEDEC requires at least 8 auto-refresh cycles during initialization
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_CBR_REFRESH          ; 0x18
    call    pci_config_write8

    ; Perform 8 dummy reads to issue 8 CBR refresh cycles
    mov     cx, 8
.cbr_loop:
    mov     al, [es:0x0000]                 ; Each read triggers one CBR refresh
    loop    .cbr_loop

    ; --- 7d: Mode Register Set (MRS) ---
    ;     Programs the SDRAM mode register with CAS latency and burst length.
    ;     The address bits encode the mode: A[6:4]=011 for CL=3.
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_MRS                  ; 0x20
    call    pci_config_write8

    ; Read from address encoding CL=3: bit pattern at A[6:4]
    ; Address 0x0030 → A6=0, A5=1, A4=1 → CL=3
    mov     al, [es:MRS_CL3_ADDR & 0xFFFF] ; Read from 0x0030 triggers MRS

    ; --- 7e: Normal SDRAM Operation ---
    ;     Transitions the controller to normal operation mode
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_NORMAL               ; 0x00
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 8: Verify memory is alive — quick sanity test
    ;         Write a pattern to low memory, read it back
    ; -------------------------------------------------------------------------
    xor     ax, ax
    mov     es, ax

    mov     dword [es:0x1000], 0xDEADBEEF   ; Write test pattern
    mov     eax, [es:0x1000]                ; Read it back
    cmp     eax, 0xDEADBEEF
    je      .mem_ok

    ; Memory test failed — zero out detected size as a warning
    mov     ax, BOOTROM_SEG
    mov     ds, ax
    mov     dword [mrc_total_ram_bytes], 0

.mem_ok:
    pop     es
    pop     ds
    popad
    ret

; =============================================================================
; mrc_detect_ram_size — Detect installed RAM via CMOS registers
; =============================================================================
; The BIOS/firmware traditionally stores extended memory size in CMOS:
;   CMOS 0x34 (low) / 0x35 (high) = memory above 16 MB, in 64 KB units
;   CMOS 0x17 (low) / 0x18 (high) = memory between 1–16 MB, in 1 KB units
;
; On QEMU, these are pre-populated by the machine model.
; On real i440FX hardware, these were set by the original BIOS during POST.
;
; Total RAM = 1 MB (base) + ext_1to16_KB*1024 + ext_above16_64KB*65536
;
; Inputs:  None
; Outputs: EBX = total RAM in bytes
;          ECX = total RAM in 8 MB units (rounded up, minimum 1)
; Clobbers: EAX, EDX (caller-saved by pushad in parent)
; =============================================================================

mrc_detect_ram_size:
    ; --- Read memory above 16 MB (CMOS 0x34/0x35) in 64 KB units ---
    mov     al, CMOS_EXT2_MEM_LO            ; 0x34
    out     CMOS_INDEX_PORT, al
    jmp     short $+2                       ; I/O delay (CMOS needs time)
    in      al, CMOS_DATA_PORT
    movzx   ebx, al                         ; EBX = low byte

    mov     al, CMOS_EXT2_MEM_HI            ; 0x35
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   eax, al
    shl     eax, 8
    or      ebx, eax                        ; EBX = ext_above_16MB in 64 KB units

    ; Convert to bytes: EBX = EBX * 65536 (shift left 16)
    shl     ebx, 16                         ; EBX = bytes above 16 MB

    ; --- Read memory 1–16 MB (CMOS 0x17/0x18) in 1 KB units ---
    mov     al, CMOS_EXT_MEM_LO             ; 0x17
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   edx, al                         ; EDX = low byte

    mov     al, CMOS_EXT_MEM_HI             ; 0x18
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   eax, al
    shl     eax, 8
    or      edx, eax                        ; EDX = ext_1to16MB in 1 KB units

    ; Convert to bytes: EDX = EDX * 1024 (shift left 10)
    shl     edx, 10                         ; EDX = bytes between 1–16 MB

    ; --- Total RAM = 1 MB (base) + ext_1to16 + ext_above16 ---
    add     ebx, edx                        ; EBX += ext_1to16MB bytes
    add     ebx, 0x00100000                 ; EBX += 1 MB (base memory)

    ; --- Sanity check: if result is ≤ 1 MB, use default ---
    cmp     ebx, 0x00200000                 ; Less than 2 MB?
    ja      .size_ok

    ; CMOS returned garbage or zero — use default (64 MB)
    mov     ebx, MRC_DEFAULT_8MB
    shl     ebx, 23                         ; EBX = default × 8 MB = bytes

.size_ok:
    ; --- Compute 8 MB units (rounded up) for DRB programming ---
    ; ECX = (EBX + 0x7FFFFF) >> 23   (round up to next 8 MB boundary)
    mov     ecx, ebx
    add     ecx, 0x007FFFFF                 ; Round up
    shr     ecx, 23                         ; ECX = 8 MB units

    ; Clamp to maximum 255 (DRB is 8-bit, max 255 × 8 MB = 2040 MB)
    cmp     ecx, 0xFF
    jbe     .clamp_ok
    mov     ecx, 0xFF

.clamp_ok:
    ret

; =============================================================================
; mrc_test_address — Test if physical memory at a given address is real
; =============================================================================
; Uses flat segment:offset in real mode. Only works for addresses < 1 MB
; unless unreal mode / A20 is enabled. For full 32-bit addressing, the
; caller must set up unreal mode (big real) or use a segment trick.
;
; Input:  ESI = physical address to test (must be < 1 MB for real mode)
;         Assumes ES = 0x0000
; Output: CF = 0 → memory present at ESI
;         CF = 1 → absent or aliased (reads back wrong value)
; Clobbers: EAX
; =============================================================================

mrc_test_address:
    push    ebx

    ; Write unique test pattern to target address
    mov     dword [es:esi], 0xDEADBEEF

    ; Write a different pattern to address 0 to detect aliasing
    ; (if ESI wraps/aliases to 0, this will overwrite our test pattern)
    mov     dword [es:0x0000], 0x12345678

    ; Small delay: allow memory bus to settle (needed on real hardware)
    jmp     short $+2
    jmp     short $+2

    ; Read back from target address
    mov     eax, [es:esi]
    cmp     eax, 0xDEADBEEF
    je      .present

    ; Memory absent or aliased
    stc                                     ; CF = 1 (absent)
    pop     ebx
    ret

.present:
    clc                                     ; CF = 0 (present)
    pop     ebx
    ret

; =============================================================================
; Data Section
; =============================================================================

align 4
mrc_total_ram_bytes  dd 0                   ; Detected total RAM in bytes
                                            ; Used by int15.asm for E820 map
