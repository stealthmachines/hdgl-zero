@echo off
REM HDGL Firmware QEMU Launcher - Shell/GDB Mode

echo Starting HDGL Firmware in QEMU (Shell Development Mode)...
echo.

"C:\Program Files\qemu\qemu-system-i386.exe" ^
    -drive file=hdgl.img,format=raw,if=floppy ^
    -boot order=a ^
    -m 64M ^
    -no-reboot ^
    -s ^
    -S ^
    -display virt ^
    -serial stdio

echo.
echo QEMU started with GDB stub on port 1234
echo.
echo IN ANOTHER TERMINAL, USE GDB:
echo   gdb
echo   (gdb) target remote :1234
echo   (gdb) load kernel_hdgl_shell.bin
echo   (gdb) load kernel_full_kernel.bin
echo   (gdb) continue
echo.
pause
