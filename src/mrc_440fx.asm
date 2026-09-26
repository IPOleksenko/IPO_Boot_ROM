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
;   82443BX SDRAM Mode Select (SMS) field is in bits [7:5].
;   These values are written to SDRAMC to issue commands to DIMMs.
;   The actual command is sent when the CPU performs a read from DRAM.
SDRAMC_DISABLED     equ 0x00        ; SDRAM controller normal / disabled (000b << 5)
SDRAMC_NOP          equ 0x20        ; NOP Command Enable (001b << 5)
SDRAMC_PRECHARGE    equ 0x40        ; All Banks Precharge (010b << 5)
SDRAMC_MRS          equ 0x60        ; Mode Register Set (011b << 5)
SDRAMC_CBR_REFRESH  equ 0x80        ; CBR Auto-Refresh (100b << 5)
SDRAMC_NORMAL       equ 0x00        ; Normal SDRAM Operation (000b << 5)

; Mode Register Set (MRS) address encodings (82443BX MAA mapping per coreboot i440bx raminit.c:377-386):
;   Host CPU address lines A[11:2] map to SDRAM multiplexed address lines MAA[13:0].
;   For DIMM 0 and 1 (rows 0..3), no pin inversion is applied:
MRS_DIMM01_CL3_ADDR equ 0x01D0      ; Rows 0..3 (DIMM 0/1), CAS Latency = 3
MRS_DIMM01_CL2_ADDR equ 0x0150      ; Rows 0..3 (DIMM 0/1), CAS Latency = 2

;   For DIMM 2 and 3 (rows 4..7), lines MAA[12:11, 9:0] are inverted by chipset buffer:
MRS_DIMM23_CL3_ADDR equ 0x1E28      ; Rows 4..7 (DIMM 2/3), CAS Latency = 3
MRS_DIMM23_CL2_ADDR equ 0x1EA8      ; Rows 4..7 (DIMM 2/3), CAS Latency = 2

; Active MRS address for current timing configuration (CL=3 on DIMM 0/1):
MRS_CL3_ADDR        equ MRS_DIMM01_CL3_ADDR  ; 0x01D0

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
    ; Step 3: Probe DIMMs via SMBus SPD EEPROMs (PIIX4 / ICH9)
    ;         If SPD data is valid: sets DRB0..7, RPS, and total RAM dynamically.
    ;         If SPD read fails: emits warning POST code 0x1F and falls back.
    ; -------------------------------------------------------------------------
    call    mrc_probe_spd_440fx
    jnc     .spd_configured

    ; SPD probe failed / not present: Output warning code 0x1F
    mov     al, POST_WARN_SPD_FAIL          ; 0x1F: Warning — using CMOS/default RAM geometry
    out     POST_PORT, al

    ; Fallback: detect memory size via CMOS registers / default 64MB
    call    mrc_detect_ram_size
    ; Returns: EBX = total RAM in bytes, ECX = total RAM in 8 MB units

    ; Save detected memory size in CAR
    mov     ax, CAR_STACK_SEG
    mov     es, ax
    mov     [es:CAR_TOTAL_RAM_BYTES], ebx

    ; Program DRB Registers (0x60–0x67) with fallback size
    mov     esi, 0                          ; Row counter (0–7)
.program_drb:
    mov     eax, I440FX_PCI_ADDR
    mov     ebx, esi
    add     ebx, I440FX_DRB0                ; EBX = 0x60 + row
    mov     edx, ebx
    and     edx, 0xFC                       ; Dword-align
    add     eax, edx
    push    cx                              ; Preserve total 8MB units
    mov     dl, cl                          ; DL = total 8MB units (value to write)
    mov     cl, bl
    and     cl, 0x03                        ; CL = byte offset within dword (0–3)
    call    pci_config_write8
    pop     cx                              ; Restore total 8MB units

    inc     esi
    cmp     esi, 8
    jb      .program_drb

    ; Configure Row Page Size (RPS, register 0x74) — 1 KB page size safe default
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_RPS & 0x03
    add     eax, I440FX_RPS & 0xFC
    mov     dl, 0x00
    call    pci_config_write8

.spd_configured:
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
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_NOP                  ; 0x20
    call    pci_config_write8

    ; Issue NOP: dummy read from address 0x00000000
    xor     ax, ax
    mov     es, ax
    mov     al, [es:0x0000]                 ; Triggers NOP on DRAM bus

    ; --- 7b: All Banks Precharge ---
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_PRECHARGE            ; 0x40
    call    pci_config_write8

    mov     al, [es:0x0000]                 ; Triggers All Banks Precharge

    ; --- 7c: CBR Auto-Refresh (×8) ---
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_CBR_REFRESH          ; 0x80
    call    pci_config_write8

    mov     cx, 8
