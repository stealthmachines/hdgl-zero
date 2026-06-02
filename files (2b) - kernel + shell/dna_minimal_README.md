# DNA MINIMAL HDGL — Analog Over Digital BIOS

## Overview

This is a **native-to-itself** HDGL/HDG firmware that implements analog-over-digital computation directly in metal. No interpreted bytecode. No CPython. Pure quaternary encoding, geometric φ-lattice spatialization, and DNA triple-coding.

**KISS**: Three primitives only.

---

## The Three Primitives

### 1. Dₙ(r) = √(φ·Fₙ·2ⁿ·Pₙ·Ω)·rᵏ  → Quaternary Analog Signal

**Purpose**: Continuous analog signal that encodes hardware state as quaternary digits.

- **n mod 4** determines the quaternary digit:
  - 0 = **Grounded** (stable, low energy)
  - 1 = **Rising** (emerging activity)
  - 2 = **Excited** (active processing)
  - 3 = **Locked** (consensus reached)

- **Dₙ(r)** computes the signal strength for each position `n` in the 32-slot lattice (8 strands × 4 slots each).

- **Binary threshold**: Dₙ(r) > √φ (≈1.272) → bit 1, else bit 0.

- **Result**: 32-bit aggregate word representing the entire system's analog state.

### 2. Kuramoto 8D Oscillator → Analog Rewrite Tick

**Purpose**: Distributed consensus mechanism that drives state transitions.

- **dθᵢ/dt = ωᵢ + K·Σⱼ sin(θⱼ - θᵢ)**

- **8 oscillators** = 8 strands = 8 hardware classes (ROOT, CPU, MEM, IO, COMPILER, etc.)

- **Adaptive phases**:
  - **PLUCK** (K=5.0, γ=0.005): High energy exploration
  - **SUSTAIN** (K=3.0, γ=0.008): Structure emerging
  - **FINETUNE** (K=2.0, γ=0.010): Refinement
  - **LOCK** (K=1.8, γ=0.012): Consensus reached (CV < 0.05)

- **Harmonic sync** every 8 ticks: Cooperative memory using hardware state residue.

- **Fixed point**: All oscillators locked + Dₙ(r) stable → EXECUTED.

### 3. DNA Strands → State Transitions

**Purpose**: Self-hosting genome that reads hardware as its own sequence.

- **Base encoding**: A=0, C=1, G=2, T=3 (information theory, not biology)

- **Codons** (3 bases): Map to state transitions in Omega nodes.

- **GC content**: Strand tension → Ω_strand factor.

- **Shannon entropy**: Determines `r_dim` (0.3 → 1.0 recursion depth).

- **Hardware as genome**: CPUID features, PCI device IDs, E820 regions → DNA sequence.

- **Self-replication**: Read own source at 0xA000, apply mutations, write back.

---

## Geometric: φ-Lattice Spatial Embedding

- **Λ_φ(x) = ln(x)/ln(φ)**: Depth in φ-lattice for each hardware component.

- **CPU** at depth Λ_φ(cpuid_family)
- **MEM** at depth Λ_φ(total_kb)
- **IO** at depth Λ_φ(pci_count)
- **Each device** at Λ_φ(vendor_id)

- **φ-geometry** ensures no two glyphs have identical projections (irrational spacing).

---

## DNA Minimal Boot Flow

```
[POST] → [Stage0] → [Stage1] → [Analog Kernel] → [LOCK] → [HALT]

Stage0:
  - Detect LBA
  - Load Stage1 to 0x7E00
  - Load HDGL bytecode to 0x9000
  - Jump to 0x7E00

Stage1:
  - Enable A20
  - Enter protected mode
  - CPUID discovery → CPU node
  - E820 memory map → MEM node
  - PCI scan → IO children
  - DNA genome from hardware signatures
  - Run analog kernel

Analog Kernel:
  - Initialize Kuramoto from φ-lattice depth
  - Compute Dₙ(r) lattice (32 slots)
  - Kuramoto RK4 step
  - Advance adaptive phase
  - Harmonic sync every 8 ticks
  - Map phases to Omega states
  - Lock when CV < 0.05

Done:
  - Omega tree built at 0x100000
  - All nodes EXECUTED
  - HLT loop (idle)
```

