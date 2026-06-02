# HDGL Firmware QEMU Launcher - Shell/GDB Mode (PowerShell)

Write-Host "Starting HDGL Firmware in QEMU (Shell Development Mode)..." -ForegroundColor Cyan
Write-Host ""

# Use -display sdl for i386 (not virt)
& "C:\Program Files\qemu\qemu-system-i386.exe" `
    -drive file=hdgl.img,format=raw,if=floppy `
    -boot order=a `
    -m 64M `
    -no-reboot `
    -s `
    -S `
    -display sdl `
    -serial stdio

Write-Host ""
Write-Host "QEMU started with GDB stub on port 1234" -ForegroundColor Yellow
Write-Host ""
Write-Host "IN ANOTHER TERMINAL, USE GDB:" -ForegroundColor Cyan
Write-Host "  gdb" -ForegroundColor White
Write-Host "  (gdb) target remote :1234" -ForegroundColor White
Write-Host "  (gdb) load kernel_hdgl_shell.bin" -ForegroundColor White
Write-Host "  (gdb) load kernel_full_kernel.bin" -ForegroundColor White
Write-Host "  (gdb) continue" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to stop QEMU..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
