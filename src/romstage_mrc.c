#include "romstage_hw.h"

/* SMBus host controller I/O register offsets */
#define SMBUS_HST_STS       0x00u
#define SMBUS_HST_CNT       0x02u
#define SMBUS_HST_CMD       0x03u
#define SMBUS_XMIT_SLVA     0x04u
#define SMBUS_HST_D0        0x05u

#define SMBUS_STS_BUSY      0x01u
#define SMBUS_STS_INTR      0x02u
#define SMBUS_STS_ERR_MASK  0x1Cu

#define SMBUS_DEFAULT_IO    0x0500u

/* Legacy host bridge SDRAM/DRAM timing registers */
#define I440_DRAMC          0x57u
#define I440_DRB0           0x60u
#define I440_DRAMT          0x68u
#define I440_RPS            0x74u
#define I440_SDRAMC         0x76u
#define I440_PGPOL          0x78u

#define SDRAMC_NORMAL       0x00u
#define SDRAMC_NOP          0x20u
#define SDRAMC_PRECHARGE    0x40u
#define SDRAMC_MRS          0x60u
#define SDRAMC_CBR_REFRESH  0x80u

/* PCIe host bridge memory controller registers */
#define Q35_MCHBAR_LO       0x48u
#define Q35_DRC             0x7Cu
#define Q35_TOM             0xA0u
#define Q35_TOLUD           0xB0u

typedef struct {
    uint32_t *slot_mb;
    uint32_t  slot_cap;
    uint32_t  slot_count;
    uint32_t  total_mb;
    uint32_t  dimm_count;
    uint8_t   mem_type;
    uint8_t   cl_max;
    uint8_t   trcd_ns;
    uint8_t   trp_ns;
    uint8_t   tras_ns;
} spd_summary_t;

static void spd_set_slot_mb(spd_summary_t *spd, uint32_t slot, uint32_t mb) {
    if (!spd) return;
    if (slot >= spd->slot_cap) {
        uint32_t new_cap = (spd->slot_cap > 0u) ? spd->slot_cap : 8u;
        while (new_cap <= slot) new_cap *= 2u;
        uint32_t *nb = (uint32_t *)rs_realloc(spd->slot_mb, (size_t)new_cap * sizeof(uint32_t));
        if (!nb) return;
        for (uint32_t i = spd->slot_cap; i < new_cap; i++) {
            nb[i] = 0u;
        }
        spd->slot_mb = nb;
        spd->slot_cap = new_cap;
    }
    spd->slot_mb[slot] = mb;
    if (slot + 1u > spd->slot_count) {
        spd->slot_count = slot + 1u;
    }
}

static uint16_t smbus_probe_controller(void) {
    /* Scan Bus 0 for a PCI SMBus controller (class 0x0C, subclass 0x05) */
    for (uint8_t dev = 0; dev < 32; dev++) {
        uint8_t max_fn = 1;
        uint32_t id0 = pci_read32(0, dev, 0, 0x00);
        if ((id0 & 0xFFFFu) == 0xFFFFu || id0 == 0u) {
            continue;
        }
        uint8_t hdr = pci_read8(0, dev, 0, 0x0E);
        if (hdr & 0x80u) {
            max_fn = 8;
        }
        for (uint8_t fn = 0; fn < max_fn; fn++) {
            uint32_t id = pci_read32(0, dev, fn, 0x00);
            uint16_t vid = (uint16_t)(id & 0xFFFFu);
            if (vid == 0xFFFFu || id == 0u) {
                continue;
            }
            uint32_t cls = pci_read32(0, dev, fn, 0x08);
            uint8_t base_cls = (uint8_t)(cls >> 24);
            uint8_t sub_cls = (uint8_t)((cls >> 16) & 0xFFu);
            if (base_cls != 0x0Cu || sub_cls != 0x05u) {
                continue;
            }

            /* Legacy 0x7113/dev7 southbridges put SMBus base at 0x90 (HOSTC 0xD2);
             * newer controllers use BAR4 (0x20), with HOSTC at 0x40 on 0x8086 parts. */
            uint8_t bar_reg = (vid == 0x8086u && ((uint16_t)(id >> 16) == 0x7113u || dev == 7)) ? 0x90u : 0x20u;
            uint32_t bar = pci_read32(0, dev, fn, bar_reg);
            uint16_t io_base = (uint16_t)(bar & 0xFFE0u);
            if (io_base == 0u || io_base >= 0xFFE0u) {
                /* Fall back to BAR0 (0x10) on third-party SMBus controllers */
                uint32_t bar0 = pci_read32(0, dev, fn, 0x10);
                if ((bar0 & 1u) != 0u && (bar0 & 0xFFE0u) != 0u) {
                    io_base = (uint16_t)(bar0 & 0xFFE0u);
                } else {
                    io_base = SMBUS_DEFAULT_IO;
                    pci_write32(0, dev, fn, bar_reg, (uint32_t)io_base | 0x01u);
                }
            }

            if (vid == 0x8086u) {
                uint8_t hostc_reg = (bar_reg == 0x90u) ? 0xD2u : 0x40u;
                pci_write8(0, dev, fn, hostc_reg, 0x01u);
            }
            uint32_t cmd = pci_read32(0, dev, fn, 0x04);
            pci_write32(0, dev, fn, 0x04, cmd | 0x01u);
            return io_base;
        }
    }
    return 0u;
}

