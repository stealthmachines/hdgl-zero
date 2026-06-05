; ============================================================
; HDGL MBR — sector 0 (512 bytes)
; Dual-path: legacy disk boot AND El Torito virtual CD boot.
; phi-neutral: mov not xor throughout.
;
; El Torito no-emulation (SeaBIOS) loads all load_count×512 bytes
; to 0x7C00. With load_count=18: stage2 lands at 0x7E00,
; runtime64 at 0x8000 — already in RAM before MBR runs.
;
; Boot-info-table (genisoimage -boot-info-table overwrites bytes 8-63):
;   [8:12]  bi_pvd    = 16 when ISO; 0 on raw disk → used for CD detect
;   [12:16] bi_file   = LBA of boot image in ISO
;   [16:20] bi_length = byte length of boot image
;   [20:64] zeroed by genisoimage
;
; Code MUST start at byte 64 or later (bytes 8-63 are clobbered by ISO tool).
; ============================================================
[bits 16]
[org  0x7C00]

; Byte 0: JMP short over boot-info-table area to code at byte 64
    db 0xEB, 0x3E, 0x90     ; JMP +62 → byte 64; NOP

; Bytes 3-7: padding
    times 8-($-$$) db 0

; Bytes 8-63: boot-info-table (patched by genisoimage -boot-info-table)
.bi_pvd    dd 0             ; → 16 (ISO PVD LBA) after genisoimage patch
.bi_file   dd 0             ; → LBA of boot image
.bi_length dd 0             ; → byte length of boot image
           times 64-($-$$) db 0   ; genisoimage clobbers through byte 63

; Byte 64: code starts here (safe from genisoimage patching)
.code:
    cli
    mov  ax, 0
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7BF0
    sti
    mov  [.drive], dl

    ; CD detect: genisoimage patches bi_pvd to 16; raw disk leaves it 0
    cmp  dword [.bi_pvd], 16
    je   .cd_path

    ; ── DISK PATH ────────────────────────────────────────────
    in   al, 0x92           ; A20 fast-gate
    or   al, 0x02
    and  al, 0xFE
    out  0x92, al
    mov  ah, 0x41           ; LBA detect
    mov  bx, 0x55AA
    int  0x13
    jc   .chs
    cmp  bx, 0xAA55
    jne  .chs
    mov  dword [.dap+8],  1
    mov  dword [.dap+12], 0
    mov  word  [.dap+2],  1
    mov  word  [.dap+4],  0x7E00
    mov  word  [.dap+6],  0
    mov  ah, 0x42
    mov  dl,  [.drive]
    mov  si,  .dap
    int  0x13
    jc   .halt
    jmp  .go
.chs:
    mov  ah, 0x02
    mov  al, 1
    mov  ch, 0
    mov  cl, 2
    mov  dh, 0
    mov  dl, [.drive]
    mov  bx, 0x7E00
    int  0x13
    jc   .halt
.go:
    mov  dl, [.drive]
    jmp  0x0000:0x7E00

    ; ── CD PATH ──────────────────────────────────────────────
    ; SeaBIOS loaded all 18 sectors: stage2@0x7E00, runtime64@0x8000
.cd_path:
    in   al, 0x92     ; A20 fast-gate
    or   al, 0x02
    and  al, 0xFE
    out  0x92, al
    ; Init COM1 9600 8N1 (stage2 probe_com will confirm+store base)
    mov  dx, 0x3F9
    mov  al, 0
    out  dx, al
    mov  dx, 0x3FB
    mov  al, 0x80
    out  dx, al
    mov  dx, 0x3F8
    mov  al, 12
    out  dx, al
    mov  dx, 0x3F9
    mov  al, 0
    out  dx, al
    mov  dx, 0x3FB
    mov  al, 0x03
    out  dx, al
    ; Store confirmed COM1 base so runtime64 uses it without probe_com
    mov  word [0x7FEC], 0x3F8
    mov  dl, [.drive]
    jmp  0x0000:0x7E00

.halt:
    cli
    hlt
    jmp  .halt

.drive  db 0x80
.dap    db 0x10, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

times 510-($-$$) db 0
dw 0xAA55
