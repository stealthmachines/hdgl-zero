[BITS 16]
[ORG 0x7C00]

COM1 equ 0x3F8

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

    ; CHS read: sectors 2..17 (1-based), cyl=0, head=0
    ; loads 16 sectors (8192 bytes) to 0x7E00
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 2           ; sector 2 (sector numbers are 1-based; MBR=1)
    mov dh, 0
    mov dl, [bdrv]
    mov bx, 0x7E00
    int 0x13
    jc  .err

    mov si, bm1
    call cprint

    jmp 0x0000:0x7E00

.err:
    mov si, bmerr
    call cprint
.h: cli
    hlt
    jmp .h

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

bdrv  db 0x00
bm0   db "[S0] Booting HDGL. Loading Stage1...",0x0D,0x0A,0
bm1   db "[S0] Stage1 loaded. JMP 0x7E00",0x0D,0x0A,0
bmerr db "[S0] DISK ERROR",0x0D,0x0A,0

times 510-($ - $$) db 0
dw 0xAA55
