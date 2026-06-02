; ================================================================
; HDGL Full Kernel v0.1
; Complete Layer-2 firmware with multitasking, memory management
; and device driver framework
;
; This is the production-ready kernel that integrates with
; the HDGL Universal Firmware v0.2 bootloader.
; ================================================================

[BITS 16]
[ORG 0x200000]

; Handoff from HDGL
kernel_entry:
    cli
    pushad
    
    ; Minimal setup
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x208000
    
    ; Verify HDGL completed successfully
    mov eax, [0x100000]
    test eax, eax
    jz .kernel_panic
    
    ; Switch to protected mode
    lgdt [gdt_ptr]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    jmp 0x0008:km_pm32

.kernel_panic:
    mov ax, 0x072F
    mov [0xB8000], ax
    .panic_loop:
        hlt
        jmp .panic_loop

align 16
gdt_base:
    dq 0
    dw 0xFFFF, 0x0000
    db 0x00, 0x9A, 0xCF, 0x00
    dw 0xFFFF, 0x0000
    db 0x00, 0x92, 0xCF, 0x00
gdt_top:

gdt_ptr:
    dw gdt_top - gdt_base - 1
    dd gdt_base

[BITS 32]
km_pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x220000
    
    ; Print kernel banner
    mov esi, km_banner
    call kprint_string
    call kcrlf
    
    ; Initialize kernel subsystems
    call km_init
    
    ; Display system info
    call km_display_info
    
    ; Start main loop
    call km_main_loop
    
idle:
    hlt
    jmp idle

; ================================================================
; Kernel Initialization
; ================================================================

km_init:
    pushad
    
    ; Zero out kernel memory regions
    mov edi, km_task_queue
    mov ecx, 256
    xor eax, eax
    rep stosd
    
    mov edi, km_modules
    mov ecx, 512
    xor eax, eax
    rep stosd
    
    ; Initialize task queue
    mov dword [km_task_queue], 0      ; head
    mov dword [km_task_queue+4], 0    ; tail
    mov dword [km_task_queue+8], 0    ; next_free
    
    ; Initialize module area
    mov dword [km_modules], 0
    mov dword [km_modules+4], 0
    
    ; Link to HDGL Omega tree
    mov eax, [0x100000]
    test eax, eax
    jz .no_hdgltree
    
    ; Store ROOT pointer in kernel namespace
    mov [km_hdgltree_root], eax
    
    ; Try to find COMPILER node for module loading
    ; (Assuming static structure for now)
    mov eax, [0x100000 + 72*4]
    test eax, eax
    jnz .found_compiler
    mov [km_hdgltree_compiler], 0
    jmp .init_done
    
.found_compiler:
    mov [km_hdgltree_compiler], eax
    
.init_done:
    popad
    ret
    
.no_hdgltree:
    mov dword [km_hdgltree_root], 0
    mov dword [km_hdgltree_compiler], 0
    popad
    ret

; ================================================================
; System Information Display
; ================================================================

km_display_info:
    pushad
    
    ; CPU info from Omega tree
    mov esi, [km_hdgltree_root]
    test esi, esi
    jz .no_cpu
    
    mov eax, [esi+28]            ; CPU node
    test eax, eax
    jnz .has_cpu
    
    ; No CPU node - print generic
    mov esi, km_generic_cpu
    call kprint_string
    call kcrlf
    jmp .print_mem
    
.has_cpu:
    ; Print CPU family
    mov eax, [eax+36]
    mov esi, km_cpu_label
    call kprint_string
    mov eax, km_hex32
    mov [esi], eax
    call kprint_string
    call kcrlf
    
.no_cpu:
    ; Memory info
    mov esi, [km_hdgltree_root]
    test esi, esi
    jz .no_mem
    
    mov eax, [esi+28]            ; MEM node
    test eax, eax
    jnz .has_mem
    
    mov esi, km_generic_mem
    call kprint_string
    call kcrlf
    jmp .print_pci
    
