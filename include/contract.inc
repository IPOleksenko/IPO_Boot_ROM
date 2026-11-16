; Shared hardware ports, MSRs, and memory map

%ifndef CONTRACT_INC
%define CONTRACT_INC

; ROM and Shadow RAM layout
BOOTROM_SEG         equ 0xF000
BOOTROM_INIT_OFF    equ 0xE000      ; 8 KiB bootblock at 0xFFFFE000..0xFFFFFFEF

FW_SHADOW_SEG       equ 0xF000
FW_ENTRY_OFF        equ 0x000C
FW_BANK_COPY_WORDS  equ 28672       ; 56 KiB in 16-bit words (0xF000:0000..0xDFFF)
FW_COPY_WORDS       equ 32768       ; 64 KiB in 16-bit words (max shadow window)

; Post-DRAM stack in conventional memory
BOOT_STACK_SEG      equ 0x0000
BOOT_STACK_PTR      equ 0x7C00

; Cache-as-RAM (CAR) window: 32 KiB at physical 0x70000-0x77FFF
CAR_BASE            equ 0x70000
CAR_SIZE            equ 0x8000
CAR_STACK_SEG       equ 0x7000
CAR_STACK_PTR       equ 0x8000
CAR_STACK32_TOP     equ 0x00077E00

; CAR scratch variables (segment 0x7000)
CAR_HOST_VID        equ 0x0000      ; word: host bridge vendor ID
CAR_HOST_DID        equ 0x0002      ; word: host bridge device ID
CAR_HAS_CPUID       equ 0x0004      ; byte: 1 if CPUID is supported
CAR_HAS_MTRR        equ 0x0005      ; byte: 1 if MTRR MSRs are active
CAR_SMBUS_BASE      equ 0x0006      ; word: SMBus I/O base port
CAR_CPU_VENDOR      equ 0x0008      ; byte: CPU vendor tag (0=unknown, 1=type 1, 2=type 2)
CAR_LPC_TYPE        equ 0x0009      ; byte: 0=none/generic, 1=legacy ISA bridge, 2=LPC bridge
CAR_SUPERIO_PORT    equ 0x000A      ; word: 0x2E, 0x4E, or 0
CAR_TOTAL_RAM_MB    equ 0x000C      ; dword: detected RAM in MiB
CAR_TOTAL_RAM_BYTES equ 0x0010      ; dword: detected RAM in bytes
CAR_SUPERIO_ID      equ 0x0014      ; word: Super I/O chip ID

; Shared packed romstage_handoff_t at physical 0x00070040 (segment 0x7000:0x0040)
CAR_HANDOFF_OFF     equ 0x0040
CAR_HANDOFF_PADDR   equ (CAR_BASE + CAR_HANDOFF_OFF)

; Pre-DRAM dynamic heap window inside CAR (0x70200..0x73FFF, below stack)
CAR_HEAP_BASE       equ 0x00070200
CAR_HEAP_SIZE       equ 0x00003E00
HO_MAGIC_VAL        equ 0x524F5049  ; "IPOR"
HO_OFF_MAGIC        equ 0
HO_OFF_HAS_CPUID    equ 4
HO_OFF_HAS_MTRR     equ 5
HO_OFF_CPU_VENDOR   equ 6
HO_OFF_LPC_TYPE     equ 7
HO_OFF_SIO_PORT     equ 8
HO_OFF_SIO_ID       equ 10
HO_OFF_HOST_VID     equ 12
HO_OFF_HOST_DID     equ 14
HO_OFF_RAM_MB       equ 16
HO_OFF_RAM_BYTES    equ 20
HO_OFF_DRAM_OK      equ 24
HO_OFF_SPD_DIMMS    equ 28
HO_OFF_MRC_FLAGS    equ 32

; CPU MTRR MSRs
MSR_MTRR_PHYSBASE0  equ 0x200
MSR_MTRR_PHYSMASK0  equ 0x201
MSR_MTRR_DEF_TYPE   equ 0x2FF

MTRR_TYPE_UC        equ 0x00
MTRR_TYPE_WB        equ 0x06

; PCI configuration mechanism #1 ports
PCI_CONFIG_ADDR     equ 0x0CF8
PCI_CONFIG_DATA     equ 0x0CFC

; Host bridge (PCI 0:0.0) registers
HOST_BRIDGE_PCI_ADDR equ 0x80000000

HOST_PAM0_STD       equ 0x59        ; legacy host bridge PAM0 (0xF0000-0xFFFFF)
HOST_PAM0_EXT       equ 0x90        ; PCIe host bridge PAM0 (0xF0000-0xFFFFF)

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

; Southbridge ISA/LPC PCI addresses
LPC_ICH_PCI_ADDR    equ 0x8000F800  ; Bus 0, Dev 31, Fn 0
LPC_PIIX_PCI_ADDR1  equ 0x80000800  ; Bus 0, Dev 1, Fn 0
LPC_PIIX_PCI_ADDR7  equ 0x80003800  ; Bus 0, Dev 7, Fn 0

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
SCRATCH_HOST_VID    equ 0x0508      ; word: host bridge vendor ID
SCRATCH_HOST_DID    equ 0x050A      ; word: host bridge device ID
SCRATCH_TOTAL_RAM   equ 0x0514      ; dword: total RAM in bytes

; POST diagnostic codes (port 0x80)
POST_PORT           equ 0x80
POST_CAR_START      equ 0x12
POST_CAR_OK         equ 0x13
POST_ROMSTAGE_START equ 0x15
POST_ROMSTAGE_OK    equ 0x16
POST_WARN_SPD_FAIL  equ 0x1F
POST_NOMTRR_BYPASS  equ 0x2E

%endif ; CONTRACT_INC
