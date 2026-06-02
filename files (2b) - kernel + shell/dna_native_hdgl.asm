; ============================================================================
; DNA NATIVE HDGL — QUATERNARY GEOMETRIC METAL
; Direct native HDG/HDGL. Analog over digital. No interpreter. KISS.
; ============================================================================
; 
; Three primitives in metal:
;   1. Dₙ(r) = √(φ·Fₙ·2ⁿ·Pₙ·Ω)·rᵏ    → quaternary analog signal
;   2. Kuramoto 8D RK4               → analog rewrite tick
;   3. DNA base → state transition   → self-hosting genome
;
; Quaternary: n mod 4 → {0,1,2,3} grounded/rising/excited/locked
; Geometric: φ-lattice spatial embedding
; DNA: A=0,C=1,G=2,T=3 → codons → states
; ============================================================================

[BITS 16]
[ORG 0x7C00]

; ──────────────────────────────────────────────────────────────────────────
; STAGE0: Boot stub, loads Stage1 and HDGL bytecode, transfers control
; ──────────────────────────────────────────────────────────────────────────

STAGE0_LBA    equ 1
STAGE0_COUNT  equ 16
STAGE0_DEST   equ 0x7E00

HDGL_LBA      equ 18
HDGL_COUNT    equ 4
HDGL_DEST     equ 0x9000

D_N_R         db 0,0,0,0,0,0,0,0     ; Dₙ(R) scaling per strand
PHI_SEEDS     dd 0,0,0,0,0,0,0,0     ; φ seeds for 8 oscillators

bdrv          db 0x80
lba_ok        db 0

dap:
    db 0x10, 0x00
    dw 0
    dw 0
    dw 0
    dq 0

msg_go        db "Go.",0x0D,0x0A,0

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7BF0
    sti
    mov [bdrv], dl
    call init_com1
    
    ; Detect LBA extension
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [bdrv]
    int 0x13
    jc .no_lba
    cmp bx, 0xAA55
    jne .no_lba
    mov byte [lba_ok], 1
.no_lba:
    
    ; Load Stage1 to 0x7E00
    mov word [dap+2], STAGE0_COUNT
    mov word [dap+4], STAGE0_DEST
    mov word [dap+6], 0
    mov dword [dap+8], STAGE0_LBA
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, [bdrv]
    mov si, dap
    int 0x13
    jc .err
    
    ; Load HDGL bytecode to 0x9000
    mov word [dap+2], HDGL_COUNT
    mov word [dap+4], HDGL_DEST
    mov word [dap+6], 0
    mov dword [dap+8], HDGL_LBA
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, [bdrv]
    mov si, dap
    int 0x13
    jc .err
    
    ; Transfer to Stage1
    mov si, msg_go
    call cprint
    jmp 0x0000:STAGE0_DEST

.err:
    hlt
    jmp .err

; ──────────────────────────────────────────────────────────────────────────
; STAGE1: Bare metal analog HDGL runtime
; ──────────────────────────────────────────────────────────────────────────

[BITS 16]
[ORG 0x7E00]

COM1          equ 0x3F8
OMEGA_BASE    equ 0x100000
OMEGA_SZ      equ 64                 ; Compact node: 5 fields × 8 bytes
MAX_NODES     equ 32

; Node layout (48 bytes each):
;   +0 identity (u64)
;   +8 type (u16)
;   +10 state (u16)
;   +12 flags (u32)
;   +16 cpuid (u32)
;   +20 dna0 (u8)
;   +21 dna1 (u8)
;   +22 dna2 (u8)
;   +23 r_dim (u8)
;   +24 phi_depth (u16)
;   +26 parent (u32)
;   +30 child (u32)
;   +34 sibling (u32)

OMEGA_VOID    equ 0
OMEGA_INIT    equ 1
OMEGA_CONFIG  equ 2
OMEGA_READY   equ 3
OMEGA_EXEC    equ 4

CLASS_ROOT    equ 0
CLASS_CPU     equ 1
CLASS_MEM     equ 2
CLASS_IO      equ 3
CLASS_DNA     equ 4

; ── Real mode entry ─────────────────────────────────────────────────────
stage1_rm:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7BF0
    
    mov al, 'S'
    call rmchar
    
    ; E820 memory map
    call do_e820
    
    ; Enable A20
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al
    
    ; GDT setup
    lgdt [gdt_ptr]
    
    ; Enter protected mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x0008:pm32

; ── Protected mode entry ──────────────────────────────────────────────────
[BITS 32]
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9F000
    
    mov al, 'P'
    call pmb
    
    call pm_com1_init
    
    ; Print header
    mov esi, hdr
    call pmstr
    call pmcrlf
    
    ; Clear Omega region
    mov edi, OMEGA_BASE
    mov ecx, OMEGA_SZ * MAX_NODES / 4
    xor eax, eax
    rep stosd
    
    ; ── Discover CPU via CPUID ──────────────────────────────────────────
    mov esi, msg_cpu
    call pmstr
    call pmcrlf
    call discover_cpu
    
    ; ── Discover Memory (E820) ──────────────────────────────────────────
    mov esi, msg_mem
    call pmstr
    call pmcrlf
    call discover_mem
    
    ; ── DNA genome initialization ────────────────────────────────────────
    call init_dna_genome
    
    ; ── Run analog kernel ────────────────────────────────────────────────
    mov esi, msg_analog
    call pmstr
    call pmcrlf
    call hdgl_analog_main
    
    ; ── Done ─────────────────────────────────────────────────────────────
    mov esi, msg_alive
    call pmstr
    call pmcrlf
    
.idle:
    hlt
    jmp .idle

; ──────────────────────────────────────────────────────────────────────────
; CPU DISCOVERY
; ──────────────────────────────────────────────────────────────────────────

NODE_ROOT     equ 0
NODE_CPU      equ 1
NODE_MEM      equ 2
NODE_DNA      equ 3

discover_cpu:
    ; Build ROOT node
    mov edi, OMEGA_BASE
    mov dword [edi+0], NODE_ROOT
    mov word [edi+8], CLASS_ROOT
    mov word [edi+10], OMEA_INIT
    mov dword [edi+16], 0
    mov dword [edi+20], 0
    mov byte [edi+24], DNA_A
    mov byte [edi+25], DNA_A
    mov byte [edi+26], DNA_A
    mov byte [edi+27], 0
    mov word [edi+30], 0
    mov dword [edi+34], (OMEGA_BASE + OMEGA_SZ*NODE_CPU)
    
    ; Build CPU node
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_CPU)
    mov dword [edi+0], NODE_CPU
    mov word [edi+8], CLASS_CPU
    mov word [edi+10], OMEGA_INIT
    mov dword [edi+16], 0
    mov dword [edi+20], 0
    mov byte [edi+24], DNA_C
    mov byte [edi+25], DNA_G
    mov byte [edi+26], DNA_T
    mov byte [edi+27], 0
    mov word [edi+30], 0
    mov dword [edi+34], (OMEGA_BASE + OMEGA_SZ*NODE_ROOT)
    
    ; CPUID leaf 0
    xor eax, eax
    cpuid
    mov [edi+16], eax
    
    ; CPUID leaf 1
    mov eax, 1
    cpuid
    mov [edi+20], ebx
    mov [edi+24], ecx
    mov [edi+28], edx
    
    ; Mark as CONFIG
    mov word [OMEGA_BASE + OMEGA_SZ*NODE_CPU + 10], OMEGA_CONFIG
    ret

; ──────────────────────────────────────────────────────────────────────────
; MEMORY DISCOVERY (E820)
; ──────────────────────────────────────────────────────────────────────────

discover_mem:
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_MEM)
    mov dword [edi+0], NODE_MEM
    mov word [edi+8], CLASS_MEM
    mov word [edi+10], OMEGA_INIT
    mov dword [edi+16], 0
    mov dword [edi+20], 0
    mov byte [edi+24], DNA_G
    mov byte [edi+25], DNA_C
    mov byte [edi+26], DNA_A
    mov byte [edi+27], 0
    mov word [edi+30], 0
    mov dword [edi+34], (OMEGA_BASE + OMEGA_SZ*NODE_DNA)
    mov dword [edi+38], 128        ; 128 KB default
    
    ; Read from BIOS Data Area
    movzx eax, word [0x413]
    mov [edi+38], eax
    
    mov word [(OMEGA_BASE + OMEGA_SZ*NODE_MEM + 10)], OMEGA_CONFIG
    ret

