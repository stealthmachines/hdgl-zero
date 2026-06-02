; ================================================================
; HDGL Native Shell v0.1
; Minimal interactive terminal for Layer-2 Runtime
; ================================================================

[BITS 16]
[ORG 0x204000]

shell_entry:
    cli
    pushad
    
    ; Setup
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x208000
    
    call shell_init
    jmp shell_loop

shell_init:
    pushad
    
    ; Initialize command history
    mov dword [0x208050], 0      ; history_head
    mov dword [0x208054], 0      ; history_tail
    mov byte [0x208058], 0       ; history_count = 0
    
    ; Initialize command buffer
    mov byte [0x208060], 0       ; cmd_len = 0
    
    ; Clear prompt display area
    mov edi, 0xB8000 + shell_prompt_offset
    mov ax, 0x2407  ; Blue on gray
    mov ecx, 80
    rep stosw
    
    ; Print welcome message
    mov esi, shell_welcome
    call print_string
    call crlf
    mov esi, shell_version
    call print_string
    call crlf
    
    ; Print prompt
    mov esi, shell_prompt
    call print_string
    
    popad
    ret

shell_loop:
    pushad
    
    ; Display prompt and buffer
    mov esi, shell_prompt
    call print_string
    
    mov ax, [0x208060]
    mov cx, ax
    mov edi, 0xB8000 + shell_buffer_offset
.print_buffer:
    lodsb
    mov [edi], al
    mov [edi+1], 0x0720  ; White on black
    add edi, 2
    loop .print_buffer
    
    ; Display cursor
    mov al, 0x07
    mov byte [edi], 0x07
    add edi, 1
    
    ; Read input
    call read_input
    
    ; Get command
    mov ax, [0x208060]
    call execute_command
    
    ; Clear buffer
    mov ax, [0x208060]
    mov word [0x208060], 0
    
    ; Echo newline if command was executed
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    
    ; Display prompt again
    mov esi, shell_prompt
    call print_string
    
    popad
    ret

; ================================================================
; Input Handling
; ================================================================

read_input:
    pushad
    
    mov byte [0x208060], 0   ; Clear buffer length
    xor di, di                ; Clear buffer
    
.read_loop:
    pushad
    
    ; Wait for key
    mov dx, 0x3F8+5
    in  al, dx
    test al, 0x20
    jz .read_loop
    
    popad
    
    test al, 0x01
    jz .got_key
    
    ; Ctrl+C - abort
    cmp al, 0x03
    je .abort
    
    ; Ctrl+D - EOF
    cmp al, 0x15
    je .eof
    
    .got_key:
    ; Print character back
    mov dx, 0x3F8
    out dx, al
    
    ; Store in buffer
    mov cl, di
    mov ch, 0
    mov [buffer_addr+cx], al
    inc byte [0x208060]
    
    ; Move cursor
    mov edi, 0xB8000 + shell_buffer_offset
    add edi, cx*2
    
    mov al, al
    mov [edi], al
    mov [edi+1], 0x0720
    
    ; If Enter, save command and return
    cmp al, 0x0D
    je .return
    
    ; If Backspace
    cmp al, 0x08
    je .backspace
    
    ; If Ctrl+L - clear screen
    cmp al, 'l'
    jc .not_lower
    cmp al, 'L'
    jz .clear_screen
    
.not_lower:
    ; Normal character (ignore for now, or could add lowercase)
    
    popad
    jmp .read_loop
    
.clear_screen:
    mov edi, 0xB8000
    mov ax, 0x0720
    mov ecx, 80*25
    rep stosw
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    jmp .read_loop
    
.abort:
    mov al, 0x03
    ret 0x03
    
.eof:
    mov al, 0x15
    ret 0x15
    
.return:
    popad
    ret

.backspace:
    dec word [0x208060]
    mov di, byte [0x208060]
    mov edi, 0xB8000 + shell_buffer_offset
    sub edi, di*2
    
    ; Clear from cursor back
    mov al, ' '
    mov [edi], al
    mov [edi+1], 0x0720
    
    ; Move cursor back
    sub edi, 2
    
    ; Handle home position
    cmp di, 0
    jb .read_loop
    
    popad
    jmp .read_loop

; ================================================================
; Command Execution
; ================================================================

execute_command:
    pushad
    
    ; Read command from buffer
    mov esi, buffer_addr
    mov cx, [0x208060]
    
    ; Find command in table
    mov edi, shell_commands
    mov byte [0x208070], 0   ; Command found flag
    