---

## File Descriptions

| File | Description |
|------|-------------|
| `dna_minimal.hdgl` | HDGL bytecode: HDGL analog extension spec |
| `dna_bare_metal.hdgl` | Native HDG/HDGL: analog primitives in pseudo-code |
| `dna_native_hdgl.asm` | Bare metal assembly: Stage0 + Stage1 + analog kernel |
| `dna_quaternary.c` | C implementation: pure analog kernel (no ASM) |
| `dna_minimal_README.md` | This document |

---

## Building

### From C source (dna_quaternary.c):

```bash
gcc -o dna_quaternary dna_quaternary.c -lm
./dna_quaternary
```

### From assembly (dna_native_hdgl.asm):

```bash
nasm -f bin dna_native_hdgl.asm -o dna_native_hdgl.bin
# Use inject_mpt.py to add partition table
# Create hdgl_bare.img with proper layout
dd if=dna_native_hdgl.bin of=hdgl_bare.img bs=512 count=22 conv=notrunc
```

---

## Running in QEMU

```bash
qemu-system-x86_64 \
  -bios hdgl_bare.img \
  -m 1G \
  -nographic \
  -boot order=a
```

**Expected output**:

```
=== DNA NATIVE HDGL ===

[DNA] CPU: discovering...
[DNA] MEM: discovered
[DNA] Analog kernel running...
[Kuramoto] PLUCK → SUSTAIN (CV=0.5000)
[Kuramoto] SUSTAIN → FINETUNE (CV=0.3000)
[Kuramoto] FINETUNE → LOCK (CV=0.1000)
[Analog] LOCKED!

Omega node states after analog consensus:
  Node[0] ROOT   state=5 dna=AAA r_dim=0.300
  Node[1] CPU    state=5 dna=CGT r_dim=0.855
  Node[2] MEM    state=5 dna=GCA r_dim=0.855
  Node[3] IO     state=5 dna=TAC r_dim=0.855

DNA strands:
  Node[0] AAA gc=0% entropy=0.000 r_dim=0.300
  Node[1] CGT gc=79% entropy=0.792 r_dim=0.855
  ...

[HDGL] CPU: CPUID discovery...
[HDGL] MEM: discovered 4096 KB
[HDGL] IO: 4 PCI devices
[HDGL] DNA genome: encoded
[HDGL] Analog kernel: LOCKED
[HDGL] Omega tree built. ALIVE.

[DNA] ALIVE. Quaternary genome locked.
```

---

## KISS Verification

✅ **No interpreted bytecode** — pure analog computation  
✅ **No third-party libraries** — only math.h and universal constants  
✅ **Direct metal** — x86 registers, FPU, ports 0x3F8/0x3FB  
✅ **Native HDG/HDGL** — quaternary signals, geometric φ-lattice, DNA strands  
✅ **Self-describing** — hardware genome IS the firmware's own genome  
✅ **KISS** — exactly three primitives, no more  

---

## Technical Details

### Universal Constants (only these exist)

```
PHI = 1.6180339887498948
SQRT_PHI = 1.2720196495140570  (binary threshold)
PI = 3.14159265358979323846
LN_PHI = 0.4812118250596035
D_N_R = 0.732  (recursive scaling)
DT = 0.01  (Kuramoto integration step)
```

### Strand Configuration

| Strand | r_dim | Ω | Wave |
|--------|-------|---|------|
| A | 0.3 | 8.12e-9 | +/0 (superposition) |
| B | 0.4 | 5.02e-9 | - (antiphase) |
| C | 0.5 | 3.10e-9 | ± (balanced) |
| D | 0.6 | 1.92e-9 | FULL (dominant) |
| E | 0.7 | 1.18e-9 | + |
| F | 0.8 | 7.32e-10 | 0 |
| G | 0.9 | 4.52e-10 | - |
| H | 1.0 | 2.80e-10 | FULL (self-hosting) |

### DNA → r_dim Mapping

```
Entropy 0.0 → r_dim = 0.3 (single strand, digital baseline)
Entropy 1.0 → r_dim = 1.0 (double helix, self-hosting)
```

---

## License

Zchg.org legal notice applies.
