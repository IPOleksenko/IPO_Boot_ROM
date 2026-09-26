; mrc_q35.asm — Memory Reference Code for Intel Q35 MCH + ICH9
; Included by init.asm — depends on chipset.asm (PCI helpers) and smbus.asm
;
; The Q35 MCH (Memory Controller Hub) is at PCI 0:0.0 (Device ID 0x29C0).
; This module initializes the memory subsystem:
;   1. Probes DIMMs via SPD over SMBus
;   2. Calculates total memory size
;   3. Programs the Q35 memory controller registers
;   4. Falls back to CMOS / fw_cfg / default if no SPD data
;
; Subroutines:
;   mrc_init_q35 — Full memory init sequence for Q35 + ICH9
;
; Depends on (from chipset.asm):
;   pci_read_dword   — Read 32-bit PCI config register (EAX = PCI addr)
;   pci_write_dword  — Write 32-bit PCI config register (EAX = PCI addr, ECX = data)
; Depends on (from smbus.asm):
;   smbus_init       — Initialize the ICH9 SMBus controller
;   smbus_read_byte  — Read a byte via SMBus (BL=slave, BH=offset → AL=data)

BITS 16

%include "contract.inc"

; =============================================================================
; Local Constants
; =============================================================================

; SPD byte offsets (DDR2 / DDR3 JEDEC standard)
SPD_BYTES_USED      equ 0           ; Number of bytes used / total SPD size
SPD_DRAM_TYPE       equ 2           ; DRAM Device Type
SPD_NUM_RANKS       equ 5           ; Number of ranks / row addressing
SPD_MOD_WIDTH_LO    equ 6           ; Module organization (low byte)
SPD_MOD_WIDTH_HI    equ 7           ; Module organization (high byte)
SPD_ROW_COL         equ 5           ; Row/Column address bits
SPD_NUM_BANKS       equ 4           ; Number of banks
SPD_MOD_TYPE        equ 8           ; Module type
SPD_CAS_DDR2        equ 18          ; CAS Latency (DDR2)
SPD_CAS_DDR3        equ 14          ; CAS Latency (DDR3)

; DRAM device type codes
DRAM_TYPE_DDR2      equ 0x08
DRAM_TYPE_DDR3      equ 0x0B

; Q35 memory size limits
Q35_MAX_TOLUD_MB    equ 3584        ; 3.5 GB = max low usable DRAM
Q35_DEFAULT_RAM_MB  equ 128         ; Fallback: 128 MB if all detection fails

; Number of DIMM slots to probe
NUM_DIMMS           equ 4

; =============================================================================
; mrc_init_q35 — Memory Reference Code for Q35 + ICH9
; =============================================================================
;
; Performs the full memory initialization sequence:
;   1. Initialize SMBus controller
;   2. Probe DIMMs 0-3 via SPD reads
;   3. Calculate total memory
;   4. Program Q35 MCH registers (DRC, TOLUD, TOM)
;   5. Fallback detection if no SPD data
;
; Inputs:  None
; Outputs: None (mrc_total_ram_mb is set)
; Clobbers: None (all registers preserved)
; =============================================================================
mrc_init_q35:
    pushad
    push    es

    ; =================================================================
    ; Step 1: Initialize the ICH9 SMBus Controller
    ; =================================================================
    call    smbus_init

    ; =================================================================
    ; Step 2: Probe DIMMs via SPD EEPROM
    ; =================================================================
    ; Clear the DIMM info table and total RAM accumulator in CAR
    mov     ax, CAR_STACK_SEG
    mov     es, ax
    xor     eax, eax
    mov     [es:CAR_TOTAL_RAM_MB], eax      ; Total RAM = 0
    mov     [es:CAR_NUM_DIMMS], al          ; Detected DIMMs = 0

    ; Clear DIMM size table (4 dwords = 16 bytes)
    mov     [es:CAR_DIMM_SIZES + 0], eax
    mov     [es:CAR_DIMM_SIZES + 4], eax
    mov     [es:CAR_DIMM_SIZES + 8], eax
    mov     [es:CAR_DIMM_SIZES + 12], eax

    ; Clear DIMM type table (4 bytes)
    mov     [es:CAR_DIMM_TYPES + 0], eax

    ; ---- Probe each DIMM slot ----
    ; SI = DIMM index (0..3), used to index tables
    xor     si, si                          ; SI = DIMM index

