; contract.inc — Contract constants for IPO_Boot_ROM
; Target Architecture: x86 (16-bit Real Mode, 386+ with Pentium MSR support)
; Target Chipsets:     Intel i440FX + PIIX3,  Intel Q35 + ICH9

%ifndef CONTRACT_INC
%define CONTRACT_INC

; =============================================================================
; 1. ROM Layout & Addresses (256 KB ROM)
; =============================================================================

; Boot ROM init code — expanded area for hardware init (CAR, MRC, etc.)
; ROM offset 0x38000 → physical 0xFFFF8000 → real-mode 0xF000:0x8000
BOOTROM_SEG         equ 0xF000      ; Segment of Boot_ROM in ROM / Shadow RAM
BOOTROM_INIT_OFF    equ 0x8000      ; Offset of Boot_ROM init entry point

; Firmware payload location in ROM (256KB ROM layout)
; ROM offset 0x30000 → physical 0xFFFF0000 → real-mode 0xF000:0x0000
FW_ROM_SEG          equ 0xF000
FW_ROM_OFF          equ 0x0000

; Firmware runs from Shadow RAM at 0xF000:0x0000 (same segment as ROM)
FW_SHADOW_SEG       equ 0xF000
FW_ENTRY_OFF        equ 0x0004      ; Entry point offset (after 4-byte magic)
FW_MAX_SIZE_BYTES   equ 32768       ; 32 KB max firmware payload
FW_COPY_WORDS       equ 32768       ; 64 KB in 16-bit words (full segment shadow)

; Legacy aliases (kept for firmware compatibility)
FW_RAM_SEG          equ 0xF000      ; Now points to Shadow RAM, not 0x0800
FW_RAM_OFF          equ 0x0000

; Firmware Magic Header (first 4 bytes of firmware payload)
; "IPOF" in memory: 'I' (0x49), 'P' (0x50), 'O' (0x4F), 'F' (0x46)
; When read as little-endian dword: 0x464F5049
FW_MAGIC            equ 0x464F5049

; =============================================================================
; 2. Stack & Register Conventions
; =============================================================================

; Post-DRAM stack (used after MRC completes and DRAM is available)
BOOT_STACK_SEG      equ 0x0000
BOOT_STACK_PTR      equ 0x7C00      ; SP=0x7C00, stack grows down (0x7000-0x7C00)

; Firmware stack
FW_STACK_SEG        equ 0x0000
FW_STACK_PTR        equ 0x7C00      ; Below MBR load area

; MBR handover (Contract 3)
MBR_SEG             equ 0x0000
MBR_OFF             equ 0x7C00
MBR_MAGIC           equ 0xAA55

; =============================================================================
; 3. Cache-as-RAM (CAR) Configuration
; =============================================================================

; CAR provides a temporary stack in CPU cache before DRAM is initialized.
; Region: 32 KB at physical 0x70000-0x77FFF
CAR_BASE            equ 0x70000     ; Physical base address of CAR region
CAR_SIZE            equ 0x8000      ; 32 KB
CAR_STACK_SEG       equ 0x7000      ; SS segment for CAR stack
CAR_STACK_PTR       equ 0x8000      ; SP offset (top of 32KB, grows down)

; CAR Scratch Data Offsets (Segment CAR_STACK_SEG = 0x7000)
; Safe writable memory in CPU cache prior to DRAM readiness
CAR_CHIPSET         equ 0x0000      ; byte: detected chipset (0=unknown, 1=i440fx, 2=q35)
CAR_SERIAL_INIT     equ 0x0001      ; byte: 1 = serial initialized
CAR_SMBUS_BASE      equ 0x0002      ; word: SMBus I/O base port
CAR_NUM_DIMMS       equ 0x0004      ; byte: number of DIMMs detected
CAR_TOTAL_RAM_MB    equ 0x0008      ; dword: total RAM in megabytes
CAR_TOTAL_RAM_BYTES equ 0x000C      ; dword: total RAM in bytes
CAR_DIMM_SIZES      equ 0x0010      ; 4 x dword = 16 bytes
CAR_DIMM_TYPES      equ 0x0020      ; 4 x byte  = 4 bytes

