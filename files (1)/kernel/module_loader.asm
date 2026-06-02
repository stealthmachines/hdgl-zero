; ================================================================
; Dynamic Module Loader for Layer-2
; Loads kernel modules from disk at runtime
; ================================================================

[BITS 16]
[ORG 0x201000]

mod_loader_entry:
    pushad
    
    ; Initialize loader state
    mov word [0x208020], 0     ; module_count = 0
    mov word [0x208022], 0     ; next_free = 0
    
    ; For now: load a simple test module
    call load_test_module
    
    popad
    ret

load_test_module:
    pushad
    
    ; Test module descriptor (stored in kernel memory)
    test_module db "test_module", 0
    test_module_magic dw 0x2002
    test_module_size dw 256
    test_module_entry dw 0x210000
    
    ; Verify we have space
    mov ax, [0x208022]
    cmp ax, 512        ; Module area limit
    jge .no_space
    
    ; Allocate module space
    mov ax, [0x208022]
    mov word [0x208020], ax  ; Increment count
    mov word [0x208022], ax + test_module_size
    
    ; Copy module code to allocated space
    mov si, test_module_code
    mov di, [0x208020]
    mov cx, test_module_size
    rep movsb
    
    ; Mark as loaded
    mov byte [di-1], 0xFF    ; End marker
    
    popad
    ret
    
.no_space:
    popad
    ret 0xFFFFFFFF  ; Error code

test_module_code:
    ; Simple test: print "Module loaded!" and return
    ; This would be x86 code that the Layer-2 runtime executes
    nop
    nop
    ; ... module code would go here
    ; For now, just placeholder
    nop
    nop
    nop
    nop
    
times 0x2FFFFF - ($ - $$) db 0
