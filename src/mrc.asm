; mrc.asm — Memory Reference Code (SMBus SPD discovery, CMOS fallback, DRAM init)

BITS 16

%include "contract.inc"

MRC_DEFAULT_RAM_MB  equ 64
MAX_TOLUD_MB        equ 3584

CMOS_EXT_MEM_LO     equ 0x17        ; 1MB-16MB in 1KB blocks
CMOS_EXT_MEM_HI     equ 0x18
CMOS_EXT2_MEM_LO    equ 0x34        ; >16MB in 64KB blocks
CMOS_EXT2_MEM_HI    equ 0x35

SDRAMC_NOP          equ 0x20
SDRAMC_PRECHARGE    equ 0x40
SDRAMC_MRS          equ 0x60
SDRAMC_CBR_REFRESH  equ 0x80
SDRAMC_NORMAL       equ 0x00

mrc_init:
    pushad
    push    ds
    push    es

    mov     ax, CAR_STACK_SEG
    mov     es, ax

    call    smbus_init
    call    mrc_detect_ram_size

    mov     [es:CAR_TOTAL_RAM_BYTES], ebx
    mov     [es:CAR_TOTAL_RAM_MB], eax

    mov     si, msg_mem_prefix
    call    serial_print
    mov     eax, [es:CAR_TOTAL_RAM_MB]
    call    serial_print_dec
    mov     si, msg_mem_suffix
    call    serial_print

    cmp     word [es:CAR_HOST_DID], 0x2500
    jae     .program_mch_q35

    ; i440FX/i440BX: configure DRAMT, DRB0..7, RPS, PGPOL, and SDRAM init sequence
    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_DRAMT & 0xFC)
    mov     cl, HOST_DRAMT & 0x03
    mov     dl, 0x10
    call    pci_config_write8

    xor     esi, esi
.program_drb:
    mov     eax, HOST_BRIDGE_PCI_ADDR
    mov     ebx, esi
    add     ebx, HOST_DRB0
    mov     edx, ebx
    and     edx, 0xFC
    add     eax, edx
    push    cx
    mov     dl, cl
    mov     cl, bl
    and     cl, 0x03
    call    pci_config_write8
    pop     cx

    inc     esi
    cmp     esi, 8
    jb      .program_drb

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_RPS & 0xFC)
    mov     cl, HOST_RPS & 0x03
    xor     dl, dl
    call    pci_config_write8

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_PGPOL & 0xFC)
    mov     cl, HOST_PGPOL & 0x03
    xor     dl, dl
    call    pci_config_write8

    ; JEDEC SDRAM initialization sequence: NOP -> Precharge -> 8x CBR -> MRS -> Normal
    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_SDRAMC & 0xFC)
    mov     cl, HOST_SDRAMC & 0x03
    mov     dl, SDRAMC_NOP
    call    pci_config_write8
    xor     ax, ax
    mov     ds, ax
    mov     al, [ds:0x0400]

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_SDRAMC & 0xFC)
    mov     cl, HOST_SDRAMC & 0x03
    mov     dl, SDRAMC_PRECHARGE
    call    pci_config_write8
    mov     al, [ds:0x0400]

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_SDRAMC & 0xFC)
    mov     cl, HOST_SDRAMC & 0x03
    mov     dl, SDRAMC_CBR_REFRESH
    call    pci_config_write8
    mov     cx, 8
.cbr_loop:
    mov     al, [ds:0x0400]
    loop    .cbr_loop

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_SDRAMC & 0xFC)
    mov     cl, HOST_SDRAMC & 0x03
    mov     dl, SDRAMC_MRS
    call    pci_config_write8
    mov     al, [ds:0x01D0]

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_SDRAMC & 0xFC)
    mov     cl, HOST_SDRAMC & 0x03
    mov     dl, SDRAMC_NORMAL
    call    pci_config_write8

    mov     eax, HOST_BRIDGE_PCI_ADDR + (HOST_DRAMC & 0xFC)
    mov     cl, HOST_DRAMC & 0x03
    mov     dl, 0x08
    call    pci_config_write8

    mov     ax, BOOTROM_SEG
    mov     ds, ax
    jmp     .mrc_done

.program_mch_q35:
    mov     ecx, [es:CAR_TOTAL_RAM_MB]
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_TOM
    call    pci_config_write32

    mov     eax, [es:CAR_TOTAL_RAM_MB]
    cmp     eax, MAX_TOLUD_MB
    jbe     .tolud_ok
    mov     eax, MAX_TOLUD_MB