; MTRR MSR Addresses
MSR_MTRR_PHYSBASE0  equ 0x200       ; Variable MTRR Physical Base 0
MSR_MTRR_PHYSMASK0  equ 0x201       ; Variable MTRR Physical Mask 0
MSR_MTRR_DEF_TYPE   equ 0x2FF       ; MTRR Default Type

; MTRR Memory Types
MTRR_TYPE_UC        equ 0x00        ; Uncacheable
MTRR_TYPE_WB        equ 0x06        ; Write-Back

; =============================================================================
; 4. PCI Configuration Space
; =============================================================================

PCI_CONFIG_ADDR     equ 0x0CF8      ; PCI Configuration Address Port
PCI_CONFIG_DATA     equ 0x0CFC      ; PCI Configuration Data Port

; PCI address format: 1 << 31 | bus << 16 | dev << 11 | fn << 8 | reg & 0xFC
; Helper macro: PCI_ADDR(bus, dev, fn, reg)
%define PCI_ADDR(bus, dev, fn, reg) (0x80000000 | ((bus) << 16) | ((dev) << 11) | ((fn) << 8) | ((reg) & 0xFC))

; =============================================================================
; 5. Chipset: Intel i440FX (82441FX PMC) — Host Bridge PCI 0:0.0
; =============================================================================

I440FX_VID          equ 0x8086      ; Intel Vendor ID
I440FX_DID          equ 0x1237      ; i440FX Device ID
I440FX_PCI_ADDR     equ 0x80000000  ; PCI Bus 0, Dev 0, Fn 0

; PAM Registers (Programmable Attribute Map)
; Control routing of reads/writes for 0xC0000-0xFFFFF to ROM or DRAM
; Bits [1:0] = low region,  Bits [5:4] = high region
;   00 = disabled (reads+writes → PCI/ROM)
;   01 = RE (reads → DRAM, writes → PCI)
;   10 = WE (reads → PCI/ROM, writes → DRAM)
;   11 = RE+WE (reads+writes → DRAM)
I440FX_PAM0         equ 0x59        ; 0xF0000-0xFFFFF (BIOS area)
I440FX_PAM1         equ 0x5A        ; 0xC0000-0xC7FFF
I440FX_PAM2         equ 0x5B        ; 0xC8000-0xCFFFF
I440FX_PAM3         equ 0x5C        ; 0xD0000-0xD7FFF
I440FX_PAM4         equ 0x5D        ; 0xD8000-0xDFFFF
I440FX_PAM5         equ 0x5E        ; 0xE0000-0xE7FFF
I440FX_PAM6         equ 0x5F        ; 0xE8000-0xEFFFF

; PAM0 bit fields for BIOS area (0xF0000-0xFFFFF) — high nibble [5:4]
PAM_DISABLED        equ 0x00        ; reads → ROM, writes → ROM
PAM_RE              equ 0x10        ; reads → DRAM (shadow), writes → ROM
PAM_WE              equ 0x20        ; reads → ROM, writes → DRAM
PAM_RW              equ 0x30        ; reads+writes → DRAM

; DRAM Row Boundary Registers (cumulative size in 8 MB units)
I440FX_DRB0         equ 0x60        ; Row 0 boundary
I440FX_DRB1         equ 0x61        ; Row 1 boundary
I440FX_DRB2         equ 0x62        ; Row 2 boundary
I440FX_DRB3         equ 0x63        ; Row 3 boundary
I440FX_DRB4         equ 0x64        ; Row 4 boundary
I440FX_DRB5         equ 0x65        ; Row 5 boundary
I440FX_DRB6         equ 0x66        ; Row 6 boundary
I440FX_DRB7         equ 0x67        ; Row 7 boundary

