[BITS 16]
[ORG 0x7E00]

OMEGA_BASE  equ 0x100000
OMEGA_SIZE  equ 64

STATE_INIT          equ 0
STATE_DISCOVERED    equ 1
STATE_CONFIGURED    equ 2
STATE_READY         equ 3
STATE_EXECUTED      equ 4

TYPE_ROOT           equ 0
TYPE_CPU            equ 1
TYPE_MEM            equ 2
TYPE_IO             equ 3
TYPE_COMPILER       equ 4
TYPE_RUNTIME        equ 5

TRANSFORM_CPUID         equ 0x00010000
TRANSFORM_E820          equ 0x00020000
TRANSFORM_PCI_WALK      equ 0x00030000
TRANSFORM_COMPILE_SELF  equ 0x00040000

%macro OMEGA_NODE 1
    (OMEGA_BASE + (%1) * OMEGA_SIZE)
%endmacro

; Node 0: ROOT
OMEGA_NODE(0):
    mov  edi, OMEGA_NODE(0)
    mov  dword [edi], 0
    mov  word  [edi + 8], TYPE_ROOT
    mov  dword [edi + 12], STATE_DISCOVERED

; Node 1: CPU
OMEGA_NODE(1):
    mov  edi, OMEGA_NODE(1)
    mov  dword [edi], 1
    mov  word  [edi + 8], TYPE_CPU
    mov  dword [edi + 12], STATE_EXECUTED
    mov  dword [edi + 24], OMEGA_BASE
    mov  dword [edi + 48], TRANSFORM_CPUID

; Node 2: MEM
OMEGA_NODE(2):
    mov  edi, OMEGA_NODE(2)
    mov  dword [edi], 2
    mov  word  [edi + 8], TYPE_MEM
    mov  dword [edi + 12], STATE_READY
    mov  dword [edi + 24], OMEGA_BASE
    mov  dword [edi + 48], TRANSFORM_E820

; Node 3: IO
OMEGA_NODE(3):
    mov  edi, OMEGA_NODE(3)
    mov  dword [edi], 3
    mov  word  [edi + 8], TYPE_IO
    mov  dword [edi + 12], STATE_CONFIGURED
    mov  dword [edi + 24], OMEGA_BASE
    mov  dword [edi + 48], TRANSFORM_PCI_WALK

; Node 4: COMPILER
OMEGA_NODE(4):
    mov  edi, OMEGA_NODE(4)
    mov  dword [edi], 4
    mov  word  [edi + 8], TYPE_COMPILER
    mov  dword [edi + 12], STATE_EXECUTED
    mov  dword [edi + 24], OMEGA_BASE
    mov  dword [edi + 48], TRANSFORM_COMPILE_SELF

; Runtime entry
runtime_entry:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7BF0
    
    ; Enable A20
    in   al, 0x92
    or   al, 0x02
    and  al, 0xFE
    out  0x92, al
    
    ; Zero Omega graph
    mov  edi, OMEGA_BASE
    mov  ecx, 4096 / 4
    xor  eax, eax
    rep  stosd
    
    ; Print message
    mov  esi, .msg_start
    call .print_string
    
    ; Halt
    .idle:
        hlt
        jmp .idle

.msg_start    db '[Native] Parser loaded, Omega graph initialized',13,10,0
.print_string:
    push ebx
    push edi
    push esi
.print_loop:
    mov  al, [esi]
    test al, al
    jz   .print_done
    mov  dx, 0x3F8
    out  dx, al
    inc  esi
    jmp .print_loop
.print_done:
    pop  esi
    pop  edi
    pop  ebx
    ret

times 510-($-$$) db 0
dw 0xAA55