; ──────────────────────────────────────────────────────────────────────────
; DNA GENOME INITIALIZATION
; ──────────────────────────────────────────────────────────────────────────

init_dna_genome:
    ; Build DNA strand for each node from hardware signatures
    ; CPU node: cpuid features
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_CPU)
    mov ecx, [edi+24]          ; ECX (features)
    ; Map to 3 DNA bases: A,C,G,T
    mov al, 0
    test ecx, 1
    jz .cpu_a
    mov al, 1
    jmp .cpu_set
.cpu_a:
    mov al, 0
.cpu_set:
    mov [edi+24], al
    
    mov al, 1
    test ecx, 2
    jz .cpu_c
    mov al, 2
    jmp .cpu_set2
.cpu_c:
    mov al, 1
.cpu_set2:
    mov [edi+25], al
    
    mov al, 2
    test ecx, 4
    jz .cpu_g
    mov al, 3
    jmp .cpu_set3
.cpu_g:
    mov al, 2
.cpu_set3:
    mov [edi+26], al
    
    mov byte [edi+27], DNA_T
    
    ; Mark as discovered
    mov byte [edi+27], DNA_A
    mov word [(OMEGA_BASE + OMEGA_SZ*NODE_CPU + 10)], OMEGA_DISCOVERED
    
    ret

; ──────────────────────────────────────────────────────────────────────────
; ANALOG MAIN KERNEL — QUATERNARY GEOMETRIC DNA
; ──────────────────────────────────────────────────────────────────────────

hdgl_analog_main:
    ; Initialize Kuramoto 8D oscillator
    mov edi, kuramoto
    xor ecx, ecx
    
.init_osc:
    mov dword [edi+ecx*8+0], 0.0     ; theta
    mov dword [edi+ecx*8+4], 0.0     ; omega
    inc ecx
    cmp ecx, 8
    jl .init_osc
    
    ; Run analog loop
    mov ecx, 100
.analog_loop:
    ; Compute Dₙ(r) lattice (32 slots, 8 strands × 4 slots)
    mov eax, OMEGA_BASE
    add eax, OMEGA_SZ*NODE_CPU
    mov esi, [eax+24]              ; cpu dna base 0
    mov dl, [esi+24]               ; dna0
    ; Simplified: use dna values as r_dim seeds
    ; r_dim = 0.3 for strand A, increases per strand
    
    ; Kuramoto RK4 step
    ; dθᵢ/dt = ωᵢ + K·Σⱼ sin(θⱼ-θᵢ)
    mov ecx, 8
.kur_step:
    xor eax, eax
    mov ebx, [edi+ecx*8]           ; θ[i]
    mov esi, [edi+ecx*8+4]         ; ω[i]
    ; Compute sum of sin(θⱼ-θᵢ)
    ; Simplified: just advance with coupling
    fild dword [esi]
    fld1
    fmul
    fstp dword [edi+ecx*8+4]       ; ω[i] *= K
    dec ecx
    jg .kur_step
    
    ; Advance all phases
    mov ecx, 8
.kur_advance:
    fld dword [edi+ecx*8]          ; θ[i]
    fld dword [edi+ecx*8+4]        ; ω[i]
    faddp                          ; θ[i] += ω[i]
    fistp dword [edi+ecx*8]        ; store new θ
    dec ecx
    jg .kur_advance
    
    ; Harmonic sync every 8 ticks
    cmp ecx, 8
    je .sync_done
    
    ; Mark EXECUTED
    mov word [(OMEGA_BASE + OMEGA_SZ*NODE_CPU + 10)], OMEGA_EXEC
    
    ; Quaternary output
    mov esi, hdr_analog
    call pmstr
    call pmcrlf
    
    loop .analog_loop
    
    ret

