; 32-bit protected mode Flash-XIP entry point
BITS 32

section .text.entry
global _romstage_entry
extern romstage_main

_romstage_entry:
    ; cdecl argument [esp + 4] = romstage_handoff_t *ho
    push    ebp
    mov     ebp, esp
    push    ebx
    push    esi
    push    edi

    mov     eax, [ebp + 8]
    push    eax
    call    romstage_main
    add     esp, 4

    pop     edi
    pop     esi
    pop     ebx
    pop     ebp
    ret
