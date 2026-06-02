@echo off
REM HDGL Firmware QEMU Launcher - Full VGA Display

echo Starting HDGL Firmware in QEMU (Full VGA Display)...
echo.

"C:\Program Files\qemu\qemu-system-i386.exe" ^
    -drive file=hdgl.img,format=raw,if=floppy ^
    -boot order=a ^
    -m 64M ^
    -no-reboot ^
    -display virt ^
    -serial stdio

echo.
echo Firmware test complete.
pause
