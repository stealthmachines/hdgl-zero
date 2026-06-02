# HDGL Universal Firmware v0.2

**NO UEFI. Verified in QEMU.**

## Boot Trace (v0.2)

```
[S0] HDGL boot. Loading Stage1+bytecode...
[S0] Loaded. JMP 0x7E00
SP
=== HDGL Universal Firmware v0.2 ===
NO UEFI | Layer-0 + Layer-1 + Discovery + Bytecode

[HDGL] CPU: CPUID discovery...
  CPU family: 00060FB1
  FPU SSE

[HDGL] MEM: memory discovery...
  Conv. mem: 0000027F KB
  Extended mem: accessible (A20 OK)

[HDGL] IO: PCI bus scan...
  PCI 0:00:0 8086:1237 cls=06   ← Intel I440FX host bridge
  PCI 0:01:0 8086:7000 cls=06   ← PIIX3 ISA bridge
  PCI 0:02:0 1234:1111 cls=03   ← VGA
  PCI 0:03:0 8086:100E cls=02   ← NIC
[HDGL] PCI scan done: 04 device(s)

[HDGL] Loading bytecode from Stage0 buffer @ 0x9000...
  Bytecode loaded.

[HDGL] Executing HDGL bytecode...
  BC: GLYPH cls=07   ← STORAGE node created
  BC: GLYPH cls=06   ← GPU node created
  BC: GLYPH cls=08   ← BOOT node created
  NODE cls=00 02     ← ROOT: DISCOVERED
  NODE cls=01 03     ← CPU:  CONFIGURED
  NODE cls=02 02     ← MEM:  DISCOVERED
  NODE cls=04 04     ← COMPILER: READY
  BC: HALT

[HDGL] ALIVE. Omega tree built. Idle.
```

## Architecture

```
Disk Layout:
  Sector 0      (512B)  Stage0 MBR
  Sectors 1-16  (8KB)   Stage1 runtime
  Sectors 17    (pad)   (empty)
  Sectors 18-21 (2KB)   HDGL bytecode

Boot Chain:
  CPU RESET
    ↓
  Stage0 @ 0x7C00  [real mode, 512 bytes]
    - Init COM1 serial
    - INT 13h: load Stage1 → 0x7E00
    - INT 13h: load HDGL bytecode → 0x9000
    - JMP 0x0000:0x7E00
    ↓
  Stage1 real-mode entry @ 0x7E00
    - Enable A20 (fast gate, port 0x92)
    - Load GDT (flat 4GB)
    - Set PE bit → protected mode
    - JMP 0x0008:pm32
    ↓
  Stage1 protected mode
    - CPUID discovery → populate CPU node
    - Memory probe (BDA + extended test) → MEM node
    - PCI bus scan (0xCF8/0xCFC via DX) → IO children
    - Copy bytecode 0x9000 → 0x110000
    - HDGL bytecode interpreter loop
    - VGA text banner
    - HLT idle loop
```

## Omega Glyph Tree (after full boot)

```
ROOT @ 0x100000   [DISCOVERED]
  CPU @ 0x100048  [CONFIGURED]
    CPUID EAX=00060FB1 (family 6, Pentium 4 compat)
    Features: FPU, SSE
  MEM @ 0x100090  [DISCOVERED]
    ~640KB conventional + 64MB+ extended
  IO  @ 0x1000D8  [CONFIGURED]
    PCI[0:0:0] host bridge
    PCI[0:1:0] ISA bridge
    PCI[0:2:0] VGA (class 03)
    PCI[0:3:0] NIC (class 02)
  COMPILER @ 0x100120  [READY → EXECUTED]
    Self-hosting anchor — executes HDGL bytecode
    Bytecode-created children:
      STORAGE [READY]
      GPU     [CONFIGURED]
      BOOT    [EXECUTED]
```

## HDGL Bytecode Format

Two bytes per instruction: `[opcode, arg]`

| Opcode | Mnemonic | Arg | Effect |
|--------|----------|-----|--------|
| 0x01 | GLYPH   | class | Create node of given class |
| 0x02 | BRANCH  | pidx  | Attach last node to node[pidx] |
| 0x03 | MUTATE  | state | Set last node state |
| 0x04 | RECURSE | nidx  | Advance all children of node[nidx] |
| 0x05 | HALT    | 0     | Stop interpreter |
| 0x06 | PRINT   | nidx  | Print node[nidx] to serial |

Magic header: `0x48 0x44` (`'H' 'D'`)

## Build & Run

```bash
# Requires: nasm, python3, qemu-system-x86_64
bash build.sh

# Run with VGA display
qemu-system-x86_64 -drive file=hdgl.img,format=raw,if=floppy \
    -boot order=a -m 64M -no-reboot

# Run headless with serial
qemu-system-x86_64 -drive file=hdgl.img,format=raw,if=floppy \
    -boot order=a -m 64M -no-reboot -display none \
    -chardev file,id=ser0,path=serial.txt -serial chardev:ser0

# Flash to USB for bare metal (CAREFUL — overwrites USB MBR)
sudo dd if=hdgl.img of=/dev/sdX bs=512 count=22
```

## Key Bugs Fixed This Session

| Bug | Fix |
|-----|-----|
| Port I/O for 0xCF8 (PCI) used direct byte encoding → silently wrote to port 0xF8 | All ports > 0xFF must use DX: `mov edx, 0xCF8; out dx, eax` |
| ORG mismatch: Stage1 at 0x7E00 but ORG was 0x0000 in earlier version | Separate files with matching ORG |
| Stage0 used far JMP to 0x0800:0x0000 but Stage1 data addresses used DS=0 | Flattened to JMP 0x0000:0x7E00 |
| UEFI-free claim: existing boot_final.bin was UTF-16 text, not x86 | Rewrote from scratch in NASM |
| ATA PIO can't read floppy sectors | Stage0 pre-loads bytecode via INT 13h in real mode |

## Next Steps

1. **Fix vendor/device ID storage**: Preserve EAX across the node allocation to correctly store `[edi+56/58]`
2. **E820 memory map**: Drop to unreal mode briefly during Stage1 RM entry to call INT 15h and store the full map
3. **HDGL self-modification**: Have the COMPILER node load its own source from disk and rewrite Stage1
4. **Bare metal**: Flash to USB and test on real x86 hardware
5. **Stage2 handoff**: Define a handoff protocol (register state + glyph tree pointer) for the next layer