static uint8_t smbus_read_byte(uint16_t io_base, uint8_t spd_addr, uint8_t reg, uint8_t *out_val) {
    if (io_base == 0u) return 0u;

    uint32_t timeout = 2000u;
    while ((inb(io_base + SMBUS_HST_STS) & SMBUS_STS_BUSY) != 0u && timeout > 0u) {
        io_delay();
        timeout--;
    }
    if (timeout == 0u) return 0u;

    outb(io_base + SMBUS_HST_STS, 0xFEu);
    outb(io_base + SMBUS_XMIT_SLVA, (uint8_t)((spd_addr << 1) | 0x01u));
    outb(io_base + SMBUS_HST_CMD, reg);
    outb(io_base + SMBUS_HST_CNT, 0x48u);

    timeout = 5000u;
    while (timeout > 0u) {
        uint8_t st = inb(io_base + SMBUS_HST_STS);
        if ((st & SMBUS_STS_ERR_MASK) != 0u) {
            outb(io_base + SMBUS_HST_STS, st);
            return 0u;
        }
        if ((st & SMBUS_STS_INTR) != 0u) {
            *out_val = inb(io_base + SMBUS_HST_D0);
            outb(io_base + SMBUS_HST_STS, st);
            return 1u;
        }
        io_delay();
        timeout--;
    }
    return 0u;
}

static uint32_t decode_ddr2_rank_mb(uint8_t spd31) {
    if (spd31 == 0x20u) return 128u;
    if (spd31 == 0x40u) return 256u;
    if (spd31 == 0x80u) return 512u;
    if (spd31 == 0x01u) return 1024u;
    if (spd31 == 0x02u) return 2048u;
    if (spd31 == 0x04u) return 4096u;
    if (spd31 == 0x08u) return 8192u;
    if (spd31 == 0x10u) return 16384u;
    return 0u;
}

static uint8_t highest_bit_index(uint8_t mask) {
    uint8_t bit = 0;
    for (uint8_t i = 0; i < 8; i++) {
        if (mask & (uint8_t)(1u << i)) bit = i;
    }
    return bit;
}

