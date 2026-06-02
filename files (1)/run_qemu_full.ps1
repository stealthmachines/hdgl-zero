# HDGL Firmware QEMU Launcher - Full VGA Display (PowerShell)

Write-Host "Starting HDGL Firmware in QEMU (Full VGA Display)..." -ForegroundColor Cyan
Write-Host ""

# Use -display sdl for i386 (not virt)
& "C:\Program Files\qemu\qemu-system-i386.exe" `
    -drive file=hdgl.img,format=raw,if=floppy `
    -boot order=a `
    -m 64M `
    -no-reboot `
    -display sdl `
    -serial stdio

Write-Host ""
Write-Host "Firmware test complete." -ForegroundColor Green
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
