#!/usr/bin/env python3
"""Inject MBR partition table into s0v3.bin (must be pre-assembled)."""
import struct, sys

fname = sys.argv[1] if len(sys.argv) > 1 else 's0v3.bin'
with open(fname, 'rb') as f:
    mbr = bytearray(f.read())

assert len(mbr) == 512 and mbr[510] == 0x55 and mbr[511] == 0xAA, \
    "Not a valid 512-byte boot sector"

# Check partition table area is unused (code should fit in 446 bytes)
if any(mbr[446:446+64]):
    print("WARNING: partition table area not empty, overwriting anyway")

def pack_part(bootable, ptype, lba_start, lba_size):
    status = 0x80 if bootable else 0x00
    chs_s = bytes([0x00, 0x02, 0x00])
    chs_e = bytes([0x00, 0xFF, 0xFF])
    return struct.pack('<B3sB3sII', status, chs_s, ptype, chs_e, lba_start, lba_size)

mbr[446:462] = pack_part(True, 0xDA, 1, 21)  # HDGL payload partition
mbr[462:510] = bytes(48)                       # empty entries 2-4

with open(fname, 'wb') as f:
    f.write(mbr)

print(f"Partition table written to {fname}")
print(f"  Entry 1: type=0xDA, bootable, LBA 1-21 (21 sectors)")
