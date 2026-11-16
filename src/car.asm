; Cache-as-RAM (CAR) setup and teardown.
; Probes EFLAGS.ID before running CPUID and bypasses CAR on pre-CPUID or
; pre-MTRR CPUs instead of halting.
; Input: EBP[15:0] = reset EDX, BL = lpc_type (saved in EBP[23:16])

BITS 16

%include "contract.inc"

car_setup:
    mov     al, POST_CAR_START
    out     POST_PORT, al

    ; Pack lpc_type (BL) into EBP[23:16], keeping reset signature in EBP[15:0]
    and     ebp, 0x0000FFFF
    and     ebx, 0x000000FF
    shl     ebx, 16
    or      ebp, ebx

    ; Temp flags in SI until CAR scratch is zeroed:
    ;   SI[7:0]  = has_cpuid (0/1)
    ;   SI[15:8] = cpu_vendor (0=unknown, 1=type 1, 2=type 2)
    xor     esi, esi

    ; Check if 0x7000:0x7FF0 is already writable (warm reset or pre-initialized RAM)
    mov     ax, CAR_STACK_SEG
    mov     ds, ax
    mov     dword [0x7FF0], 0xA55A1234
    mov     dword [0x7FF4], 0x5AA5EDCB
    cmp     dword [0x7FF0], 0xA55A1234
    jne     .cold_pre_dram
    cmp     dword [0x7FF4], 0x5AA5EDCB
    jne     .cold_pre_dram

    ; RAM at 0x70000 responds; use temp stack at 0x7000:0x8000 to probe EFLAGS.ID
    mov     ax, CAR_STACK_SEG
    mov     ss, ax
    xor     esp, esp
    mov     sp, CAR_STACK_PTR

    pushfd
    pop     eax
    mov     ecx, eax
    xor     eax, 0x00200000             ; Toggle EFLAGS.ID (bit 21)
    push    eax
    popfd
    pushfd
    pop     eax
    push    ecx
    popfd
    xor     eax, ecx
    test    eax, 0x00200000
    jz      .car_bypass                 ; Pre-CPUID CPU: skip CPUID and MSR writes

    mov     si, 1                       ; has_cpuid = 1
    jmp     .check_vendor_and_mtrr

.cold_pre_dram:
    ; Cold boot without DRAM at 0x70000: check reset EDX family in EBP[11:8]
    mov     eax, ebp
    and     eax, 0x0F00
    cmp     eax, 0x0500
    jb      .car_bypass                 ; Family < 5 lacks reliable CPUID; skip CAR
    mov     si, 1

.check_vendor_and_mtrr:
    ; Classify CPUID leaf 0 vendor ID (1=type 1, 2=type 2)
    xor     eax, eax
    cpuid
    cmp     ebx, 0x756E6547
    jne     .chk_amd
    cmp     edx, 0x49656E69
    jne     .chk_amd
    cmp     ecx, 0x6C65746E
    jne     .chk_amd
    or      si, (1 << 8)
    jmp     .chk_mtrr_bit

.chk_amd:
    cmp     ebx, 0x68747541
    jne     .chk_mtrr_bit
    cmp     edx, 0x69746E65
    jne     .chk_mtrr_bit
    cmp     ecx, 0x444D4163
    jne     .chk_mtrr_bit
    or      si, (2 << 8)

.chk_mtrr_bit:
    mov     eax, 1
    cpuid
    test    edx, (1 << 12)              ; CPUID.1:EDX[12] = MTRR
    jnz     .has_mtrr
    jmp     .car_bypass                 ; Pre-MTRR CPU: skip CAR setup

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

    ; Disable and flush caches before programming MTRR0
    mov     eax, cr0
    or      eax, (1 << 30)
    and     eax, ~(1 << 29)
    mov     cr0, eax
    wbinvd

    ; Enable MTRRs with UC default type during CAR
    mov     ecx, MSR_MTRR_DEF_TYPE
    xor     edx, edx
    mov     eax, 0x00000800
    wrmsr

    ; Map 32 KiB CAR window (0x70000-0x77FFF) as WB in MTRR0
    mov     ecx, MSR_MTRR_PHYSBASE0
    xor     edx, edx
    mov     eax, CAR_BASE | MTRR_TYPE_WB
    wrmsr

    mov     ecx, MSR_MTRR_PHYSMASK0
    mov     edx, ebx
    mov     eax, 0xFFFF8800
    wrmsr

    ; Briefly enable cache to populate CAR lines
    mov     eax, cr0
    and     eax, ~(1 << 30)
    mov     cr0, eax

    mov     ax, CAR_STACK_SEG
    mov     es, ax
    xor     di, di
    xor     eax, eax
    cld

    mov     cx, 8192
    rep     stosd

    ; Lock cache in no-eviction mode (CR0.CD = 1)
    mov     eax, cr0
    or      eax, (1 << 30)
    mov     cr0, eax

    mov     dl, 1                       ; has_mtrr = 1
    jmp     .finalize_car_scratch

.car_bypass:
    mov     al, POST_NOMTRR_BYPASS
    out     POST_PORT, al

    ; Enable caches (CD=0, NW=0) on pre-CPUID / pre-MTRR CPUs
    mov     eax, cr0
    and     eax, ~((1 << 30) | (1 << 29))
    mov     cr0, eax

    mov     ax, CAR_STACK_SEG
    mov     es, ax
    xor     di, di
    xor     eax, eax
    cld
    mov     cx, 64
    rep     stosd
    xor     dl, dl                      ; has_mtrr = 0

.finalize_car_scratch:
    mov     ax, CAR_STACK_SEG
    mov     ss, ax
    xor     esp, esp
    mov     sp, CAR_STACK_PTR

    mov     ax, CAR_STACK_SEG
    mov     es, ax
    xor     di, di
    xor     eax, eax
    cld
    mov     cx, 64
    rep     stosd

    mov     ax, si
    mov     [es:CAR_HAS_CPUID], al
    mov     [es:CAR_HAS_MTRR], dl
    mov     [es:CAR_CPU_VENDOR], ah

    mov     eax, ebp
    shr     eax, 16
    mov     [es:CAR_LPC_TYPE], al

    mov     al, POST_CAR_OK
    out     POST_PORT, al
    jmp     car_setup_finished

; Tear down CAR after switching the stack to verified DRAM.
; Input: AL = has_mtrr (1 to reprogram MTRRs for DRAM WB / MMIO UC)
car_teardown_dram:
    test    al, al
    jz      .teardown_nomtrr

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

    ; MTRR0: 0xE0000000 - 0xFFFFFFFF (512 MiB PCI MMIO / APIC / ROM) = UC
    mov     ecx, MSR_MTRR_PHYSBASE0
    xor     edx, edx
    mov     eax, 0xE0000000 | MTRR_TYPE_UC
    wrmsr

    mov     ecx, MSR_MTRR_PHYSMASK0
    mov     edx, ebx
    mov     eax, 0xE0000800
    wrmsr

    ; Default MTRR type WB for DRAM (0x00000000 - 0xDFFFFFFF)
    mov     ecx, MSR_MTRR_DEF_TYPE
    xor     edx, edx
    mov     eax, 0x00000800 | MTRR_TYPE_WB
    wrmsr

.teardown_nomtrr:
    mov     eax, cr0
    and     eax, ~((1 << 30) | (1 << 29))
    mov     cr0, eax
    ret

car_setup_finished:
