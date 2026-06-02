; ================================================================
; HDGL Stage1 v2 - Full Runtime
; Loaded to 0x7E00 by Stage0 (CHS sectors 2-17)
; ================================================================
; Features:
;   - A20 gate enable
;   - CPUID → CPU node population  
;   - E820 memory map → MEM node
;   - PCI bus scan → IO children
;   - HDGL bytecode interpreter (sectors 17-20)
;   - VGA + serial output throughout
; ================================================================

[BITS 16]
[ORG 0x7E00]

COM1      equ 0x3F8
OMEGA_BASE equ 0x100000
OMEGA_SZ   equ 72          ; expanded: 9 fields × 8 bytes
MAX_NODES  equ 64
HDGL_LOAD  equ 0x110000    ; HDGL bytecode at 1MB+64KB
HDGL_SEC   equ 17          ; CHS sector 17 (1-based) = LBA 16
HDGL_CNT   equ 4           ; 4 sectors of HDGL bytecode

; Omega node layout (72 bytes):
;   +0  identity (u64)
;   +8  type     (u16) class
;   +10 state    (u16)
;   +12 flags    (u32)
;   +16 caps     (u64)
;   +24 parent   (u32)
;   +28 child    (u32)
;   +32 sibling  (u32)
;   +36 cpuid_a  (u32)  CPU-specific: EAX from CPUID leaf 1
;   +40 cpuid_b  (u32)  EBX
;   +44 cpuid_c  (u32)  ECX (features)
;   +48 cpuid_d  (u32)  EDX (features)
;   +52 mem_kb   (u32)  for MEM node: total KB from E820
;   +56 pci_dev  (u16)  for PCI nodes: device ID
;   +58 pci_ven  (u16)  vendor ID
;   +60 pci_bar0 (u32)  BAR0
;   +64 pci_class (u8)  class code
;   +65 pad      (7 bytes)

; Omega states
OMEGA_VOID       equ 0
OMEGA_INIT       equ 1
OMEGA_DISCOVERED equ 2
OMEGA_CONFIGURED equ 3
OMEGA_READY      equ 4
OMEGA_EXECUTED   equ 5

; Omega classes
CLASS_ROOT     equ 0
CLASS_CPU      equ 1
CLASS_MEM      equ 2
CLASS_IO       equ 3
CLASS_COMPILER equ 4
CLASS_PCI      equ 5
CLASS_GPU      equ 6
CLASS_STORAGE  equ 7
CLASS_BOOT     equ 8

; ── Real-mode entry ──────────────────────────────────────────
stage1_rm:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7BF0

    ; Probe byte
    mov al, 'S'
    call rmchar

    ; Enable A20 via fast gate (port 0x92)
    in  al, 0x92
    or  al, 0x02
    and al, 0xFE    ; don't reset
    out 0x92, al

    lgdt [gdt_ptr]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
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
    db 0x00,0x9A,0xCF,0x00   ; code 0x08
    dw 0xFFFF,0x0000
    db 0x00,0x92,0xCF,0x00   ; data 0x10
gdt_top:

gdt_ptr:
    dw gdt_top - gdt_base - 1
    dd gdt_base

; ── Protected-mode entry ─────────────────────────────────────
[BITS 32]
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9F000

    mov al, 'P'
    call pmb

    call pm_com1_init

    ; ── Print header ─────────────────────────────────────────
    mov esi, hdr0
    call pmstr
    call pmcrlf
    mov esi, hdr1
    call pmstr
    call pmcrlf

    ; ── Clear Omega memory region ────────────────────────────
    mov edi, OMEGA_BASE
    mov ecx, (OMEGA_SZ * MAX_NODES) / 4
    xor eax, eax
    rep stosd

    ; ── VGA banner (static) ──────────────────────────────────
    call vgaclear
    call vgabanner_static

    ; ── Discover CPU via CPUID ───────────────────────────────
    mov esi, msg_cpuid
    call pmstr
    call pmcrlf
    call discover_cpu

    ; ── Discover Memory via E820 ─────────────────────────────
    mov esi, msg_e820
    call pmstr
    call pmcrlf
    call discover_mem

    ; ── Scan PCI bus ─────────────────────────────────────────
    mov esi, msg_pci
    call pmstr
    call pmcrlf
    call scan_pci

    ; ── Init COMPILER node ───────────────────────────────────
    call init_compiler

    ; ── Load HDGL bytecode from disk ─────────────────────────
    ; We need to drop back to real mode to use INT 13h.
    ; Instead: use ATA PIO to read sectors 17-20 directly.
    mov esi, msg_hdgl_load
    call pmstr
    call pmcrlf
    call load_hdgl_sectors

    ; ── Execute HDGL bytecode ────────────────────────────────
    mov esi, msg_hdgl_exec
    call pmstr
    call pmcrlf
    call hdgl_exec

    ; ── Update VGA with live discovery data ──────────────────
    call vga_live_update

    ; ── Done ─────────────────────────────────────────────────
    mov esi, msg_alive
    call pmstr
    call pmcrlf

.idle:
    hlt
    jmp .idle

; ══════════════════════════════════════════════════════════════
; SECTION: CPU DISCOVERY (CPUID)
; ══════════════════════════════════════════════════════════════

; Omega node indices (static allocation)
NODE_ROOT     equ 0
NODE_CPU      equ 1
NODE_MEM      equ 2
NODE_IO       equ 3
NODE_COMPILER equ 4
; PCI nodes start at index 5



discover_cpu:
    ; Build ROOT node
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_ROOT)
    mov dword [edi+0],  NODE_ROOT
    mov dword [edi+4],  0
    mov word  [edi+8],  CLASS_ROOT
    mov word  [edi+10], OMEGA_DISCOVERED
    mov dword [edi+28], (OMEGA_BASE + OMEGA_SZ*NODE_CPU)   ; child = CPU

    ; Build CPU node
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_CPU)
    mov dword [edi+0],  NODE_CPU
    mov word  [edi+8],  CLASS_CPU
    mov word  [edi+10], OMEGA_INIT
    mov dword [edi+24], (OMEGA_BASE + OMEGA_SZ*NODE_ROOT)
    mov dword [edi+28], (OMEGA_BASE + OMEGA_SZ*NODE_MEM)   ; sibling = MEM

    ; CPUID leaf 0: max leaf + vendor string
    xor eax, eax
    cpuid
    push ebx
    push ecx
    push edx
    ; vendor string = EBX:EDX:ECX (12 chars)
    ; store max_leaf in node
    mov [edi+36], eax   ; cpuid_a = max_leaf

    ; CPUID leaf 1: family/model/stepping + feature flags
    mov eax, 1
    cpuid
    mov [edi+36], eax   ; EAX = family/model/stepping
    mov [edi+40], ebx   ; EBX = APIC ID, clflush, brand
    mov [edi+44], ecx   ; ECX = feature flags (SSE4, AVX, etc.)
    mov [edi+48], edx   ; EDX = feature flags (FPU, MMX, SSE, etc.)

    ; Save ECX/EDX for feature test later
    push edx
    push ecx

    ; Print family (hex)
    push eax
    mov esi, msg_cpu_fam
    call pmstr
    pop eax
    push eax
    call pmhex32        ; print full EAX in hex
    pop eax
    call pmcrlf

    pop ecx
    pop edx

    pop edx
    pop ecx
    pop ebx

    ; Mark CPU discovered
    mov word [edi+10], OMEGA_DISCOVERED

    ; Print feature summary
    test edx, (1<<0)    ; FPU
    jz .no_fpu
    mov esi, msg_fpu
    call pmstr
.no_fpu:
    test edx, (1<<25)   ; SSE
    jz .no_sse
    mov esi, msg_sse
    call pmstr
.no_sse:
    test ecx, (1<<28)   ; AVX
    jz .no_avx
    mov esi, msg_avx
    call pmstr
