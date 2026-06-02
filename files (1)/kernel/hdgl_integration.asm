; ================================================================
; HDGL Integration Module
; Bridges Layer-2 with the existing HDGL Omega tree
; ================================================================

[BITS 16]
[ORG 0x202000]

; Function pointers table for HDGL operations
hdgl_ops_table dd load_node, get_node, mutate_node, recurse_node, halt_tree

hdgl_integrate:
    pushad
    
    ; Get ROOT node pointer from HDGL
    mov eax, [0x100000]
    test eax, eax
    jz .no_hdgltree
    
    ; Copy ROOT to Layer-2 namespace for reference
    mov [0x208030], eax
    
    ; Link Layer-2 structures to HDGL tree
    call link_layer2_to_hdgltree
    
    ; Setup callbacks from Layer-2 to HDGL
    call setup_hdgltree_callbacks
    
    popad
    ret
    
.no_hdgltree:
    ; HDGL didn't create a tree - minimal mode
    mov word [0x208040], 0    ; flag = minimal mode
    popad
    ret
    
.link_layer2_to_hdgltree:
    pushad
    
    ; Link Layer-2 task queue to HDGL COMPILER node
    mov esi, [0x208030]          ; ROOT
    mov eax, [esi+28]             ; Get child (CPU)
    ; Continue walking to find COMPILER...
    
    ; For simplicity, assume COMPILER is at index 4 in original plan
    mov esi, [0x100000 + 72*4]   ; Direct access if structure preserved
    
    ; Link Layer-2 scheduler to COMPILER
    mov [esi+36], 0x208000       ; Store task queue ptr in COMPILER
    
    popad
    ret
    
.setup_hdgltree_callbacks:
    pushad
    
    ; Store addresses of Layer-2 functions into HDGL callback table
    mov eax, load_node
    mov [hdgl_ops_table], eax
    mov eax, get_node
    mov [hdgl_ops_table+4], eax
    mov eax, mutate_node
    mov [hdgl_ops_table+8], eax
    mov eax, recurse_node
    mov [hdgl_ops_table+12], eax
    mov eax, halt_tree
    mov [hdgl_ops_table+16], eax
    
    popad
    ret

; ================================================================
; Layer-2 Functions (to be linked with kernel)
; ================================================================

load_node:
    ; Stub - will be implemented when full kernel loaded
    ret

get_node:
    ret

mutate_node:
    ret

recurse_node:
    ret

halt_tree:
    ret

; ================================================================
; Strings
; ================================================================

.integrate_msg db "HDGL Integration: Layer-2 connected", 0
.no_tree_msg   db "HDGL: No tree found - minimal mode", 0

times 0x2FFFFF - ($ - $$) db 0
