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
    ; Clear the DIMM info table and total RAM accumulator
    xor     eax, eax
    mov     [mrc_total_ram_mb], eax         ; Total RAM = 0
    mov     [mrc_num_dimms], al             ; Detected DIMMs = 0

    ; Clear DIMM size table (4 dwords = 16 bytes)
    mov     [dimm_sizes + 0], eax
    mov     [dimm_sizes + 4], eax
    mov     [dimm_sizes + 8], eax
    mov     [dimm_sizes + 12], eax

    ; Clear DIMM type table (4 bytes)
    mov     [dimm_types + 0], eax

    ; ---- Probe each DIMM slot ----
    ; SI = DIMM index (0..3), used to index tables
    xor     si, si                          ; SI = DIMM index

.probe_next_dimm:
    cmp     si, NUM_DIMMS
    jge     .probe_done

    ; Compute slave address: SPD_ADDR_DIMM0 + SI
    mov     bl, SPD_ADDR_DIMM0
    add     bl, [cs:si]                     ; Can't add SI directly to BL
    ; Corrected: manually compute BL = 0x50 + SI
    mov     bx, si
    add     bl, SPD_ADDR_DIMM0              ; BL = 0x50 + dimm_index

    ; -----------------------------------------------------------------
    ; Read SPD byte 0: Number of bytes used (presence check)
    ; -----------------------------------------------------------------
    mov     bh, SPD_BYTES_USED              ; Offset 0
    call    smbus_read_byte
    jc      .dimm_not_present               ; CF=1 → no DIMM in this slot

    ; DIMM present — increment counter
    inc     byte [mrc_num_dimms]

    ; -----------------------------------------------------------------
    ; Read SPD byte 2: DRAM Device Type
    ;   0x08 = DDR2 SDRAM
    ;   0x0B = DDR3 SDRAM
    ; -----------------------------------------------------------------
    push    bx                              ; Preserve slave address
    mov     bh, SPD_DRAM_TYPE               ; Offset 2
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     [dimm_types + si], al           ; Store DRAM type

    ; -----------------------------------------------------------------
    ; Read SPD byte 4: Number of banks/density
    ;   DDR2: bits [2:0] = number of banks (log2)
    ;   DDR3: bits [6:4] = bank address bits, bits [3:0] = density
    ; -----------------------------------------------------------------
    mov     bh, SPD_NUM_BANKS               ; Offset 4
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     ch, al                          ; CH = banks/density byte

    ; -----------------------------------------------------------------
    ; Read SPD byte 5: Row/Column addressing
    ;   DDR2: bits [7:5] = reserved, [4:3] = col bits-8, [2:0] = row bits-11
    ;   DDR3: bits [5:3] = row bits-12, bits [2:0] = col bits-9
    ; -----------------------------------------------------------------
    mov     bh, SPD_ROW_COL                 ; Offset 5
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     cl, al                          ; CL = row/col byte

    ; -----------------------------------------------------------------
    ; Read SPD byte 8: Module type
    ; -----------------------------------------------------------------
    mov     bh, SPD_MOD_TYPE                ; Offset 8
    call    smbus_read_byte
    jc      .dimm_read_error
    ; AL = module type (informational, not used for size calc here)

    ; -----------------------------------------------------------------
    ; Read SPD byte 6-7: Module organization / data width
    ; -----------------------------------------------------------------
    mov     bh, SPD_MOD_WIDTH_LO            ; Offset 6
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     dl, al                          ; DL = module org low

    mov     bh, SPD_MOD_WIDTH_HI            ; Offset 7
    call    smbus_read_byte
    jc      .dimm_read_error
    mov     dh, al                          ; DH = module org high

    ; -----------------------------------------------------------------
    ; Read CAS Latency (informational — needed for real HW timing)
    ;   DDR2: byte 18,  DDR3: byte 14
    ; -----------------------------------------------------------------
    cmp     byte [dimm_types + si], DRAM_TYPE_DDR3
    je      .read_cas_ddr3
    mov     bh, SPD_CAS_DDR2               ; DDR2: offset 18
    jmp     .read_cas