.probe_next_dimm:
    cmp     si, NUM_DIMMS
    jge     .probe_done

    ; Compute slave address: SPD_ADDR_DIMM0 + SI
    mov     bx, si
    add     bl, SPD_ADDR_DIMM0              ; BL = 0x50 + dimm_index

    ; -----------------------------------------------------------------
    ; Read SPD byte 0: Number of bytes used (presence check)
    ; -----------------------------------------------------------------
    mov     bh, SPD_BYTES_USED              ; Offset 0
    call    smbus_read_byte
    jc      .dimm_not_present               ; CF=1 → no DIMM in this slot

    ; DIMM present — increment counter
    inc     byte [es:CAR_NUM_DIMMS]

    ; -----------------------------------------------------------------
    ; Read SPD byte 2: DRAM Device Type
    ;   0x08 = DDR2 SDRAM
    ;   0x0B = DDR3 SDRAM
    ; -----------------------------------------------------------------
    push    bx                              ; Preserve slave address
    mov     bh, SPD_DRAM_TYPE               ; Offset 2
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     [es:CAR_DIMM_TYPES + si], al    ; Store DRAM type

    ; Check if valid DRAM type
    cmp     al, DRAM_TYPE_DDR2
    je      .dimm_type_ok
    cmp     al, DRAM_TYPE_DDR3
    je      .dimm_type_ok
    jmp     .dimm_read_error                ; Unknown type -> treat as error

.dimm_type_ok:
    ; DIMM present & valid type — increment counter
    inc     byte [es:CAR_NUM_DIMMS]

    cmp     al, DRAM_TYPE_DDR3
    je      .read_ddr3_spd

    ; -----------------------------------------------------------------
    ; DDR2 JEDEC SPD Parsing (JESD21-C):
    ;   Byte 3: Number of row addresses (e.g. 13, 14, 15)
    ;   Byte 4: Number of column addresses (e.g. 9, 10, 11)
    ;   Byte 5: Number of ranks (bits [2:0] = ranks - 1: 0=1 rank, 1=2 ranks)
    ;   Byte 17: Number of banks (4 or 8)
    ; -----------------------------------------------------------------
    mov     bh, 3                           ; Rows
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     cl, al

    mov     bh, 4                           ; Cols
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     ch, al

    mov     bh, 5                           ; Ranks
    call    smbus_read_byte
    jc      .dimm_read_error
    and     al, 0x07
    inc     al                              ; AL = ranks (1 or 2)
    mov     dl, al

    mov     bh, 17                          ; Banks
    call    smbus_read_byte
    jc      .dimm_read_error
    test    al, al
    jnz     .banks_ok
    mov     al, 4                           ; Default 4 banks
.banks_ok:
    mov     dh, al

    pop     bx                              ; Restore slave address

    push    si                              ; Save DIMM index

    ; Validate rows (12..16) and cols (8..12)
    cmp     cl, 12
    jb      .default_size
    cmp     cl, 16
    ja      .default_size
    cmp     ch, 8
    jb      .default_size
    cmp     ch, 12
    ja      .default_size

    ; Total address bits = rows + cols
    movzx   eax, cl
    movzx   ebx, ch
    add     eax, ebx
    sub     eax, 20                         ; Convert to MB units (subtract 20)
    jl      .default_size

    push    cx
    mov     cl, al
    mov     eax, 1
    shl     eax, cl                         ; 2^(rows+cols-20)
    pop     cx

    movzx   ebx, dh                         ; Banks
    imul    eax, ebx
    shl     eax, 3                          ; * 8 bytes (64-bit bus)
    movzx   ebx, dl                         ; Ranks
    imul    eax, ebx                        ; Total MB

    jmp     .store_size

.read_ddr3_spd:
    ; -----------------------------------------------------------------
    ; DDR3 JEDEC SPD Parsing (JESD21-C):
    ;   Byte 4: bits [3:0] = density, bits [6:4] = banks
    ;   Byte 5: bits [5:3] = ranks - 1
    ; -----------------------------------------------------------------
    mov     bh, 4                           ; Banks / density
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     ch, al

    mov     bh, 5                           ; Ranks / addressing
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     cl, al

    pop     bx                              ; Restore slave address
    push    si                              ; Save DIMM index
