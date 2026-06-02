@echo off
echo ============================================================================
echo HDGL NATIVE PARSER - ASSEMBLE AND TEST
echo ============================================================================
echo.

echo [1/2] Assembling native_parser.asm to native_parser.bin
nasm -f bin native_parser.asm -o native_parser.bin

if errorlevel 1 (
    echo ERROR: NASM failed!
    echo Please ensure NASM is installed and in PATH.
    echo Install: winget install NASM.NASM
    pause
    exit /b 1
)

echo.
echo [2/2] Testing in QEMU
echo.
echo Starting QEMU... (Close this window when done)
echo.

"C:\Program Files\qemu\qemu-system-i386.exe" -drive file=native_parser.bin,format=raw,if=floppy ^
    -boot a -m 64M -no-reboot -serial stdio

echo.
echo Done!
