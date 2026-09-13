; init.asm — Early initialization for IPO_Boot_ROM (Hardware-Compatible)
; Assembled with ORG 0x8000, executed in CS=0xF000 (Physical 0xF8000 / 0xFFFF8000)
;
; Boot sequence for real hardware:
;   1. CAR setup (stack in CPU cache — no DRAM yet)
;   2. Chipset detection (i440FX vs Q35 via PCI probe)
;   3. MRC: DRAM controller initialization
;   4. CAR teardown, stack moves to real DRAM
;   5. PIC 8259A cascade initialization
;   6. PIT 8254 system timer initialization
;   7. COM1 serial initialization
;   8. Shadow ROM: copy 64KB ROM → DRAM via PAM, lock read-only
;   9. Validate firmware magic, jump to 0xF000:0x0004

BITS 16
ORG 0x8000

%include "contract.inc"

global bootrom_init

bootrom_init:
    ; =========================================================================
    ; Phase 0: CPU Initialization (no stack, no DRAM)
    ; =========================================================================
    cli
    cld

    ; Set DS = CS = 0xF000 so we can access ROM data (strings, tables)
    mov     ax, BOOTROM_SEG
    mov     ds, ax

    ; =========================================================================
    ; Phase 1: Cache-as-RAM Setup (inline — NO stack operations allowed yet)
    ; car.asm provides the car_setup block which falls through to car_setup_done
    ; After this, SS:SP is valid (stack in CPU cache)
    ; =========================================================================
    %include "car.asm"
    ; Falls through to car_setup_done label

    ; =========================================================================
    ; Phase 2: Hardware Initialization (stack available via CAR)
    ; =========================================================================

    ; 2a. Detect chipset (reads PCI 0:0.0 Device ID)
    call    chipset_detect

    ; 2b. Initialize DRAM via Memory Reference Code
    cmp     byte [detected_chipset], CHIPSET_I440FX
    je      .mrc_440fx
    cmp     byte [detected_chipset], CHIPSET_Q35
    je      .mrc_q35

    ; Unknown chipset — skip MRC, hope DRAM works (QEMU fallback)
    mov     si, msg_chipset_unknown
    call    serial_print_early
    jmp     .mrc_done

.mrc_440fx:
    mov     si, msg_chipset_440fx
    call    serial_print_early
    call    mrc_init_440fx
    jmp     .mrc_done

.mrc_q35:
    mov     si, msg_chipset_q35
    call    serial_print_early
    call    mrc_init_q35
    jmp     .mrc_done

.mrc_done:
    ; 2c. Tear down CAR — move stack to real DRAM
    call    car_teardown

    ; 2d. Initialize PIC (8259A cascade mode)
    call    pic_init

    ; 2e. Initialize PIT (8254 system timer, 18.2 Hz)
    call    pit_init

    ; 2f. Initialize COM1 serial port for diagnostics
    call    serial_init

    ; =========================================================================
    ; Phase 3: Boot Banner
    ; =========================================================================
    mov     si, msg_banner
    call    serial_print
    call    vga_print

    ; =========================================================================
    ; Phase 4: Shadow ROM — Copy ROM to DRAM at 0xF0000, lock read-only
    ; =========================================================================
    %include "payload_call.asm"

    ; If payload_call returns (validation failed), halt
halt_system:
    mov     si, msg_halted
    call    serial_print
    call    vga_print
.loop:
    hlt
    jmp     .loop

; =============================================================================
; Early Serial Output (uses CAR stack — before full serial_init)
; Minimal: polls TX ready, sends character. Used before PIC/PIT are configured.
; =============================================================================
serial_print_early:
    push    si
    push    ax
    push    dx

    ; Quick COM1 setup: 115200 8N1 (same as serial_init but inline)
    ; Only done once — check if already initialized
    cmp     byte [serial_initialized], 1
    je      .early_loop

    ; Initialize COM1 at 115200 baud, 8N1
    mov     dx, COM1_PORT + 1
    xor     al, al
    out     dx, al              ; Disable interrupts

    mov     dx, COM1_PORT + 3
    mov     al, 0x80
    out     dx, al              ; Enable DLAB

    mov     dx, COM1_PORT + 0
    mov     al, 0x01
    out     dx, al              ; Divisor low = 1 (115200 baud)

    mov     dx, COM1_PORT + 1
    xor     al, al
    out     dx, al              ; Divisor high = 0

    mov     dx, COM1_PORT + 3
    mov     al, 0x03
    out     dx, al              ; 8N1, disable DLAB

    mov     dx, COM1_PORT + 2
    mov     al, 0xC7
    out     dx, al              ; Enable FIFO

    mov     dx, COM1_PORT + 4
    mov     al, 0x0B
    out     dx, al              ; DTR + RTS + OUT2

    mov     byte [serial_initialized], 1