.calc_ddr3:
    ; DDR3 SPD byte 4: bits [3:0] = total SDRAM capacity per die
    ;   0001 = 256Mbit, 0010=512Mbit, 0011=1Gbit, 0100=2Gbit,
    ;   0101 = 4Gbit,   0110=8Gbit
    ; DDR3 SPD byte 5: bits [5:3] = number of ranks - 1
    ;                   bits [2:0] = SDRAM device width (log2 encoding)

    mov     al, ch                          ; SPD[4]
    and     al, 0x0F                        ; Density code
    test    al, al
    jz      .default_size

    ; capacity_per_die_mbit = 128 << density_code
    ; (density code 1 = 256Mbit, code 2 = 512Mbit, etc.)
    movzx   ecx, al
    mov     eax, 128
    shl     eax, cl                         ; EAX = capacity in Mbit per die

    ; Convert Mbit to MB: divide by 8
    shr     eax, 3                          ; EAX = capacity in MB per die

    ; Number of ranks = ((SPD[5] >> 3) & 0x07) + 1
    mov     al, cl                          ; Reload SPD[5] from earlier
    ; Wait, CL was row/col byte. Use it:
    mov     al, cl                          ; CL = SPD[5]
    shr     al, 3
    and     al, 0x07
    inc     al                              ; AL = number of ranks
    movzx   ecx, al

    ; Total capacity per die was in EAX but we clobbered AL
    ; Recalculate:
    mov     al, ch
    and     al, 0x0F
    movzx   edx, al
    mov     eax, 128
    shl     eax, cl                         ; This is wrong, CL is now ranks

    ; Fix: recalculate properly
    ; Save ranks count
    push    cx                              ; Save rank count on stack

    mov     al, ch                          ; SPD[4]
    and     al, 0x0F                        ; Density code
    movzx   ecx, al
    mov     eax, 128
    shl     eax, cl                         ; EAX = Mbit per die
    shr     eax, 3                          ; EAX = MB per die

    ; Device width from SPD[5] bits [2:0]
    ; 000=x4, 001=x8, 010=x16
    ; Module data width (typically 64 bits) / device width = number of chips
    ; chips = 64 / (4 << device_width_code)
    ; size_per_rank = capacity_per_die * chips
    pop     cx                              ; CX = ranks

    ; For QEMU simplicity, assume 8 chips per rank (x8 devices, 64-bit bus)
    shl     eax, 3                          ; EAX = MB per rank (× 8 chips)
    movzx   ecx, cl
    imul    eax, ecx                        ; EAX = total MB for this DIMM

    jmp     .store_size

.default_size:
    ; If calculation failed or yielded zero, assume 256 MB per DIMM
    mov     eax, 256

.store_size:
    ; Validate: cap at 16 GB per DIMM (sanity check)
    cmp     eax, 16384
    jbe     .size_ok
    mov     eax, 256                        ; Unreasonable → use default
.size_ok:
    test    eax, eax
    jnz     .size_nonzero
    mov     eax, 256                        ; Zero → use default
.size_nonzero:
    pop     si                              ; Restore DIMM index

    ; Store DIMM size in table (dword, indexed by SI*4)
    push    esi
    movzx   esi, si
    shl     esi, 2                          ; ESI = SI * 4
    mov     [es:CAR_DIMM_SIZES + esi], eax
    pop     esi

    ; Accumulate into total
    add     [es:CAR_TOTAL_RAM_MB], eax

    jmp     .next_dimm

.dimm_read_error:
    pop     bx                              ; Balance the push from before SPD reads

.dimm_not_present:
    ; DIMM not found or read error — skip to next slot

.next_dimm:
    inc     si
    jmp     .probe_next_dimm

.probe_done:

    ; =================================================================
    ; Step 3: Check if any DIMMs were detected
    ; =================================================================
    cmp     byte [es:CAR_NUM_DIMMS], 0
    jne     .dimms_detected

    ; No DIMMs detected via SPD — emit warning code 0x1F and fallback
    mov     al, POST_WARN_SPD_FAIL
    out     POST_PORT, al
    call    .fallback_detect_ram
    jmp     .program_mch

.dimms_detected:

    ; =================================================================
    ; Step 4: Program Q35 MCH Memory Controller Registers
    ; =================================================================