; DRAM Timing Register
I440FX_DRAMT        equ 0x68
; Bits [1:0]: MA Wait States (00=0ws, 01=1ws)
; Bits [3:2]: CAS Latency (00=3clk, 01=2clk)
; Bit    [4]: EDO/SDRAM (0=EDO, 1=SDRAM)

; DRAM Control Register
I440FX_DRAMC        equ 0x57
; Bit [0]: Hole at 15-16 MB enable
; Bits [1:0]: DRAM type (depends on revision)

; SDRAM Control Register
I440FX_SDRAMC       equ 0x76

; Row Page Size Register
I440FX_RPS          equ 0x74

; Paging Policy Register
I440FX_PGPOL        equ 0x78

; =============================================================================
; 6. Chipset: Intel Q35 MCH — Host Bridge PCI 0:0.0
; =============================================================================

Q35_VID             equ 0x8086      ; Intel Vendor ID
Q35_DID             equ 0x29C0      ; Q35 MCH Device ID
Q35_PCI_ADDR        equ 0x80000000  ; PCI Bus 0, Dev 0, Fn 0

; Q35 MCH PAM Registers (same offsets as i440FX)
Q35_PAM0            equ 0x90        ; 0xF0000-0xFFFFF (BIOS area)
Q35_PAM1            equ 0x91        ; 0xC0000-0xC3FFF
Q35_PAM2            equ 0x92        ; 0xC4000-0xC7FFF
Q35_PAM3            equ 0x93        ; 0xC8000-0xCBFFF
Q35_PAM4            equ 0x94        ; 0xCC000-0xCFFFF
Q35_PAM5            equ 0x95        ; 0xD0000-0xD3FFF
Q35_PAM6            equ 0x96        ; 0xD4000-0xD7FFF

; Q35 MCH Memory Controller Registers
Q35_GGC             equ 0x52        ; GMCH Graphics Control
Q35_DEVEN           equ 0x54        ; Device Enable
Q35_TOLUD           equ 0xB0        ; Top of Low Usable DRAM
Q35_TOUUD           equ 0xA2        ; Top of Upper Usable DRAM
Q35_TOM             equ 0xA0        ; Top of Memory
Q35_TSEG            equ 0xB8        ; TSEG Memory Base

; Q35 DRAM Timing / Configuration (simplified)
Q35_DRC             equ 0x7C        ; DRAM Controller Mode
Q35_DRT             equ 0x60        ; DRAM Timing
Q35_DRB0            equ 0x60        ; DRAM Rank Boundary 0

; =============================================================================
; 7. Chipset: Intel PIIX3 (82371SB) — PCI 0:1.0 (ISA/LPC Bridge)
; =============================================================================

PIIX3_PCI_ADDR      equ 0x80000800  ; PCI Bus 0, Dev 1, Fn 0
PIIX3_VID           equ 0x8086
PIIX3_DID           equ 0x7000      ; PIIX3 ISA Bridge

; =============================================================================
; 8. Chipset: Intel ICH9 — PCI 0:1F.0 (LPC Bridge)
; =============================================================================

ICH9_LPC_PCI_ADDR   equ 0x8000F800  ; PCI Bus 0, Dev 31, Fn 0
ICH9_VID            equ 0x8086
ICH9_DID            equ 0x2918      ; ICH9 LPC Bridge

; ICH9 SMBus Controller — PCI 0:1F.3
ICH9_SMBUS_PCI_ADDR equ 0x8000FB00  ; PCI Bus 0, Dev 31, Fn 3
ICH9_SMBUS_BAR      equ 0x20        ; Base Address Register (I/O)
ICH9_SMBUS_HOSTC    equ 0x40        ; Host Configuration

; PIIX4 SMBus Controller — PCI 0:7.3 (for i440FX/440BX boards)
PIIX4_SMBUS_PCI_ADDR equ 0x80003B00  ; PCI Bus 0, Dev 7, Fn 3
PIIX4_SMBUS_BAR      equ 0x90        ; Base Address Register in PIIX4
PIIX4_SMBUS_HOSTC    equ 0xD2        ; Host Configuration in PIIX4

; SMBus Register Offsets (from BAR base)
SMBUS_HST_STS       equ 0x00        ; Host Status
SMBUS_HST_CNT       equ 0x02        ; Host Control
SMBUS_HST_CMD       equ 0x03        ; Host Command
SMBUS_XMIT_SLVA     equ 0x04        ; Transmit Slave Address
SMBUS_HST_D0        equ 0x05        ; Host Data 0
SMBUS_HST_D1        equ 0x06        ; Host Data 1

; SMBus Host Status bits
SMBUS_STS_BUSY      equ 0x01        ; Host Busy
SMBUS_STS_INTR      equ 0x02        ; Interrupt
SMBUS_STS_ERROR     equ 0x04        ; Device Error
SMBUS_STS_FAILED    equ 0x10        ; Failed

; SMBus Host Control
SMBUS_CNT_START     equ 0x40        ; Start
SMBUS_CNT_BYTE_DATA equ 0x08        ; Byte Data command (SMBus protocol)

; SPD DIMM Addresses (I2C: 0x50-0x57)
SPD_ADDR_DIMM0      equ 0x50
SPD_ADDR_DIMM1      equ 0x51
SPD_ADDR_DIMM2      equ 0x52
SPD_ADDR_DIMM3      equ 0x53

; =============================================================================
; 9. PIC (8259A Programmable Interrupt Controller)
; =============================================================================

PIC1_CMD            equ 0x20        ; Master PIC Command port
PIC1_DATA           equ 0x21        ; Master PIC Data port
PIC2_CMD            equ 0xA0        ; Slave PIC Command port
PIC2_DATA           equ 0xA1        ; Slave PIC Data port

; ICW/OCW constants
PIC_EOI             equ 0x20        ; End Of Interrupt command

; Standard PC interrupt vector mapping:
; Master: IRQ 0-7  → INT 08h-0Fh
; Slave:  IRQ 8-15 → INT 70h-77h

; =============================================================================
; 10. PIT (8254 Programmable Interval Timer)
; =============================================================================

PIT_CH0             equ 0x40        ; Channel 0 Data port (System timer)
PIT_CH1             equ 0x41        ; Channel 1 Data port (DRAM refresh)
PIT_CH2             equ 0x42        ; Channel 2 Data port (PC Speaker)
PIT_CMD             equ 0x43        ; Mode/Command register

; PIT oscillator frequency: 1,193,182 Hz
; Standard PC BIOS tick rate: ~18.2 Hz (divider = 65535)
PIT_DIVIDER         equ 0xFFFF

; =============================================================================
; 11. Diagnostic / Peripheral Hardware Ports
; =============================================================================

COM1_PORT           equ 0x03F8      ; UART COM1 base I/O port
VGA_TEXT_SEG        equ 0xB800      ; Standard VGA text video memory segment
CRT_ADDR_PORT       equ 0x03D4      ; CRT Controller index register
CRT_DATA_PORT       equ 0x03D5      ; CRT Controller data register

; CMOS / RTC Ports
CMOS_INDEX_PORT     equ 0x0070
CMOS_DATA_PORT      equ 0x0071

; QEMU fw_cfg Ports (used as fallback enhancement, not required)
FW_CFG_PORT_SEL     equ 0x0510
FW_CFG_PORT_DATA    equ 0x0511
FW_CFG_ID_RAM_SIZE  equ 0x0001

; Fast A20 Gate
PORT_A20_FAST       equ 0x92

; =============================================================================
; 12. Chipset Detection Result (stored in CAR/DRAM by chipset_detect)
; =============================================================================

; Values for detected chipset
CHIPSET_UNKNOWN     equ 0x00
CHIPSET_I440FX      equ 0x01
CHIPSET_Q35         equ 0x02

