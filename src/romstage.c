#include "romstage_hw.h"

#define RS_HEAP_MAGIC 0x52534850u /* "RSHP" */
#define RS_BLK_MAGIC  0x5253424Bu /* "RSBK" */
#define RS_BLK_FREE   1u

typedef struct {
    uint32_t magic;
    uint32_t total_bytes;
} rs_heap_hdr_t;

typedef struct {
    uint32_t magic;
    uint32_t size;
    uint32_t flags;
    uint32_t reserved;
} rs_blk_hdr_t;

static inline rs_blk_hdr_t *rs_heap_first(void) {
    return (rs_blk_hdr_t *)(uintptr_t)(CAR_HEAP_BASE + 16u);
}

static inline uintptr_t rs_heap_end(void) {
    return (uintptr_t)(CAR_HEAP_BASE + CAR_HEAP_SIZE);
}

void rs_heap_init(void) {
    rs_heap_hdr_t *hh = (rs_heap_hdr_t *)(uintptr_t)CAR_HEAP_BASE;
    hh->magic = RS_HEAP_MAGIC;
    hh->total_bytes = CAR_HEAP_SIZE;

    rs_blk_hdr_t *first = rs_heap_first();
    first->magic = RS_BLK_MAGIC;
    first->size = CAR_HEAP_SIZE - 16u - (uint32_t)sizeof(rs_blk_hdr_t);
    first->flags = RS_BLK_FREE;
    first->reserved = 0u;
}

static void rs_heap_coalesce(void) {
    rs_blk_hdr_t *blk = rs_heap_first();
    uintptr_t end = rs_heap_end();
    while ((uintptr_t)blk + sizeof(rs_blk_hdr_t) <= end && blk->magic == RS_BLK_MAGIC) {
        uintptr_t next_addr = (uintptr_t)blk + sizeof(rs_blk_hdr_t) + blk->size;
        if (next_addr + sizeof(rs_blk_hdr_t) > end) break;
        rs_blk_hdr_t *next = (rs_blk_hdr_t *)next_addr;
        if (next->magic != RS_BLK_MAGIC) break;
        if ((blk->flags & RS_BLK_FREE) && (next->flags & RS_BLK_FREE)) {
            blk->size += (uint32_t)sizeof(rs_blk_hdr_t) + next->size;
            continue;
        }
        blk = next;
    }
}

void *rs_malloc(size_t size) {
    rs_heap_hdr_t *hh = (rs_heap_hdr_t *)(uintptr_t)CAR_HEAP_BASE;
    if (hh->magic != RS_HEAP_MAGIC) {
        rs_heap_init();
    }
    if (size == 0u) size = 1u;
    uint32_t aligned = ((uint32_t)size + 15u) & ~15u;

    rs_blk_hdr_t *blk = rs_heap_first();
    uintptr_t end = rs_heap_end();
    while ((uintptr_t)blk + sizeof(rs_blk_hdr_t) <= end && blk->magic == RS_BLK_MAGIC) {
        if ((blk->flags & RS_BLK_FREE) && blk->size >= aligned) {
            if (blk->size >= aligned + (uint32_t)sizeof(rs_blk_hdr_t) + 16u) {
                rs_blk_hdr_t *rem = (rs_blk_hdr_t *)((uintptr_t)blk + sizeof(rs_blk_hdr_t) + aligned);
                rem->magic = RS_BLK_MAGIC;
                rem->size = blk->size - aligned - (uint32_t)sizeof(rs_blk_hdr_t);
                rem->flags = RS_BLK_FREE;
                rem->reserved = 0u;
                blk->size = aligned;
            }
            blk->flags &= ~RS_BLK_FREE;
            return (void *)((uintptr_t)blk + sizeof(rs_blk_hdr_t));
        }
        uintptr_t next_addr = (uintptr_t)blk + sizeof(rs_blk_hdr_t) + blk->size;
        if (next_addr >= end) break;
        blk = (rs_blk_hdr_t *)next_addr;
    }
    return NULL;
}

