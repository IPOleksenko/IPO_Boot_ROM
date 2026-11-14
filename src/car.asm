; car.asm — Cache-as-RAM (CAR) setup and teardown
; Allocates a 32 KB pre-DRAM stack in CPU cache at physical 0x70000-0x77FFF.

BITS 16

%include "contract.inc"

car_setup:
    mov     al, POST_CAR_START
    out     POST_PORT, al

    ; Verify CPU MTRR support (CPUID.1:EDX[12])
    mov     eax, 1
    cpuid
    test    edx, (1 << 12)
    jnz     .has_mtrr
    mov     al, POST_ERR_NO_CAR
    out     POST_PORT, al
    cli
.halt_no_mtrr:
    hlt
    jmp     .halt_no_mtrr

.has_mtrr:
    ; Query MAXPHYADDR for MTRR PHYSMASK0 high bits
    mov     eax, 0x80000000
    cpuid
    cmp     eax, 0x80000008
    jb      .use_default_pae
    mov     eax, 0x80000008
    cpuid
    and     eax, 0xFF
    jmp     .calc_mask

.use_default_pae:
    mov     eax, 1
    cpuid
    test    edx, (1 << 6)
    mov     eax, 32
    jz      .calc_mask
    mov     eax, 36

.calc_mask:
    xor     edx, edx
    cmp     eax, 32
    jbe     .mask_done
    mov     ecx, eax
    sub     ecx, 32
    mov     edx, 1
    shl     edx, cl
    dec     edx

.mask_done:
    mov     ebx, edx

    ; Enter cache-disable mode and flush caches before programming MTRRs
    mov     eax, cr0
    or      eax, (1 << 30)
    and     eax, ~(1 << 29)
    mov     cr0, eax
    wbinvd

    ; Enable MTRRs with default type Uncacheable (UC) during CAR
    mov     ecx, MSR_MTRR_DEF_TYPE
    xor     edx, edx
    mov     eax, 0x00000800
    wrmsr

    ; Map 32 KB CAR window (0x70000-0x77FFF) as Write-Back (WB) in MTRR0
    mov     ecx, MSR_MTRR_PHYSBASE0
    xor     edx, edx
    mov     eax, CAR_BASE | MTRR_TYPE_WB
    wrmsr

    mov     ecx, MSR_MTRR_PHYSMASK0
    mov     edx, ebx
    mov     eax, 0xFFFF8800
    wrmsr

    ; Enable caching to allocate cache lines for the CAR region
    mov     eax, cr0
    and     eax, ~(1 << 30)
    mov     cr0, eax

    mov     al, POST_CAR_START
    out     POST_PORT, al
    out     POST_PORT, al

    mov     ax, CAR_STACK_SEG
    mov     es, ax
    xor     di, di
    xor     eax, eax
    cld

    mov     cx, 64
.car_warmup_loop:
    stosd
    out     POST_PORT, al
    loop    .car_warmup_loop

    mov     cx, 8192 - 64
    rep     stosd

    ; Lock cache in No-Eviction Mode (CR0.CD = 1) and initialize CAR stack
    mov     eax, cr0
    or      eax, (1 << 30)
    mov     cr0, eax

    mov     ax, CAR_STACK_SEG
    mov     ss, ax
    xor     esp, esp
    mov     sp, CAR_STACK_PTR

    xor     di, di
    mov     cx, 64
    xor     eax, eax
    rep     stosd

car_setup_done:
    mov     al, POST_CAR_OK
    out     POST_PORT, al
    jmp     car_setup_finished

; Tear down CAR, configure WB caching for DRAM and UC for PCI MMIO, and switch stack to DRAM
car_teardown:
    pop     bp

    ; Save BX (VID), DX (DID), and ECX (RAM bytes) across CPUID/WRMSR
    shl     ebx, 16
    mov     bx, dx
    mov     esi, ebx
    mov     edi, ecx

    mov     eax, 1
    cpuid
    test    edx, (1 << 12)
    jz      .car_teardown_nomtrr

    wbinvd

    mov     eax, 0x80000000
    cpuid
    cmp     eax, 0x80000008
    jb      .td_default_pae
    mov     eax, 0x80000008
    cpuid
    and     eax, 0xFF
    jmp     .td_calc_mask
.td_default_pae:
    mov     eax, 1
    cpuid
    test    edx, (1 << 6)
    mov     eax, 32
    jz      .td_calc_mask
    mov     eax, 36
.td_calc_mask:
    xor     ebx, ebx
    cmp     eax, 32
    jbe     .td_mask_done
    mov     ecx, eax
    sub     ecx, 32
    mov     ebx, 1
    shl     ebx, cl
    dec     ebx
.td_mask_done:

    ; MTRR0: 0xE0000000 - 0xFFFFFFFF (512 MB PCI MMIO / APIC / ROM) = Uncacheable (UC)
    mov     ecx, MSR_MTRR_PHYSBASE0
    xor     edx, edx
    mov     eax, 0xE0000000 | MTRR_TYPE_UC
    wrmsr

    mov     ecx, MSR_MTRR_PHYSMASK0
    mov     edx, ebx
    mov     eax, 0xE0000800
    wrmsr

    ; Default memory type = Write-Back (WB) for all DRAM (0x00000000 - 0xDFFFFFFF)
    mov     ecx, MSR_MTRR_DEF_TYPE
    xor     edx, edx
    mov     eax, 0x00000800 | MTRR_TYPE_WB
    wrmsr

.car_teardown_nomtrr:
    mov     eax, cr0
    and     eax, ~((1 << 30) | (1 << 29))
    mov     cr0, eax

    mov     ax, BOOT_STACK_SEG
    mov     ss, ax
    xor     esp, esp
    mov     sp, BOOT_STACK_PTR

    mov     ebx, esi
    mov     dx, bx
    shr     ebx, 16
    mov     ecx, edi

    jmp     bp

car_setup_finished:
