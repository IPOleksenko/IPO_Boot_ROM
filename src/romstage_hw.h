#ifndef ROMSTAGE_HW_H
#define ROMSTAGE_HW_H

#include <stdint.h>
#include <stddef.h>

#define HO_MAGIC_VAL        0x524F5049u /* "IPOR" */
#define CAR_HEAP_BASE       0x00070200u
#define CAR_HEAP_SIZE       0x00003E00u
#define MAX_TOLUD_MB        3584u
#define MRC_DEFAULT_RAM_MB  64u

#define COM1_PORT           0x03F8u
#define CMOS_INDEX_PORT     0x0070u
#define CMOS_DATA_PORT      0x0071u
#define PCI_CONFIG_ADDR     0x0CF8u
#define PCI_CONFIG_DATA     0x0CFCu
#define POST_PORT           0x0080u

#define MRC_FLAG_SPD        (1u << 0)
#define MRC_FLAG_CMOS       (1u << 1)
#define MRC_FLAG_HW_PROBE   (1u << 2)
#define MRC_FLAG_CHIPSET    (1u << 3)

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint8_t  has_cpuid;
    uint8_t  has_mtrr;
    uint8_t  cpu_vendor_type;
    uint8_t  lpc_bridge_type;
    uint16_t superio_port;
    uint16_t superio_chip_id;
    uint16_t host_vid;
    uint16_t host_did;
    uint32_t total_ram_mb;
    uint32_t total_ram_bytes;
    uint32_t dram_verified;
    uint32_t spd_dimm_count;
    uint32_t mrc_mode_flags;
} romstage_handoff_t;

static inline uint8_t inb(uint16_t port) {
    uint8_t val;
    __asm__ volatile("inb %1, %0" : "=a"(val) : "Nd"(port));
    return val;
}

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint32_t inl(uint16_t port) {
    uint32_t val;
    __asm__ volatile("inl %1, %0" : "=a"(val) : "Nd"(port));
    return val;
}

static inline void outl(uint16_t port, uint32_t val) {
    __asm__ volatile("outl %0, %1" : : "a"(val), "Nd"(port));
}

static inline void io_delay(void) {
    __asm__ volatile("outb %%al, $0x80" : : "a"((uint8_t)0x15));
}

static inline void cpuid_leaf(uint32_t leaf, uint32_t *eax, uint32_t *ebx,
                              uint32_t *ecx, uint32_t *edx) {
    uint32_t a = leaf, b = 0, c = 0, d = 0;
    __asm__ volatile("cpuid" : "+a"(a), "=b"(b), "+c"(c), "=d"(d) : : "memory");
    if (eax) *eax = a;
    if (ebx) *ebx = b;
    if (ecx) *ecx = c;
    if (edx) *edx = d;
}

static inline uint32_t pci_addr(uint8_t bus, uint8_t dev, uint8_t fn, uint8_t reg) {
    return 0x80000000u |
           ((uint32_t)bus << 16) |
           ((uint32_t)(dev & 0x1Fu) << 11) |
           ((uint32_t)(fn & 0x07u) << 8) |
           ((uint32_t)(reg & 0xFCu));
}

static inline uint32_t pci_read32(uint8_t bus, uint8_t dev, uint8_t fn, uint8_t reg) {
    outl(PCI_CONFIG_ADDR, pci_addr(bus, dev, fn, reg));
    return inl(PCI_CONFIG_DATA);
}

static inline void pci_write32(uint8_t bus, uint8_t dev, uint8_t fn, uint8_t reg, uint32_t val) {
    outl(PCI_CONFIG_ADDR, pci_addr(bus, dev, fn, reg));
    outl(PCI_CONFIG_DATA, val);
}

static inline uint8_t pci_read8(uint8_t bus, uint8_t dev, uint8_t fn, uint8_t reg) {
    uint32_t d = pci_read32(bus, dev, fn, reg);
    return (uint8_t)((d >> ((reg & 3u) * 8u)) & 0xFFu);
}

static inline void pci_write8(uint8_t bus, uint8_t dev, uint8_t fn, uint8_t reg, uint8_t val) {
    outl(PCI_CONFIG_ADDR, pci_addr(bus, dev, fn, reg));
    outb((uint16_t)(PCI_CONFIG_DATA + (reg & 3u)), val);
}

static inline uint16_t pci_read16(uint8_t bus, uint8_t dev, uint8_t fn, uint8_t reg) {
    uint32_t d = pci_read32(bus, dev, fn, reg);
    return (uint16_t)((d >> ((reg & 2u) * 8u)) & 0xFFFFu);
}

static inline uint8_t cmos_read(uint8_t reg) {
    outb(CMOS_INDEX_PORT, reg);
    io_delay();
    return inb(CMOS_DATA_PORT);
}

static inline void cmos_write(uint8_t reg, uint8_t val) {
    outb(CMOS_INDEX_PORT, reg);
    io_delay();
    outb(CMOS_DATA_PORT, val);
}

void rs_serial_init(void);
void rs_putc(char c);
void rs_puts(const char *s);
void rs_hex16(uint16_t v);
void rs_hex32(uint32_t v);
void rs_dec(uint32_t v);

void  rs_heap_init(void);
void *rs_malloc(size_t size);
void *rs_realloc(void *ptr, size_t new_size);
void  rs_free(void *ptr);

void mrc_run(romstage_handoff_t *ho);

#endif