void rs_free(void *ptr) {
    if (!ptr) return;
    uintptr_t addr = (uintptr_t)ptr;
    if (addr < (uintptr_t)rs_heap_first() + sizeof(rs_blk_hdr_t) || addr >= rs_heap_end()) {
        return;
    }
    rs_blk_hdr_t *blk = (rs_blk_hdr_t *)(addr - sizeof(rs_blk_hdr_t));
    if (blk->magic != RS_BLK_MAGIC) return;
    blk->flags |= RS_BLK_FREE;
    rs_heap_coalesce();
}

void *rs_realloc(void *ptr, size_t new_size) {
    if (!ptr) return rs_malloc(new_size);
    if (new_size == 0u) {
        rs_free(ptr);
        return NULL;
    }
    uintptr_t addr = (uintptr_t)ptr;
    if (addr < (uintptr_t)rs_heap_first() + sizeof(rs_blk_hdr_t) || addr >= rs_heap_end()) {
        return NULL;
    }
    rs_blk_hdr_t *blk = (rs_blk_hdr_t *)(addr - sizeof(rs_blk_hdr_t));
    if (blk->magic != RS_BLK_MAGIC) return NULL;

    uint32_t aligned = ((uint32_t)new_size + 15u) & ~15u;
    if (blk->size >= aligned) {
        return ptr;
    }

    void *nb = rs_malloc(new_size);
    if (!nb) return NULL;
    uint32_t copy_len = blk->size < (uint32_t)new_size ? blk->size : (uint32_t)new_size;
    uint8_t *dst = (uint8_t *)nb;
    const uint8_t *src = (const uint8_t *)ptr;
    for (uint32_t i = 0u; i < copy_len; i++) {
        dst[i] = src[i];
    }
    rs_free(ptr);
    return nb;
}

void rs_serial_init(void) {
    /* Probe COM1 scratchpad register */
    outb(COM1_PORT + 7u, 0xA5u);
    if (inb(COM1_PORT + 7u) != 0xA5u) {
        return;
    }
    outb(COM1_PORT + 1u, 0x00u);
    outb(COM1_PORT + 3u, 0x80u); /* DLAB on */
    outb(COM1_PORT + 0u, 0x01u); /* 115200 baud */
    outb(COM1_PORT + 1u, 0x00u);
    outb(COM1_PORT + 3u, 0x03u); /* 8N1 */
    outb(COM1_PORT + 2u, 0xC7u); /* FIFO */
    outb(COM1_PORT + 4u, 0x0Bu); /* DTR/RTS/OUT2 */
}

void rs_putc(char c) {
    if (c == '\n') {
        rs_putc('\r');
    }
    for (uint32_t i = 0; i < 65535u; i++) {
        if ((inb(COM1_PORT + 5u) & 0x20u) != 0u) {
            outb(COM1_PORT, (uint8_t)c);
            return;
        }
    }
}

void rs_puts(const char *s) {
    if (!s) return;
    while (*s) {
        rs_putc(*s++);
    }
}

void rs_hex16(uint16_t v) {
    for (int shift = 12; shift >= 0; shift -= 4) {
        uint8_t n = (uint8_t)((v >> shift) & 0x0Fu);
        rs_putc((char)(n < 10 ? ('0' + n) : ('A' + n - 10)));
    }
}

void rs_hex32(uint32_t v) {
    rs_hex16((uint16_t)(v >> 16));
    rs_hex16((uint16_t)(v & 0xFFFFu));
}

