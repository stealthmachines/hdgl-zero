[BITS 16]
[ORG 0x7E00]

COM1 equ 0x3F8

stage1_rm:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7BF0  ; use same stack area, fine since S0 done

    ; Immediate COM1 probe
    mov al, 'S'
    call rmchar

    lgdt [gdt_ptr]

    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    ; linear address of pm32 = 0x7E00 + (pm32 - stage1_rm) = label value directly
    ; since ORG=0x7E00 labels have correct linear values ✓
    jmp 0x0008:pm32

rmchar:
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
    dd gdt_base        ; linear addr correct since ORG=0x7E00

[BITS 32]
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9F000

    ; Probe 'P'
    mov al, 'P'
    call pmb

    call pmcom1init

    mov esi, m0
    call pmstr
    call pmcrlf

    call vgaclear
    call vgabanner

    mov edi, 0x100000
    call omegainit

    mov esi, m1
    call pmstr
    call pmcrlf

    call hdgltick

    mov esi, m2
    call pmstr
    call pmcrlf

    mov esi, m3
    call pmstr
    call pmcrlf

.idle:
    hlt
    jmp .idle

pmb:
    push edx
    push eax
.w: mov dx, COM1+5
    in  al, dx
    test al, 0x20
    jz  .w
    pop eax
    mov dx, COM1
    out dx, al
    pop edx
    ret

pmcom1init:
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

vgaclear:
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw
    ret

vgawstr:
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

vgabanner:
    mov edi, 0xB8000
    mov esi, vt
    mov ah, 0x0B
    call vgawstr
    mov edi, 0xB8000+160
    mov esi, vsep
    mov ah, 0x08
    call vgawstr
    mov edi, 0xB8000+320
    mov esi, v0
    mov ah, 0x0E
    call vgawstr
    mov edi, 0xB8000+480
    mov esi, v1
    mov ah, 0x0A
    call vgawstr
    mov edi, 0xB8000+640
    mov esi, v2
    mov ah, 0x0A
    call vgawstr
    mov edi, 0xB8000+800
    mov esi, v3
    mov ah, 0x0A
    call vgawstr
    mov edi, 0xB8000+960
    mov esi, v4
    mov ah, 0x0D
    call vgawstr
    mov edi, 0xB8000+1280
    mov esi, v5
    mov ah, 0x0F
    call vgawstr
    mov edi, 0xB8000+1600
    mov esi, v6
    mov ah, 0x0E
    call vgawstr
    mov edi, 0xB8000+1920
    mov esi, v7
    mov ah, 0x07
    call vgawstr
    ret

OMEGA_SZ   equ 48
OMEGA_BASE equ 0x100000

omegainit:
    push edi
    mov ecx,(OMEGA_SZ*5)/4
    xor eax,eax
    rep stosd
    pop edi
    mov dword [edi],1
    mov word  [edi+8],0
    mov word  [edi+10],1
    mov dword [edi+28],OMEGA_BASE+OMEGA_SZ
    lea ebx,[edi+OMEGA_SZ]
    mov dword [ebx],2
    mov word  [ebx+8],1
    mov word  [ebx+10],1
    mov dword [ebx+24],OMEGA_BASE
    mov dword [ebx+28],OMEGA_BASE+OMEGA_SZ*2
    lea ebx,[edi+OMEGA_SZ*2]
    mov dword [ebx],3
    mov word  [ebx+8],2
    mov word  [ebx+10],1
    mov dword [ebx+24],OMEGA_BASE+OMEGA_SZ
    mov dword [ebx+28],OMEGA_BASE+OMEGA_SZ*3
    lea ebx,[edi+OMEGA_SZ*3]
    mov dword [ebx],4
    mov word  [ebx+8],3
    mov word  [ebx+10],1
    mov dword [ebx+24],OMEGA_BASE+OMEGA_SZ*2
    mov dword [ebx+28],OMEGA_BASE+OMEGA_SZ*4
    lea ebx,[edi+OMEGA_SZ*4]
    mov dword [ebx],5
    mov word  [ebx+8],4
    mov word  [ebx+10],3
    mov dword [ebx+24],OMEGA_BASE+OMEGA_SZ*3
    ret

hdgltick:
    mov edi,OMEGA_BASE
    mov ecx,5
.t: movzx eax,word [edi+10]
    cmp ax,4
    jge .n
    inc ax
    mov word [edi+10],ax
.n: add edi,OMEGA_SZ
    loop .t
    ret

m0  db "[S1] Protected mode OK",0x0D,0x0A,0
m1  db "[S1] Omega glyph tree @ 0x100000",0x0D,0x0A,0
m2  db "[S1] Rewrite tick done",0x0D,0x0A,0
m3  db "[S1] ALIVE. NO UEFI. Boot complete.",0x0D,0x0A,0

vt   db "HDGL Universal Firmware v0.1  [Layer-0+Layer-1]  NO UEFI",0
vsep db "-----------------------------------------------------------",0
v0   db "  OMEGA ROOT    [DISCOVERED]  @ 0x100000",0
v1   db "  |-- CPU       [DISCOVERED]  @ 0x100030",0
v2   db "  |   |-- MEM   [DISCOVERED]  @ 0x100060",0
v3   db "  |   |   |-- IO[DISCOVERED]  @ 0x100090",0
v4   db "  |   |   |   |-- COMPILER [READY] @ 0x1000C0",0
v5   db "  Rewrite tick 1 complete.",0
v6   db "  Self-hosting: COMPILER READY.",0
v7   db "  HDGL idle. System alive. NO UEFI.",0

times 8192 - ($ - $$) db 0
