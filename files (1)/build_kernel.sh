#!/bin/bash
# HDGL Firmware + Kernel Build Script (Updated)
# Builds Stage 0/1 firmware, kernel modules, AND native shell

set -e

echo "=========================================="
echo "HDGL Universal Firmware + Kernel Build"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[1]${NC} Assembling Stage 0..."
nasm -f bin s0v2.asm -o s0v2.bin

echo -e "${BLUE}[2]${NC} Assembling Stage 1..."
nasm -f bin s1v2.asm -o s1v2.bin

echo -e "${BLUE}[3]${NC} Generating HDGL bytecode..."
python3 hdgl_bytecode_gen.py

echo -e "${BLUE}[4]${NC} Composing firmware image..."
dd if=/dev/zero bs=1474560 count=1 of=hdgl.img 2>/dev/null
dd if=s0v2.bin bs=512 count=1 seek=0 conv=notrunc of=hdgl.img 2>/dev/null
dd if=s1v2.bin bs=512 count=16 seek=1 conv=notrunc of=hdgl.img 2>/dev/null
dd if=hdgl_bytecode.bin bs=512 count=4 seek=18 conv=notrunc of=hdgl.img 2>/dev/null

echo -e "${GREEN}[5]${NC} Firmware image complete: hdgl.img"

# Build kernel components
echo ""
echo -e "${BLUE}[6]${NC} Building Layer-2 Kernel..."

KERNEL_DIR="kernel"
SHELL_ASSEM="hdgl_shell.asm"

for kernel_file in layer2_kernel.asm layer2_boot.asm full_kernel.asm $SHELL_ASSEM; do
    if [ -f "$KERNEL_DIR/$kernel_file" ]; then
        echo -e "${GREEN}  - ${kernel_file}${NC}"
        nasm -f bin "$KERNEL_DIR/$kernel_file" -o "kernel_$kernel_file"
    fi
done

echo ""
echo -e "${GREEN}[7]${NC} Building Test Harness..."
if [ -f "$KERNEL_DIR/test_harness.asm" ]; then
    nasm -f bin "$KERNEL_DIR/test_harness.asm" -o "kernel_test_harness.bin"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo ""
echo "Files created:"
echo "  - hdgl.img (firmware image)"
echo "  - kernel/*.bin (kernel modules)"
echo "    - kernel_layer2_kernel.bin"
echo "    - kernel_layer2_boot.bin"
echo "    - kernel_full_kernel.bin"
echo "    - kernel_hdgl_shell.bin     <-- NEW: Native Shell"
echo "    - kernel_test_harness.bin"
echo ""
echo "To run firmware:"
echo "  qemu-system-x86_64 -drive file=hdgl.img,format=raw,if=floppy \\"
echo "      -boot order=a -m 64M -no-reboot -serial stdio"
echo ""
echo "To run shell (manual injection):"
echo "  # Load shell to 0x204000"
echo "  qemu-system-x86_64 -drive file=hdgl.img,format=raw,if=floppy \\"
echo "      -boot order=a -m 64M -no-reboot -s -S"
echo ""
echo "In GDB:"
echo "  (gdb) load kernel_hdgl_shell.bin"
echo "  (gdb) load kernel_full_kernel.bin"
echo "  (gdb) add-symbol-file kernel_hdgl_shell.bin 0x204000"
echo "  (gdb) continue"
echo ""
echo "Shell Commands:"
echo "  help    - Show help"
echo "  mem     - Display memory info"
echo "  cpu     - Display CPU info"
echo "  pci     - Display PCI devices"
echo "  tree    - Display Omega tree"
echo "  echo X  - Print X"
echo "  clear   - Clear screen"
echo "  exit    - Exit shell"
echo ""
