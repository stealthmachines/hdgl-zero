# HDGL Firmware + Kernel Build Script (PowerShell)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "HDGL Universal Firmware + Kernel Build" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Colors
function Write-Green { param($text) Write-Host $text -ForegroundColor Green }
function Write-Blue { param($text) Write-Host $text -ForegroundColor Blue }

Write-Blue "[1] Assembling Stage 0..."
& "nasm" "-f bin" "s0v2.asm" "-o s0v2.bin"

Write-Blue "[2] Assembling Stage 1..."
& "nasm" "-f bin" "s1v2.asm" "-o s1v2.bin"

Write-Blue "[3] Generating HDGL bytecode..."
& "python3" "hdgl_bytecode_gen.py"

Write-Blue "[4] Composing firmware image..."
& "dd" "if=\\dev\zero" "bs=1474560" "count=1" "of=hdgl.img" 2>$null
& "dd" "if=s0v2.bin" "bs=512" "count=1" "seek=0" "conv=notrunc" "of=hdgl.img" 2>$null
& "dd" "if=s1v2.bin" "bs=512" "count=16" "seek=1" "conv=notrunc" "of=hdgl.img" 2>$null
& "dd" "if=hdgl_bytecode.bin" "bs=512" "count=4" "seek=18" "conv=notrunc" "of=hdgl.img" 2>$null

Write-Green "[5] Firmware image complete: hdgl.img"

# Build kernel components
Write-Blue "[6] Building Layer-2 Kernel..."

$kernelFiles = @("layer2_kernel.asm", "layer2_boot.asm", "full_kernel.asm", "hdgl_shell.asm", "test_harness.asm")

foreach ($file in $kernelFiles) {
    if (Test-Path "kernel\$file") {
        Write-Green "  - $file"
        & "nasm" "-f bin" "kernel\$file" "-o kernel_$file"
    }
}

Write-Host ""
Write-Green "========================================="
Write-Green "Build Complete!"
Write-Host ""
Write-Host "Files created:" -ForegroundColor Yellow
Write-Host "  - hdgl.img (firmware image)"
Write-Host "  - kernel/*.bin (kernel modules)"
Write-Host ""
Write-Host "To run firmware:" -ForegroundColor Yellow
Write-Host "  .\run_qemu.bat         - Quick boot (serial)"
Write-Host "  .\run_qemu_full.ps1    - Full VGA display"
Write-Host "  .\run_qemu_shell.ps1   - Shell/GDB mode"
Write-Host ""
Write-Host "Quick test:" -ForegroundColor Yellow
Write-Host "  .\build_kernel.ps1 && .\run_qemu.ps1"
Write-Host ""
