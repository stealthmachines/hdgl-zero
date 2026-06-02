[BITS 16]
[ORG 0x7C00]

COM1 equ 0x3F8
STAGE1_ADDR equ 0x7E00    ; Stage1 lands here
HDGL_RM_ADDR equ 0x9000   ; HDGL bytecode temp in real mode (36KB mark)
; After PM, Stage1 copies from 0x9000 to 0x110000

boot_entry:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7BF0
    sti
    mov [bdrv], dl

    call com1_init

    mov si, bm0
    call cprint

    ; Load Stage1: sectors 2-17 (CHS, 1-based) → 0x7E00
    ; That's file sectors 1-16 (0-based)
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [bdrv]
    mov bx, 0x7E00
    int 0x13
    jc .err

    ; Load HDGL bytecode: cyl=0, head=1, sectors 1-4 → ES:0x9000
    ; This is LBA 18-21 = file bytes 9216-10239
    mov ax, 0x0000
    mov es, ax
    mov ah, 0x02
    mov al, 4             ; 4 sectors
    mov ch, 0             ; cylinder 0
    mov cl, 1             ; sector 1 (1-based)
    mov dh, 1             ; head 1
    mov dl, [bdrv]
    mov bx, 0x9000
    int 0x13
    jc .err_bc

    ; Store HDGL load address for Stage1 to find
    mov word [0x7FF0], 0x9000   ; RM address of bytecode
    mov word [0x7FF2], 0x0000   ; segment

    mov si, bm1
    call cprint

    jmp 0x0000:0x7E00

.err:
    mov si, bmerr
    call cprint
.h: cli
    hlt
    jmp .h

.err_bc:
    ; Bytecode load failed - store 0 as indicator and continue
    mov word [0x7FF0], 0x0000
    mov si, bm_bc_err
    call cprint
    jmp 0x0000:0x7E00

com1_init:
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

cchar:
    push dx
    push ax
.w: mov dx, COM1+5
    in  al, dx
    test al, 0x20
    jz  .w
    pop ax
    mov dx, COM1
    out dx, al
    pop dx
    ret

cprint:
    pusha
.l: lodsb
    test al, al
    jz .d
    call cchar
    jmp .l
.d: popa
    ret

bdrv    db 0x00
bm0     db "[S0] HDGL boot. Loading Stage1+bytecode...",0x0D,0x0A,0
bm1     db "[S0] Loaded. JMP 0x7E00",0x0D,0x0A,0
bmerr   db "[S0] DISK ERROR (Stage1)",0x0D,0x0A,0
bm_bc_err db "[S0] Bytecode load failed (continuing)",0x0D,0x0A,0

times 510-($ - $$) db 0
dw 0xAA55