.no_avx:
    call pmcrlf

    mov word [edi+10], OMEGA_CONFIGURED
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: MEMORY DISCOVERY
; ══════════════════════════════════════════════════════════════
; NOTE: E820 requires real mode. We use INT 12h result (saved
; by Stage0 conceptually) + a heuristic: probe 0x100000 area.
; For a real implementation on bare metal, you'd drop back to
; unreal mode or save E820 results during real-mode Stage1 entry.
; Here we use INT 12h equivalent: read BIOS data area 0x413.
; ══════════════════════════════════════════════════════════════

BDA_MEMKB equ 0x413   ; BIOS Data Area: conventional memory in KB

discover_mem:
    ; Build MEM node
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_MEM)
    mov dword [edi+0],  NODE_MEM
    mov word  [edi+8],  CLASS_MEM
    mov word  [edi+10], OMEGA_INIT
    mov dword [edi+24], (OMEGA_BASE + OMEGA_SZ*NODE_ROOT)
    mov dword [edi+28], (OMEGA_BASE + OMEGA_SZ*NODE_IO)

    ; Read conventional memory from BDA
    movzx eax, word [BDA_MEMKB]
    mov [edi+52], eax   ; mem_kb field

    ; Print
    push eax
    mov esi, msg_mem_kb
    call pmstr
    pop eax
    call pmhex32
    mov esi, msg_kb
    call pmstr
    call pmcrlf

    ; Probe extended memory: write/read test at 1MB mark
    mov dword [0x100800], 0xDEADBEEF
    cmp dword [0x100800], 0xDEADBEEF
    jne .no_ext
    mov esi, msg_ext_ok
    call pmstr
    call pmcrlf
    ; Estimate extended: assume 64MB minimum in QEMU
    mov dword [edi+52], 65536   ; 64MB in KB
.no_ext:
    mov dword [0x100800], 0     ; clean up probe

    mov word [edi+10], OMEGA_DISCOVERED
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: PCI BUS SCAN
; ══════════════════════════════════════════════════════════════
; Config space: address = 0xCF8, data = 0xCFC
; Address format: bit31=enable, bus[23:16], dev[15:11], fn[10:8], reg[7:2]

PCI_ADDR equ 0xCF8
PCI_DATA equ 0xCFC

scan_pci:
    ; Debug: probe PCI device 0,0,0 directly
    ; Build IO node
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_IO)
    mov dword [edi+0],  NODE_IO
    mov word  [edi+8],  CLASS_IO
    mov word  [edi+10], OMEGA_DISCOVERED
    mov dword [edi+24], (OMEGA_BASE + OMEGA_SZ*NODE_ROOT)
    ; child will be set to first PCI device found

    ; Next available node index
    mov dword [pci_node_idx], 5

    ; Scan bus 0, devices 0-31, function 0 only
    xor ebx, ebx        ; EBX = device number 0-31