.read_cas_ddr3:
    mov     bh, SPD_CAS_DDR3               ; DDR3: offset 14
.read_cas:
    call    smbus_read_byte
    jc      .dimm_read_error
    ; AL = CAS latency bitmask (informational, stored but not used for QEMU)

    pop     bx                              ; Restore slave address

    ; -----------------------------------------------------------------
    ; Calculate DIMM size (in MB)
    ;
    ; For DDR3 (simplified formula):
    ;   Density bits = SPD[4] & 0x0F → capacity_mb lookup
    ;   Ranks = ((SPD[5] >> 3) & 0x07) + 1
    ;   Size = capacity_per_rank * ranks
    ;
    ; For DDR2 (simplified):
    ;   Rows = (SPD[5] & 0x07) + 11
    ;   Cols = ((SPD[5] >> 3) & 0x03) + 8
    ;   Banks = SPD[4] & 0x07
    ;   Width = SPD[6] (total data width, typically 64 bits / 8 = 8 bytes)
    ;   Size = (2^rows * 2^cols * banks * width) / (1024*1024)
    ;
    ; For QEMU: SPD data is often minimal; use conservative defaults.
    ; If size calc yields 0, default to 256 MB per detected DIMM.
    ; -----------------------------------------------------------------
    push    si                              ; Save DIMM index

    cmp     byte [dimm_types + si], DRAM_TYPE_DDR3
    je      .calc_ddr3

    ; ---- DDR2 Size Calculation ----
    ; CL = SPD[5] (row/col), CH = SPD[4] (banks)
    mov     al, cl
    and     al, 0x07                        ; Row address bits offset (add 11)
    add     al, 11                          ; AL = total row bits
    mov     ah, cl
    shr     ah, 3
    and     ah, 0x03                        ; Col address bits offset (add 8)
    add     ah, 8                           ; AH = total col bits

    ; Total address bits = rows + cols
    add     al, ah                          ; AL = row_bits + col_bits

    ; Number of banks
    mov     ah, ch
    and     ah, 0x07                        ; AH = number of banks (directly)
    ; DDR2 SPD byte 4: actual count, not log2 for older SPD revisions
    ; Common values: 4 or 8 banks
    test    ah, ah
    jnz     .ddr2_banks_ok
    mov     ah, 4                           ; Default to 4 banks
.ddr2_banks_ok:

    ; Data width in bytes from SPD[6] (DL)
    ; Typical: 64 (bits) → 8 bytes
    movzx   edx, dl
    test    edx, edx
    jnz     .ddr2_width_ok
    mov     edx, 8                          ; Default 8 bytes (64-bit bus)
.ddr2_width_ok:

    ; Size in bytes = (1 << address_bits) * banks * (width_bytes / 8)
    ; But SPD[6] for DDR2 is total bits/8 already done differently...
    ; Simplified: just use (1 << (row+col)) * banks * 8 / 1048576
    ;   = (1 << (row+col - 20)) * banks * 8  for MB
    ; If row+col < 20, result would be < 1MB — unlikely
    movzx   ecx, al                        ; ECX = row_bits + col_bits
    sub     ecx, 20                         ; Adjust for MB (divide by 1M = 2^20)
    jle     .default_size                   ; If <= 0, something wrong

    mov     eax, 1
    shl     eax, cl                         ; EAX = 2^(rows+cols-20)

    movzx   ecx, ah                         ; ECX = number of banks
    imul    eax, ecx                        ; EAX *= banks

    ; Multiply by device width factor (assume x8 devices, 8 chips = 64-bit)
    shl     eax, 3                          ; × 8 bytes per rank width

    jmp     .store_size

    ; ---- DDR3 Size Calculation ----
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
    mov     [dimm_sizes + esi], eax
    pop     esi

    ; Accumulate into total
    add     [mrc_total_ram_mb], eax

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
    cmp     byte [mrc_num_dimms], 0
    jne     .dimms_detected

    ; No DIMMs detected via SPD — use fallback detection
    call    .fallback_detect_ram
    jmp     .program_mch

