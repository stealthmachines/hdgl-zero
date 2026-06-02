; ================================================================
; HDGL Layer-2 Kernel
; Native extension for HDGL Universal Firmware v0.2
; 
; This kernel takes over after HDGL bytecode completes and
; provides a more sophisticated runtime environment.
;
; Handoff from HDGL:
;   - Register state preserved in EAX/EBX/ECX/EDX
;   - Omega tree pointer in [0x100000] (ROOT node address)
;   - Transition to Layer-2 at 0x200000
; ================================================================

[BITS 16]
[ORG 0x200000]

; Handoff stub from HDGL bytecode interpreter
layer2_entry:
    ; HDGL should have jumped here or we trap here
    cli
    pushad
    
    ; Setup initial state
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x208000
    
    ; Verify Omega tree pointer
    mov eax, [0x100000]
    test eax, eax
    jz .handoff_error
    
    ; Switch to protected mode
    lgdt [gdt_ptr]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    jmp 0x0008:l2_pm32

.handoff_error:
    mov ax, 0x0707
    mov [0x100000+10], ax  ; Set error state on ROOT
    ; Continue to minimal idle loop

align 16
gdt_base:
    dq 0
    dw 0xFFFF, 0x0000
    db 0x00, 0x9A, 0xCF, 0x00   ; Code 0x08
    dw 0xFFFF, 0x0000
    db 0x00, 0x92, 0xCF, 0x00   ; Data 0x10
gdt_top:

gdt_ptr:
    dw gdt_top - gdt_base - 1
    dd gdt_base

[BITS 32]
l2_pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x210000
    
    ; Print Layer-2 banner
    mov esi, l2_banner
    call print_string
    call crlf
    
    ; Verify handoff
    mov eax, [0x100000]
    mov ebx, [0x100000+28]  ; ROOT child should be CPU
    
    ; Initialize Layer-2 structures
    call l2_init
    
    ; Resume HDGL tree execution or start new tasks
    call l2_scheduler
    
idle_loop:
    hlt
    jmp idle_loop

; ================================================================
; Layer-2 Initialization
; ================================================================

l2_init:
    pushad
    
    ; Clear L2 memory region (0x200000 - 0x300000)
    mov edi, 0x200000
    mov ecx, 512          ; 4KB
    xor eax, eax
    rep stosd
    
    ; Setup task queue
    mov dword [0x208000], 0     ; head
    mov dword [0x208004], 0     ; tail
    
    ; Link CPU node from Omega tree (if valid)
    mov esi, [0x100000]
    test esi, esi
    jz .skip_cpu_link
    
    mov eax, [esi]            ; Get CPU node address
    ; Store pointer in L2 for later retrieval
    mov [0x208010], eax
    
.skip_cpu_link:
    popad
    ret

; ================================================================
; Simple Scheduler
; ================================================================

l2_scheduler:
    ; For now, just a placeholder
    ; In future: load tasks from Omega tree COMPILER node
    mov eax, 0
    ret

; ================================================================
; Print Functions
; ================================================================

print_string:
    push esi
    push edi
    mov edi, 0xB8000
.print_loop:
    lodsb
    test al, al
    jz .print_done
    mov [edi], al
    mov [edi+1], 0x0720
    add edi, 2
    jmp .print_loop
.print_done:
    pop edi
    pop esi
    ret

crlf:
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    ret

print_char:
    push eax
    mov dx, 0x3F8+5
    in  al, dx
    test al, 0x20
    jz .wait
    out 0x3F8, al
    pop eax
    ret

.wait:
    pop eax
    ret

; ================================================================
; Strings
; ================================================================

l2_banner db "HDGL Layer-2 Kernel Loaded", 0
l2_sub1   db "Omega tree pointer: 0x", 0
l2_sub2   db "Ready for task execution", 0

times 0x20FFFF - ($ - $$) db 0
