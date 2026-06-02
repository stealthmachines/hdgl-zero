# HDGL Universal Firmware v0.3

**No UEFI. No OS. No libc. Raw x86.**

Boots on real hardware from USB. Verified in QEMU (floppy + HDD/LBA).

---

## Boot trace

```
[S0]S1 OK
[S0]BC OK
[S0]Go.

=== HDGL Universal Firmware v0.2 ===
NO UEFI | Layer-0 + Layer-1 + Discovery + Bytecode

[HDGL] CPU: CPUID discovery...
  CPU family: 00060FB1  SSE

[HDGL] MEM: memory discovery...
  E820: 07 entries
  Total usable: 0000FDFF KB

[HDGL] IO: PCI bus scan...
  PCI 0:00:0 8086:1237 cls=06   ← Intel I440FX host bridge
  PCI 0:01:0 8086:7000 cls=06   ← PIIX3 ISA bridge
  PCI 0:02:0 1234:1111 cls=03   ← VGA
  PCI 0:03:0 8086:100E cls=02   ← NIC
[HDGL] PCI scan done: 04 device(s)

[HDGL] Executing HDGL bytecode...        ← FIRST PASS
  BC: GLYPH cls=07  (STORAGE)
  BC: GLYPH cls=06  (GPU)
  BC: GLYPH cls=08  (BOOT)
  NODE cls=00 02    ROOT:     DISCOVERED
  NODE cls=01 03    CPU:      CONFIGURED
  NODE cls=02 02    MEM:      DISCOVERED
  NODE cls=04 04    COMPILER: READY

  BC: SELFMOD → COMPILER EXECUTED. Bytecode rewritten.

  NODE cls=00 02    ROOT:     DISCOVERED  ← SECOND PASS
  NODE cls=01 03    CPU:      CONFIGURED
  NODE cls=02 02    MEM:      DISCOVERED
  NODE cls=04 05    COMPILER: EXECUTED    ← self-modified ✓

  BC: HALT
```

---

## Architecture

```
Disk layout (sectors):
  0       Stage0 MBR        512B   boot code + partition table
  1-16    Stage1 runtime    8KB    hardware discovery + PM + HDGL interpreter
  17      (padding)         512B
  18-21   HDGL bytecode     2KB    the glyph program

Boot chain:
  CPU RESET
    ↓
  Stage0 @ 0x7C00  [real mode]
    LBA extension detection (INT 13h AH=41h)
    Load Stage1 → 0x7E00  (LBA or CHS, 3 retries)
    Load bytecode → 0x9000 (LBA or CHS, 3 retries)
    JMP 0x0000:0x7E00
    ↓
  Stage1 real-mode entry @ 0x7E00
    INT 15h E820 memory map → stored at 0x500
    A20 enable (fast gate, port 0x92)
    Flat GDT → protected mode
    JMP 0x0008:pm32
    ↓
  Stage1 protected mode
    CPU: CPUID leaves 0+1 → Omega CPU node
    MEM: E820 map parsed → total usable KB in MEM node
    IO:  PCI bus scan (0xCF8/0xCFC) → IO child nodes per device
    COMPILER node initialized (READY)
    Copy bytecode 0x9000 → 0x110000
    HDGL bytecode interpreter loop
    HLT idle
```

## Omega Glyph Tree

Memory layout at 0x100000 (1MB), each node 72 bytes:

```
Node 0  ROOT     @ 0x100000  state: DISCOVERED
Node 1  CPU      @ 0x100048  state: CONFIGURED
  CPUID[1].EAX = family/model/stepping
  CPUID[1].ECX/EDX = feature flags (FPU, SSE, AVX, ...)
Node 2  MEM      @ 0x100090  state: DISCOVERED
  Total usable KB from E820 map
Node 3  IO       @ 0x1000D8  state: CONFIGURED
  PCI device children (one node each, class/vendor/device stored)
Node 4  COMPILER @ 0x100120  state: EXECUTED (after self-modification)
  Executed two passes of HDGL bytecode
Nodes 5+ PCI/STORAGE/GPU/BOOT  (dynamic)
```

## HDGL Bytecode

Two bytes per instruction `[opcode, arg]`, magic header `HD` (0x48 0x44):