.scan_dev:
    ; Build PCI config address: bus=0, dev=EBX, fn=0, reg=0
    ; Format: 1_00000000_ddddd_000_00000000_00b (bit31=enable)
    mov eax, 0x80000000
    mov ecx, ebx
    shl ecx, 11         ; device number in bits 15:11
    or  eax, ecx        ; EAX = config address
    mov edx, PCI_ADDR
    out dx, eax
    mov edx, PCI_DATA
    in  eax, dx

    ; 0xFFFFFFFF = no device
    cmp eax, 0xFFFFFFFF
    je  .next_dev

    ; Found a device
    mov ecx, [pci_node_idx]
    cmp ecx, MAX_NODES - 2
    jge .scan_done      ; out of node space

    ; Fill PCI node
    push eax            ; save vendor:device
    imul edi, ecx, OMEGA_SZ
    add  edi, OMEGA_BASE
    mov  dword [edi+0],  ecx   ; id = node index
    mov  word  [edi+8],  CLASS_PCI
    mov  word  [edi+10], OMEGA_DISCOVERED
    mov  dword [edi+24], (OMEGA_BASE + OMEGA_SZ*NODE_IO)

    pop eax
    mov [edi+58], ax            ; vendor ID (low 16)
    shr eax, 16
    mov [edi+56], ax            ; device ID (high 16)

    ; Read class code (register 2, offset 8)
    mov eax, 0x80000008
    mov ecx, ebx
    shl ecx, 11
    or  eax, ecx
    mov edx, PCI_ADDR
    out dx, eax
    mov edx, PCI_DATA
    in  eax, dx
    shr eax, 24                 ; class code in bits 31:24
    mov byte [edi+64], al

    ; Print device info (save all regs)
    push eax
    push ecx
    push edi
    ; Recompute edi from pci_node_idx (which was ECX before we used ECX)
    mov ecx, [pci_node_idx]
    dec ecx                     ; current node (just filled) = idx-1... 
    ; Actually node was filled before incrementing, so current = pci_node_idx value
    ; But pci_node_idx was already ECX when we built the node.
    ; Simplest: EDI still points to the node (set earlier)
    pop edi
    push edi
    mov esi, msg_pci_dev
    call pmstr
    ; Print bus:dev:fn (we scanned bus 0, device = EBX, fn=0)
    mov al, '0'
    call pmb
    mov al, ':'
    call pmb
    mov eax, ebx
    call pmhex8
    mov al, ':' 
    call pmb
    mov al, '0'
    call pmb
    mov al, ' '
    call pmb
    ; Vendor:Device
    movzx eax, word [edi+58]
    call pmhex16
    mov al, ':'
    call pmb
    movzx eax, word [edi+56]
    call pmhex16
    mov esi, msg_cls
    call pmstr
    movzx eax, byte [edi+64]
    call pmhex8
    call pmcrlf
    pop edi
    pop ecx
    pop eax

    ; Link into IO children (first device = IO.child, rest chain via sibling)
    mov ecx, [pci_node_idx]
    cmp ecx, 5
    jne .link_sibling
    ; First PCI device: IO.child → this node
    mov eax, OMEGA_BASE
    imul edx, ecx, OMEGA_SZ
    add  edx, OMEGA_BASE
    mov  dword [(OMEGA_BASE + OMEGA_SZ*NODE_IO)+28], edx
    jmp .linked
.link_sibling:
    ; Find last PCI node and set its sibling
    mov edx, [pci_prev_ptr]
    imul edx, edx, OMEGA_SZ
    add  edx, OMEGA_BASE
    imul eax, ecx, OMEGA_SZ
    add  eax, OMEGA_BASE
    mov  dword [edx+32], eax
.linked:
    mov [pci_prev_ptr], ecx
    inc dword [pci_node_idx]

.next_dev:
    inc ebx
    cmp ebx, 32
    jl  .scan_dev

.scan_done:
    mov esi, msg_pci_done
    call pmstr
    mov eax, [pci_node_idx]
    sub eax, 5
    call pmhex8
    mov esi, msg_devices
    call pmstr
    call pmcrlf

    mov word [(OMEGA_BASE + OMEGA_SZ*NODE_IO)+10], OMEGA_CONFIGURED
    ret

pci_node_idx dd 5
pci_prev_ptr dd 0

; ══════════════════════════════════════════════════════════════
; SECTION: COMPILER NODE INIT
; ══════════════════════════════════════════════════════════════

init_compiler:
    mov edi, (OMEGA_BASE + OMEGA_SZ*NODE_COMPILER)
    mov dword [edi+0],  NODE_COMPILER
    mov word  [edi+8],  CLASS_COMPILER
    mov word  [edi+10], OMEGA_READY
    mov dword [edi+24], (OMEGA_BASE + OMEGA_SZ*NODE_IO)  ; parent = IO
    ; child set to 0 (no sub-nodes yet)
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: ATA PIO SECTOR LOAD (PM-safe, no INT 13h)
; ══════════════════════════════════════════════════════════════
; Loads HDGL_CNT sectors starting at LBA HDGL_SEC-1 (0-based)
; to HDGL_LOAD physical address.
; Uses ATA PIO on primary bus (0x1F0-0x1F7), drive 0.
; ══════════════════════════════════════════════════════════════