void rs_dec(uint32_t v) {
    if (v == 0u) {
        rs_putc('0');
        return;
    }
    char *buf = (char *)rs_malloc(16u);
    if (!buf) {
        uint32_t div = 1000000000u;
        uint8_t started = 0u;
        while (div > 0u) {
            uint32_t d = v / div;
            v %= div;
            if (d > 0u || started || div == 1u) {
                rs_putc((char)('0' + d));
                started = 1u;
            }
            div /= 10u;
        }
        return;
    }
    int idx = 0;
    while (v > 0u && idx < 15) {
        buf[idx++] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    while (idx > 0) {
        rs_putc(buf[--idx]);
    }
    rs_free(buf);
}

static void print_cpu_identity(const romstage_handoff_t *ho) {
    rs_puts("[IPO_Boot_ROM] CPU: ");
    if (!ho->has_cpuid) {
        rs_puts("x86 (pre-CPUID 386/486)");
    } else {
        uint32_t max_ext = 0, ebx = 0, ecx = 0, edx = 0;
        cpuid_leaf(0x80000000u, &max_ext, &ebx, &ecx, &edx);
        if (max_ext >= 0x80000004u) {
            uint32_t *regs = (uint32_t *)rs_malloc(12u * sizeof(uint32_t));
            if (regs) {
                cpuid_leaf(0x80000002u, &regs[0], &regs[1], &regs[2], &regs[3]);
                cpuid_leaf(0x80000003u, &regs[4], &regs[5], &regs[6], &regs[7]);
                cpuid_leaf(0x80000004u, &regs[8], &regs[9], &regs[10], &regs[11]);
                const char *p = (const char *)regs;
                uint8_t started = 0u;
                for (int i = 0; i < 48; i++) {
                    char c = p[i];
                    if (c == '\0') break;
                    if (c == ' ' && !started) continue;
                    started = 1u;
                    rs_putc(c);
                }
                if (!started) rs_puts("x86");
                rs_free(regs);
            } else {
                rs_puts("x86");
            }
        } else {
            uint32_t *vbuf = (uint32_t *)rs_malloc(4u * sizeof(uint32_t));
            if (vbuf) {
                uint32_t r0 = 0;
                cpuid_leaf(0u, &r0, &vbuf[0], &vbuf[2], &vbuf[1]);
                vbuf[3] = 0u;
                rs_puts((const char *)vbuf);
                rs_free(vbuf);
            } else {
                rs_puts("x86");
            }
        }
    }

    rs_puts(" | CAR=");
    if (ho->has_mtrr) {
        rs_puts(ho->cpu_vendor_type == 2u ? "AMD-MTRR" : "Intel-MTRR");
    } else {
        rs_puts("Bypassed(pre-MTRR)");
    }
    rs_putc('\n');
}

static void print_lpc_superio(const romstage_handoff_t *ho) {
    rs_puts("[IPO_Boot_ROM] Platform: LPC=");
    if (ho->lpc_bridge_type == 2u) rs_puts("ICH/PCH");
    else if (ho->lpc_bridge_type == 1u) rs_puts("PIIX");
    else rs_puts("Generic");

    rs_puts(", SuperIO=");
    if (ho->superio_port != 0u && ho->superio_chip_id != 0xFFFFu) {
        rs_puts("0x");
        rs_hex16(ho->superio_port);
        rs_puts("(ID=0x");
        rs_hex16(ho->superio_chip_id);
        rs_puts(")");
    } else {
        rs_puts("none");
    }
    rs_putc('\n');
}

void romstage_main(romstage_handoff_t *ho) {
    outb(POST_PORT, 0x15u); /* POST_ROMSTAGE_START */
    rs_serial_init();

    if (!ho || ho->magic != HO_MAGIC_VAL) {
        rs_puts("[IPO_Boot_ROM] ERROR: Invalid romstage handoff!\n");
        return;
    }

    rs_heap_init();
    rs_puts("[IPO_Boot_ROM] 32-bit romstage XIP active\n");
    print_lpc_superio(ho);
    print_cpu_identity(ho);
    mrc_run(ho);

    outb(POST_PORT, 0x16u); /* POST_ROMSTAGE_OK */
}