; =============================================================================
; 13. Scratch RAM Offsets (Segment 0x0000, safe conventional memory)
; =============================================================================
SCRATCH_SEG         equ 0x0000
SCRATCH_CHIPSET     equ 0x0508      ; byte: detected chipset
SCRATCH_MEM_FLAG    equ 0x0510      ; byte: 1 = memory already detected
SCRATCH_TOTAL_RAM   equ 0x0514      ; dword: total RAM in bytes
SCRATCH_RAM_1_16M   equ 0x0518      ; word: RAM 1-16MB in KB
SCRATCH_RAM_ABOVE16 equ 0x051A      ; word: RAM above 16MB in 64KB blocks

; Storage Device Registry in Scratch RAM
SCRATCH_AHCI_FOUND  equ 0x0540      ; byte: 1 = AHCI controller detected
SCRATCH_AHCI_BUS    equ 0x0541      ; byte: PCI bus
SCRATCH_AHCI_DEVFN  equ 0x0542      ; byte: PCI dev/fn
SCRATCH_AHCI_PORT_N equ 0x0543      ; byte: active boot port index
SCRATCH_AHCI_BAR5   equ 0x0544      ; dword: AHCI ABAR physical base
SCRATCH_AHCI_PORTS  equ 0x0548      ; dword: Implemented ports mask

SCRATCH_USB_FOUND   equ 0x0550      ; byte: 1 = USB controller detected
SCRATCH_USB_TYPE    equ 0x0551      ; byte: 1 = EHCI, 2 = xHCI
SCRATCH_USB_BUS     equ 0x0552      ; byte: PCI bus
SCRATCH_USB_DEVFN   equ 0x0553      ; byte: PCI dev/fn
SCRATCH_USB_BAR0    equ 0x0554      ; dword: USB MMIO/IO Base

SCRATCH_VGA_FOUND   equ 0x0560      ; byte: 1 = VGA controller detected
SCRATCH_VGA_BUS     equ 0x0561      ; byte: PCI bus
SCRATCH_VGA_DEVFN   equ 0x0562      ; byte: PCI dev/fn
SCRATCH_VGA_ROMBAR  equ 0x0564      ; dword: Expansion ROM BAR

SCRATCH_NVME_FOUND    equ 0x0580    ; byte: 1 = NVMe detected
SCRATCH_NVME_BUS      equ 0x0581    ; byte: PCI bus
SCRATCH_NVME_DEVFN    equ 0x0582    ; byte: PCI dev/fn
SCRATCH_NVME_BAR0     equ 0x0584    ; dword: NVMe BAR0 MMIO address
SCRATCH_NVME_NSID     equ 0x0588    ; dword: active Namespace ID (usually 1)
SCRATCH_NVME_SEC_SIZE equ 0x058C    ; word: sector size in bytes (512)
SCRATCH_NVME_SQ_TAIL  equ 0x058E    ; byte: IO SQ tail index
SCRATCH_NVME_CQ_HEAD  equ 0x058F    ; byte: IO CQ head index
SCRATCH_NVME_CQ_PHASE equ 0x0592    ; byte: IO CQ expected phase bit (1 or 0)
SCRATCH_E820_COUNT    equ 0x0590    ; word: number of valid E820 entries
SCRATCH_E820_TABLE    equ 0x0598    ; buffer: dynamically generated E820 table

; Drive Types for INT 13h dispatch (stored in Scratch RAM)
SCRATCH_DRV_TYPE_80 equ 0x0570      ; byte: 0=None, 1=ATA_PIO, 2=SATA_AHCI, 3=USB_BOT, 4=NVME
SCRATCH_DRV_TYPE_81 equ 0x0571      ; byte
SCRATCH_DRV_TYPE_82 equ 0x0572      ; byte
SCRATCH_DRV_TYPE_83 equ 0x0573      ; byte

DRV_TYPE_NONE       equ 0x00
DRV_TYPE_ATA_PIO    equ 0x01
DRV_TYPE_SATA_AHCI  equ 0x02
DRV_TYPE_USB_BOT    equ 0x03
DRV_TYPE_NVME       equ 0x04