static void spd_scan_dimms(uint16_t smbus_io, spd_summary_t *spd) {
    spd->slot_mb = NULL;
    spd->slot_cap = 0u;
    spd->slot_count = 0u;
    spd->total_mb = 0u;
    spd->dimm_count = 0u;
    spd->mem_type = 0u;
    spd->cl_max = 3u;
    spd->trcd_ns = 20u;
    spd->trp_ns = 20u;
    spd->tras_ns = 45u;

    if (smbus_io == 0u) return;

    for (uint8_t slot = 0; slot < 8u; slot++) {
        uint8_t addr = (uint8_t)(0x50u + slot);
        uint8_t mtype = 0u;
        if (!smbus_read_byte(smbus_io, addr, 2u, &mtype)) {
            continue;
        }
        if (mtype == 0u || mtype == 0xFFu) {
            continue;
        }

        uint32_t dimm_mb = 0u;
        uint8_t cl = 3u, trcd = 20u, trp = 20u, tras = 45u;

        if (mtype == 0x04u || mtype == 0x07u) {
            /* SDRAM (0x04) / DDR1 (0x07) */
            uint8_t ranks = 1u, b31 = 0u, b18 = 0u, b27 = 0u, b29 = 0u, b30 = 0u;
            if (smbus_read_byte(smbus_io, addr, 5u, &ranks)) {
                ranks = (uint8_t)(ranks & 0x07u);
                if (ranks == 0u || ranks > 4u) ranks = 1u;
            }
            if (smbus_read_byte(smbus_io, addr, 31u, &b31) && b31 != 0u) {
                dimm_mb = (uint32_t)b31 * 4u * (uint32_t)ranks;
            }
            if (smbus_read_byte(smbus_io, addr, 18u, &b18) && b18 != 0u) {
                cl = (uint8_t)(highest_bit_index(b18) + 1u);
            }
            if (smbus_read_byte(smbus_io, addr, 27u, &b27) && b27 != 0u) trp = (uint8_t)(b27 >> 2);
            if (smbus_read_byte(smbus_io, addr, 29u, &b29) && b29 != 0u) trcd = (uint8_t)(b29 >> 2);
            if (smbus_read_byte(smbus_io, addr, 30u, &b30) && b30 != 0u) tras = b30;
        } else if (mtype == 0x08u) {
            /* DDR2 */
            uint8_t b5 = 0u, b31 = 0u, b18 = 0u, b27 = 0u, b29 = 0u, b30 = 0u;
            uint32_t ranks = 1u;
            if (smbus_read_byte(smbus_io, addr, 5u, &b5)) {
                ranks = (uint32_t)(b5 & 0x07u) + 1u;
            }
            if (smbus_read_byte(smbus_io, addr, 31u, &b31)) {
                dimm_mb = decode_ddr2_rank_mb(b31) * ranks;
            }
            if (smbus_read_byte(smbus_io, addr, 18u, &b18) && b18 != 0u) {
                cl = highest_bit_index(b18);
            }
            if (smbus_read_byte(smbus_io, addr, 27u, &b27) && b27 != 0u) trp = (uint8_t)(b27 >> 2);
            if (smbus_read_byte(smbus_io, addr, 29u, &b29) && b29 != 0u) trcd = (uint8_t)(b29 >> 2);
            if (smbus_read_byte(smbus_io, addr, 30u, &b30) && b30 != 0u) tras = b30;
        } else if (mtype == 0x0Bu) {
            /* DDR3: Bytes 4, 7, 8 */
            uint8_t b4 = 0u, b7 = 0u, b8 = 0u, b12 = 0u, b16 = 0u;
            if (smbus_read_byte(smbus_io, addr, 4u, &b4) &&
                smbus_read_byte(smbus_io, addr, 7u, &b7) &&
                smbus_read_byte(smbus_io, addr, 8u, &b8)) {
                uint32_t sdram_cap_mb = 32u << (b4 & 0x0Fu); /* die MiB (Mbit / 8) */
                uint32_t bus_bits = 8u << (b8 & 0x07u);
                uint32_t dev_bits = 4u << (b7 & 0x07u);
                uint32_t ranks = (uint32_t)((b7 >> 3) & 0x07u) + 1u;
                if (dev_bits != 0u) {
                    dimm_mb = (sdram_cap_mb * bus_bits * ranks) / dev_bits;
                }
            }
            if (smbus_read_byte(smbus_io, addr, 12u, &b12) &&
                smbus_read_byte(smbus_io, addr, 16u, &b16) && b12 != 0u) {
                cl = (uint8_t)((b16 + b12 - 1u) / b12);
            }
        } else if (mtype == 0x0Cu) {
            /* DDR4: Bytes 4, 12, 13 */
            uint8_t b4 = 0u, b12 = 0u, b13 = 0u, b18 = 0u, b24 = 0u;
            if (smbus_read_byte(smbus_io, addr, 4u, &b4) &&
                smbus_read_byte(smbus_io, addr, 12u, &b12) &&
                smbus_read_byte(smbus_io, addr, 13u, &b13)) {
                uint32_t sdram_cap_mb = 32u << (b4 & 0x0Fu);
                uint32_t dev_bits = 4u << (b12 & 0x07u);
                uint32_t ranks = (uint32_t)((b12 >> 3) & 0x07u) + 1u;
                uint32_t bus_bits = 8u << (b13 & 0x07u);
                if (dev_bits != 0u) {
                    dimm_mb = (sdram_cap_mb * bus_bits * ranks) / dev_bits;
                }
            }
            if (smbus_read_byte(smbus_io, addr, 18u, &b18) &&
                smbus_read_byte(smbus_io, addr, 24u, &b24) && b18 != 0u) {
                cl = (uint8_t)((b24 + b18 - 1u) / b18);
            }
        }

        if (dimm_mb > 0u) {
            spd_set_slot_mb(spd, slot, dimm_mb);
            spd->total_mb += dimm_mb;
            spd->dimm_count++;
            spd->mem_type = mtype;
            if (cl > spd->cl_max) spd->cl_max = cl;
            if (trcd > spd->trcd_ns) spd->trcd_ns = trcd;
            if (trp > spd->trp_ns) spd->trp_ns = trp;
            if (tras > spd->tras_ns) spd->tras_ns = tras;

            rs_puts("[IPO_Boot_ROM] DIMM");
            rs_dec(slot);
            rs_puts(": ");
            if (mtype == 0x04u) rs_puts("SDRAM ");
            else if (mtype == 0x07u) rs_puts("DDR ");
            else if (mtype == 0x08u) rs_puts("DDR2 ");
            else if (mtype == 0x0Bu) rs_puts("DDR3 ");
            else if (mtype == 0x0Cu) rs_puts("DDR4 ");
            else rs_puts("DRAM ");
            rs_dec(dimm_mb);
            rs_puts(" MiB (CL=");
            rs_dec(cl);
            rs_puts(")\n");
        }
    }
}