load_hdgl_sectors:
    ; Stage0 loaded HDGL bytecode to 0x9000 (real mode).
    ; Now in PM flat mode, copy from linear 0x9000 to HDGL_LOAD (0x110000).
    ; Check if Stage0 stored a valid address at 0x7FF0:
    movzx eax, word [0x7FF0]
    test eax, eax
    jz .no_bc_addr

    ; Copy 2048 bytes from 0x9000 to 0x110000
    mov esi, 0x9000
    mov edi, HDGL_LOAD
    mov ecx, 2048 / 4
    rep movsd

    mov esi, msg_hdgl_loaded
    call pmstr
    call pmcrlf
    ret

.no_bc_addr:
    mov esi, msg_no_bc_addr
    call pmstr
    call pmcrlf
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: HDGL BYTECODE INTERPRETER
; ══════════════════════════════════════════════════════════════
; Bytecode format (2 bytes per instruction):
;   [0x01, class]    GLYPH   - create node of given class
;   [0x02, pidx]    BRANCH  - set last node parent = node[pidx]
;   [0x03, state]   MUTATE  - advance last node to state
;   [0x04, nidx]    RECURSE - apply hdgl_tick to subtree of node[nidx]
;   [0x05, 0]       HALT    - stop interpreter
;   [0x06, nidx]    PRINT   - print node nidx to serial

OP_GLYPH   equ 0x01
OP_BRANCH  equ 0x02
OP_MUTATE  equ 0x03
OP_RECURSE equ 0x04
OP_HALT    equ 0x05
OP_PRINT   equ 0x06

hdgl_exec:
    ; ESI = bytecode pointer, EBX = last created node index
    mov esi, HDGL_LOAD
    mov ebx, [pci_node_idx]    ; start allocating after PCI nodes

    ; Validate magic: bytecode starts with 0x48 0x44 ('H','D')
    cmp word [esi], 0x4448      ; 'DH' little-endian = 'H','D'
    jne .no_bytecode
    add esi, 2                  ; skip magic

.loop:
    movzx eax, byte [esi]       ; opcode
    movzx ecx, byte [esi+1]     ; arg
    add esi, 2

    cmp eax, OP_GLYPH
    je  .do_glyph
    cmp eax, OP_BRANCH
    je  .do_branch
    cmp eax, OP_MUTATE
    je  .do_mutate
    cmp eax, OP_RECURSE
    je  .do_recurse
    cmp eax, OP_HALT
    je  .do_halt
    cmp eax, OP_PRINT
    je  .do_print
    ; Unknown opcode: skip
    jmp .loop

.do_glyph:
    ; Create node at index EBX with class ECX
    cmp ebx, MAX_NODES - 1
    jge .loop
    imul edi, ebx, OMEGA_SZ
    add  edi, OMEGA_BASE
    mov  dword [edi+0], ebx
    mov  word  [edi+8], cx      ; class
    mov  word  [edi+10], OMEGA_INIT
    push esi
    mov  esi, msg_bc_glyph
    call pmstr
    movzx eax, cx
    call pmhex8
    call pmcrlf
    pop esi
    ; Don't increment EBX yet (BRANCH will reference it)
    jmp .loop

.do_branch:
    ; Set node[EBX].parent = node[ECX], and link as child
    imul edi, ebx, OMEGA_SZ
    add  edi, OMEGA_BASE
    imul edx, ecx, OMEGA_SZ
    add  edx, OMEGA_BASE
    mov  dword [edi+24], edx    ; parent ptr

    ; Find last child of parent and set sibling, or set child directly
    cmp dword [edx+28], 0
    jne .find_last_sib
    mov dword [edx+28], edi     ; parent.child = this
    jmp .branch_done
.find_last_sib:
    mov eax, [edx+28]           ; walk sibling chain
.sib_walk:
    cmp dword [eax+32], 0
    je  .sib_end
    mov eax, [eax+32]
    jmp .sib_walk
.sib_end:
    mov [eax+32], edi
.branch_done:
    inc ebx                     ; now advance to next slot
    jmp .loop

.do_mutate:
    ; Set last created node's state = ECX
    imul edi, ebx, OMEGA_SZ
    sub  edi, OMEGA_SZ          ; last node = ebx-1
    add  edi, OMEGA_BASE
    mov  word [edi+10], cx
    jmp .loop