.command_loop:
    movzx eax, word [edi]    ; opcode
    test eax, eax
    jz .no_command
    
    movzx edx, byte [edi+2]  ; arg offset
    movzx ebx, cx           ; Copy command length
    
    ; Compare with buffer
    mov edi, buffer_addr
    mov cl, edx
    cmp cx, ebx
    jne .next_command
    
    ; Match found!
    mov byte [0x208070], 1
    movzx eax, word [edi+4]  ; Get function pointer
    popad
    call [eax]
    jmp .done
    
.next_command:
    add edi, 3  ; opcode, arg, function
    inc byte [0x208070]
    jmp .command_loop
    
.no_command:
    popad
    mov esi, shell_unknown
    call print_string
    call crlf
    ret
    
.done:
    test byte [0x208070], 1
    jz .done_no_cmd
    
    popad
    ret
    
.done_no_cmd:
    mov byte [0x208070], 0
    popad
    ret

; ================================================================
; Command Table
; ================================================================

shell_commands:
    ; Format: [opcode, arg, function_ptr]
    dw CMD_HELP, 0, handle_help
    dw CMD_ECHO, 1, handle_echo
    dw CMD_MEM, 0, handle_mem
    dw CMD_CPU, 0, handle_cpu
    dw CMD_PCI, 0, handle_pci
    dw CMD_TREE, 0, handle_tree
    dw CMD_CLEAR, 0, handle_clear
    dw CMD_EXIT, 0, handle_exit
    dw CMD_VERSION, 0, handle_version
    dw 0, 0, 0

; ================================================================
; Command Handlers
; ================================================================

handle_help:
    mov esi, help_msg
    call print_string
    call crlf
    call crlf
    mov esi, help_commands
    call print_string
    call crlf
    ret

handle_echo:
    pushad
    movzx eax, word [si+2]  ; Arg from table
    test eax, eax
    jz .echo_rest
    
    mov esi, [si+6]         ; Arg value
    call print_string
    jmp .echo_done
    
.echo_rest:
    ; Echo rest of command
    mov esi, buffer_addr
    mov cx, [0x208060]
    call print_string
    
.echo_done:
    popad
    ret

handle_mem:
    pushad
    mov esi, mem_info_msg
    call print_string
    call crlf
    
    ; Get memory from Omega tree
    mov eax, [0x100000]
    test eax, eax
    jz .mem_unknown
    
    mov eax, [eax+28]        ; MEM node
    test eax, eax
    jz .mem_unknown
    
    mov eax, [eax+52]        ; mem_kb
    call print_hex32
    mov esi, mem_kb_msg
    call print_string
    call crlf
    
.mem_unknown:
    mov esi, mem_unknown_msg
    call print_string
    call crlf
    popad
    ret

handle_cpu:
    pushad
    mov esi, cpu_info_msg
    call print_string
    call crlf
    
    ; Get CPU from Omega tree
    mov eax, [0x100000]
    test eax, eax
    jz .cpu_unknown
    
    mov eax, [eax+28]        ; CPU node
    test eax, eax
    jz .cpu_unknown
    
    ; Print CPUID
    mov eax, [eax+36]
    call print_hex32
    call crlf
    
    ; Print features
    mov eax, [eax+44]        ; ECX features
    test eax, 1
    jz .no_fpu
    mov esi, " FPU"
    call print_string
    
    test eax, 0x02000000
    jz .no_sse
    mov esi, " SSE"
    call print_string
    
    test eax, 0x08000000
    jz .no_avx
    mov esi, " AVX"
    call print_string
    
.no_avx:
.no_sse:
.no_fpu:
    call crlf
    popad
    ret
    
.cpu_unknown:
    mov esi, cpu_unknown_msg
    call print_string
    call crlf
    popad
    ret

handle_pci:
    pushad
    mov esi, pci_info_msg
    call print_string
    call crlf
    
    ; Count PCI devices from Omega tree
    mov eax, [0x100000]
    test eax, eax
    jz .pci_unknown
    
    mov eax, [eax+28]        ; IO node
    test eax, eax
    jz .pci_unknown
    
    mov ecx, 0
    mov eax, [eax+28]        ; First PCI device
    
.pci_count:
    test eax, eax
    jz .print_count
    inc ecx
    mov eax, [eax+32]        ; Next sibling
    jmp .pci_count
    
.print_count:
    mov esi, pci_count_msg
    call print_string
    call print_hex8
    mov esi, pci_devices_msg
    call print_string
    call crlf
    popad
    ret
    
.pci_unknown:
    mov esi, pci_unknown_msg
    call print_string
    call crlf
    popad
    ret

handle_tree:
    pushad
    mov esi, tree_info_msg
    call print_string
    call crlf
    
    ; Walk Omega tree
    mov ecx, 0
    mov eax, [0x100000]
    
