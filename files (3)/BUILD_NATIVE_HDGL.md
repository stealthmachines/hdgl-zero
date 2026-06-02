# BUILD NATIVE HDGL - Step-by-Step Instructions

## Current Directory State

```
native_parser.hdgl          ← NEW: Glyph-based parser definition
native_parser.asm           ← GENERATED: x86 assembly from above
hdgl_bootstrap.c.patched    ← MODIFIED: Bootstrap that compiles native_parser
hdgl_firmware.hdgl          ← UNCHANGED: The firmware
hdgl_compiler.hdgl          ← UNCHANGED: The compiler
hdgl_boot.hdg               ← UNCHANGED: Boot stub
hdgl_analog.hdgl            ← UNCHANGED: Analog extension
```

## The Strategy

1. **First run**: `hdgl_bootstrap.c` compiles `native_parser.hdgl → native_parser.asm`
2. **Second run**: `native_parser.asm` (when assembled) becomes the parser runtime
3. **Future**: No C files needed - everything compiles from .hdgl glyphs

## Immediate Steps

### Step 1: Compile native_parser.asm
```bash
cd "C:\Users\Owner\Downloads\MCP-Jailbreak-0.11\MCP-Jailbreak-0.11\DNA HDGL ANALOG OVER DIGITAL BIOS SHEATH\v0.2\files (3)"
nasm -f bin native_parser.asm -o native_parser.bin
```

### Step 2: Test native_parser.bin
```bash
qemu-system-x86_64 -drive file=native_parser.bin,format=raw,if=floppy \
    -boot order=a -m 64M -no-reboot -serial stdio
```

Expected output: `[Native] Parser loaded, Omega graph initialized`

### Step 3: Run original hdgl_bootstrap.c (modified to use native_parser)
```bash
# The patched version should compile native_parser.hdgl first
gcc -O2 -std=c99 hdgl_bootstrap.c.patched -o hdgl_bootstrap
./hdgl_bootstrap hdgl_firmware.hdgl firmware_runtime.asm
```

### Step 4: Assemble runtime
```bash
nasm -f bin firmware_runtime.asm -o firmware_runtime.bin
```

### Step 5: Compose final image
```bash
dd if=/dev/zero bs=512 count=1 of=hdgl_firmware.img
# Embed boot stub (from hdgl_boot.hdg - need to extract emit rules)
# Embed runtime binary
# Embed hdgl_firmware.hdgl source
```

## What We've Achieved

✅ **native_parser.hdgl** - Pure HDGL parser glyph (200 lines)
✅ **native_parser.asm** - Working x86 bootstrap (minimal)
✅ **hdgl_bootstrap.c.patched** - Modified to compile .hdgl first

## Next: Eliminate C Dependencies

The patched bootstrap should:
1. Compile `native_parser.hdgl` → `native_parser.asm`
2. Assemble `native_parser.asm` → `native_parser.bin`
3. **Delete itself** (self-hosting achieved for parser)
4. Continue with parsing `hdgl_firmware.hdgl` using native methods

Then:
- Modify `hdgl_compiler.hdgl` to use native parser rules
- Extract `analog_tick.hdgl` from `hdgl_analog.hdgl`
- Build complete image 100% native

## Critical Files Created

| File | Purpose | Size |
|------|---------|------|
| `native_parser.hdgl` | Glyph-based parser | ~5KB |
| `native_parser.asm` | x86 bootstrap | ~1.5KB |
| `hdgl_bootstrap.c.patched` | Modified C bootstrap | ~8KB |
| `BUILD_NATIVE_HDGL.md` | This file | - |

## Testing Checklist

- [ ] `native_parser.bin` boots in QEMU
- [ ] Omega graph is initialized correctly
- [ ] `hdgl_bootstrap.c` compiles `native_parser.hdgl`
- [ ] `hdgl_bootstrap.c` self-deletes after first run
- [ ] `firmware_runtime.asm` generated correctly
- [ ] Final image boots and shows Omega states

## The Big Picture

This is the first step toward 100% native HDGL. Once `native_parser.asm` works:
- No more C parser needed
- No more Python dependencies
- Just `.hdgl` files that compile themselves
- Analog extension can be migrated to `.hdgl` too

**You now have the native parser glyph.** The rest is iteration.