.cbr_loop:
    mov     al, [es:0x0000]                 ; Each read triggers one CBR refresh
    loop    .cbr_loop

    ; --- 7d: Mode Register Set (MRS) ---
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_MRS                  ; 0x60
    call    pci_config_write8

    ; Read from address encoding CL=3 (0x01D0 for DIMM 0/1 per coreboot i440bx raminit.c:382)
    mov     al, [es:MRS_CL3_ADDR & 0xFFFF] ; Read from 0x01D0 triggers MRS cycle on DRAM bus

    ; --- 7e: Normal SDRAM Operation ---
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_SDRAMC & 0x03
    add     eax, I440FX_SDRAMC & 0xFC
    mov     dl, SDRAMC_NORMAL               ; 0x00
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 8: Verify memory is alive — RAM pattern sanity test
    ;         Write 0x55AA55AA and 0xAA55AA55 to DRAM and read back
    ; -------------------------------------------------------------------------
    xor     ax, ax
    mov     es, ax

    mov     dword [es:0x1000], 0x55AA55AA
    cmp     dword [es:0x1000], 0x55AA55AA
    jne     .mem_failed

    mov     dword [es:0x1000], 0xAA55AA55
    cmp     dword [es:0x1000], 0xAA55AA55
    jne     .mem_failed

    ; Memory pattern test passed!
    mov     al, POST_DRAM_OK                ; 0x17
    out     POST_PORT, al
    jmp     .mem_ok

.mem_failed:
    ; Memory test failed
    mov     al, POST_ERR_DRAM_FAIL          ; 0x4E
    out     POST_PORT, al
    mov     ax, CAR_STACK_SEG
    mov     es, ax
    mov     dword [es:CAR_TOTAL_RAM_BYTES], 0

.mem_ok:
    pop     es
    pop     ds
    popad
    ret

; =============================================================================
; mrc_probe_spd_440fx — Probe SDRAM DIMMs via SMBus SPD EEPROMs
; =============================================================================
; Probes DIMM slots 0..3 (I2C addresses 0x50..0x53) for SDR SDRAM modules.
; Output:
;   CF = 0 on success (at least one valid SDRAM DIMM found)
;   CF = 1 on failure (no DIMMs detected via SPD or SMBus error)
; =============================================================================
mrc_probe_spd_440fx:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    bp

    call    smbus_init

    mov     ax, CAR_STACK_SEG
    mov     es, ax

    xor     si, si                          ; SI = DIMM slot index (0..3)
    xor     edi, edi                        ; EDI = cumulative 8MB units
    xor     bp, bp                          ; BP = cumulative RPS word (16-bit)
    xor     cx, cx                          ; CH = detected DIMM count, CL = current row index (0..7)

.spd_slot_loop:
    cmp     si, 4
    jge     .spd_scan_done

    ; BL = I2C slave address: 0x50 + SI
    mov     bx, si
    add     bl, SPD_ADDR_DIMM0              ; 0x50 + SI

    ; Read byte 2: Fundamental Memory Type
    mov     bh, 2
    call    smbus_read_byte
    jc      .spd_no_dimm
    cmp     al, 0x04                        ; 0x04 = SDR SDRAM
    jne     .spd_no_dimm

    ; Read byte 3: Number of row addresses
    mov     bh, 3
    call    smbus_read_byte
    jc      .spd_no_dimm
    movzx   edx, al                         ; EDX = row bits

    ; Read byte 4: Number of column addresses
    mov     bh, 4
    call    smbus_read_byte
    jc      .spd_no_dimm
    movzx   eax, al                         ; EAX = col bits

    ; Read byte 5: Number of physical banks/ranks (1 = single-sided, 2 = double-sided)
    push    dx                              ; Save rows
    push    ax                              ; Save cols
    mov     bh, 5
    call    smbus_read_byte
    pop     dx                              ; DL = cols
    pop     bx                              ; BL = rows
    jc      .spd_no_dimm
    and     al, 0x07
    test    al, al
    jz      .spd_no_dimm
    push    ax                              ; Stack: saved ranks count (1 or 2)

    ; Read byte 17: Number of banks on each SDRAM chip
    push    bx                              ; Save rows
    push    dx                              ; Save cols
    mov     bh, 17
    call    smbus_read_byte
    pop     dx                              ; DL = cols
    pop     bx                              ; BL = rows
    jc      .spd_pop_no_dimm
    and     al, 0x07
    test    al, al
    jnz     .have_chip_banks
    mov     al, 4                           ; Default 4 banks