.tree_walk:
    test eax, eax
    jz .tree_done
    inc ecx
    
    ; Print node info
    mov edx, [eax+8]         ; Class
    cmp edx, 0
    je .class_root
    cmp edx, 1
    je .class_cpu
    cmp edx, 2
    je .class_mem
    cmp edx, 3
    je .class_io
    cmp edx, 4
    je .class_compiler
    cmp edx, 5
    je .class_pci
    cmp edx, 6
    je .class_gpu
    cmp edx, 7
    je .class_storage
    cmp edx, 8
    je .class_boot
    
.class_root:
    mov esi, "ROOT"
    jmp .print_class
    
.class_cpu:
    mov esi, "CPU"
    jmp .print_class
    
.class_mem:
    mov esi, "MEM"
    jmp .print_class
    
.class_io:
    mov esi, "IO"
    jmp .print_class
    
.class_compiler:
    mov esi, "COMPILER"
    jmp .print_class
    
.class_pci:
    mov esi, "PCI"
    jmp .print_class
    
.class_gpu:
    mov esi, "GPU"
    jmp .print_class
    
.class_storage:
    mov esi, "STORAGE"
    jmp .print_class
    
.class_boot:
    mov esi, "BOOT"
    
.print_class:
    push esi
    mov edi, 0xB8000 + tree_output_offset
    mov ah, 0x0A
    call print_vga_string
    pop esi
    
    mov esi, tree_node_msg
    call print_string
    call crlf
    
    mov eax, [eax+28]        ; Child
    mov esi, [eax+8]          ; Child class
    cmp esi, 0
    je .next_node
    cmp esi, 1
    je .node_cpu
    cmp esi, 2
    je .node_mem
    jmp .next_node
    
.node_cpu:
    mov esi, " CPU child"
    jmp .print_node
    
.node_mem:
    mov esi, " MEM child"
    
.print_node:
    push esi
    mov edi, 0xB8000 + tree_output_offset + 160
    mov ah, 0x0A
    call print_vga_string
    pop esi
    
.next_node:
    mov eax, [eax+32]        ; Sibling
    jmp .tree_walk
    
.tree_done:
    call crlf
    popad
    ret

handle_clear:
    mov edi, 0xB8000
    mov ax, 0x0720
    mov ecx, 80*25
    rep stosw
    mov esi, shell_prompt
    call print_string
    popad
    ret

handle_exit:
    mov esi, shell_exit_msg
    call print_string
    call crlf
    mov ax, 0x100
    ret

handle_version:
    mov esi, version_msg
    call print_string
    call crlf
    popad
    ret

; ================================================================
; Helper Functions
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

print_hex32:
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
    call print_char
    pop eax
    loop .loop
    pop ecx
    pop eax
    ret

print_hex8:
    push eax
    mov ecx, 2
.loop:
    rol eax, 4
    push eax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jl .hex_ok
    add al, 7
.hex_ok:
    call print_char
    pop eax
    loop .loop
    pop eax
    ret

print_vga_string:
    push esi
    push edi
.print_loop2:
    lodsb
    test al, al
    jz .done2
    mov [edi], al
    mov [edi+1], ah
    add edi, 2
    jmp .print_loop2
.done2:
    pop edi
    pop esi
    ret

crlf:
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    ret

; ================================================================
; Strings
; ================================================================

shell_welcome  db "HDGL Native Shell v0.1", 0
shell_version  db "Layer-2 Runtime - Native Terminal", 0
shell_prompt   db "hdgl> ", 0

help_msg       db "HDGL Native Shell - Help", 0
help_commands  db "Commands:", 0
              db "  help    - Show this help message", 0
              db "  echo [text]  - Echo text", 0
              db "  mem     - Display memory info", 0
              db "  cpu     - Display CPU info", 0
              db "  pci     - Display PCI device count", 0
              db "  tree    - Display Omega tree structure", 0
              db "  clear   - Clear screen", 0
              db "  exit    - Exit shell", 0
              db "  version - Show version", 0

mem_info_msg   db "Memory Information:", 0
mem_kb_msg     db "  Total: ", 0
mem_unknown_msg db "  Unknown", 0

cpu_info_msg   db "CPU Information:", 0
cpu_unknown_msg db "  Unknown CPU", 0

pci_info_msg   db "PCI Information:", 0
pci_count_msg  db "  Devices: "
pci_devices_msg db " devices", 0
pci_unknown_msg db "  Unknown", 0

tree_info_msg  db "Omega Tree Structure:", 0
tree_node_msg  db "  ", 0
tree_output_offset equ 0x1400

shell_buffer_offset equ 0x400
shell_prompt_offset equ 0x800

buffer_addr:
times 80 db 0

help_msg_end:
version_msg    db "Version: 0.1", 0
shell_exit_msg db "Exiting shell...", 0

times 0x20FFFF - ($ - $$) db 0
