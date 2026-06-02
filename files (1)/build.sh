#!/bin/bash
# HDGL Firmware v0.2 Build Script
set -e

echo "[BUILD] Assembling Stage0..."
nasm -f bin s0v2.asm -o s0v2.bin

echo "[BUILD] Assembling Stage1..."
nasm -f bin s1v2.asm -o s1v2.bin

echo "[BUILD] Generating HDGL bytecode..."
python3 hdgl_bytecode_gen.py

echo "[BUILD] Composing floppy image..."
dd if=/dev/zero bs=1474560 count=1 of=hdgl.img 2>/dev/null
dd if=s0v2.bin         bs=512 count=1  seek=0  conv=notrunc of=hdgl.img 2>/dev/null
dd if=s1v2.bin         bs=512 count=16 seek=1  conv=notrunc of=hdgl.img 2>/dev/null
dd if=hdgl_bytecode.bin bs=512 count=4 seek=18 conv=notrunc of=hdgl.img 2>/dev/null

echo "[BUILD] Done. Image: hdgl.img"
echo ""
echo "[RUN]  qemu-system-x86_64 -drive file=hdgl.img,format=raw,if=floppy -boot order=a -m 64M -no-reboot -serial stdio"