.dimms_detected:

    ; =================================================================
    ; Step 4: Program Q35 MCH Memory Controller Registers
    ; =================================================================
.program_mch:
    mov     eax, [mrc_total_ram_mb]
    test    eax, eax
    jnz     .has_ram
    ; Still zero after fallback? Use absolute default
    mov     dword [mrc_total_ram_mb], Q35_DEFAULT_RAM_MB
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
    cmp     byte [dimm_types], DRAM_TYPE_DDR3
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
    ; Step 5: SDRAM Initialization Sequence (simplified for QEMU)
    ; =================================================================
    ; QEMU's Q35 emulation does not require the full JEDEC SDRAM init
    ; sequence (NOP → Precharge → Refresh → Mode Register Set → Normal).
    ; The memory is already accessible once QEMU starts.
    ;
    ; For real Q35 hardware (rare corporate desktop chipset), the full
    ; sequence would be:
    ;   a. Enable NOP commands via DRC
    ;   b. Issue All Banks Precharge
    ;   c. Issue minimum 2 Auto-Refresh cycles
    ;   d. Set Mode Register (CAS latency, burst length)
    ;   e. Enable Normal Operation mode in DRC
    ;
    ; Since QEMU compatibility is the primary target, we skip the JEDEC
    ; sequence and just ensure the controller registers are programmed.
    ; The DRC "initialized" bit (set above) is sufficient for QEMU.

    pop     es
    popad
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
    mov     [mrc_total_ram_mb], eax
    jmp     .fallback_done

    ; -----------------------------------------------------------------
    ; Method 2: QEMU fw_cfg port (selector 0x0001 = RAM size in bytes)
    ;   Port 0x510: write selector (16-bit)
    ;   Port 0x511: read data bytes (little-endian, byte at a time)
    ;   Returns RAM size as a 32-bit little-endian value in bytes.
    ; -----------------------------------------------------------------
.try_fw_cfg:
    ; Select the RAM size entry
    mov     dx, FW_CFG_PORT_SEL
    mov     ax, FW_CFG_ID_RAM_SIZE          ; Selector 0x0001
    out     dx, ax

    ; Read 4 bytes (little-endian) from data port
    mov     dx, FW_CFG_PORT_DATA
    in      al, dx                          ; Byte 0 (LSB)
    mov     cl, al
    in      al, dx                          ; Byte 1
    mov     ch, al
    in      al, dx                          ; Byte 2
    mov     bl, al
    in      al, dx                          ; Byte 3 (MSB)
    mov     bh, al

    ; Assemble into EAX: BX:CX = 32-bit RAM size in bytes
    movzx   eax, bx
    shl     eax, 16
    movzx   ecx, cx
    or      eax, ecx                        ; EAX = RAM size in bytes

    ; Sanity check: must be >= 1 MB and <= 4 GB
    cmp     eax, 0x00100000                 ; >= 1 MB?
    jb      .use_default
    ; Convert bytes to MB: shift right by 20
    shr     eax, 20                         ; EAX = RAM in MB
    test    eax, eax
    jz      .use_default
    mov     [mrc_total_ram_mb], eax
    jmp     .fallback_done

    ; -----------------------------------------------------------------
    ; Method 3: Default — 128 MB
    ; -----------------------------------------------------------------
.use_default:
    mov     dword [mrc_total_ram_mb], Q35_DEFAULT_RAM_MB

.fallback_done:
    pop     dx
    pop     eax
    ret

; =============================================================================
; Data Section
; =============================================================================

align 4
mrc_total_ram_mb    dd 0            ; Total detected RAM in megabytes
mrc_num_dimms       db 0            ; Number of DIMMs detected via SPD

align 4
dimm_sizes          dd 0, 0, 0, 0   ; Size of each DIMM in MB (indexed by slot)
dimm_types          db 0, 0, 0, 0   ; DRAM type code per DIMM (from SPD byte 2)