.early_loop:
    lodsb
    test    al, al
    jz      .early_done
    cmp     al, 10
    jne     .early_send
    push    ax
    mov     al, 13
    call    serial_tx_char_early
    pop     ax
.early_send:
    call    serial_tx_char_early
    jmp     .early_loop
.early_done:
    pop     dx
    pop     ax
    pop     si
    ret

serial_tx_char_early:
    push    dx
    push    ax
    mov     ah, al
    mov     dx, COM1_PORT + 5
.wait:
    in      al, dx
    test    al, 0x20
    jz      .wait
    mov     al, ah
    mov     dx, COM1_PORT
    out     dx, al
    pop     ax
    pop     dx
    ret

; =============================================================================
; Full Serial (COM1) Driver Routines (used after Phase 2)
; =============================================================================
serial_init:
    ; Already initialized by serial_print_early, just mark ready
    mov     byte [serial_initialized], 1
    ret

serial_tx_char:
    push    dx
    push    ax
    mov     ah, al
    mov     dx, COM1_PORT + 5
.wait_empty:
    in      al, dx
    test    al, 0x20
    jz      .wait_empty
    mov     al, ah
    mov     dx, COM1_PORT
    out     dx, al
    pop     ax
    pop     dx
    ret

serial_print:
    push    si
    push    ax
.loop:
    lodsb
    test    al, al
    jz      .done
    cmp     al, 10
    jne     .send
    push    ax
    mov     al, 13
    call    serial_tx_char
    pop     ax
.send:
    call    serial_tx_char
    jmp     .loop
.done:
    pop     ax
    pop     si
    ret

; =============================================================================
; Direct VGA Text Buffer (0xB800:0000) Output Routines
; =============================================================================
vga_print:
    push    es
    push    si
    push    di
    push    ax
    push    bx

    ; Read cursor offset from RAM 0x0000:0x0500
    xor     ax, ax
    mov     es, ax
    mov     di, [es:0x0500]

    ; Point ES to VGA text segment
    mov     ax, VGA_TEXT_SEG
    mov     es, ax

.loop:
    lodsb
    test    al, al
    jz      .done

    cmp     al, 10
    je      .newline

    ; Write character + attribute (0x0F = white on black)
    mov     ah, 0x0F
    stosw
    jmp     .loop

.newline:
    mov     ax, di
    xor     dx, dx
    mov     bx, 160
    div     bx
    inc     ax
    mul     bx
    mov     di, ax
    jmp     .loop

.done:
    ; Save updated DI back to scratch RAM 0x0000:0x0500
    xor     ax, ax
    mov     es, ax
    mov     [es:0x0500], di

    pop     bx
    pop     ax
    pop     di
    pop     si
    pop     es
    ret

; =============================================================================
; Included Modules (Hardware Initialization)
; =============================================================================
; NOTE: car.asm is %included inline above (Phase 1) because it contains
;       a code block that must execute without stack.
;       All other modules are %included here as subroutine libraries.

%include "chipset.asm"
%include "mrc_440fx.asm"
%include "smbus.asm"
%include "mrc_q35.asm"
%include "pic.asm"
%include "pit.asm"

; =============================================================================
; Data / Strings (Stored in ROM)
; =============================================================================
serial_initialized  db 0

msg_banner          db "[IPO_Boot_ROM] Hardware initialized. Shadowing firmware...", 10, 0
msg_chipset_440fx   db "[IPO_Boot_ROM] Detected chipset: Intel i440FX (82441FX)", 10, 0
msg_chipset_q35     db "[IPO_Boot_ROM] Detected chipset: Intel Q35 (MCH)", 10, 0
msg_chipset_unknown db "[IPO_Boot_ROM] WARNING: Unknown chipset, skipping MRC", 10, 0
msg_copying         db "[IPO_Boot_ROM] Shadowing ROM segment 0xF000 to DRAM...", 10, 0
msg_shadow_ok       db "[IPO_Boot_ROM] Shadow RAM locked (read-only). PAM configured.", 10, 0
msg_fw_ok           db "[IPO_Boot_ROM] Firmware magic 'IPOF' validated. Jumping to 0xF000:0004", 10, 0
msg_fw_invalid      db "[IPO_Boot_ROM] ERROR: Firmware magic header mismatch!", 10, 0
msg_halted          db "[IPO_Boot_ROM] System halted.", 10, 0
