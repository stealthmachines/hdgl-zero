#!/bin/bash
# HDGL Universal Firmware — build with virtual CD support
# Requires: nasm, gcc, genisoimage
set -e

echo "[1] MBR stage1 (512B, dual disk+CD)..."
nasm -f bin src/hdgl_mbr.asm -o bin/hdgl_mbr.bin

echo "[2] Stage2 stub (512B, full disk path)..."
nasm -f bin src/hdgl_stage2.asm -o bin/hdgl_stage2.bin

echo "[3] Stage2 CD stub (512B, minimal El Torito path)..."
nasm -f bin src/hdgl_stage2_cd.asm -o bin/hdgl_stage2_cd.bin

echo "[4] Runtime64 (8KB, 64-bit long mode)..."
nasm -f bin src/hdgl_runtime64.asm -o bin/hdgl_runtime64.bin

echo "[5] UEFI stub..."
nasm -f bin src/hdgl_uefi_stub.asm -o uefi/BOOTX64.EFI

echo "[6] Conscious OS port self-test..."
gcc -O3 -std=c99 -D_POSIX_C_SOURCE=200809L \
    src/conscious_os_port.c -o bin/cos_test -lm
./bin/cos_test

echo "[7] Disk image (uses full stage2)..."
SRC=src/hdgl_firmware.hdgl
SRCSEC=$(( ($(wc -c < $SRC) + 511)/512 ))
TOTAL=$(( 18 + SRCSEC + 4 ))
dd if=/dev/zero bs=512 count=$TOTAL of=bin/hdgl_universal.img 2>/dev/null
dd if=bin/hdgl_mbr.bin          bs=512 count=1        seek=0  conv=notrunc of=bin/hdgl_universal.img 2>/dev/null
dd if=bin/hdgl_stage2.bin       bs=512 count=1        seek=1  conv=notrunc of=bin/hdgl_universal.img 2>/dev/null
dd if=bin/hdgl_runtime64.bin    bs=512 count=16       seek=2  conv=notrunc of=bin/hdgl_universal.img 2>/dev/null
dd if=$SRC                      bs=512 count=$SRCSEC  seek=18 conv=notrunc of=bin/hdgl_universal.img 2>/dev/null

echo "[8] CD ISO image (uses minimal CD stage2)..."
# El Torito payload: MBR + CD-stage2 + runtime64 (the 18 sectors SeaBIOS loads)
# stage2_cd is the minimal stub — avoids ATAPI load corruption of full stage2
mkdir -p /tmp/hdgl_iso_work
dd if=/dev/zero bs=512 count=18 of=/tmp/hdgl_iso_work/hdgl_payload.img 2>/dev/null
dd if=bin/hdgl_mbr.bin       bs=512 count=1  seek=0  conv=notrunc of=/tmp/hdgl_iso_work/hdgl_payload.img 2>/dev/null
dd if=bin/hdgl_stage2_cd.bin bs=512 count=1  seek=1  conv=notrunc of=/tmp/hdgl_iso_work/hdgl_payload.img 2>/dev/null
dd if=bin/hdgl_runtime64.bin bs=512 count=16 seek=2  conv=notrunc of=/tmp/hdgl_iso_work/hdgl_payload.img 2>/dev/null

if command -v genisoimage &>/dev/null; then
    genisoimage -quiet \
        -o bin/hdgl_boot.iso \
        -b hdgl_payload.img \
        -no-emul-boot \
        -boot-load-size 18 \
        -boot-info-table \
        -V "HDGL_BOOT" \
        /tmp/hdgl_iso_work
elif command -v mkisofs &>/dev/null; then
    mkisofs -quiet \
        -o bin/hdgl_boot.iso \
        -b hdgl_payload.img \
        -no-emul-boot \
        -boot-load-size 18 \
        -boot-info-table \
        -V "HDGL_BOOT" \
        /tmp/hdgl_iso_work
else
    python3 src/make_iso.py /tmp/hdgl_iso_work/hdgl_payload.img bin/hdgl_boot.iso
fi
rm -rf /tmp/hdgl_iso_work

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Artifacts:"
echo "    bin/hdgl_universal.img   raw disk image (legacy BIOS)"
echo "    bin/hdgl_boot.iso        virtual CD (El Torito, IPMI/iDRAC/iLO)"
echo "    uefi/BOOTX64.EFI         UEFI application"
echo ""
echo "  Run (disk):  qemu-system-x86_64 -drive file=bin/hdgl_universal.img,format=raw,if=ide -boot order=c -m 64M -serial stdio"
echo "  Run (CD):    qemu-system-x86_64 -drive id=cd0,file=bin/hdgl_boot.iso,format=raw,if=none,media=cdrom -device ide-cd,drive=cd0,bus=ide.1 -boot order=d -m 64M -serial stdio"
echo "  Flash disk:  dd if=bin/hdgl_universal.img of=/dev/sdX bs=512 oflag=sync"
echo "  Burn CD:     cdrecord dev=/dev/cdrom bin/hdgl_boot.iso"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