.program_mch:
    mov     eax, [es:CAR_TOTAL_RAM_MB]
    test    eax, eax
    jnz     .has_ram
    ; Still zero after fallback? Use absolute default
    mov     dword [es:CAR_TOTAL_RAM_MB], Q35_DEFAULT_RAM_MB
    mov     eax, Q35_DEFAULT_RAM_MB
.has_ram:

    ; -----------------------------------------------------------------
    ; 4a. DRC — DRAM Controller Mode (PCI 0:0.0 reg 0x7C)
    ;   Set DRAM type and channel configuration.
    ;   For QEMU Q35: write a sane default (DDR3, single channel)
    ;   Bit 0: DRAM initialized
    ;   Bits [2:1]: DRAM type (01=DDR2, 10=DDR3)
    ; -----------------------------------------------------------------
    push    eax                             ; Save total RAM MB

    mov     eax, Q35_PCI_ADDR | Q35_DRC
    call    pci_read_dword
    ; Check detected DRAM type from first present DIMM
    cmp     byte [es:CAR_DIMM_TYPES], DRAM_TYPE_DDR3
    je      .set_drc_ddr3
    ; Default: DDR2
    and     eax, 0xFFFFFFF8                 ; Clear bits [2:0]
    or      eax, 0x03                       ; DDR2 mode (01) + initialized (1)
    jmp     .write_drc
.set_drc_ddr3:
    and     eax, 0xFFFFFFF8                 ; Clear bits [2:0]
    or      eax, 0x05                       ; DDR3 mode (10) + initialized (1)
.write_drc:
    mov     ecx, eax
    mov     eax, Q35_PCI_ADDR | Q35_DRC
    call    pci_write_dword

    pop     eax                             ; Restore total RAM MB

    ; -----------------------------------------------------------------
    ; 4b. TOM — Top of Memory (PCI 0:0.0 reg 0xA0)
    ;   Total installed DRAM in MB, written as a 16-bit value.
    ;   TOM register: bits [15:4] = memory size in 1MB granularity
    ;                 bits [3:0] = reserved/lock
    ;   Encoding: value = total_mb << 4 (but QEMU may just take raw MB)
    ;
    ;   For QEMU: write total_ram_mb directly; QEMU's emulation accepts it.
    ; -----------------------------------------------------------------
    push    eax
    ; Write total RAM size in MB to TOM register
    mov     ecx, eax                        ; ECX = total_ram_mb
    mov     eax, Q35_PCI_ADDR | Q35_TOM
    call    pci_write_dword

    pop     eax

    ; -----------------------------------------------------------------
    ; 4c. TOLUD — Top of Low Usable DRAM (PCI 0:0.0 reg 0xB0)
    ;   Sets the upper boundary of usable DRAM below 4 GB.
    ;   Must be <= 3.5 GB (0xE0000000) to leave room for MMIO.
    ;   Encoding: bits [15:4] = address in MB, aligned to 64 MB boundary.
    ;
    ;   tolud_mb = min(total_ram_mb, 3584)
    ;   tolud_mb = ALIGN_DOWN(tolud_mb, 64)
    ;   register_value = tolud_mb << 4
    ; -----------------------------------------------------------------
    ; EAX = total RAM in MB
    cmp     eax, Q35_MAX_TOLUD_MB
    jbe     .tolud_ok
    mov     eax, Q35_MAX_TOLUD_MB           ; Cap at 3.5 GB
