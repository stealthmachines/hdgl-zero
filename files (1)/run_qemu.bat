@echo off
REM HDGL Universal Firmware QEMU Launcher
REM Quick boot - serial output only

echo Starting HDGL Firmware in QEMU...
echo.

"C:\Program Files\qemu\qemu-system-i386.exe" ^
    -drive file=hdgl.img,format=raw,if=floppy ^
    -boot order=a ^
    -m 64M ^
    -no-reboot ^
    -serial stdio ^
    -display none

echo.
echo Firmware test complete.
pause
