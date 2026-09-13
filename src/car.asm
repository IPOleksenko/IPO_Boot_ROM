; car.asm — Cache-as-RAM (CAR) Setup and Teardown
; Provides a working stack in CPU cache before DRAM is initialized.
; CAR Region: 32 KB at physical 0x70000-0x77FFF (SS:SP = 0x7000:0x8000)
;
; car_setup:    Fall-through code block — jumped to, NOT called (no stack yet)
; car_teardown: Normal subroutine — called after MRC when DRAM is available

BITS 16

%include "contract.inc"

; =============================================================================
; car_setup — Establish Cache-as-RAM for pre-DRAM stack
; =============================================================================
; ENTRY: Jumped to from reset path. NO STACK available.
;        All operations use only registers — no push/pop/call/ret.
; EXIT:  Falls through to car_setup_done with:
;        SS:SP = 0x7000:0x8000 (32 KB CAR stack, grows downward)
;        Cache locked in No-Eviction Mode
; =============================================================================
car_setup:

    ; -------------------------------------------------------------------------
    ; Step 1: Disable caching via CR0
    ; -------------------------------------------------------------------------
    ; CR0.CD (bit 30) = 1  → Cache Disable: prevent new cache fills
    ; CR0.NW (bit 29) = 0  → Not Write-through: clear to avoid write-through
    mov     eax, cr0
    or      eax, (1 << 30)          ; Set CD (Cache Disable)
    and     eax, ~(1 << 29)         ; Clear NW (Not Write-through)
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 2: Flush and invalidate all caches
    ; -------------------------------------------------------------------------
    ; WBINVD: Write-Back and Invalidate — ensures caches are clean and empty
    wbinvd

    ; -------------------------------------------------------------------------
    ; Step 3: Program MTRR Default Type register (MSR 0x2FF)
    ; -------------------------------------------------------------------------
    ; MSR_MTRR_DEF_TYPE layout:
    ;   Bit 11:  E (MTRR Enable) — enables variable/fixed MTRRs
    ;   Bit 10:  FE (Fixed-range Enable) — we leave this off
    ;   Bits 7:0: Default memory type — UC (0x00)
    ; Value: 0x0000_0800 → MTRRs enabled, default type = Uncacheable
    mov     ecx, MSR_MTRR_DEF_TYPE ; ECX = 0x2FF
    xor     edx, edx                ; EDX = 0 (high 32 bits)
    mov     eax, 0x00000800         ; EAX = E=1, type=UC
    wrmsr

    ; -------------------------------------------------------------------------
    ; Step 4: Program Variable MTRR 0 for the CAR region
    ; -------------------------------------------------------------------------

    ; --- PHYSBASE0 (MSR 0x200) ---
    ; Bits 35:12 = Physical base address (aligned)
    ; Bits  7:0  = Memory type
    ; CAR_BASE = 0x70000, type = WB (0x06)
    ; EAX = 0x00070006 → base[31:12]=0x00070, type=WB
    mov     ecx, MSR_MTRR_PHYSBASE0 ; ECX = 0x200
    xor     edx, edx                ; EDX = 0 (base[35:32] = 0)
    mov     eax, 0x00070006         ; Base = 0x70000, Type = Write-Back
    wrmsr

    ; --- PHYSMASK0 (MSR 0x201) ---
    ; Bits 35:12 = Address mask (determines region size)
    ; Bit  11    = V (Valid) — enables this MTRR pair
    ; For 32 KB (0x8000): mask = ~(0x8000 - 1) & 0xFFFFF000 = 0xFFFF8000
    ; EAX = 0xFFFF8800 → mask[31:12] | Valid bit (bit 11)
    ; EDX = 0x0000000F → mask[35:32] for 36-bit physical addressing
    mov     ecx, MSR_MTRR_PHYSMASK0 ; ECX = 0x201
    mov     edx, 0x0000000F         ; Mask bits [35:32] (36-bit phys addr)
    mov     eax, 0xFFFF8800         ; Mask[31:12] = 0xFFFF8, Valid = 1
    wrmsr

    ; -------------------------------------------------------------------------
    ; Step 5: Re-enable caching (clear CR0.CD)
    ; -------------------------------------------------------------------------
    ; With MTRR set to WB for our CAR region, CPU will cache accesses there.
    ; Everything else defaults to UC, so only our region gets cached.
    mov     eax, cr0
    and     eax, ~(1 << 30)         ; Clear CD — allow cache fills
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 6: Fill CAR region to allocate cache lines
    ; -------------------------------------------------------------------------
    ; Write 32 KB of zeros to physical 0x70000-0x77FFF.
    ; In 16-bit real mode: ES=0x7000, DI=0x0000 → phys = 0x70000 + DI
    ; REP STOSD writes 4 bytes per iteration; CX=8192 → 32,768 bytes = 32 KB
    ; The CPU caches these writes (WB region) — data stays in cache, not DRAM.
    mov     ax, CAR_STACK_SEG       ; AX = 0x7000
    mov     es, ax                  ; ES = 0x7000
    xor     di, di                  ; DI = 0x0000
    mov     cx, 8192                ; 8192 dwords × 4 bytes = 32,768 bytes
    xor     eax, eax                ; Fill pattern = 0x00000000
    cld                             ; Direction flag: forward (DI increments)
    rep stosd                       ; Fill CAR region — allocates cache lines

    ; -------------------------------------------------------------------------
    ; Step 7: Set No-Eviction Mode (NEM)
    ; -------------------------------------------------------------------------
    ; Set CR0.CD = 1 to prevent the CPU from evicting dirty cache lines
    ; to non-existent DRAM. The cache now acts as locked SRAM.
    mov     eax, cr0
    or      eax, (1 << 30)          ; Set CD — no new fills, no evictions
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 8: Set up stack pointer in CAR region
    ; -------------------------------------------------------------------------
    ; SS:SP = 0x7000:0x8000 → physical 0x78000 (top of 32 KB region)
    ; Stack grows downward from 0x78000 toward 0x70000
    mov     ax, CAR_STACK_SEG       ; AX = 0x7000
    mov     ss, ax                  ; SS = 0x7000
    mov     sp, CAR_STACK_PTR       ; SP = 0x8000

    ; =========================================================================
    ; CAR is now active — stack is available, push/pop/call/ret are safe
    ; =========================================================================