static uint8_t dram_rw_test(uint32_t phys_addr) {
    volatile uint32_t *p = (volatile uint32_t *)phys_addr;
    uint32_t orig = *p;
    *p = 0x5A3C961Fu;
    io_delay();
    uint32_t r1 = *p;
    *p = 0xA5C369E0u;
    io_delay();
    uint32_t r2 = *p;
    *p = orig;
    return (r1 == 0x5A3C961Fu && r2 == 0xA5C369E0u) ? 1u : 0u;
}

static uint8_t dram_probe_at_mb(uint32_t mb) {
    /* Probe inside 16 MiB+ physical window avoiding VGA/BIOS holes and PCI MMIO (>=3584 MiB) */
    if (mb < 2u || mb > MAX_TOLUD_MB) return 0u;
    uint32_t addr = (mb * 1024u * 1024u) - 0x1000u;
    volatile uint32_t *base_ref = (volatile uint32_t *)0x00100100u;
    volatile uint32_t *p = (volatile uint32_t *)addr;

    uint32_t orig_base = *base_ref;
    uint32_t orig_top = *p;

    *base_ref = 0x11223344u;
    *p = 0xA55A5AA5u;
    io_delay();
    uint32_t v_top = *p;
    uint32_t v_base = *base_ref;

    *p = orig_top;
    *base_ref = orig_base;

    /* Pass only if pattern matches without aliasing 0x00100100 */
    return (v_top == 0xA55A5AA5u && v_base == 0x11223344u) ? 1u : 0u;
}

static uint32_t cold_probe_ram_mb(void) {
    /* Verify base extended RAM at 1 MiB first */
    if (!dram_rw_test(0x00100100u)) {
        return 0u;
    }

    uint32_t last_ok = 16u;
    if (!dram_probe_at_mb(last_ok)) {
        return dram_probe_at_mb(2u) ? 4u : 0u;
    }

    uint32_t step_mb = 32u;
    while (step_mb <= 2048u) {
        if (!dram_probe_at_mb(step_mb)) {
            break;
        }
        last_ok = step_mb;
        step_mb *= 2u;
    }

    /* Binary refine [last_ok .. min(step_mb, MAX_TOLUD_MB)] in 16 MiB increments */
    uint32_t hi = (step_mb <= MAX_TOLUD_MB) ? step_mb : MAX_TOLUD_MB;
    uint32_t lo = last_ok;
    while (lo + 16u <= hi) {
        uint32_t mid = (lo + ((hi - lo) / 2u)) & ~15u;
        if (mid <= lo) break;
        if (dram_probe_at_mb(mid)) {
            lo = mid;
        } else {
            hi = mid - 16u;
        }
    }
    return lo;
}

static void sync_cmos_ram(uint32_t total_bytes) {
    cmos_write(0x17u, 0x00u);
    cmos_write(0x18u, 0x3Cu);
    uint32_t above_16m_64k = 0u;
    if (total_bytes > 0x01000000u) {
        above_16m_64k = (total_bytes - 0x01000000u) >> 16;
    }
    cmos_write(0x34u, (uint8_t)(above_16m_64k & 0xFFu));
    cmos_write(0x35u, (uint8_t)((above_16m_64k >> 8) & 0xFFu));
}

static inline void dram_dummy_read8(uint32_t phys_addr) {
    uint8_t dummy;
    __asm__ volatile("movb (%1), %0" : "=q"(dummy) : "r"(phys_addr) : "memory");
    (void)dummy;
}