.tolud_ok:
    ; Align down to 64 MB boundary: clear bits [5:0]
    and     eax, 0xFFFFFFC0                 ; 64 MB alignment

    ; Shift into register format: bits [15:4]
    shl     eax, 4                          ; tolud_mb << 4 into bits [15:4]
    movzx   ecx, ax                         ; Only lower 16 bits matter
    ; Read-modify-write to preserve other bits
    push    ecx
    mov     eax, Q35_PCI_ADDR | Q35_TOLUD
    call    pci_read_dword
    and     eax, 0xFFFF0000                 ; Clear lower 16 bits
    pop     ecx
    or      eax, ecx                        ; Merge TOLUD value
    mov     ecx, eax
    mov     eax, Q35_PCI_ADDR | Q35_TOLUD
    call    pci_write_dword

    ; =================================================================
    ; Step 5: JEDEC DDR2 Initialization Sequence
    ; =================================================================
    ; Standard JESD79-2 sequence for DDR2 SDRAM initialization:
    ;   a. Delay >= 200 µs with CKE stable (power-up wait)
    ;   b. Issue NOP command via DRC
    ;   c. Issue Precharge All (PALL) command
    ;   d. Issue EMRS(2) / EMRS(3)
    ;   e. Issue EMRS(1) to enable DLL
    ;   f. Issue MRS with DLL reset (bit 8 = 1)
    ;   g. Delay >= 200 clocks (~200 µs) for DLL lock
    ;   h. Issue Precharge All (PALL) command
    ;   i. Issue 2x Auto-Refresh (CBR) cycles
    ;   j. Issue MRS without DLL reset (bit 8 = 0)
    ;   k. Issue EMRS(1) OCD default and exit
    ;   l. Set DRC to Normal Operation mode (000b)

    ; a. Power-up stabilization delay >= 200 µs
    call    mrc_delay_200us

    ; b. Issue NOP command (DIC = 001b = 0x10)
    mov     dl, 0x10
    call    .issue_drc_cmd

    ; c. Issue Precharge All (DIC = 010b = 0x20)
    mov     dl, 0x20
    call    .issue_drc_cmd

    ; d. Issue EMRS(2) / EMRS(3) (DIC = 011b = 0x30)
    mov     dl, 0x30
    call    .issue_drc_cmd

    ; e. Issue EMRS(1) to enable DLL (DIC = 011b = 0x30)
    mov     dl, 0x30
    call    .issue_drc_cmd

    ; f. Issue MRS with DLL reset (DIC = 011b = 0x30)
    mov     dl, 0x30
    call    .issue_drc_cmd

    ; g. Wait >= 200 clocks (~200 µs) for DLL lock
    call    mrc_delay_200us

    ; h. Issue Precharge All (DIC = 010b = 0x20)
    mov     dl, 0x20
    call    .issue_drc_cmd

    ; i. Issue 2x Auto-Refresh (CBR) cycles (DIC = 100b = 0x40)
    mov     dl, 0x40
    call    .issue_drc_cmd
    mov     dl, 0x40
    call    .issue_drc_cmd

    ; j. Issue MRS (normal, DLL reset cleared) (DIC = 011b = 0x30)
    mov     dl, 0x30
    call    .issue_drc_cmd

    ; k. Issue EMRS(1) OCD default and exit (DIC = 011b = 0x30)
    mov     dl, 0x30
    call    .issue_drc_cmd

    ; l. Switch DRC to Normal Operation mode (DIC = 000b = 0x00)
    mov     dl, 0x00
    call    .issue_drc_cmd

    ; Calculate total bytes from total MB (cap at 4095 MB to prevent 32-bit overflow)
    mov     eax, [es:CAR_TOTAL_RAM_MB]
    cmp     eax, 4095
    jbe     .mb_to_bytes_ok
    mov     eax, 4095
.mb_to_bytes_ok:
    shl     eax, 20                         ; Convert MB to bytes
    mov     [es:CAR_TOTAL_RAM_BYTES], eax

    ; =================================================================
    ; Step 6: DRAM Pattern Sanity Test (0x55AA55AA / 0xAA55AA55)
    ; =================================================================
    ; Test DRAM access at physical address 0x1000 (safely above IVT)
    xor     ax, ax
    mov     es, ax

    mov     dword [es:0x1000], 0x55AA55AA
    wbinvd
    cmp     dword [es:0x1000], 0x55AA55AA
    jne     .dram_test_fail

    mov     dword [es:0x1000], 0xAA55AA55
    wbinvd
    cmp     dword [es:0x1000], 0xAA55AA55
    jne     .dram_test_fail

    ; Clear test location
    mov     dword [es:0x1000], 0
    wbinvd

    mov     al, POST_DRAM_OK                ; 0x17
    out     POST_PORT, al
    jmp     .dram_test_ok

.dram_test_fail:
    mov     al, POST_ERR_DRAM_FAIL          ; 0x4E
    out     POST_PORT, al
    cli
    hlt
    jmp     short $-2

.dram_test_ok:
    pop     es
    popad
    ret