car_setup_done:
    ; init.asm continues execution from this label


; =============================================================================
; car_teardown — Migrate from Cache-as-RAM to real DRAM
; =============================================================================
; ENTRY: Called after MRC has initialized DRAM. Stack is still in CAR.
; EXIT:  SS:SP = 0x0000:0x7000 (DRAM stack), caching restored to normal.
;        Dirty CAR data flushed to DRAM via WBINVD.
; =============================================================================
car_teardown:
    push    eax
    push    ecx
    push    edx

    ; -------------------------------------------------------------------------
    ; Step 1: Clear Variable MTRR 0 (disable CAR MTRR pair)
    ; -------------------------------------------------------------------------
    ; Zero out PHYSBASE0 — clears base address and memory type
    mov     ecx, MSR_MTRR_PHYSBASE0 ; ECX = 0x200
    xor     eax, eax                ; EAX = 0
    xor     edx, edx                ; EDX = 0
    wrmsr

    ; Zero out PHYSMASK0 — clears mask and Valid bit (disables this MTRR)
    mov     ecx, MSR_MTRR_PHYSMASK0 ; ECX = 0x201
    xor     eax, eax                ; EAX = 0
    xor     edx, edx                ; EDX = 0
    wrmsr

    ; -------------------------------------------------------------------------
    ; Step 2: Flush dirty cache lines to DRAM
    ; -------------------------------------------------------------------------
    ; WBINVD writes all modified (dirty) cache lines back to memory.
    ; Since DRAM is now online, the CAR data lands safely in physical RAM.
    wbinvd

    ; -------------------------------------------------------------------------
    ; Step 3: Re-enable normal caching
    ; -------------------------------------------------------------------------
    ; Clear CR0.CD so the CPU resumes normal cache fill/evict behavior.
    mov     eax, cr0
    and     eax, ~(1 << 30)         ; Clear CD — normal caching
    and     eax, ~(1 << 29)         ; Clear NW — ensure write-back
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 4: Restore MTRR default type (MTRRs enabled, default UC)
    ; -------------------------------------------------------------------------
    ; This ensures MTRRs remain active for any future MTRR configuration
    ; (e.g., MRC may have programmed additional variable MTRRs for DRAM).
    mov     ecx, MSR_MTRR_DEF_TYPE ; ECX = 0x2FF
    xor     edx, edx                ; EDX = 0
    mov     eax, 0x00000800         ; E=1, default type = UC
    wrmsr

    ; -------------------------------------------------------------------------
    ; Step 5: Move stack to real DRAM
    ; -------------------------------------------------------------------------
    ; SS:SP = 0x0000:0x7000 → physical 0x7000 (conventional memory)
    ; Stack grows down from 0x7000 toward 0x6000
    pop     edx
    pop     ecx
    pop     eax

    mov     ax, BOOT_STACK_SEG      ; AX = 0x0000
    mov     ss, ax                  ; SS = 0x0000
    mov     sp, BOOT_STACK_PTR      ; SP = 0x7000

    ret