static void program_i440_raminit(const spd_summary_t *spd, uint32_t total_mb) {
    /* Compute DRAMT from SPD (bit 2 selects CAS# 2 vs 3; bits 7:4 set conservative tRCD/tRP) */
    uint8_t dramt = (spd->cl_max <= 2u) ? 0x10u : 0x14u;
    if (spd->trcd_ns >= 20u || spd->trp_ns >= 20u) {
        dramt |= 0x20u;
    }
    pci_write8(0, 0, 0, I440_DRAMT, dramt);

    /* Distribute detected memory across DRB0..DRB7 in 8 MiB units */
    uint32_t rem_units = total_mb >> 3;
    if (rem_units == 0u) rem_units = 1u;
    uint32_t cum = 0u;
    for (uint8_t r = 0; r < 8u; r++) {
        uint32_t add = 0u;
        if (spd->dimm_count > 0u && spd->slot_mb && r < spd->slot_cap && spd->slot_mb[r] > 0u) {
            add = spd->slot_mb[r] >> 3;
        } else if (r == 0u) {
            add = (rem_units > 255u) ? 255u : rem_units;
        }
        cum += add;
        if (cum > 255u) cum = 255u;
        pci_write8(0, 0, 0, (uint8_t)(I440_DRB0 + r), (uint8_t)cum);
    }

    pci_write8(0, 0, 0, I440_RPS, 0x00u);
    pci_write8(0, 0, 0, I440_PGPOL, 0x00u);

    /* JEDEC SDRAM init sequence: NOP -> Precharge -> 8x CBR Refresh -> MRS -> Normal */
    pci_write8(0, 0, 0, I440_SDRAMC, SDRAMC_NOP);
    dram_dummy_read8(0x00000400u);

    pci_write8(0, 0, 0, I440_SDRAMC, SDRAMC_PRECHARGE);
    dram_dummy_read8(0x00000400u);

    pci_write8(0, 0, 0, I440_SDRAMC, SDRAMC_CBR_REFRESH);
    for (int i = 0; i < 8; i++) {
        dram_dummy_read8(0x00000400u);
    }

    pci_write8(0, 0, 0, I440_SDRAMC, SDRAMC_MRS);
    dram_dummy_read8(0x000001D0u);

    pci_write8(0, 0, 0, I440_SDRAMC, SDRAMC_NORMAL);
    pci_write8(0, 0, 0, I440_DRAMC, 0x08u);
}

static void program_q35_mch(uint32_t total_mb) {
    /* Enable host memory controller MMIO BAR if populated (PCI 0:0.0 reg 0x48) */
    uint32_t mchbar_lo = pci_read32(0, 0, 0, Q35_MCHBAR_LO);
    if ((mchbar_lo & 0xFFFFC000u) != 0u && (mchbar_lo & 1u) == 0u) {
        pci_write32(0, 0, 0, Q35_MCHBAR_LO, mchbar_lo | 1u);
    }

    pci_write32(0, 0, 0, Q35_TOM, total_mb);

    uint32_t tolud_mb = (total_mb <= MAX_TOLUD_MB) ? total_mb : MAX_TOLUD_MB;
    uint32_t tolud_val = (tolud_mb & 0xFFFFFFC0u) << 4;
    uint32_t cur_tolud = pci_read32(0, 0, 0, Q35_TOLUD) & 0xFFFF0000u;
    pci_write32(0, 0, 0, Q35_TOLUD, cur_tolud | (tolud_val & 0xFFFFu));

    uint32_t drc = pci_read32(0, 0, 0, Q35_DRC);
    pci_write32(0, 0, 0, Q35_DRC, drc | 0x01u);
}

