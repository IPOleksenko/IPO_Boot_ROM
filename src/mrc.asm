; mrc.asm — Generic Memory Reference Code (MRC) for Host Bridges
; Included by init.asm
;
; Discovers installed memory via SMBus SPD or standard CMOS RTC registers,
; and programs host bridge memory decoding registers (Row Boundaries and TOLUD/TOM).
;
; Dependencies (defined in host_bridge.asm, linked before this file):
;   pci_config_read8   — EAX=PCI addr, CL=byte offset -> AL
;   pci_config_write8  — EAX=PCI addr, CL=byte offset, DL=value
;   pci_config_read16  — EAX=PCI addr -> AX
;   pci_config_read32  — EAX=PCI addr -> EAX
;   pci_config_write32 — EAX=PCI addr, ECX=data
;   pci_read_dword, pci_write_dword

BITS 16

%include "contract.inc"

; Default fallback memory size
MRC_DEFAULT_RAM_MB  equ 64          ; 64 MB fallback
MAX_TOLUD_MB        equ 3584        ; 3.5 GB top of low usable DRAM

; CMOS extended memory registers
CMOS_EXT2_MEM_LO    equ 0x34        ; Above 16MB (in 64KB blocks)
CMOS_EXT2_MEM_HI    equ 0x35
CMOS_EXT_MEM_LO     equ 0x17        ; 1MB-16MB (in 1KB blocks)
CMOS_EXT_MEM_HI     equ 0x18

; SDRAM Controller Command Constants
SDRAMC_DISABLED     equ 0x00
SDRAMC_NOP          equ 0x20
SDRAMC_PRECHARGE    equ 0x40
SDRAMC_MRS          equ 0x60
SDRAMC_CBR_REFRESH  equ 0x80
SDRAMC_NORMAL       equ 0x00

; =============================================================================
; mrc_init — Initialize DRAM controllers on host bridge
; =============================================================================
; Inputs:  None
; Outputs: [CAR_TOTAL_RAM_BYTES] and [CAR_TOTAL_RAM_MB] in CAR scratch
; Clobbers: None (all registers preserved)
; =============================================================================
mrc_init:
    pushad
    push    ds
    push    es

    mov     ax, CAR_STACK_SEG
    mov     es, ax

    ; -------------------------------------------------------------------------
    ; Step 1: Detect memory size via CMOS RTC registers
    ; -------------------------------------------------------------------------
    call    mrc_detect_ram_size
    ; Returns: EBX = total RAM in bytes, ECX = total RAM in 8 MB units, EAX = RAM in MB

    ; Store detected memory size in CAR
    mov     [es:CAR_TOTAL_RAM_BYTES], ebx
    mov     [es:CAR_TOTAL_RAM_MB], eax

    ; Print detected memory size: "[IPO_Boot_ROM] Memory: <RAM_MB> MB\n"
    mov     si, msg_mem_prefix
    call    serial_print_early

    mov     eax, [es:CAR_TOTAL_RAM_MB]
    call    serial_print_dec_early

    mov     si, msg_mem_suffix
    call    serial_print_early

    ; -------------------------------------------------------------------------
    ; Step 2: Program Row Boundary (DRB) registers (0x60-0x67) & SDRAM controls
    ; -------------------------------------------------------------------------
    ; Set DRAM Timing (reg 0x68): SDRAM mode, CAS 3, 0ws
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     cl, HOST_DRAMT & 0x03
    add     eax, HOST_DRAMT & 0xFC
    mov     dl, 0x10                        ; SDRAM mode
    call    pci_config_write8

    ; Program DRB Registers (0x60-0x67) with cumulative 8MB units
    mov     esi, 0                          ; Row counter (0..7)
