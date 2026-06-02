; ================================================================
; Kernel Test Harness
; Validates Layer-2 kernel integration with HDGL
; ================================================================

[BITS 16]
[ORG 0x203000]

test_entry:
    cli
    pushad
    
    ; Minimal setup
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x208000
    
    call test_hdgltree
    call test_memory
    call test_hardware
    call test_omega_walk
    
    ; All tests done
    mov esi, test_complete_msg
    call print_string
    
    jmp test_idle

test_hdgltree:
    pushad
    mov esi, test_hdgltree_msg
    call print_string
    
    mov eax, [0x100000]
    test eax, eax
    jz .fail_tree
    
    mov eax, [eax+8]
    cmp eax, 0         ; Should be ROOT class
    jne .fail_tree
    
    mov eax, [eax+10]
    cmp eax, 2         ; Should be DISCOVERED
    jne .fail_tree
    
    mov esi, test_hdgltree_ok
    call print_string
    call crlf
    jmp .pass_tree
    
.fail_tree:
    mov esi, test_hdgltree_fail
    call print_string
    jmp .pass_tree  ; Don't fail entirely
    
.pass_tree:
    popad
    ret

test_memory:
    pushad
    mov esi, test_mem_msg
    call print_string
    
    ; Check if memory was discovered
    mov esi, [0x100000]
    test esi, esi
    jz .fail_mem
    
    mov eax, [esi+28]        ; MEM node
    test eax, eax
    jnz .check_mem_size
    
    mov esi, test_mem_fail
    call print_string
    jmp .pass_mem
    
.check_mem_size:
    mov eax, [eax+52]        ; mem_kb
    cmp eax, 64              ; Minimum 64MB
    jl .fail_mem
    
    mov esi, test_mem_ok
    call print_string
    call crlf
    
.pass_mem:
    popad
    ret

test_hardware:
    pushad
    mov esi, test_hw_msg
    call print_string
    
    ; Check PCI scan completed
    mov esi, [0x100000]
    test esi, esi
    jz .fail_hw
    
    mov eax, [esi+28]        ; IO node
    test eax, eax
    jnz .check_pci
    
    mov esi, test_hw_fail
    call print_string
    jmp .pass_hw
    
.check_pci:
    mov ecx, 0
    mov eax, [eax+28]        ; First child
    
.check_pci_count:
    test eax, eax
    jz .print_pci_count
    
    inc ecx
    mov eax, [eax+32]        ; Next sibling
    jmp .check_pci_count
    
.print_pci_count:
    mov esi, test_pci_msg
    call print_string
    mov eax, km_hex32
    mov [esi], ecx
    call km_hex32
    mov esi, test_pci_count_msg
    call print_string
    call crlf
    
.pass_hw:
    popad
    ret

test_omega_walk:
    pushad
    mov esi, test_walk_msg
    call print_string
    
    ; Walk ROOT -> CPU -> MEM chain
    mov esi, [0x100000]
    test esi, esi
    jz .fail_walk
    
.walk_chain:
    mov ecx, 0
    mov eax, esi
    
    .check_node:
        test eax, eax
        jz .walk_done
        
        mov edx, [eax+8]      ; Class
        .print_class:
            cmp edx, 0
            jz .class_root
            cmp edx, 1
            jz .class_cpu
            cmp edx, 2
            jz .class_mem
            jmp .unknown_class
            
        .class_root:
            inc ecx
            mov esi, "ROOT"
            jmp .print_node_name
            
        .class_cpu:
            inc ecx
            mov esi, "CPU"
            jmp .print_node_name
            
        .class_mem:
            inc ecx
            mov esi, "MEM"
            jmp .print_node_name
            
        .unknown_class:
            inc ecx
            mov esi, "???"
            
        .print_node_name:
            push esi
            mov edi, 0xB8000 + 0x7000
            mov ah, 0x0A
            call print_vga_string
            pop esi
            
            ; Move to next
            mov eax, [eax+32]  ; Sibling
            mov esi, [eax+28]  ; Parent
            jmp .check_node
            
.walk_done:
    call crlf
    mov esi, test_walk_ok
    call print_string
    call crlf
    
.fail_walk:
    mov esi, test_walk_fail
    call print_string
    
.pass_walk:
    popad
    ret

test_idle:
hlt_loop:
    hlt
    jmp hlt_loop

; ================================================================
; Test Messages
; ================================================================

test_hdgltree_msg db "[TEST] HDGL Tree Structure: ", 0
test_hdgltree_ok  db "OK - ROOT node valid", 0x0D, 0x0A, 0
test_hdgltree_fail db "FAIL - Invalid tree", 0x0D, 0x0A, 0

test_mem_msg db "[TEST] Memory Discovery: ", 0
test_mem_ok  db "OK - Memory detected", 0x0D, 0x0A, 0
test_mem_fail db "FAIL - No memory info", 0x0D, 0x0A, 0

test_hw_msg db "[TEST] Hardware Scan: ", 0
test_pci_msg db "  PCI devices found: "
test_pci_count_msg db " devices", 0x0D, 0x0A, 0
test_hw_fail db "FAIL - No hardware data", 0x0D, 0x0A, 0

test_walk_msg db "[TEST] Omega Walk Test: ", 0
test_walk_ok  db "OK - Chain traversal working", 0x0D, 0x0A, 0
test_walk_fail db "FAIL - Could not traverse", 0x0D, 0x0A, 0

test_complete_msg db "======================================", 0
                db "All tests completed!", 0x0D, 0x0A, 0
                db "======================================", 0x0D, 0x0A, 0

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

print_vga_string:
    push esi
    push edi
    mov edi, es:[di]
    ; VGA text mode already set up by caller
    ret

print_hex32:
    ; Placeholder for hex printing
    ret

times 0x2FFFFF - ($ - $$) db 0