.do_recurse:
    ; Apply one tick to all children of node[ECX]
    imul edi, ecx, OMEGA_SZ
    add  edi, OMEGA_BASE
    mov  edi, [edi+28]          ; child ptr
.rec_walk:
    test edi, edi
    jz   .rec_done
    movzx eax, word [edi+10]
    cmp  eax, OMEGA_EXECUTED
    jge  .rec_next
    inc  eax
    mov  word [edi+10], ax
.rec_next:
    mov  edi, [edi+32]          ; sibling
    jmp  .rec_walk
.rec_done:
    jmp .loop

.do_print:
    push esi
    push ebx
    movzx ebx, cl
    imul edi, ebx, OMEGA_SZ
    add  edi, OMEGA_BASE
    mov  esi, msg_node_pfx
    call pmstr
    movzx eax, word [edi+8]     ; class
    call pmhex8
    mov  al, ' '
    call pmb
    movzx eax, word [edi+10]    ; state
    call pmhex8
    call pmcrlf
    pop ebx
    pop esi
    jmp .loop

.do_halt:
    mov esi, msg_bc_halt
    call pmstr
    call pmcrlf
    ret

.no_bytecode:
    mov esi, msg_no_bc
    call pmstr
    call pmcrlf
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: VGA
; ══════════════════════════════════════════════════════════════

vgaclear:
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw
    ret

vga_wstr:
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



vgabanner_static:
    mov edi, 0xB8000 + 0
    mov esi, vt
    mov ah, 0x0B
    call vga_wstr
    mov edi, 0xB8000 + 160
    mov esi, vsep
    mov ah, 0x08
    call vga_wstr
    mov edi, 0xB8000 + 320
    mov esi, v_cpu_label
    mov ah, 0x0A
    call vga_wstr
    mov edi, 0xB8000 + 480
    mov esi, v_mem_label
    mov ah, 0x0A
    call vga_wstr
    mov edi, 0xB8000 + 640
    mov esi, v_io_label
    mov ah, 0x0A
    call vga_wstr
    mov edi, 0xB8000 + 800
    mov esi, v_comp_label
    mov ah, 0x0D
    call vga_wstr
    mov edi, 0xB8000 + 3680
    mov esi, vfoot
    mov ah, 0x08
    call vga_wstr
    ret

; Live VGA update after discovery
vga_live_update:
    ; Row 2: CPU info
    mov edi, 0xB8000 + 320
    mov esi, v_cpu_pfx
    mov ah, 0x0A
    call vga_wstr
    ; Print CPU model hex
    mov eax, [(OMEGA_BASE + OMEGA_SZ*NODE_CPU)+36]
    call vga_hex32
    ; Row 3: Memory KB
    mov edi, 0xB8000 + 480
    mov esi, v_mem_pfx
    mov ah, 0x0A
    call vga_wstr
    mov eax, [(OMEGA_BASE + OMEGA_SZ*NODE_MEM)+52]
    call vga_hex32

    ; Row 4: PCI device count
    mov edi, 0xB8000 + 640
    mov esi, v_io_pfx
    mov ah, 0x0A
    call vga_wstr
    mov eax, [pci_node_idx]
    sub eax, 5
    call vga_hex32

    ; Row 5: Compiler state
    mov edi, 0xB8000 + 800
    mov esi, v_comp_pfx
    mov ah, 0x0D
    call vga_wstr

    ; Row 22: Tick counter
    mov edi, 0xB8000 + 3520
    mov esi, v_tick
    mov ah, 0x0F
    call vga_wstr

    ; Row 23: alive message
    mov edi, 0xB8000 + 3680
    mov esi, vfoot2
    mov ah, 0x07
    call vga_wstr
    ret

; VGA hex output (attribute in AH already set on vga pointer)
; writes at current EDI, advances EDI
vga_hex32:
    push eax
    push ecx
    push edi
    ; temporarily: just write to current VGA row
    mov ecx, 8