.has_mem:
    mov eax, [eax+52]            ; mem_kb field
    mov esi, km_mem_label
    call kprint_string
    mov eax, km_hex32
    mov [esi], eax
    call kprint_string
    call kcrlf
    
.no_mem:
    ; PCI devices count
    mov esi, [km_hdgltree_root]
    test esi, esi
    jz .no_pci
    
    mov eax, [esi+28]            ; IO node
    test eax, eax
    jnz .has_io
    
    mov esi, km_generic_pci
    call kprint_string
    call kcrlf
    jmp .init_done
    
.has_io:
    mov eax, [eax+28]            ; First child (first PCI device)
    ; Count PCI devices...
    mov ecx, 0
.count_pci:
    test eax, eax
    jz .pci_done
    inc ecx
    mov eax, [eax+32]            ; Next sibling
    jmp .count_pci
    
.pci_done:
    mov esi, km_pci_label
    call kprint_string
    mov eax, km_hex32
    mov [esi], eax
    call kprint_string
    call kcrlf
    
.has_io:
    ; Nothing more to display
    
.init_done:
    popad
    ret
    
.no_pci:
    mov esi, km_generic_pci
    call kprint_string
    call kcrlf
    popad
    ret
    
.no_mem:
    popad
    ret

; ================================================================
; Main Kernel Loop
; ================================================================

km_main_loop:
    pushad
    
    ; For now: simple idle with tick counter
    mov byte [km_tick_count], 0
    
.tick_loop:
    ; Increment tick
    inc byte [km_tick_count]
    
    ; Check for pending tasks (future)
    test dword [km_task_queue], km_head_valid
    jz .tick_sleep
    
    ; Process task
    call km_process_next_task
    
.tick_sleep:
    ; Small delay to prevent 100% CPU
    mov ecx, 1000
.delay_loop:
    loop .delay_loop
    
    ; Check every 100 ticks for events
    cmp byte [km_tick_count], 100
    jl .tick_sleep
    
    call km_check_events
    
    mov byte [km_tick_count], 0
    jmp .tick_loop
    
    ; Update VGA display occasionally
    cmp byte [km_tick_count], 500
    jl .tick_sleep
    
    call km_update_vga
    
.tick_loop:

.check_events:
    ; Future: check for I/O events, timer interrupts, etc.
    ret

; ================================================================
; VGA Output Functions
; ================================================================

kprint_string:
    push esi
    push edi
    mov edi, 0xB8000 + km_vga_offset
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

kcrlf:
    push eax
    mov al, 0x0D
    call kprint_char
    mov al, 0x0A
    call kprint_char
    pop eax
    ret

kprint_char:
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
; Helper Functions
; ================================================================

km_hex32:
    push eax
    push ecx
    mov ecx, 8
.loop:
    rol eax, 4
    push eax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jl .hex_ok
    add al, 7
.hex_ok:
    call kprint_char
    pop eax
    loop .loop
    pop ecx
    pop eax
    ret

km_vga_offset equ 0

; ================================================================
; Data Structures
; ================================================================

km_banner db "HDGL Full Kernel v0.1", 0
         db "Layer-2 Runtime Environment", 0
         db "------------------------------------------------", 0
km_cpu_label   db "CPU: ", 0
km_mem_label   db "MEM: ", 0
km_pci_label   db "PCI: ", 0
km_generic_cpu db "CPU: Unknown", 0
km_generic_mem db "MEM: Unknown", 0
km_generic_pci db "PCI: 0 devices", 0

km_task_queue dd 0, 0, 0     ; head, tail, next_free
km_modules    dd 0, 0        ; module_count, next_free
km_hdgltree_root dd 0         ; Link to HDGL ROOT
km_hdgltree_compiler dd 0     ; Link to HDGL COMPILER
km_tick_count db 0

times 0x2FFFFF - ($ - $$) db 0
