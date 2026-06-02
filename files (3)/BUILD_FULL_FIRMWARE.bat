@echo off
setlocal enabledelayedexpansion

echo ============================================================================
echo HDGL FULL FIRMWARE BUILD
echo Goal: Create bootable firmware with analog extension
echo ============================================================================
echo.

echo [1/8] Assembling native_parser.asm
nasm -f bin native_parser.asm -o native_parser.bin
if errorlevel 1 (
    echo ERROR: NASM failed
    pause
    exit /b 1
)
echo SUCCESS: native_parser.bin

echo.
echo [2/8] Compiling hdgl_bootstrap.c
gcc -O2 -std=c99 hdgl_bootstrap.c.patched -o hdgl_bootstrap.exe
if errorlevel 1 (
    echo ERROR: GCC failed
    echo Install MinGW: winget install "MinGW.org Gitlab.mingw"
    pause
    exit /b 1
)
echo SUCCESS: hdgl_bootstrap.exe

echo.
echo [3/8] Running hdgl_bootstrap (compiles native_parser.hdgl)
hdgl_bootstrap.exe
if errorlevel 1 (
    echo ERROR: hdgl_bootstrap failed
    pause
    exit /b 1
)
echo SUCCESS: Native parser compiled

echo.
echo [4/8] Compiling firmware with native parser
hdgl_bootstrap.exe hdgl_firmware.hdgl firmware_runtime.asm
if errorlevel 1 (
    echo ERROR: Firmware compilation failed
    pause
    exit /b 1
)
echo SUCCESS: firmware_runtime.asm

echo.
echo [5/8] Assembling firmware_runtime.asm
nasm -f bin firmware_runtime.asm -o firmware_runtime.bin
echo SUCCESS: firmware_runtime.bin

echo.
echo [6/8] Creating minimal boot stub (512 bytes)
dd if=CON nul of=hdgl_boot_stub.bin bs=512 count=1
echo SUCCESS: hdgl_boot_stub.bin

echo.
echo [7/8] Composing final firmware image
copy /b hdgl_boot_stub.bin+firmware_runtime.bin+hdgl_firmware.hdgl hdgl_firmware.img
echo SUCCESS: hdgl_firmware.img

echo.
echo [8/8] Verifying image
echo Image size: %ERRORLEVEL% bytes
attrib hdgl_firmware.img

echo.
echo ============================================================================
echo BUILD COMPLETE!
echo.
echo Run in QEMU:
echo   "C:\Program Files\qemu\qemu-system-i386.exe" -drive file=hdgl_firmware.img,format=raw,if=floppy ^
echo     -boot a -m 64M -no-reboot -serial stdio
echo ============================================================================

pause
