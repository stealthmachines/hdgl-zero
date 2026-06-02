[BITS 16]
[ORG 0x7C00]

STAGE1_LBA   equ 1
STAGE1_COUNT equ 16
STAGE1_DEST  equ 0x7E00
HDGL_LBA     equ 18
HDGL_COUNT   equ 4
HDGL_DEST    equ 0x9000

    jmp short start
    nop

; ── Data at known offsets ─────────────────────────────────────
bdrv   db 0x80
lba_ok db 0

align 4
dap:
    db 0x10, 0x00
    dw 0                ; sector count
    dw 0                ; buffer offset
    dw 0                ; buffer segment
    dq 0                ; LBA

msg_s1  db "[S0]S1",0
msg_bc  db "BC",0
msg_ok  db "OK",0x0D,0x0A,0
msg_err db "ERR",0x0D,0x0A,0
msg_go  db "Go.",0x0D,0x0A,0

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

    ; Detect LBA
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [bdrv]
    int 0x13
    jc  .no_lba
    cmp bx, 0xAA55
    jne .no_lba
    mov byte [lba_ok], 1
.no_lba:

    ; Load Stage1
    mov si, msg_s1
    call cprint
    call load_s1
    jc  .err

    ; Load bytecode
    mov si, msg_bc
    call cprint
    call load_bc
    jnc .bc_ok
    mov word [0x7FF0], 0
    jmp .launch
.bc_ok:
    mov word [0x7FF0], HDGL_DEST
    mov word [0x7FF2], 0

.launch:
    mov si, msg_go
    call cprint
    jmp 0x0000:STAGE1_DEST

.err:
    mov si, msg_err
    call cprint
.halt: cli
    hlt
    jmp .halt

; ── load_s1: LBA 1-16 → 0x7E00 ───────────────────────────────
load_s1:
    cmp byte [lba_ok], 0
    je  .chs
    mov word [dap+2], STAGE1_COUNT
    mov word [dap+4], STAGE1_DEST
    mov word [dap+6], 0
    mov dword [dap+8],  STAGE1_LBA
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, [bdrv]
    mov si, dap
    int 0x13
    ret
.chs:
    mov ah, 0x02
    mov al, STAGE1_COUNT
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [bdrv]
    mov bx, STAGE1_DEST
    int 0x13
    ret

; ── load_bc: LBA 18-21 → 0x9000 ──────────────────────────────
load_bc:
    cmp byte [lba_ok], 0
    je  .chs
    mov word [dap+2], HDGL_COUNT
    mov word [dap+4], HDGL_DEST
    mov word [dap+6], 0
    mov dword [dap+8],  HDGL_LBA
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, [bdrv]
    mov si, dap
    int 0x13
    ret
.chs:
    mov ah, 0x02
    mov al, HDGL_COUNT
    mov ch, 0
    mov cl, 1
    mov dh, 1
    mov dl, [bdrv]
    mov bx, HDGL_DEST
    int 0x13
    ret

; ── COM1 ──────────────────────────────────────────────────────
init_com1:
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, 12
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al
    ret

cchar:
    push dx
    push ax
.w: mov dx, 0x3FD
    in  al, dx
    test al, 0x20
    jz  .w
    pop ax
    mov dx, 0x3F8
    out dx, al
    pop dx
    ret

cprint:
    pusha
.l: lodsb
    test al, al
    jz  .d
    call cchar
    jmp .l
.d: popa
    ret

; ── Partition table placeholder (will be filled by Python) ────
times 446-($ - $$) db 0     ; pad to partition table offset

; 4 × 16-byte entries (filled externally or left as zeros)
part_table times 64 db 0

dw 0xAA55