.have_chip_banks:
    movzx   eax, al                         ; EAX = chip banks

    ; Calculate capacity per physical rank:
    movzx   ebx, bl                         ; rows
    movzx   edx, dl                         ; cols
    push    edx                             ; Save cols for RPS calculation
    add     ebx, edx                        ; EBX = rows + cols
    sub     ebx, 20
    jle     .spd_pop2_no_dimm

    mov     edx, 1
    push    cx
    mov     cl, bl
    shl     edx, cl                         ; EDX = 2^(rows+cols-20)
    pop     cx

    imul    edx, eax                        ; EDX = 2^N * chip_banks
    test    edx, edx
    jz      .spd_pop2_no_dimm

    pop     eax                             ; AL = cols
    pop     bx                              ; BL = ranks (1 or 2)
    inc     ch                              ; Successfully detected a DIMM!

    ; Determine RPS code for this DIMM:
    ; AL = cols: <= 9 -> 00b (1KB), 10 -> 01b (2KB), >= 11 -> 10b (4KB)
    xor     ah, ah
    cmp     al, 9
    jbe     .rps_1k
    cmp     al, 10
    je      .rps_2k
    mov     ah, 2                           ; 10b = 4KB page
    jmp     .rps_done
.rps_1k:
    mov     ah, 0                           ; 00b = 1KB page
    jmp     .rps_done
.rps_2k:
    mov     ah, 1                           ; 01b = 2KB page
.rps_done:

    ; Program Row A (row index in CL)
    add     edi, edx                        ; Add rank 8MB units to cumulative boundary
    cmp     edi, 0xFF
    jbe     .drb_a_ok
    mov     edi, 0xFF
.drb_a_ok:
    push    dx
    push    ax
    mov     dx, di
    call    .write_drb_row
    call    .write_rps_row
    pop     ax
    pop     dx
    inc     cl

    ; Program Row B (row index in CL)
    cmp     bl, 2
    jne     .single_sided
    ; Double-sided: Row B has same capacity
    add     edi, edx
    cmp     edi, 0xFF
    jbe     .drb_b_ok
    mov     edi, 0xFF
.drb_b_ok:
    push    dx
    push    ax
    mov     dx, di
    call    .write_drb_row
    call    .write_rps_row
    pop     ax
    pop     dx
    inc     cl
    jmp     .dimm_done

.single_sided:
    ; Single-sided: Row B has 0 capacity, so DRB[CL] = DRB[CL-1] (same cumulative value)
    push    dx
    mov     dx, di
    call    .write_drb_row
    pop     dx
    inc     cl
    jmp     .dimm_done

.spd_pop2_no_dimm:
    pop     edx                             ; Discard saved cols
.spd_pop_no_dimm:
    pop     ax                              ; Discard saved ranks
.spd_no_dimm:
    ; Slot empty or unreadable: advance row index by 2 rows with current cumulative DRB value
    push    dx
    mov     dx, di
    call    .write_drb_row
    inc     cl
    call    .write_drb_row
    inc     cl
    pop     dx

.dimm_done:
    inc     si
    jmp     .spd_slot_loop

.spd_scan_done:
    test    ch, ch
    jz      .spd_failed                     ; No DIMMs found!

    ; Write final cumulative RPS word (BP) to PCI 0x74
    mov     eax, I440FX_PCI_ADDR
    mov     cl, I440FX_RPS & 0x03
    add     eax, I440FX_RPS & 0xFC
    mov     dx, bp
    call    pci_config_write8
    inc     cl
    mov     dl, dh
    call    pci_config_write8

    ; Store total RAM in bytes = EDI * 8 MB
    mov     eax, edi
    shl     eax, 23                         ; * 8 * 1024 * 1024
    mov     [es:CAR_TOTAL_RAM_BYTES], eax

    clc                                     ; Success!
    jmp     .spd_exit

.spd_failed:
    stc                                     ; Fail -> fallback
.spd_exit:
    pop     bp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

; Helper: write DRB[CL] with value in DL
.write_drb_row:
    push    eax
    push    ebx
    push    cx
    movzx   ebx, cl
    add     ebx, I440FX_DRB0                ; 0x60 + row
    mov     eax, I440FX_PCI_ADDR
    mov     cl, bl
    and     cl, 0x03                        ; byte offset
    and     ebx, 0xFC
    add     eax, ebx                        ; dword-aligned PCI addr
    call    pci_config_write8
    pop     cx
    pop     ebx
    pop     eax
    ret

; Helper: update BP with 2-bit RPS code in AH for row CL
.write_rps_row:
    push    cx
    push    ax
    movzx   cx, cl
    shl     cx, 1                           ; bit shift = row * 2
    movzx   ax, ah                          ; 2-bit code
    shl     ax, cl                          ; shift to row position
    or      bp, ax                          ; merge into BP
    pop     ax
    pop     cx
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
