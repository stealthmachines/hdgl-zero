# HDGL Kernel Extensions

**Layer-2 Runtime Environment** for HDGL Universal Firmware v0.2

## Overview

The kernel extensions provide a complete **Layer-2 runtime** that takes over after the HDGL bytecode interpreter completes. This creates a two-layer architecture:

- **Layer-0/1**: HDGL Stage 0 + Stage 1 + Bytecode (existing)
- **Layer-2**: Native kernel with multitasking, memory management, and device drivers

## Architecture

```
Boot Process:
  ┌─────────────────┐
  │   Stage 0 (512B)│  ← MBR, loads Stage 1 & bytecode
  └────────┬────────┘
           │
  ┌────────▼────────┐
  │   Stage 1 (8KB) │  ← Real→Protected mode, HDGL interpreter
  └────────┬────────┘
           │ HDGL bytecode executes
  ┌────────▼────────┐
  │  Omega Tree     │  ← Glyph nodes created (ROOT, CPU, MEM, IO, etc.)
  └────────┬────────┘
           │ HALT instruction
  ┌────────▼────────┐
  │ Layer-2 Kernel  │  ← Takes over at 0x200000
  │   (Layer 2)     │     - Multitasking
  └─────────────────┘     - Memory management
                          - Device drivers
                          - Module loading
```

## Kernel Components

### 1. `layer2_kernel.asm`
Basic Layer-2 kernel with:
- Handoff from HDGL bytecode
- Protected mode transition
- Minimal VGA/serial output
- Idle loop

### 2. `full_kernel.asm` (Production)
Complete runtime with:
- **Task Queue System**: Foundation for multitasking
- **Module Loader**: Dynamic kernel module loading
- **HDGL Integration**: Links Layer-2 to Omega tree
- **System Info Display**: Reports CPU, memory, PCI devices
- **Tick Counter**: For scheduling and events
- **VGA Console**: Text-based user interface

### 3. `layer2_boot.asm`
Transitional bootloader between HDGL and kernel. Provides:
- Handoff verification
- Error handling
- Fallback to minimal idle

### 4. `module_loader.asm`
Framework for dynamic module loading:
- Module descriptor structure
- Runtime code copying
- Space allocation

### 5. `hdgl_integration.asm`
Bridges Layer-2 with HDGL:
- Omega tree navigation
- Callback setup
- COMPILER node linking

## Data Structures

### Omega Tree (from HDGL)
Located at `0x100000`, 72 bytes per node:
- Offset 0:   Identity (u32)
- Offset 8:   Type/Class (u16)
- Offset 10:  State (u16)
- Offset 12:  Flags (u32)
- Offset 16:  Caps (u64)
- Offset 24:  Parent (u32)
- Offset 28:  Child (u32)
- Offset 32:  Sibling (u32)
- Offset 36-64: CPUID/PCI/Mem data

### Layer-2 Kernel Space (starting 0x200000)
- `km_task_queue`: Task scheduler queue
- `km_modules`: Module loading area
- `km_hdgltree_root`: Pointer to HDGL ROOT node
- `km_hdgltree_compiler`: Pointer to HDGL COMPILER node
- `km_tick_count`: Scheduler tick counter

## Build Instructions

### Prerequisites
- NASM assembler
- Python 3
- QEMU (for testing)

### Build
```bash
chmod +x build_kernel.sh
./build_kernel.sh
```

This produces:
- `hdgl.img` - Complete firmware image (1.5MB)
- `kernel/*.bin` - Individual kernel modules

### Run with QEMU
```bash
qemu-system-x86_64 \
  -drive file=hdgl.img,format=raw,if=floppy \
  -boot order=a \
  -m 64M \
  -no-reboot \
  -serial stdio
```

Expected output:
```
[S0] HDGL boot. Loading Stage1+bytecode...
[S0] Loaded. JMP 0x7E00
[HDGL] CPU: CPUID discovery...
  CPU family: 00060FB1
[HDGL] MEM: memory discovery...
  Conv. mem: XXXX KB
[HDGL] IO: PCI bus scan...
  PCI 0:00:0 ...
[HDGL] PCI scan done: 4 device(s)
[HDGL] Loading bytecode from Stage0 buffer @ 0x9000...
  Bytecode loaded.
[HDGL] Executing HDGL bytecode...
  BC: GLYPH cls=07
  BC: GLYPH cls=06
  BC: GLYPH cls=08
[HDGL] ALIVE. Omega tree built. Idle.

HDGL Full Kernel v0.1
Layer-2 Runtime Environment
------------------------------------------------
CPU: 00060FB1
MEM: 65536 KB
PCI: 4 devices
```

## Extension Points

### 1. Task Scheduler
Currently a placeholder. Extend `km_process_next_task()` to:
- Load task descriptors from HDGL COMPILER node
- Context switch between tasks
- Handle task priorities

### 2. Device Drivers
The PCI scan data in Omega tree can be used to:
- Load appropriate drivers for detected devices
- Initialize interrupt handlers
- Setup DMA channels

### 3. Filesystem
COMPILER node can be programmed to:
- Mount a simple filesystem
- Load kernel modules from disk
- Execute user programs

### 4. Interrupt Handlers
Add interrupt vector table (IVT) support for:
- Timer interrupts (for scheduling)
- Keyboard input
- Serial COM ports
- DMA interrupts

## Future Development

1. **Preemptive Multitasking**: Real time slicing instead of cooperative
2. **Memory Manager**: Virtual memory, paging support
3. **Filesystem**: FAT12/16 support for module loading
4. **Shell**: Command-line interface
5. **Network Stack**: IP/TCP/IPX over detected NIC
6. **Graphics**: Mode X, direct VGA manipulation

## Technical Notes

### Handoff Mechanism
HDGL bytecode interpreter ends with:
```asm
JMP 0x200000  ; Layer-2 entry point
```

The Omega tree at `0x100000` remains intact and serves as:
- Hardware discovery results
- Runtime state
- Module metadata (in COMPILER node)

### Why Layer-2?
Traditional bootloaders don't support:
- Dynamic bytecode execution
- Self-modifying code
- Runtime hardware discovery

Layer-2 provides a stable foundation that can:
- Execute HDGL-created tasks
- Load traditional kernels
- Run as a pure firmware OS

## Debugging

### Serial Output
Run QEMU with:
```bash
-serial stdio
```

### Memory Dump
After boot, dump Omega tree:
```bash
xxd -l 5760 0x100000  # 80 nodes × 72 bytes
```

### Single-Step
Use GDB with QEMU:
```bash
qemu-system-x86_64 \
  -drive file=hdgl.img,format=raw,if=floppy \
  -s -S \
  -m 64M
```

Then in GDB:
```
(gdb) target remote :1234
(gdb) info registers
(gdb) continue
```

## License

This kernel extension is designed to work with HDGL Universal Firmware v0.2.
See main README.md for full license information.
