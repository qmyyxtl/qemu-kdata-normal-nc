#!/usr/bin/env bash
set -euo pipefail

# UEFI launcher for the ARM virt kernel-data Normal-NC experiment.
# This uses -bios and boots the kernel from the openEuler disk via GRUB.
# Override variables from the environment, for example:
#   KERNEL_DATA_UNCACHED=off ./scripts/run-kdata-normal-nc-uefi.sh

QEMU_BIN=${QEMU_BIN:-./build/qemu-system-aarch64}
FIRMWARE=${FIRMWARE:-/usr/share/edk2/aarch64/QEMU_EFI.fd}
DISK=${DISK:-/home/qmyyxtl/openEuler-24.03-LTS-SP2-aarch64.qcow2}
SYSTEM_MAP=${SYSTEM_MAP:-/mnt/openeuler-efi/System.map-6.6.0-125.0.0.125.oe2403sp2.aarch64}
SSH_FWD=${SSH_FWD:-2612}
SMP=${SMP:-4}
MEM=${MEM:-4G}
RAM_BASE=${RAM_BASE:-0x40000000}
KDATA_ALIGN=${KDATA_ALIGN:-0x10000}
KDATA_MEMDEV=${KDATA_MEMDEV:-kdata}
KERNEL_DATA_UNCACHED=${KERNEL_DATA_UNCACHED:-on}

# Fallback values verified with openEuler 24.03 LTS-SP2:
#   vmlinuz-6.6.0-125.0.0.125.oe2403sp2.aarch64
#   _sdata=ffff800081ee0000, _edata=ffff800082428200
KDATA_START=${KDATA_START:-}
KDATA_SIZE=${KDATA_SIZE:-}
FALLBACK_KDATA_START=${FALLBACK_KDATA_START:-0x41ee0000}
FALLBACK_KDATA_SIZE=${FALLBACK_KDATA_SIZE:-0x550000}

if [[ ! -x "$QEMU_BIN" ]]; then
    echo "QEMU binary not found or not executable: $QEMU_BIN" >&2
    echo "Build first, for example: mkdir -p build && cd build && ../configure --target-list=aarch64-softmmu && make -j\$(nproc)" >&2
    exit 1
fi

if [[ ! -f "$FIRMWARE" ]]; then
    echo "UEFI firmware not found: $FIRMWARE" >&2
    exit 1
fi

if [[ ! -f "$DISK" ]]; then
    echo "Guest disk image not found: $DISK" >&2
    exit 1
fi

if [[ -z "$KDATA_START" || -z "$KDATA_SIZE" ]]; then
    if [[ -f "$SYSTEM_MAP" ]]; then
        read -r KDATA_START KDATA_SIZE < <(
            python3 - "$SYSTEM_MAP" "$RAM_BASE" "$KDATA_ALIGN" <<'PY'
import sys

path, ram_base_s, align_s = sys.argv[1:]
ram_base = int(ram_base_s, 0)
align = int(align_s, 0)
symbols = {}

with open(path, "r", encoding="ascii", errors="ignore") as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 3 and parts[2] in {"_text", "_sdata", "_edata"}:
            symbols[parts[2]] = int(parts[0], 16)

missing = {"_text", "_sdata", "_edata"} - symbols.keys()
if missing:
    raise SystemExit(f"missing symbols in System.map: {', '.join(sorted(missing))}")

start = ram_base + (symbols["_sdata"] - symbols["_text"])
size = symbols["_edata"] - symbols["_sdata"]
size = (size + align - 1) & ~(align - 1)
print(f"0x{start:x} 0x{size:x}")
PY
        )
    else
        echo "System.map not found: $SYSTEM_MAP" >&2
        echo "Using verified fallback range: ${FALLBACK_KDATA_START}+${FALLBACK_KDATA_SIZE}" >&2
        KDATA_START=$FALLBACK_KDATA_START
        KDATA_SIZE=$FALLBACK_KDATA_SIZE
    fi
fi

echo "UEFI kernel data range: ${KDATA_START}+${KDATA_SIZE} uncached=${KERNEL_DATA_UNCACHED}" >&2

exec sudo "$QEMU_BIN" \
    -nographic \
    -cpu host \
    -machine "virt,gic-version=3,its=off,kernel-data-start=${KDATA_START},kernel-data-size=${KDATA_SIZE},kernel-data-memdev=${KDATA_MEMDEV},kernel-data-uncached=${KERNEL_DATA_UNCACHED}" \
    -smp "$SMP" \
    -m "$MEM" \
    -object "memory-backend-ram,id=${KDATA_MEMDEV},size=${KDATA_SIZE}" \
    -enable-kvm \
    -bios "$FIRMWARE" \
    -global virtio-mmio.ioeventfd=off \
    -serial mon:stdio \
    -monitor none \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_FWD}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -drive "if=none,file=${DISK},id=hd0,file.locking=off" \
    -device virtio-blk-device,drive=hd0
