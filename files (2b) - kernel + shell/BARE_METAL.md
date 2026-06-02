# HDGL Firmware — Bare Metal Guide

## What you need
- x86 PC or laptop (any hardware from ~2000 onwards)
- USB drive ≥ 64KB (seriously — we only use 11264 bytes)
- Linux machine to write the image

## Flash to USB

```bash
# Find your USB device (look for the right size)
lsblk -d -o NAME,SIZE,MODEL

# Flash (replace sdX with your device — BE CAREFUL)
sudo ./flash_hdgl.sh /dev/sdX

# Or manually:
sudo dd if=hdgl_bare.img of=/dev/sdX bs=512 count=22 oflag=sync
```

Only the first 22 sectors (11264 bytes) are written. The rest of the USB is untouched.

## Boot it

1. Plug USB into the target machine
2. Enter BIOS/firmware setup (F2, F12, DEL, ESC at POST)
3. Set boot order: USB first, then internal disk
4. **Disable Secure Boot** (required — we have no Microsoft signing key)
5. Enable **Legacy/CSM boot** if available (not UEFI boot)
6. Save and reboot

## What you'll see

On VGA: the HDGL banner will appear (Stage0 uses INT 10h for VGA output before PM).
On serial (COM1, 9600 8N1): full boot trace.

```
[S0]S1 OK
[S0]BC OK
[S0]Go.

=== HDGL Universal Firmware v0.2 ===
NO UEFI | Layer-0 + Layer-1 + Discovery + Bytecode

[HDGL] CPU: CPUID discovery...
  CPU family: XXXXXXXX  FPU SSE
[HDGL] MEM: E820: XX entries  Total usable: XXXXXXXX KB
[HDGL] IO: PCI bus scan...
  PCI 0:00:0 XXXX:XXXX cls=06   ← your host bridge
  PCI 0:01:0 XXXX:XXXX cls=XX   ← your devices
  ...
[HDGL] Executing HDGL bytecode...
  BC: SELFMOD → COMPILER EXECUTED. Bytecode rewritten.
  NODE cls=04 05                 ← COMPILER: EXECUTED
  BC: HALT
[HDGL] ALIVE. Omega tree built. Idle.
```

Then the system enters an idle HLT loop — it's alive.

## What's happening

The firmware has no OS, no filesystem, no keyboard handler. It:

1. Discovers real hardware via CPUID, INT 15h E820, PCI config space
2. Builds the Omega glyph tree representing your actual hardware
3. Loads and executes HDGL bytecode (compiled from `firmware.hdgl`)
4. The COMPILER node rewrites the bytecode in memory and re-runs it
5. Halts with the complete hardware graph in RAM at 0x100000

The glyph tree is at physical address 0x100000 (1MB). Each Omega node is 72 bytes.

## Common issues

**Nothing on screen**: Normal if you have no serial. The firmware runs but there's
no display driver beyond the Stage0 VGA print via INT 10h (which only works before
protected mode entry). A monitor plugged into the VGA port should show the banner.

**System reboots**: Usually means a triple fault in Stage1 PM entry. The A20 gate
and GDT may be configured differently on real hardware. The fast A20 (port 0x92)
works on most modern boards; some older boards need the keyboard controller method.

**Disk error**: The LBA extension path (INT 13h AH=42h) should work on any USB
boot. If it fails, check the BIOS reports the device as bootable via legacy mode.

**Secure Boot error**: Disable Secure Boot in BIOS. We don't have a signing key.

## Disk layout

```
Sector 0       (512B)   MBR: Stage0 boot code + partition table
Sectors 1-16   (8KB)    Stage1: hardware discovery + HDGL runtime
Sector 17      (512B)   Padding (empty)
Sectors 18-21  (2KB)    HDGL bytecode payload

Partition table:
  Entry 1: type=0xDA (non-FS), bootable, LBA 1-21
```

## Building from source

```bash
nasm -f bin s0v3_compact.asm -o s0v3_compact.bin
# Inject partition table:
python3 inject_mpt.py s0v3_compact.bin
nasm -f bin s1v3.asm -o s1v3.bin
python3 hdgl_bytecode_gen.py

# Compose image:
dd if=/dev/zero bs=10485760 count=1 of=hdgl_bare.img
dd if=s0v3_compact.bin bs=512 count=1  seek=0  conv=notrunc of=hdgl_bare.img
dd if=s1v3.bin         bs=512 count=16 seek=1  conv=notrunc of=hdgl_bare.img
dd if=hdgl_bytecode.bin bs=512 count=4 seek=18 conv=notrunc of=hdgl_bare.img
```
