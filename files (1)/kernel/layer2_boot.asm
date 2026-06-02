; ================================================================
; Layer-2 Bootloader
; Transitional code between HDGL and full kernel
;
; This stage:
; 1. Copies layer2_kernel.asm to execution address
; 2. Transfers control via JMP
; 3. Can extend to load modules dynamically
; ================================================================

[BITS 16]
[ORG 0x110200]  ; Just after HDGL bytecode region

l2_boot_stub:
    cli
    pushad
    
    ; Setup minimal segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x110800
    
    ; The HDGL bytecode interpreter should JMP to us
    ; If we're here, assume control transfer completed
    call verify_handoff
    
    ; Jump to Layer-2 kernel
    jmp layer2_entry

verify_handoff:
    ; Check that Omega tree was created
    mov eax, [0x100000]
    test eax, eax
    jz .handoff_failed
    
    ; Check bytecode completed normally
    cmp byte [0x90000], 0x05  ; HALT opcode at end?
    jne .handoff_failed
    
    ; Success - proceed
    ret
    
.handoff_failed:
    ; Fallback to idle
    jmp l2_fallback

l2_fallback:
    mov esi, fallback_msg
    call print_string
    jmp idle_loop_fallback

; ================================================================
; Print Functions (same as kernel for compatibility)
; ================================================================

print_string:
    push esi
    push edi
    mov edi, 0xB8000
.loop:
    lodsb
    test al, al
    jz .done
    mov [edi], al
    mov [edi+1], 0x0720
    add edi, 2
    jmp .loop
.done:
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

idle_loop_fallback:
    hlt
    jmp idle_loop_fallback

; ================================================================
; Strings
; ================================================================

fallback_msg db "Layer-2: Handoff verification failed", 0
            db "Falling back to minimal idle...", 0

times 0x110FFF - ($ - $$) db 0
