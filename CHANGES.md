# HDGL CD Boot — Drop-in Changes

Drop these files into your hdgl_complete.zip structure.
No other files change. Rebuild with ./build.sh.

## Files changed

| File | Change |
|---|---|
| `src/hdgl_mbr.asm` | CD detection via boot-info-table `bi_pvd==16`; COM1 init in CD path; stores `0x3F8` to `[0x7FEC]` before jump |
| `src/hdgl_stage2.asm` | Added `.et_path`: detects El Torito boot (`DL<0x80`), skips disk reads, jumps directly to `0x8000` |
| `src/hdgl_stage2_cd.asm` | **NEW** — minimal 12-byte CD stub used only inside the ISO payload |
| `src/make_iso.py` | **NEW** — pure-Python El Torito ISO builder (fallback if `genisoimage`/`mkisofs` absent) |
| `build.sh` | Updated — adds step [7] ISO build using CD-specific stage2 in El Torito payload |

## Why two stage2 files?

`hdgl_stage2.asm` (full, for disk image sector 1): handles A20 verify + KBC
fallback, E820 memory map, COM probe, LBA/CHS runtime load. All the real-mode
work needed before protected mode.

`hdgl_stage2_cd.asm` (minimal, for ISO El Torito payload sector 1): 12 bytes.
`mov word [0x7FEC], 0x3F8` then `jmp 0x0000:0x8000`. That's it.

Why? The full stage2's `probe_com` call zeros `[0x7FEC]` before detecting the
port, then fails under ATAPI — leaving the COM base as 0 and silencing all
serial output. The MBR CD path already initializes COM1 hardware before jumping
to stage2; stage2 just needs to record the base and hand off to runtime64.

## Boot-info-table mechanics

`genisoimage -boot-info-table` patches bytes 8-63 of the boot sector:
- `[8:12]`  `bi_pvd` → LBA of Primary Volume Descriptor (= 16)
- `[12:16]` `bi_file` → LBA of boot image in ISO
- `[16:20]` `bi_length` → byte length of boot image
- `[20:64]` zeroed

Code in MBR must start at byte ≥ 64. Our MBR uses `JMP short` at byte 0
to skip the reserved 8-63 area and reach code at byte 64.

CD detection: `cmp dword [.bi_pvd], 16` at runtime. On raw disk, `bi_pvd`
stays 0. On ISO, genisoimage patches it to 16. Clean, no DL ambiguity.

## QEMU commands

```bash
# Disk
qemu-system-x86_64 -drive file=bin/hdgl_universal.img,format=raw,if=ide \
    -boot order=c -m 64M -serial stdio

# Virtual CD
qemu-system-x86_64 \
    -drive id=cd0,file=bin/hdgl_boot.iso,format=raw,if=none,media=cdrom \
    -device ide-cd,drive=cd0,bus=ide.1 \
    -boot order=d -m 64M -serial stdio

# Burn to real CD
cdrecord dev=/dev/cdrom bin/hdgl_boot.iso

# IPMI / iDRAC / iLO virtual media
# Upload hdgl_boot.iso as virtual CD-ROM
```

## Test results

| Config | Disk | CD |
|---|---|---|
| i440FX 64MB | ✓ | ✓ |
| Q35 64MB | ✓ | ✓ |
| CPU: Haswell | ✓ | ✓ |
| 4MB RAM | ✓ | — |
| 128MB RAM | ✓ | ✓ |