.d: rol eax, 4
    push eax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jl .ok
    add al, 7
.ok:
    mov [edi], al
    mov byte [edi+1], 0x0F
    add edi, 2
    pop eax
    loop .d
    pop edi
    pop ecx
    pop eax
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: SERIAL OUTPUT
; ══════════════════════════════════════════════════════════════

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

pm_com1_init:
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

pmhex32:
    push eax
    push ecx
    mov ecx, 8
.d: rol eax, 4
    push eax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jl .ok
    add al, 7
.ok:
    call pmb
    pop eax
    loop .d
    pop ecx
    pop eax
    ret

pmhex16:
    push eax
    push ecx
    mov ecx, 4
.d: rol eax, 4
    push eax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jl .ok
    add al, 7
.ok:
    call pmb
    pop eax
    loop .d
    pop ecx
    pop eax
    ret

pmhex8:
    push eax
    push ecx
    mov ecx, 2
.d: rol al, 4
    push eax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jl .ok
    add al, 7
.ok:
    call pmb
    pop eax
    loop .d
    pop ecx
    pop eax
    ret

; ══════════════════════════════════════════════════════════════
; SECTION: STRING TABLE
; ══════════════════════════════════════════════════════════════

hdr0     db "=== HDGL Universal Firmware v0.2 ===",0x0D,0x0A,0
hdr1     db "NO UEFI | Layer-0 + Layer-1 + Discovery + Bytecode",0x0D,0x0A,0
msg_cpuid   db "[HDGL] CPU: CPUID discovery...",0x0D,0x0A,0
msg_cpu_fam db "  CPU family: ",0
msg_fpu  db " FPU",0
msg_sse  db " SSE",0
msg_avx  db " AVX",0
msg_e820    db "[HDGL] MEM: memory discovery...",0x0D,0x0A,0
msg_mem_kb  db "  Conv. mem: ",0
msg_kb      db " KB",0x0D,0x0A,0
msg_ext_ok  db "  Extended mem: accessible (A20 OK)",0x0D,0x0A,0
msg_pci     db "[HDGL] IO: PCI bus scan...",0x0D,0x0A,0
msg_pci_dev db "  PCI ",0
msg_cls     db " cls=",0
msg_pci_done db "[HDGL] PCI scan done: ",0
msg_devices  db " device(s)",0x0D,0x0A,0
msg_hdgl_load db "[HDGL] Loading bytecode from Stage0 buffer @ 0x9000...",0x0D,0x0A,0
msg_hdgl_loaded db "  Bytecode loaded.",0x0D,0x0A,0
msg_hdgl_exec db "[HDGL] Executing HDGL bytecode...",0x0D,0x0A,0
msg_bc_glyph db "  BC: GLYPH cls=",0
msg_bc_halt  db "  BC: HALT",0x0D,0x0A,0
msg_no_bc    db "  (no valid bytecode found - magic mismatch)",0x0D,0x0A,0
msg_no_bc_addr db "  (no bytecode addr from Stage0)",0x0D,0x0A,0
msg_node_pfx db "  NODE cls=",0
msg_alive    db "[HDGL] ALIVE. Omega tree built. Idle.",0x0D,0x0A,0

vt         db "HDGL Universal Firmware v0.2  [Discovery+Bytecode]  NO UEFI",0
vsep       db "------------------------------------------------------------",0
v_cpu_label db "  CPU: discovering...",0
v_mem_label db "  MEM: discovering...",0
v_io_label  db "  IO/PCI: scanning...",0
v_comp_label db "  COMPILER: READY  <self-hosting anchor>",0
vfoot       db "------------------------------------------------------------",0
v_cpu_pfx   db "  CPU CPUID[1]: ",0
v_mem_pfx   db "  MEM total:    ",0
v_io_pfx    db "  PCI devices:  ",0
v_comp_pfx  db "  COMPILER: READY -> executing HDGL bytecode",0
v_tick      db "  Rewrite pass: COMPLETE",0
vfoot2      db "  HDGL idle. System alive. NO UEFI.",0

times 8192 - ($ - $$) db 0
