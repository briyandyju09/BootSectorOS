#!/usr/bin/env bash
# Build NanoKernel into a bootable 1.44MB floppy image.
#   Requires: nasm  (override the binary with $NASM)
#   Usage:    ./build.sh
#   Output:   build/nanokernel.img
set -euo pipefail

NASM="${NASM:-nasm}"
OUT=build
mkdir -p "$OUT"

# 1. assemble stage2 (the kernel)
"$NASM" kernel/stage2.asm -f bin -o "$OUT/stage2.bin"

# 2. how many 512-byte sectors does stage2 need?
size=$(wc -c < "$OUT/stage2.bin")
sectors=$(( (size + 511) / 512 ))
echo "stage2: $size bytes -> $sectors sectors"

# 3. assemble stage1 (the boot sector), telling it how many sectors to load
"$NASM" boot/stage1.asm -f bin -DSTAGE2_SECTORS="$sectors" -o "$OUT/stage1.bin"

# stage1 must be exactly one sector
s1=$(wc -c < "$OUT/stage1.bin")
if [ "$s1" -ne 512 ]; then
    echo "ERROR: stage1 is $s1 bytes, expected 512" >&2
    exit 1
fi

# 4. pad stage2 up to a whole number of sectors
pad=$(( sectors * 512 - size ))
if [ "$pad" -gt 0 ]; then
    dd if=/dev/zero bs=1 count="$pad" >> "$OUT/stage2.bin" 2>/dev/null
fi

# 5. concatenate and pad the disk image to 1.44MB
cat "$OUT/stage1.bin" "$OUT/stage2.bin" > "$OUT/nanokernel.img"
truncate -s 1474560 "$OUT/nanokernel.img" 2>/dev/null || \
    dd if=/dev/zero of="$OUT/nanokernel.img" bs=1 seek=1474559 count=1 conv=notrunc 2>/dev/null

echo "built $OUT/nanokernel.img"