; Dedicated 4KB page-aligned NVMe queues in lower memory (0x3000-0x6FFF)
NVME_ADMIN_SQ_ADDR  equ 0x3000
NVME_ADMIN_CQ_ADDR  equ 0x4000
NVME_IO_SQ_ADDR     equ 0x5000
NVME_IO_CQ_ADDR     equ 0x6000

; =============================================================================
; 14. POST Diagnostic Port 0x80 Codes
; =============================================================================
POST_PORT           equ 0x80

; Standard Boot_ROM milestones
POST_RESET          equ 0x10        ; CPU Reset Vector reached (0xFFFFFFF0)
POST_INIT_ENTRY     equ 0x11        ; Entered Boot_ROM initialization code
POST_CAR_START      equ 0x12        ; Configuring CPU MTRRs for Cache-as-RAM
POST_CAR_OK         equ 0x13        ; CAR stack active at 0x7000:0x8000
POST_CHIPSET_PROBE  equ 0x14        ; Scanning PCI host bridge for chipset ID
POST_CHIPSET_OK     equ 0x15        ; Chipset recognized (i440FX or Q35)
POST_DRAM_START     equ 0x16        ; MRC initializing memory controllers
POST_DRAM_OK        equ 0x17        ; DRAM test passed
POST_CAR_TEARDOWN   equ 0x18        ; Cache flushed, stack moved to DRAM
POST_PIC_PIT_OK     equ 0x19        ; Legacy 8259 PIC and 8254 PIT initialized
POST_SERIAL_OK      equ 0x1A        ; COM1 UART initialized at 115200 baud
POST_SHADOW_START   equ 0x1B        ; Copying ROM to Shadow RAM (0xF0000)
POST_SHADOW_LOCK    equ 0x1C        ; PAM locked read-only
POST_FW_VALIDATE    equ 0x1D        ; Checking Firmware header magic ('IPOF')
POST_FW_JUMP        equ 0x1E        ; Jumping to Firmware entry point
POST_WARN_SPD_FAIL  equ 0x1F        ; Warning: SPD read failed on SMBus, falling back to default

; Standard Firmware milestones
POST_FW_ENTRY       equ 0x20        ; Firmware entry point reached (0xF000:0x0004)
POST_PCI_SCAN       equ 0x21        ; PCI bus enumeration completed
POST_IVT_INIT       equ 0x22        ; Real-mode IVT installed
POST_ACPI_INIT      equ 0x23        ; ACPI tables installed in EBDA
POST_VGA_INIT       equ 0x24        ; Video initialized (VBIOS or native text mode)
POST_A20_INIT       equ 0x25        ; Fast A20 Gate activated
POST_MEM_MAP        equ 0x26        ; E820 / E801 memory map prepared
POST_KBD_INIT       equ 0x27        ; 8042 PS/2 keyboard controller initialized
POST_STORAGE_OK     equ 0x28        ; Storage controllers initialized
POST_DISK_SPINUP_WAIT equ 0x29      ; Waiting for drive spin-up (ATA/AHCI)
POST_CHAINLOAD      equ 0x30        ; Commenced drive scan for bootable media
POST_MBR_FOUND      equ 0x31        ; Valid MBR signature 0xAA55 loaded at 0x7C00
POST_BOOT_JUMP      equ 0xF0        ; Handing off control to OS Bootloader

; Error codes
POST_ERR_NO_CAR     equ 0x2E        ; CPU lacks MTRR support or CAR setup failed
POST_ERR_UNKNOWN_CS equ 0x3E        ; Unrecognized PCI host bridge
POST_ERR_DRAM_FAIL  equ 0x4E        ; DRAM memory test failed
POST_ERR_FW_MAGIC   equ 0x7E        ; Firmware magic mismatch
POST_ERR_NO_BOOT    equ 0xEE        ; No bootable media found

SCRATCH_VBIOS_ACTIVE equ 0x0568     ; byte: 1 = external VBIOS executed

%endif ; CONTRACT_INC
