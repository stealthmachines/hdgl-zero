# HDGL Universal Firmware QEMU Launcher (PowerShell)
# Quick boot - serial output only

Write-Host "Starting HDGL Firmware in QEMU..." -ForegroundColor Cyan
Write-Host ""

& "C:\Program Files\qemu\qemu-system-i386.exe" `
    -drive file=hdgl.img,format=raw,if=floppy `
    -boot order=a `
    -m 64M `
    -no-reboot `
    -serial stdio `
    -display none

Write-Host ""
Write-Host "Firmware test complete." -ForegroundColor Green
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
