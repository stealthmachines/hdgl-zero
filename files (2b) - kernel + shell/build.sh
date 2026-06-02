#!/bin/bash
# HDGL v0.3 Build Script
set -e
echo "[BUILD] Stage0..."
nasm -f bin s0v3.asm -o s0v3.bin
python3 inject_mpt.py s0v3.bin

echo "[BUILD] Stage1..."
nasm -f bin s1v3.asm -o s1v3.bin

echo "[BUILD] Bytecode..."
python3 hdgl_bytecode_gen.py

echo "[BUILD] Composing images..."
# Floppy (for QEMU testing)
dd if=/dev/zero bs=1474560 count=1 of=hdgl_floppy.img 2>/dev/null
dd if=s0v3.bin          bs=512 count=1  seek=0  conv=notrunc of=hdgl_floppy.img 2>/dev/null
dd if=s1v3.bin          bs=512 count=16 seek=1  conv=notrunc of=hdgl_floppy.img 2>/dev/null
dd if=hdgl_bytecode.bin bs=512 count=4  seek=18 conv=notrunc of=hdgl_floppy.img 2>/dev/null

# Bare metal HDD/USB image (10MB, but only first 22 sectors matter)
dd if=/dev/zero bs=10485760 count=1 of=hdgl_bare.img 2>/dev/null
dd if=s0v3.bin          bs=512 count=1  seek=0  conv=notrunc of=hdgl_bare.img 2>/dev/null
dd if=s1v3.bin          bs=512 count=16 seek=1  conv=notrunc of=hdgl_bare.img 2>/dev/null
dd if=hdgl_bytecode.bin bs=512 count=4  seek=18 conv=notrunc of=hdgl_bare.img 2>/dev/null

echo "[BUILD] Done."
echo ""
echo "QEMU floppy test:"
echo "  qemu-system-x86_64 -drive file=hdgl_floppy.img,format=raw,if=floppy -boot order=a -m 64M -no-reboot -serial stdio"
echo ""
echo "QEMU HDD test (LBA path):"
echo "  qemu-system-x86_64 -drive file=hdgl_bare.img,format=raw,if=ide -boot order=c -m 64M -no-reboot -serial stdio"
echo ""
echo "USB flash (bare metal):"
echo "  sudo ./flash_hdgl.sh /dev/sdX"
