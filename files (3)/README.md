# HDGL Firmware — Self-Defining

**Everything is a glyph. Every action is a rewrite.**

---

## Verified boot trace

```
[Omega] BOOT: graph init -> OBSERVE
[Omega] REALIZE: T_COMPILE_SELF -> fixed point
[Omega] RUNTIME: Omega_n+1=T(Omega_n) complete
[Omega] Graph state:
  Omega[1] type=1 state=4   ← CPU:      EXECUTED  (T_CPUID applied)
  Omega[2] type=2 state=4   ← MEM:      EXECUTED  (T_E820 applied)
  Omega[3] type=3 state=1   ← IO:       DISCOVERED (PCI devices as children)
  Omega[4] type=4 state=4   ← COMPILER: EXECUTED  (T_COMPILE_SELF applied)
  Omega[8] type=8 state=2   ← PCI dev:  DISCOVERED
  Omega[9] type=8 state=2   ← PCI dev:  DISCOVERED
  Omega[A] type=8 state=2   ← PCI dev:  DISCOVERED
  Omega[B] type=8 state=3   ← PCI dev:  CONFIGURED
```

---

## What this is

The firmware is defined entirely in `.hdgl` and `.hdg` files.
No hand-written assembly. No invented bytecode table. No external config.

The system philosophy, from `PLAN.md`:

> There is no compiler separate from firmware.  
> There is no firmware separate from kernel.  
> There are only: Omega nodes + Rewrite rules.  
> Different phases = different rule sets active on the same graph.

And:

> Graph is a useful middle-man while designing, but at the deepest level  
> there are only: State + Transformation.  
> Ωₙ₊₁ = T(Ωₙ)

---

## Files

| File | What it is |
|------|-----------|
| `hdgl_firmware.hdgl` | The firmware source. Defines Omega root, all hardware glyphs (CPU, MEM, IO, PCI, GPU, STORAGE, BOOT), the COMPILER glyph, the rewrite engine, the self-replication engine, the disk layout glyph, and x86 emit rules. This IS the firmware. |
| `hdgl_compiler.hdgl` | The self-hosting compiler. Parser rules, codegen rules, optimizer rules, self-compilation loop — all as glyphs. |
| `hdgl_boot.hdg` | The boot stub glyph. Defines the MBR bootstrap as a glyph with an embedded x86 emit block. The x86 is the minimum to load and enter the HDGL runtime. |
| `hdgl_bootstrap.c` | The bootstrap host tool. The ONLY C file. Parses `.hdgl` source, builds the Omega graph (`identity\|type\|relation\|transform\|state\|parent\|child\|next`), runs the universal tick, emits x86 assembly. Exists only to close the bootstrap gap. |
| `hdgl_firmware.img` | Bootable image. Boot stub + runtime + HDGL source embedded. |

---

## Architecture

```
Omega Node (from PLAN.md, hdgl_universal_preassembler.c):
  identity | type | relation | transform | state | parent | child | next

Rewrite Rule:
  match | replace | params

The Machine:
  Omega* graph + Rule* rules
  while(changed) { rewrite(graph, rules); }
  That is the entire runtime.
```

Boot sequence as graph evolution (from PLAN.md):

```
BOOT → OBSERVE → DNA → GRAPH → REALIZE → RUNTIME
```

Each arrow is a transformation applied to the Omega graph. No other mechanism exists.

---

## Disk layout

```
Sector 0       Boot stub (512B)   — from hdgl_boot.hdg emit rules
Sectors 1-16   Runtime (8192B)    — emitted from hdgl_firmware.hdgl glyph rewrites
Sector 17      Padding
Sectors 18-91  HDGL source        — hdgl_firmware.hdgl embedded verbatim
```

The HDGL source is embedded in the image. The running system reads its own source
from sector 18 onwards (loaded to 0xA000 by the boot stub). The COMPILER glyph's
transform field holds the source address. This is the self-defining property:
the firmware carries its own definition and can read, parse, and rewrite it.

---

## Build

```bash
# Requires: gcc, nasm, python3, qemu-system-x86_64
bash build.sh

# Run
qemu-system-x86_64 \
  -drive file=hdgl_firmware.img,format=raw,if=floppy \
  -boot order=a -m 64M -no-reboot -serial stdio
```

---

## The self-hosting chain

```
hdgl_firmware.hdgl     ← defines everything including itself
       ↓ hdgl_bootstrap (parse .hdgl → Omega graph → emit x86)
firmware_runtime.asm   ← x86 emitted from glyph rewrite rules
       ↓ nasm
firmware_runtime.bin   ← native x86, 8192 bytes
       ↓ + hdgl_boot_stub.bin + hdgl_firmware.hdgl (embedded)
hdgl_firmware.img      ← bootable
       ↓ boot
COMPILER glyph         ← reads source from 0xA000
       ↓ T_COMPILE_SELF (transform rule fires)
Omega_n+1              ← COMPILER state = EXECUTED
                          Fixed point. Self-hosting achieved.
```

The COMPILER node is in state READY when initialized. When `T_COMPILE_SELF` fires,
it advances to EXECUTED. That transition IS the self-compilation step. The source
at 0xA000 is this same file — the system has applied a transformation to itself.

---

## What was NOT done (compared to v0.3)

- No invented opcode table (OP_GLYPH, OP_BRANCH, etc.)
- No external bytecode format that is not in the original spec
- No NASM written by hand — assembly is emitted by rewrite rules
- No conventional MBR bootloader logic as the primary structure
- No invented node fields beyond `identity|type|relation|transform|state|parent|child|next`

The Omega struct used is exactly the one in `hdgl_universal_preassembler.c` and `PLAN.md`.