void mrc_run(romstage_handoff_t *ho) {
    uint32_t hb = pci_read32(0, 0, 0, 0x00u);
    uint16_t vid = (uint16_t)(hb & 0xFFFFu);
    uint16_t did = (uint16_t)(hb >> 16);
    if (hb == 0xFFFFFFFFu || hb == 0u) {
        vid = 0u;
        did = 0u;
    }
    ho->host_vid = vid;
    ho->host_did = did;

    rs_puts("[IPO_Boot_ROM] Host Bridge: ");
    if (vid == 0u) {
        rs_puts("Not detected\n");
    } else {
        rs_puts("PCI ID [");
        rs_hex16(vid);
        rs_putc(':');
        rs_hex16(did);
        rs_puts("] ");
        if (vid == 0x8086u) {
            if (did == 0x1237u) rs_puts("(Intel i440FX)");
            else if (did == 0x7190u || did == 0x7192u) rs_puts("(Intel i440BX)");
            else if (did == 0x29C0u) rs_puts("(Intel Q35 MCH)");
            else if (did < 0x2500u) rs_puts("(Intel Legacy MCH)");
            else if (did < 0x3000u) rs_puts("(Intel Bearlake/9xx MCH)");
            else rs_puts("(Intel IMC/Core)");
        } else if (vid == 0x1022u) {
            rs_puts("(AMD Host Bridge)");
        } else if (vid == 0x1106u) {
            rs_puts("(VIA Host Bridge)");
        } else if (vid == 0x1039u) {
            rs_puts("(SiS Host Bridge)");
        } else {
            rs_puts("(Generic PCI Host Bridge)");
        }
        rs_putc('\n');
    }

    uint16_t smbus_io = smbus_probe_controller();
    spd_summary_t spd;
    spd_scan_dimms(smbus_io, &spd);
    ho->spd_dimm_count = spd.dimm_count;

    uint32_t total_mb = 0u;
    uint32_t flags = 0u;

    if (spd.total_mb > 0u) {
        total_mb = spd.total_mb;
        flags |= MRC_FLAG_SPD;
        if (total_mb > MAX_TOLUD_MB) total_mb = MAX_TOLUD_MB;
        sync_cmos_ram(total_mb * 1024u * 1024u);
    } else {
        outb(POST_PORT, 0x1Fu); /* POST_WARN_SPD_FAIL */
        uint32_t ext2 = (uint32_t)cmos_read(0x34u) | ((uint32_t)cmos_read(0x35u) << 8);
        if (ext2 > 0u) {
            total_mb = (ext2 >> 4) + 16u; /* 64 KiB blocks above 16 MiB */
            flags |= MRC_FLAG_CMOS;
        } else {
            uint32_t ext1 = (uint32_t)cmos_read(0x17u) | ((uint32_t)cmos_read(0x18u) << 8);
            if (ext1 > 0u) {
                total_mb = (ext1 >> 10) + 1u;
                flags |= MRC_FLAG_CMOS;
            } else {
                /* Empty SPD and CMOS: fall back to direct RAM probing */
                uint32_t probed = cold_probe_ram_mb();
                if (probed > 0u) {
                    total_mb = probed;
                    flags |= MRC_FLAG_HW_PROBE;
                } else {
                    total_mb = MRC_DEFAULT_RAM_MB;
                }
                sync_cmos_ram(total_mb * 1024u * 1024u);
            }
        }
        if (total_mb > MAX_TOLUD_MB) total_mb = MAX_TOLUD_MB;
    }

    if (vid == 0x8086u) {
        if (did < 0x2500u) {
            program_i440_raminit(&spd, total_mb);
            flags |= MRC_FLAG_CHIPSET;
        } else if (did < 0x3000u) {
            program_q35_mch(total_mb);
            flags |= MRC_FLAG_CHIPSET;
        } else {
            rs_puts("[IPO_Boot_ROM] MRC: Newer Intel IMC detected (DRAM PHY training left to HW/FSP)\n");
        }
    } else if (vid != 0u) {
        rs_puts("[IPO_Boot_ROM] MRC: Non-Intel Host Bridge (chipset-specific PHY training skipped)\n");
    }

    /* Test DRAM R/W at target stack (0x7BF0) and 1 MiB before leaving CAR */
    uint8_t low_ok = dram_rw_test(0x00007BF0u);
    uint8_t high_ok = dram_rw_test(0x00100100u);
    ho->dram_verified = (low_ok && high_ok) ? 1u : 0u;

    ho->total_ram_mb = total_mb;
    ho->total_ram_bytes = (total_mb >= MAX_TOLUD_MB) ? 0xE0000000u : (total_mb * 1024u * 1024u);
    ho->mrc_mode_flags = flags;

    rs_puts("[IPO_Boot_ROM] Memory: ");
    rs_dec(total_mb);
    rs_puts(" MiB (source=");
    if (flags & MRC_FLAG_SPD) rs_puts("SPD");
    else if (flags & MRC_FLAG_CMOS) rs_puts("CMOS");
    else if (flags & MRC_FLAG_HW_PROBE) rs_puts("HW_PROBE");
    else rs_puts("DEFAULT");
    rs_puts(", R/W=");
    rs_puts(ho->dram_verified ? "OK" : "FAIL");
    rs_puts(")\n");

    if (spd.slot_mb) {
        rs_free(spd.slot_mb);
        spd.slot_mb = NULL;
    }
}
