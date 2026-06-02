#!/bin/bash
# HDGL Firmware v0.3 - Self-Defining Build
# ==========================================
# This script compiles the HDGL firmware from its own source.
# The firmware defines itself: source, compiler, runtime, disk layout -
# all expressed as glyph definitions and rewrite rules in .hdgl/.hdg files.
#
# Build chain:
#   hdgl_firmware.hdgl  (glyph source - the firmware defining itself)
#         ↓ hdgl_bootstrap (parses .hdgl, builds Omega graph, emits x86)
#   firmware_runtime.asm (x86 assembly emitted from glyph rewrites)
#         ↓ nasm
#   firmware_runtime.bin (runtime binary - 8192 bytes = 16 sectors)
#
#   hdgl_boot.hdg       (boot stub glyph with embedded x86 emit rules)
#         ↓ extract + nasm
#   hdgl_boot_stub.bin  (MBR boot sector - 512 bytes)
#
#   hdgl_firmware.img   (bootable image: boot stub + runtime + HDGL source)
#
# Self-defining property:
#   hdgl_firmware.hdgl is embedded in hdgl_firmware.img (sectors 18+)
#   The running firmware reads it from disk at 0xA000
#   The COMPILER glyph (node 4) has the source address stored in its transform field
#   This is the fixed point: the system carries and can read its own definition

set -e

echo "[HDGL] Building bootstrap compiler..."
gcc -O2 -std=c99 hdgl_bootstrap.c -o hdgl_bootstrap

echo "[HDGL] Parsing hdgl_firmware.hdgl → Omega graph → x86 assembly..."
./hdgl_bootstrap hdgl_firmware.hdgl firmware_runtime.asm

echo "[HDGL] Assembling runtime..."
nasm -f bin firmware_runtime.asm -o firmware_runtime.bin
echo "  firmware_runtime.bin: $(wc -c < firmware_runtime.bin) bytes"

echo "[HDGL] Extracting boot stub from hdgl_boot.hdg..."
python3 extract_boot_stub.py

echo "[HDGL] Assembling boot stub..."
nasm -f bin hdgl_boot_stub.asm -o hdgl_boot_stub.bin
echo "  hdgl_boot_stub.bin: $(wc -c < hdgl_boot_stub.bin) bytes"

echo "[HDGL] Composing firmware image..."
SOURCE_SECS=$(( ($(wc -c < hdgl_firmware.hdgl) + 511) / 512 ))
IMAGE_SIZE=$(( (18 + SOURCE_SECS) * 512 ))
dd if=/dev/zero bs=$IMAGE_SIZE count=1 of=hdgl_firmware.img 2>/dev/null
dd if=hdgl_boot_stub.bin    bs=512 count=1            seek=0  conv=notrunc of=hdgl_firmware.img 2>/dev/null
dd if=firmware_runtime.bin  bs=512 count=16           seek=1  conv=notrunc of=hdgl_firmware.img 2>/dev/null
dd if=hdgl_firmware.hdgl    bs=512 count=$SOURCE_SECS seek=18 conv=notrunc of=hdgl_firmware.img 2>/dev/null
echo "  hdgl_firmware.img: $(wc -c < hdgl_firmware.img) bytes ($((IMAGE_SIZE/512)) sectors)"
echo "  Layout: [boot:0][runtime:1-16][pad:17][source:18-$((17+SOURCE_SECS))]"

echo ""
echo "[HDGL] Done. Run with:"
echo "  qemu-system-x86_64 -drive file=hdgl_firmware.img,format=raw,if=floppy \\"
echo "    -boot order=a -m 64M -no-reboot -serial stdio"