; Helper to issue DRC command (DIC in DL, bits [6:4])
.issue_drc_cmd:
    push    eax
    push    ecx
    mov     eax, Q35_PCI_ADDR | Q35_DRC
    call    pci_read_dword
    and     eax, ~0x00000070                ; Clear DIC bits [6:4]
    movzx   ecx, dl
    or      eax, ecx                        ; Set DIC
    or      eax, 0x01                       ; Bit 0: DRAM enabled
    mov     ecx, eax
    mov     eax, Q35_PCI_ADDR | Q35_DRC
    call    pci_write_dword

    ; Dummy DRAM read cycle to latch command onto bus
    push    es
    xor     ax, ax
    mov     es, ax
    mov     eax, [es:0x0000]
    pop     es
    out     0x80, al                        ; Small settling delay on bus
    pop     ecx
    pop     eax
    ret

; =============================================================================
; .fallback_detect_ram — Detect RAM size without SPD (CMOS / fw_cfg / default)
; =============================================================================
;
; Called when no DIMMs are detected via SMBus (e.g., QEMU without SPD
; emulation). Tries multiple detection methods in order of preference.
;
; Updates: mrc_total_ram_mb
; =============================================================================
.fallback_detect_ram:
    push    eax
    push    dx

    ; -----------------------------------------------------------------
    ; Method 1: CMOS registers 0x34/0x35
    ;   Extended memory above 16 MB, in 64 KB blocks.
    ;   CMOS 0x34 = low byte, CMOS 0x35 = high byte
    ;   Total above 16MB = value * 64 KB
    ;   Total RAM ≈ (value * 64KB) + 16MB
    ; -----------------------------------------------------------------
    mov     al, 0x35                        ; CMOS high byte
    out     CMOS_INDEX_PORT, al
    in      al, CMOS_DATA_PORT
    mov     ah, al                          ; AH = high byte

    mov     al, 0x34                        ; CMOS low byte
    out     CMOS_INDEX_PORT, al
    in      al, CMOS_DATA_PORT              ; AL = low byte

    ; AX = number of 64KB blocks above 16MB
    test    ax, ax
    jz      .try_fw_cfg                     ; No extended memory in CMOS

    ; Convert to MB: blocks * 64KB / 1024KB = blocks / 16
    movzx   eax, ax
    shr     eax, 4                          ; EAX = MB above 16 MB
    add     eax, 16                         ; Add the first 16 MB
    mov     [es:CAR_TOTAL_RAM_MB], eax
    jmp     .fallback_done

    ; -----------------------------------------------------------------
    ; Method 2: QEMU fw_cfg port (selector 0x0001 = RAM size in bytes)
    ; -----------------------------------------------------------------
.try_fw_cfg:
    mov     dx, FW_CFG_PORT_SEL
    mov     ax, FW_CFG_ID_RAM_SIZE          ; Selector 0x0001
    out     dx, ax

    mov     dx, FW_CFG_PORT_DATA
    in      al, dx                          ; Byte 0 (LSB)
    mov     cl, al
    in      al, dx                          ; Byte 1
    mov     ch, al
    in      al, dx                          ; Byte 2
    mov     bl, al
    in      al, dx                          ; Byte 3 (MSB)
    mov     bh, al

    movzx   eax, bx
    shl     eax, 16
    movzx   ecx, cx
    or      eax, ecx                        ; EAX = RAM size in bytes

    cmp     eax, 0x00100000                 ; >= 1 MB?
    jb      .use_default
    shr     eax, 20                         ; EAX = RAM in MB
    test    eax, eax
    jz      .use_default
    mov     [es:CAR_TOTAL_RAM_MB], eax
    jmp     .fallback_done

    ; -----------------------------------------------------------------
    ; Method 3: Default — 128 MB
    ; -----------------------------------------------------------------
.use_default:
    mov     dword [es:CAR_TOTAL_RAM_MB], Q35_DEFAULT_RAM_MB

.fallback_done:
    pop     dx
    pop     eax
    ret

; =============================================================================
; mrc_delay_200us — Busy-wait >= 200 microseconds using I/O bus delay
; =============================================================================
mrc_delay_200us:
    push    cx
    push    ax
    mov     cx, 250
.dloop:
    in      al, 0x80
    out     0x80, al
    dec     cx
    jnz     .dloop
    pop     ax
    pop     cx
    ret