.program_drb:
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     ebx, esi
    add     ebx, HOST_DRB0                  ; EBX = 0x60 + row
    mov     edx, ebx
    and     edx, 0xFC                       ; Dword-align
    add     eax, edx
    push    cx                              ; Preserve total 8MB units
    mov     dl, cl                          ; DL = total 8MB units
    mov     cl, bl
    and     cl, 0x03                        ; CL = byte offset within dword (0-3)
    call    pci_config_write8
    pop     cx                              ; Restore total 8MB units

    inc     esi
    cmp     esi, 8
    jb      .program_drb

    ; Configure Row Page Size (reg 0x74)
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     cl, HOST_RPS & 0x03
    add     eax, HOST_RPS & 0xFC
    mov     dl, 0x00
    call    pci_config_write8

    ; Configure Paging Policy (reg 0x78)
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     cl, HOST_PGPOL & 0x03
    add     eax, HOST_PGPOL & 0xFC
    mov     dl, 0x00
    call    pci_config_write8

    ; Issue SDRAM normal operation commands (SDRAMC reg 0x76)
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     cl, HOST_SDRAMC & 0x03
    add     eax, HOST_SDRAMC & 0xFC
    mov     dl, SDRAMC_NORMAL
    call    pci_config_write8

    ; -------------------------------------------------------------------------
    ; Step 3: Program TOLUD & TOM registers for host bridges using boundary BARs
    ; -------------------------------------------------------------------------
    mov     eax, [es:CAR_TOTAL_RAM_MB]

    ; Program TOM (Top of Memory, reg 0xA0)
    mov     ecx, eax
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_TOM
    call    pci_write_dword

    ; Program TOLUD (Top of Low Usable DRAM, reg 0xB0)
    mov     eax, [es:CAR_TOTAL_RAM_MB]
    cmp     eax, MAX_TOLUD_MB
    jbe     .tolud_ok
    mov     eax, MAX_TOLUD_MB               ; Cap at 3.5 GB
.tolud_ok:
    and     eax, 0xFFFFFFC0                 ; 64 MB alignment
    shl     eax, 4                          ; tolud_mb << 4
    movzx   ecx, ax
    push    ecx
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_TOLUD
    call    pci_read_dword
    and     eax, 0xFFFF0000
    pop     ecx
    or      eax, ecx
    mov     ecx, eax
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_TOLUD
    call    pci_write_dword

    ; Enable DRAM Controller (DRC reg 0x7C)
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_DRC
    call    pci_read_dword
    or      eax, 0x01                       ; Bit 0: DRAM initialized
    mov     ecx, eax
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_DRC
    call    pci_write_dword

    pop     es
    pop     ds
    popad
    ret

; =============================================================================
; mrc_detect_ram_size — Detect installed RAM via standard CMOS RTC registers
; =============================================================================
; Outputs:
;   EBX = total RAM in bytes
;   ECX = total RAM in 8 MB units (capped at 255)
;   EAX = total RAM in megabytes
; =============================================================================
mrc_detect_ram_size:
    push    edx

    ; Read memory above 16 MB (CMOS 0x34/0x35) in 64 KB units
    mov     al, CMOS_EXT2_MEM_LO            ; 0x34
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   edx, al                         ; DL = low byte

    mov     al, CMOS_EXT2_MEM_HI            ; 0x35
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    mov     dh, al                          ; DX = 64KB blocks above 16 MB

    test    dx, dx
    jz      .try_base_ext

    ; Memory above 16MB present: total = 16MB + (DX * 64KB)
    movzx   ebx, dx
    shl     ebx, 16                         ; EBX = bytes above 16 MB
    add     ebx, 0x01000000                 ; Add 16 MB base
    jmp     .calc_units

.try_base_ext:
    ; Read memory 1-16 MB (CMOS 0x17/0x18) in 1 KB units
    mov     al, CMOS_EXT_MEM_LO             ; 0x17
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   edx, al

    mov     al, CMOS_EXT_MEM_HI             ; 0x18
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    mov     dh, al                          ; DX = KB between 1MB and 16MB

    test    dx, dx
    jz      .use_default

    movzx   ebx, dx
    shl     ebx, 10                         ; Convert KB to bytes
    add     ebx, 0x00100000                 ; Add 1 MB base
    jmp     .calc_units

.use_default:
    ; Fallback default: 64 MB
    mov     ebx, MRC_DEFAULT_RAM_MB * 1024 * 1024

.calc_units:
    ; Convert EBX (bytes) to ECX (8 MB units)
    mov     eax, ebx
    shr     eax, 23                         ; Divide by 8MB (8388608 bytes)
    test    eax, eax
    jnz     .units_nonzero
    mov     eax, 1
.units_nonzero:
    cmp     eax, 255
    jbe     .units_ok
    mov     eax, 255                        ; Cap at 255 (2040 MB)
.units_ok:
    mov     ecx, eax                        ; ECX = total 8MB units

    ; Convert EBX (bytes) to EAX (megabytes)
    mov     eax, ebx
    shr     eax, 20                         ; Divide by 1MB (1048576 bytes)

    pop     edx
    ret