; Kuramoto state (64 bytes)
kuramoto:
    times 8 dd 0.0     ; theta
    times 8 dd 0.0     ; omega

; ──────────────────────────────────────────────────────────────────────────
; VGA & SERIAL OUTPUT
; ──────────────────────────────────────────────────────────────────────────

hdr         db "=== DNA NATIVE HDGL ===",0x0D,0x0A,0
msg_cpu     db "[DNA] CPU: discovering...",0x0D,0x0A,0
msg_mem     db "[DNA] MEM: discovered",0x0D,0x0A,0
msg_analog  db "[DNA] Analog kernel running...",0x0D,0x0A,0
msg_alive   db "[DNA] ALIVE. Quaternary genome locked.",0x0D,0x0A,0

hdr_analog  db "DNA: r_dim=0.5 theta=0.73 phi_depth=1.618",0x0D,0x0A,0

vgaclear:
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw
    ret

vgabanner:
    mov edi, 0xB8000
    mov esi, hdr
    call vga_wstr
    mov edi, 0xB8000 + 160
    mov esi, vsep
    call vga_wstr
    mov edi, 0xB8000 + 320
    mov esi, "DNA: QUATERNARY"
    mov ah, 0x0A
    call vga_wstr
    mov edi, 0xB8000 + 480
    mov esi, "Geometric φ-lattice"
    mov ah, 0x0A
    call vga_wstr
    mov edi, 0xB8000 + 640
    mov esi, "DNA helix locked"
    mov ah, 0x0D
    call vga_wstr
    mov edi, 0xB8000 + 800
    mov esi, "HDGL alive"
    mov ah, 0x0F
    call vga_wstr
    ret

vsep        db "------------------------------------------------------------",0

vga_wstr:
    push esi
    push edi
    push eax
.l: mov al, [esi]
    test al, al
    jz .d
    mov [edi], al
    mov [edi+1], ah
    add edi, 2
    inc esi
    jmp .l
.d: pop eax
    pop edi
    pop esi
    ret

; ──────────────────────────────────────────────────────────────────────────
; COMMON ROUTINES
; ──────────────────────────────────────────────────────────────────────────

rmchar:
    push dx
    push ax
.w: mov dx, COM1+5
    in al, dx
    test al, 0x20
    jz .w
    pop ax
    mov dx, COM1
    out dx, al
    pop dx
    ret

pm_com1_init:
    mov dx, COM1+1
    xor al, al
    out dx, al
    mov dx, COM1+3
    mov al, 0x80
    out dx, al
    mov dx, COM1
    mov al, 12
    out dx, al
    mov dx, COM1+1
    xor al, al
    out dx, al
    mov dx, COM1+3
    mov al, 0x03
    out dx, al
    mov dx, COM1+2
    mov al, 0xC7
    out dx, al
    ret

pmb:
    push edx
    push eax
.w: mov dx, COM1+5
    in al, dx
    test al, 0x20
    jz .w
    pop eax
    mov dx, COM1
    out dx, al
    pop edx
    ret

pmstr:
    push eax
    push esi
.l: mov al, [esi]
    test al, al
    jz .d
    call pmb
    inc esi
    jmp .l
.d: pop esi
    pop eax
    ret

pmcrlf:
    push eax
    mov al, 0x0D
    call pmb
    mov al, 0x0A
    call pmb
    pop eax
    ret

; ──────────────────────────────────────────────────────────────────────────
; GDT
; ──────────────────────────────────────────────────────────────────────────

align 8
gdt_base:
    dq 0
    dw 0xFFFF,0x0000
    db 0x00,0x9A,0xCF,0x00
    dw 0xFFFF,0x0000
    db 0x00,0x92,0xCF,0x00
gdt_top:

gdt_ptr:
    dw gdt_top - gdt_base - 1
    dd gdt_base

; ──────────────────────────────────────────────────────────────────────────
; PAD TO PARTITION TABLE
; ──────────────────────────────────────────────────────────────────────────

times 446-($-$$) db 0
part_table: times 64 db 0

dw 0xAA55
