#!/bin/bash
# HDGL Firmware USB Flash Script
# Usage: sudo ./flash_hdgl.sh /dev/sdX
# WARNING: Destroys the first 22 sectors (11264 bytes) of the target device.
# This only touches sectors 0-21 - it does NOT wipe the whole drive.

set -e

TARGET="$1"

if [ -z "$TARGET" ]; then
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Available drives:"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null || ls /dev/sd* /dev/nvme* 2>/dev/null
    exit 1
fi

if [ ! -b "$TARGET" ]; then
    echo "Error: $TARGET is not a block device"
    exit 1
fi

if [ "$(id -u)" != "0" ]; then
    echo "Error: must run as root (sudo)"
    exit 1
fi

# Safety check: don't accidentally wipe system disk
BOOT_DEV=$(df / | tail -1 | cut -d' ' -f1 | sed 's/[0-9]*$//')
if [ "$TARGET" = "$BOOT_DEV" ]; then
    echo "Error: $TARGET appears to be your boot device ($BOOT_DEV)"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
IMG="${SCRIPT_DIR}/hdgl_bare.img"

if [ ! -f "$IMG" ]; then
    echo "Error: hdgl_bare.img not found in $SCRIPT_DIR"
    exit 1
fi

echo "Target:  $TARGET"
echo "Image:   $IMG"
echo "Writing: sectors 0-21 (11264 bytes)"
echo ""
echo "This will overwrite the MBR and first 22 sectors of $TARGET"
read -p "Continue? [y/N] " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# Write only the first 22 sectors
dd if="$IMG" of="$TARGET" bs=512 count=22 oflag=sync
echo ""
echo "Done. Boot from $TARGET to run HDGL firmware."
echo "Serial output on COM1 (9600 8N1)."
echo "VGA output visible if a monitor is connected."
