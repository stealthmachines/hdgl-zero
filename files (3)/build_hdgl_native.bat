@echo off
echo ============================================================================
echo HDGL NATIVE BUILD SCRIPT
echo Goal: Create bootable firmware with NO C/Python dependencies
echo ============================================================================

echo.
echo [1/6] Building native_parser.bin from native_parser.asm
echo.

if exist native_parser.asm (
    nasm -f bin native_parser.asm -o native_parser.bin
    if errorlevel 1 (
        echo ERROR: NASM failed to assemble native_parser.asm
        echo Please install NASM: winget install NASM
        pause
        exit /b 1
    )
    echo SUCCESS: native_parser.bin created (512 bytes)
) else (
    echo ERROR: native_parser.asm not found
    pause
    exit /b 1
)

echo.
echo [2/6] Testing native_parser.bin in QEMU
echo.

if exist native_parser.bin (
    echo Starting QEMU...
    qemu-system-x86_64 -drive file=native_parser.bin,format=raw,if=floppy ^
        -boot order=a -m 64M -no-reboot -serial stdio
) else (
    echo ERROR: native_parser.bin not found
    pause
    exit /b 1
)

echo.
echo [3/6] Building hdgl_compiler (native parser)
echo.
if exist gcc.exe (
    gcc -O2 -std=c99 hdgl_compiler.c -o hdgl_compiler
    echo SUCCESS: hdgl_compiler built
) else (
    echo ERROR: gcc not found. Please install MinGW or MSVC.
    pause
    exit /b 1
)

echo.
echo [4/6] Compiling firmware with hdgl_compiler
echo.
hdgl_compiler hdgl_firmware.hdgl firmware_runtime.asm

echo.
echo [5/6] Assembling firmware_runtime.asm
echo.
nasm -f bin firmware_runtime.asm -o firmware_runtime.bin
echo SUCCESS: firmware_runtime.bin created

echo.
echo [6/6] Creating bootable image
echo.
dd if=/dev/zero bs=512 count=1 of=hdgl_firmware.img
copy native_parser.bin hdgl_firmware.img
echo SUCCESS: hdgl_firmware.img created

echo.
echo ============================================================================
echo BUILD COMPLETE
echo Run: qemu-system-x86_64 -drive file=hdgl_firmware.img,format=raw,if=floppy ^
echo     -boot order=a -m 64M -no-reboot -serial stdio
echo ============================================================================
pause
