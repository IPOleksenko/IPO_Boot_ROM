; contract.inc — Hardware ports, MSRs, and memory layout for IPO_Boot_ROM

%ifndef CONTRACT_INC
%define CONTRACT_INC

; ROM and Shadow RAM layout
BOOTROM_SEG         equ 0xF000
BOOTROM_INIT_OFF    equ 0x8000

FW_SHADOW_SEG       equ 0xF000
FW_ENTRY_OFF        equ 0x000C
FW_COPY_WORDS       equ 32768       ; 64 KB in 16-bit words

; Post-DRAM stack in conventional memory
BOOT_STACK_SEG      equ 0x0000
BOOT_STACK_PTR      equ 0x7C00

; Cache-as-RAM (CAR) window: 32 KB at physical 0x70000-0x77FFF
CAR_BASE            equ 0x70000
CAR_SIZE            equ 0x8000
CAR_STACK_SEG       equ 0x7000
CAR_STACK_PTR       equ 0x8000

; CAR scratch variables (segment 0x7000)
CAR_HOST_VID        equ 0x0000      ; word: Host Bridge Vendor ID
CAR_HOST_DID        equ 0x0002      ; word: Host Bridge Device ID
CAR_SMBUS_BASE      equ 0x0006      ; word: SMBus I/O base port
CAR_TOTAL_RAM_MB    equ 0x000C      ; dword: detected RAM in MB
CAR_TOTAL_RAM_BYTES equ 0x0010      ; dword: detected RAM in bytes

; CPU MTRR MSRs
MSR_MTRR_PHYSBASE0  equ 0x200
MSR_MTRR_PHYSMASK0  equ 0x201
MSR_MTRR_DEF_TYPE   equ 0x2FF

MTRR_TYPE_UC        equ 0x00
MTRR_TYPE_WB        equ 0x06

; PCI Configuration Space ports (Mechanism #1)
PCI_CONFIG_ADDR     equ 0x0CF8
PCI_CONFIG_DATA     equ 0x0CFC

; Host Bridge (PCI 0:0.0) registers
HOST_BRIDGE_PCI_ADDR equ 0x80000000

HOST_PAM0_STD       equ 0x59        ; i440FX/i440BX PAM0 (0xF0000-0xFFFFF)
HOST_PAM0_EXT       equ 0x90        ; Q35/MCH PAM0 (0xF0000-0xFFFFF)

PAM_DISABLED        equ 0x00        ; reads -> ROM, writes -> PCI
PAM_RE              equ 0x10        ; reads -> DRAM, writes -> PCI
PAM_WE              equ 0x20        ; reads -> ROM, writes -> DRAM
PAM_RW              equ 0x30        ; reads/writes -> DRAM

HOST_DRAMC          equ 0x57
HOST_DRB0           equ 0x60
HOST_DRAMT          equ 0x68
HOST_RPS            equ 0x74
HOST_SDRAMC         equ 0x76
HOST_PGPOL          equ 0x78

HOST_DRC            equ 0x7C
HOST_TOM            equ 0xA0
HOST_TOLUD          equ 0xB0

; SMBus controller PCI addresses and registers
SMBUS_PCI_ADDR_PRI  equ 0x8000FB00  ; Bus 0, Dev 31, Fn 3 (ICH)
SMBUS_BAR_PRI       equ 0x20
SMBUS_HOSTC_PRI     equ 0x40

SMBUS_PCI_ADDR_SEC  equ 0x80003B00  ; Bus 0, Dev 7, Fn 3 (PIIX4)
SMBUS_BAR_SEC       equ 0x90
SMBUS_HOSTC_SEC     equ 0xD2

SMBUS_HST_STS       equ 0x00
SMBUS_HST_CNT       equ 0x02
SMBUS_HST_CMD       equ 0x03
SMBUS_XMIT_SLVA     equ 0x04
SMBUS_HST_D0        equ 0x05

SMBUS_STS_BUSY      equ 0x01
SMBUS_STS_INTR      equ 0x02
SMBUS_STS_ERROR     equ 0x04
SMBUS_STS_FAILED    equ 0x10

SMBUS_CNT_START     equ 0x40
SMBUS_CNT_BYTE_DATA equ 0x08

; JEDEC SPD I2C addresses and byte offsets
SPD_ADDR_DIMM0      equ 0x50
SPD_ADDR_DIMM3      equ 0x53

SPD_MEM_TYPE        equ 0x02
SPD_NUM_BANKS       equ 0x05
SPD_BANKS_DENSITY   equ 0x1F

; 8259A PIC ports
PIC1_CMD            equ 0x20
PIC1_DATA           equ 0x21
PIC2_CMD            equ 0xA0
PIC2_DATA           equ 0xA1

; 8254 PIT ports
PIT_CH0             equ 0x40
PIT_CH1             equ 0x41
PIT_CMD             equ 0x43
PIT_DIVIDER         equ 0xFFFF

; Standard I/O ports
COM1_PORT           equ 0x03F8
VGA_TEXT_SEG        equ 0xB800
CMOS_INDEX_PORT     equ 0x0070
CMOS_DATA_PORT      equ 0x0071

; Scratch RAM handoff area (segment 0x0000)
SCRATCH_SEG         equ 0x0000
SCRATCH_HOST_VID    equ 0x0508      ; word: Host Bridge Vendor ID
SCRATCH_HOST_DID    equ 0x050A      ; word: Host Bridge Device ID
SCRATCH_TOTAL_RAM   equ 0x0514      ; dword: total RAM in bytes

; POST diagnostic codes (port 0x80)
POST_PORT           equ 0x80
POST_CAR_START      equ 0x12
POST_CAR_OK         equ 0x13
POST_WARN_SPD_FAIL  equ 0x1F
POST_ERR_NO_CAR     equ 0x2E

%endif ; CONTRACT_INC
