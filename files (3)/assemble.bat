@echo off
echo HDGL Native Parser Assembly
echo.

echo Finding nasm.exe...
for %%i in (C:\Program Files\NASM\bin\nasm.exe C:\Program Files (x86)\NASM\bin\nasm.exe C:\ProgramData\chocolatey\bin\nasm.exe) do (
    if exist "%%~$PATH:i" set NASM="%%~$PATH:i"
)

if not defined NASM (
    echo NASM not found in common paths. Installing...
    winget install --id NASM.NASM -e --accept-source-agreements -q
    set NASM=C:\ProgramData\chocolatey\bin\nasm.exe
)

if not defined NASM (
    echo Manual installation required. Download from: https://www.nasm.us/
    pause
    exit /b 1
)

echo Using: %NASM%
%NASM% -f bin native_parser.asm -o native_parser.bin
if errorlevel 1 (
    echo ERROR: Assembly failed
    pause
    exit /b 1
)

echo SUCCESS: native_parser.bin created
echo Size: %ERRORLEVEL% bytes

echo.
echo Test in QEMU (close window when done):
"C:\Program Files\qemu\qemu-system-i386.exe" -drive file=native_parser.bin,format=raw,if=floppy -boot a -m 64M -no-reboot -serial stdio
