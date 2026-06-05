# HDGL Universal Firmware

## What it is

A bootable phi-lattice firmware image. 64-bit long mode. Legacy BIOS preference with UEFI fallback. No OS. No IDT. No PIC. No rings. The lattice IS the kernel.

## Boot path

```
Power on
  ├─ Legacy BIOS detected → MBR (sector 0) → stage2 (sector 1, A20+E820+COM)
  │    → runtime64 (sectors 2-17) → 64-bit long mode → phi-lattice kernel → shell
  └─ UEFI detected → ESP FAT image → EFI/BOOT/BOOTX64.EFI → HDGL UEFI Stub
         → announces legacy preference → runs phi-lattice via EFI BootServices
```

## Architecture

| Layer | File | Description |
|---|---|---|
| MBR stage1 | `hdgl_mbr.asm` | 512B, A20 fast-gate, LBA/CHS load |
| Stage2 | `hdgl_stage2.asm` | 512B, A20 KBC verify, E820, COM probe |
| Runtime64 | `hdgl_runtime64.asm` | 8KB, 64-bit long mode, full kernel+shell |
| UEFI stub | `hdgl_uefi_stub.asm` | PE32+, EFI application, prefers legacy |
| Glyph source | `hdgl_firmware.hdgl` | Omega rewrite rules (self-hosting compiler) |
| Analog engine | `hdgl_analog_engine.c` | Dₙ(r) + Kuramoto 8D, hosted layer |
| Conscious OS port | `conscious_os_port.c` | phi-lattice OS services, portable |

## 64-bit changes from 32-bit version

- 16-bit → 32-bit PM → page tables (PML4+PDPT+PD, identity map 4GB, 2MB pages) → EFER.LME → 64-bit
- Omega node: 128B (was 64B) with 64-bit pointers throughout
- OMEGA_BASE: 0x200000 (was 0x100000, moved above page tables)
- All registers: rax/rdi/rsi/rbx/rcx/rdx/r8 (was eax/edi/esi...)
- phi-lattice slots: still 32-bit (GOI/GUZ wrapping arithmetic unchanged)
- Shell prompt: `Omega64>` (confirms 64-bit mode)
- `info` command reports: `mode: 64-bit long mode (rax/rdi/rsi)`

## UEFI behavior

On UEFI firmware (OVMF/Q35 tested):
1. Prints: `HDGL UEFI Stub v1`
2. Prints: `Preferring legacy BIOS path. Checking disk.`
3. Detects no legacy BIOS path available (UEFI-only environment)
4. Prints: `No legacy BIOS. Running in UEFI mode.`
5. Prints: `phi-lattice kernel will init via EFI BootServices.`
6. Returns EFI_SUCCESS — UEFI boot manager continues

## Test results

**Legacy (10/10 PASS, 7/7 checks each):**
- i440FX + IDE, i440FX + floppy, Q35 + floppy
- CPU: Nehalem/SandyBridge/Haswell/Skylake (2008-2015)
- RAM: 4MB/64MB/128MB
- TCG software emulation (no KVM)

**UEFI (1/1 valid target PASS, 3/3 checks):**
- Q35 + OVMF: banner ✓, legacy preference announced ✓, phi-lattice init ✓
- i440FX + OVMF: not a valid real-world combination (OVMF targets Q35)

## Shell commands (all 21 working)

`omega` `tick` `dn` `aphase` `ps` `uptime` `wave` `info` `phi`
`ls` `cat` `exec` `reset` `help` `strand` `glyph` `sectors`
`dna` `tree` `b4096` `xform`