.tolud_ok:
    and     eax, 0xFFFFFFC0
    shl     eax, 4
    movzx   ecx, ax
    push    ecx
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_TOLUD
    call    pci_config_read32
    and     eax, 0xFFFF0000
    pop     ecx
    or      ecx, eax
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_TOLUD
    call    pci_config_write32

    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_DRC
    call    pci_config_read32
    or      eax, 0x01
    mov     ecx, eax
    mov     eax, HOST_BRIDGE_PCI_ADDR | HOST_DRC
    call    pci_config_write32

.mrc_done:
    pop     es
    pop     ds
    popad
    ret

; Detect installed RAM via SMBus SPD (slots 0x50..0x53) or CMOS RTC registers
; Returns: EBX = bytes, ECX = 8MB units (1..255), EAX = MB
mrc_detect_ram_size:
    push    edx
    push    esi
    push    edi

    xor     esi, esi
    mov     bl, SPD_ADDR_DIMM0
.spd_slot_loop:
    mov     bh, SPD_MEM_TYPE
    call    smbus_read_byte
    jc      .spd_next_slot
    test    al, al
    jz      .spd_next_slot
    cmp     al, 0xFF
    je      .spd_next_slot

    mov     bh, SPD_BANKS_DENSITY
    call    smbus_read_byte
    jc      .spd_slot_fallback
    test    al, al
    jz      .spd_slot_fallback
    movzx   edi, al
    shl     edi, 2

    mov     bh, SPD_NUM_BANKS
    call    smbus_read_byte
    jc      .spd_one_rank
    and     al, 0x07
    test    al, al
    jnz     .spd_ranks_ok
.spd_one_rank:
    mov     al, 1
.spd_ranks_ok:
    movzx   eax, al
    imul    edi, eax
    add     esi, edi
    jmp     .spd_next_slot

.spd_slot_fallback:
    add     esi, 64

.spd_next_slot:
    inc     bl
    cmp     bl, SPD_ADDR_DIMM3
    jbe     .spd_slot_loop

    test    esi, esi
    jz      .spd_failed

    mov     ebx, esi
    shl     ebx, 20
    call    mrc_sync_cmos_ram
    jmp     .calc_units

.spd_failed:
    mov     al, POST_WARN_SPD_FAIL
    out     POST_PORT, al

    mov     al, CMOS_EXT2_MEM_LO
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   edx, al

    mov     al, CMOS_EXT2_MEM_HI
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    mov     dh, al

    test    dx, dx
    jz      .try_base_ext

    movzx   ebx, dx
    shl     ebx, 16
    add     ebx, 0x01000000
    jmp     .calc_units

.try_base_ext:
    mov     al, CMOS_EXT_MEM_LO
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    movzx   edx, al

    mov     al, CMOS_EXT_MEM_HI
    out     CMOS_INDEX_PORT, al
    jmp     short $+2
    in      al, CMOS_DATA_PORT
    mov     dh, al

    test    dx, dx
    jz      .use_default

    movzx   ebx, dx
    shl     ebx, 10
    add     ebx, 0x00100000
    jmp     .calc_units

.use_default:
    mov     ebx, MRC_DEFAULT_RAM_MB * 1024 * 1024
    call    mrc_sync_cmos_ram

.calc_units:
    mov     eax, ebx
    shr     eax, 23
    test    eax, eax
    jnz     .units_nonzero
    mov     eax, 1
.units_nonzero:
    cmp     eax, 255
    jbe     .units_ok
    mov     eax, 255
.units_ok:
    mov     ecx, eax

    mov     eax, ebx
    shr     eax, 20

    pop     edi
    pop     esi
    pop     edx
    ret

mrc_sync_cmos_ram:
    push    eax
    push    edx

    mov     al, CMOS_EXT_MEM_LO
    out     CMOS_INDEX_PORT, al
    mov     al, 0x00
    out     CMOS_DATA_PORT, al
    mov     al, CMOS_EXT_MEM_HI
    out     CMOS_INDEX_PORT, al
    mov     al, 0x3C
    out     CMOS_DATA_PORT, al

    mov     edx, ebx
    cmp     edx, 0x01000000
    ja      .above_16m
    xor     edx, edx
    jmp     .write_ext2
.above_16m:
    sub     edx, 0x01000000
    shr     edx, 16
.write_ext2:
    mov     al, CMOS_EXT2_MEM_LO
    out     CMOS_INDEX_PORT, al
    mov     al, dl
    out     CMOS_DATA_PORT, al
    mov     al, CMOS_EXT2_MEM_HI
    out     CMOS_INDEX_PORT, al
    mov     al, dh
    out     CMOS_DATA_PORT, al

    pop     edx
    pop     eax
    ret
