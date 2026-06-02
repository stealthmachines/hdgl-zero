# HDGL Universal Firmware — QEMU-Verified Boot

## What This Is

A working, UEFI-free firmware built from scratch in x86 assembly.
Two-stage bootloader implementing your HDGL Layer-0 / Layer-1 architecture.

## Boot Trace (verified in QEMU)

```
[S0] Booting HDGL. Loading Stage1...
[S0] Stage1 loaded. JMP 0x7E00
S P
[S1] Protected mode OK
[S1] Omega glyph tree @ 0x100000
[S1] Rewrite tick done
[S1] ALIVE. NO UEFI. Boot complete.
```

## Files

| File | Role |
|------|------|
| `s0.asm` / `s0.bin` | Stage0 (Layer-0): 512-byte MBR boot sector |
| `s1.asm` / `s1.bin` | Stage1 (Layer-1): 8192-byte protected-mode Omega runtime |
| `hdgl.img` | Bootable 1.44MB floppy image for QEMU |

## Architecture

```
RESET
  ↓
Stage0 (s0.bin @ 0x7C00)          ← 512 bytes, real mode
  - Init COM1 serial (9600 8N1)
  - Load Stage1 via INT 13h CHS
  - JMP 0x0000:0x7E00
  ↓
Stage1 real-mode entry (0x7E00)
  - Emit 'S' to serial (probe)
  - Load flat GDT (base=0, 4GB)
  - Enable PE bit → CR0
  - JMP 0x0008:pm32
  ↓
Stage1 protected mode (pm32)       ← 32-bit flat
  - Set DS/ES/SS to 0x10 (flat data)
  - Emit 'P' to serial (PM probe)
  - Reinit COM1 in PM
  - Write VGA banner (0xB8000)
  - Initialize Omega glyph tree @ 0x100000
  - Run hdgl_tick (one rewrite pass)
  - Idle loop (HLT)
```

## Omega Glyph Tree (@ 1MB)

```
ROOT     @ 0x100000  [DISCOVERED → READY]
  |── CPU     @ 0x100030  [DISCOVERED → READY]
      |── MEM @ 0x100060  [DISCOVERED → READY]
          |── IO @ 0x100090  [DISCOVERED → READY]
              |── COMPILER @ 0x1000C0  [READY → EXECUTED]  ← self-host anchor
```

Each Omega node (48 bytes):
- `id` (uint64), `class` (uint16), `state` (uint16), `flags` (uint32)
- `caps` (uint64), `parent` (ptr32), `child` (ptr32), `sibling` (ptr32)

## Running in QEMU

```bash
# Build from source
nasm -f bin s0.asm -o s0.bin
nasm -f bin s1.asm -o s1.bin
dd if=/dev/zero bs=1474560 count=1 of=hdgl.img
dd if=s0.bin bs=512 count=1 seek=0 conv=notrunc of=hdgl.img
dd if=s1.bin bs=512 count=16 seek=1 conv=notrunc of=hdgl.img

# Run (headless with serial output)
qemu-system-x86_64 \
    -drive file=hdgl.img,format=raw,if=floppy \
    -boot order=a \
    -m 64M \
    -no-reboot \
    -display none \
    -chardev file,id=ser0,path=serial.txt \
    -serial chardev:ser0

# Run with display (VGA text output)
qemu-system-x86_64 \
    -drive file=hdgl.img,format=raw,if=floppy \
    -boot order=a \
    -m 64M \
    -no-reboot

cat serial.txt
```

## What "Native to Itself" Means Here

The COMPILER node starts in state `READY`, which is the self-hosting anchor.
The `hdgl_tick` function advances it to `EXECUTED`.

The next step for self-hosting is to store HDGL source code in sectors 17+
and have the COMPILER node load and interpret it during boot, replacing
the hardcoded state machine with a live glyph-parsed graph.

## What Was Fixed

Your existing `boot_final.bin` had the `0xAA55` boot signature but no
real x86 code — it was UTF-16 encoded text ("HDGL Booting...") which a
CPU would attempt to execute as instructions and immediately triple-fault.

The key bugs solved:
1. Boot sector needed real x86 code at `0x7C00`, not text
2. Stage1 ORG address and GDT linear base had to match the load address
3. The far JMP into protected mode needed the correct linear address
4. COM1 needed re-initialization after entering PM

## Next Steps

1. **Self-hosting**: Store HDGL bytecode in sectors 17+ and have COMPILER load it
2. **Hardware discovery**: Scan PCI config space to populate IO node children
3. **A20 gate**: Enable for >1MB access (needed for Omega tree at 0x100000)
4. **Handoff**: After graph is built, JMP to a payload at a known address
5. **Native bare-metal**: Flash `s0.bin+s1.bin` to a USB stick and test on real hardware