| Op   | Name     | Arg    | Effect |
|------|----------|--------|--------|
| 0x01 | GLYPH    | class  | Create node at next index |
| 0x02 | BRANCH   | parent | Link last node to parent, advance index |
| 0x03 | MUTATE   | state  | Set last node state |
| 0x04 | RECURSE  | node   | Advance all children of node one state |
| 0x05 | HALT     | 0      | Stop interpreter |
| 0x06 | PRINT    | node   | Print node class+state to serial |
| 0x07 | SELFMOD  | node   | Advance node→EXECUTED, overwrite bytecode, re-run |

## Files

| File | Description |
|------|-------------|
| `s0v3.asm` | Stage0 source (NASM, 446B code + 64B partition table) |
| `s0v3.bin` | Stage0 binary with injected MBR partition table |
| `s1v3.asm` | Stage1 source (NASM, ~3.5KB code in 8KB binary) |
| `s1v3.bin` | Stage1 binary |
| `hdgl_bytecode.bin` | Compiled HDGL program (2KB) |
| `hdgl_bytecode_gen.py` | Bytecode assembler (Python) |
| `hdgl_floppy.img` | 1.44MB floppy image (QEMU floppy/CHS) |
| `hdgl_bare.img` | 10MB HDD image (QEMU HDD + USB bare metal) |
| `inject_mpt.py` | Injects partition table into s0v3.bin |
| `build.sh` | Builds everything from source |
| `flash_hdgl.sh` | Flashes to USB (run as root) |
| `BARE_METAL.md` | Bare metal boot guide |

## Build from source

```bash
# Requires: nasm, python3, qemu-system-x86_64 (for testing)
bash build.sh
```

## Run in QEMU

```bash
# Floppy (CHS path):
qemu-system-x86_64 \
  -drive file=hdgl_floppy.img,format=raw,if=floppy \
  -boot order=a -m 64M -no-reboot -serial stdio

# HDD (LBA path, more representative of bare metal):
qemu-system-x86_64 \
  -drive file=hdgl_bare.img,format=raw,if=ide \
  -boot order=c -m 64M -no-reboot -serial stdio
```

## Flash to USB (bare metal)

```bash
# Find your USB device:
lsblk -d -o NAME,SIZE,MODEL

# Flash (only writes 22 sectors = 11264 bytes):
sudo ./flash_hdgl.sh /dev/sdX

# Or directly:
sudo dd if=hdgl_bare.img of=/dev/sdX bs=512 count=22 oflag=sync
```

Then: disable Secure Boot, enable Legacy/CSM boot in BIOS, boot from USB.

## Bugs fixed across sessions

| Bug | Root cause | Fix |
|-----|-----------|-----|
| Boot sector was text, not x86 | Original `boot_final.bin` was UTF-16 encoded | Rewrote from scratch in NASM |
| Stage1 never executed | ORG mismatch: code at 0x7E00 but ORG=0x0000 | Separate files with matching ORG |
| PCI config space returning 0xFF | `out 0xCF8, eax` truncated to `out 0xF8, eax` (port > 255 needs DX) | All high ports via DX register |
| PCI vendor:device = 0000:0000 | `pci_node_idx` started at 4 = COMPILER node index | Start at 5; first 5 nodes reserved |
| PCI hex printing = 0000 | `pmhex16` rotated 32-bit register, printing MSBs of 0x00008086 | `rol eax, 16` first to bring low 16 to top |
| CPU node state = 0 in bytecode | `mov word [edi+10], state` used clobbered EDI | Write via absolute address |
| E820 not called | Was estimating memory from BDA only | INT 15h E820 in real-mode Stage1 entry |
| Bytecode not loaded in PM | ATA PIO can't read floppy sectors | Stage0 pre-loads via INT 13h in real mode |
| Self-modification infinite loop | Re-entered from top of bytecode, re-creating nodes | Overwrite bytecode with clean second-pass program |

## What "native to itself" means here

The COMPILER node (index 4) starts in state READY. When `OP_SELFMOD` fires:

1. COMPILER advances to EXECUTED
2. The bytecode at 0x110000 is overwritten with a new program (PRINT + RECURSE + HALT)
3. The interpreter re-enters with the new bytecode
4. Second pass shows COMPILER in state EXECUTED — it processed its own program

The system rewrote and re-executed its own glyph program during a single boot.
That is the self-hosting anchor: the firmware's own runtime is now a data structure
the firmware can inspect, modify, and re-run without any external tools.
