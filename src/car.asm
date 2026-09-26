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
    mov     al, POST_CAR_START
    out     POST_PORT, al

    ; -------------------------------------------------------------------------
    ; Step 0: Check CPUID for MTRR support (registers only, no stack)
    ; -------------------------------------------------------------------------
    mov     eax, 1
    cpuid
    test    edx, (1 << 12)          ; Bit 12: MTRR support
    jnz     .has_mtrr
    mov     al, POST_ERR_NO_CAR
    out     POST_PORT, al
    cli
.halt_no_mtrr:
    hlt
    jmp     .halt_no_mtrr

.has_mtrr:

    ; Determine MAXPHYADDR for PHYSMASK (avoid #GP on CPUs with != 36 bit address)
    mov     eax, 0x80000000
    cpuid
    cmp     eax, 0x80000008
    jb      .use_default_pae
    mov     eax, 0x80000008
    cpuid
    and     eax, 0xFF               ; AL = Physical Address Bits (e.g. 36, 40)
    jmp     .calc_mask

.use_default_pae:
    mov     eax, 1
    cpuid
    test    edx, (1 << 6)           ; CPUID.1:EDX[bit 6] = PAE
    mov     eax, 32
    jz      .calc_mask
    mov     eax, 36

.calc_mask:
    ; Mask for bits [63:32] in EDX
    ; If MAXPHYADDR <= 32: EDX = 0
    ; If MAXPHYADDR > 32: EDX = (1 << (MAXPHYADDR - 32)) - 1
    xor     edx, edx
    cmp     eax, 32
    jbe     .mask_done
    mov     ecx, eax
    sub     ecx, 32                 ; Shift count: MAXPHYADDR - 32
    mov     edx, 1
    shl     edx, cl
    dec     edx                     ; EDX = (1 << cl) - 1 (e.g. 0x0F for 36-bit)

.mask_done:
    ; Save EDX mask in EBX temporarily (no stack available)
    mov     ebx, edx

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
    mov     ecx, MSR_MTRR_DEF_TYPE  ; ECX = 0x2FF
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
    mov     ecx, MSR_MTRR_PHYSBASE0 ; ECX = 0x200
    xor     edx, edx                ; EDX = 0 (base[63:32] = 0)
    mov     eax, 0x00070006         ; Base = 0x70000, Type = Write-Back
    wrmsr

    ; --- PHYSMASK0 (MSR 0x201) ---
    ; Bits 35:12 = Address mask (determines region size, 32KB = 0xFFFF8000)
    ; Bit  11    = V (Valid) — enables this MTRR pair
    mov     ecx, MSR_MTRR_PHYSMASK0 ; ECX = 0x201
    mov     edx, ebx                ; EDX = calculated PHYSMASK high bits
    mov     eax, 0xFFFF8800         ; Mask[31:12] = 0xFFFF8, Valid = 1
    wrmsr

    ; -------------------------------------------------------------------------
    ; Step 5: Re-enable caching (clear CR0.CD)
    ; -------------------------------------------------------------------------
    mov     eax, cr0
    and     eax, ~(1 << 30)         ; Clear CD — allow cache fills
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 6: Fill CAR region to allocate cache lines
    ; -------------------------------------------------------------------------
    ; HARDWARE MITIGATION:
    ; On physical Intel P6 processors (Pentium II/III Klamath/Deschutes/Coppermine),
    ; writing to a Write-Back region when DRAM is not yet initialized causes a
    ; Write-Allocate cache miss, which emits an RFO (Read-For-Ownership) bus cycle
    ; on the FSB. If the host bridge (82441FX / 82443BX) does not terminate unmapped
    ; DRAM cycles cleanly, a continuous burst rep stosd can hang the bus.
    ;
    ; Mitigation:
    ; 1. CAR region (0x70000-0x77FFF) is strictly in conventional RAM space (below 640K).
    ; 2. MTRR is configured as WB for exactly this 32KB window.
    ; 3. Initial 64 dwords (8 cache lines = 256 bytes) are written in a paced loop
    ;    with an explicit unbuffered ISA/LPC I/O write (out 0x80, al) per iteration,
    ;    providing ~1-2 us bus settling time.
    ; 4. The remaining 8128 dwords are filled via rep stosd.
    ;
    ; NOTE: This is a hardware-stepping mitigation, not a mathematical guarantee.
    ; If a physical board hangs at POST code 0x12, check CPU stepping or board revision.
    ; -------------------------------------------------------------------------
    ; Short settling delay after MTRR WRMSR
    mov     al, POST_CAR_START
    out     POST_PORT, al
    out     POST_PORT, al

    mov     ax, CAR_STACK_SEG       ; AX = 0x7000
    mov     es, ax                  ; ES = 0x7000
    xor     di, di                  ; DI = 0x0000
    xor     eax, eax                ; Fill pattern = 0x00000000
    cld                             ; Direction flag: forward (DI increments)

    ; Paced warmup: 64 dwords with ISA bus delay between stores
    mov     cx, 64
.car_warmup_loop:
    stosd
    out     POST_PORT, al           ; ~1-2 us ISA bus cycle delay (AL is 0)
    loop    .car_warmup_loop

    ; Bulk fill remaining (8192 - 64 = 8128 dwords = 32,512 bytes)
    mov     cx, 8192 - 64
    rep     stosd

    ; -------------------------------------------------------------------------
    ; Step 7: Set No-Eviction Mode (NEM)
    ; -------------------------------------------------------------------------
    mov     eax, cr0
    or      eax, (1 << 30)          ; Set CD — no new fills, no evictions
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 8: Set up stack pointer in CAR region
    ; -------------------------------------------------------------------------
    mov     ax, CAR_STACK_SEG       ; AX = 0x7000
    mov     ss, ax                  ; SS = 0x7000
    mov     sp, CAR_STACK_PTR       ; SP = 0x8000

    ; Zero out CAR scratch area (0x7000:0x0000 - 0x7000:0x00FF)
    xor     di, di
    mov     cx, 64                  ; 64 dwords = 256 bytes
    xor     eax, eax
    rep stosd

car_setup_done:
    mov     al, POST_CAR_OK
    out     POST_PORT, al
    jmp     car_setup_finished


; =============================================================================
; car_teardown — Migrate from Cache-as-RAM to real DRAM
; =============================================================================
; ENTRY: Called after MRC has initialized DRAM. Stack is still in CAR.
;        Caller parameters in BL and ECX are preserved across teardown.
; EXIT:  SS:SP = 0x0000:BOOT_STACK_PTR (DRAM stack), caching restored.
; =============================================================================
car_teardown:
    ; -------------------------------------------------------------------------
    ; Step 1: Pop return address from CAR stack into BP
    ;         (BP is preserved across CPUID/WRMSR/WBINVD)
    ; -------------------------------------------------------------------------
    pop     bp

    ; Preserve live register parameters (BL = CAR_CHIPSET, ECX = CAR_TOTAL_RAM_BYTES)
    ; in registers unaffected by CPUID and WRMSR
    mov     esi, ebx
    mov     edi, ecx

    ; -------------------------------------------------------------------------
    ; Step 2: Check MTRR support before tearing down MSRs
    ; -------------------------------------------------------------------------
    mov     eax, 1
    cpuid
    test    edx, (1 << 12)          ; Bit 12: MTRR support
    jz      .car_teardown_nomtrr

    ; -------------------------------------------------------------------------
    ; Step 3: Flush dirty cache lines to DRAM
    ;         MUST execute before disabling MTRR0 so lines write back cleanly
    ; -------------------------------------------------------------------------
    wbinvd

    ; -------------------------------------------------------------------------
    ; Step 4: Clear Variable MTRR 0 (disable CAR MTRR pair)
    ; -------------------------------------------------------------------------
    mov     ecx, MSR_MTRR_PHYSBASE0 ; ECX = 0x200
    xor     eax, eax
    xor     edx, edx
    wrmsr

    mov     ecx, MSR_MTRR_PHYSMASK0 ; ECX = 0x201
    xor     eax, eax
    xor     edx, edx
    wrmsr

    ; -------------------------------------------------------------------------
    ; Step 5: Restore MTRR default type (MTRRs enabled, default UC)
    ; -------------------------------------------------------------------------
    mov     ecx, MSR_MTRR_DEF_TYPE  ; ECX = 0x2FF
    xor     edx, edx
    mov     eax, 0x00000800         ; E=1, default type = UC
    wrmsr

.car_teardown_nomtrr:
    ; -------------------------------------------------------------------------
    ; Step 6: Re-enable normal caching
    ; -------------------------------------------------------------------------
    mov     eax, cr0
    and     eax, ~(1 << 30)         ; Clear CD — normal caching
    and     eax, ~(1 << 29)         ; Clear NW — ensure write-back
    mov     cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 7: Switch stack to real DRAM
    ; -------------------------------------------------------------------------
    mov     ax, BOOT_STACK_SEG      ; AX = 0x0000
    mov     ss, ax                  ; SS = 0x0000
    mov     sp, BOOT_STACK_PTR      ; SP = BOOT_STACK_PTR (0x7C00)

    ; -------------------------------------------------------------------------
    ; Step 8: Restore preserved registers
    ; -------------------------------------------------------------------------
    mov     ebx, esi
    mov     ecx, edi

    ; Return to caller via saved BP (return address from CAR stack)
    jmp     bp

car_setup_finished:
