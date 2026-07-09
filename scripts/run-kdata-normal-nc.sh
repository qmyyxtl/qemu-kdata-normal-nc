#!/usr/bin/env bash
set -euo pipefail

# Example launcher for the ARM virt kernel-data Normal-NC experiment.
# Override any variable from the environment, for example:
#   KERNEL_DATA_UNCACHED=off DISK=/path/to/rootfs.qcow2 ./scripts/run-kdata-normal-nc.sh

QEMU_BIN=${QEMU_BIN:-./build/qemu-system-aarch64}
KERNEL=${KERNEL:-/home/qmyyxtl/guest-kernel/arch/arm64/boot/Image}
DISK=${DISK:-/home/qmyyxtl/openEuler-24.03-LTS-SP2-aarch64.qcow2}
SSH_FWD=${SSH_FWD:-2610}
SMP=${SMP:-4}
MEM=${MEM:-4G}
KDATA_START=${KDATA_START:-0x427b0000}
KDATA_SIZE=${KDATA_SIZE:-0x4e0000}
KDATA_MEMDEV=${KDATA_MEMDEV:-kdata}
KERNEL_DATA_UNCACHED=${KERNEL_DATA_UNCACHED:-on}
ROOT_DEV=${ROOT_DEV:-/dev/vda2}
EXTRA_APPEND=${EXTRA_APPEND:-}

if [[ ! -x "$QEMU_BIN" ]]; then
    echo "QEMU binary not found or not executable: $QEMU_BIN" >&2
    echo "Build first, for example: mkdir -p build && cd build && ../configure --target-list=aarch64-softmmu && make -j\$(nproc)" >&2
    exit 1
fi

if [[ ! -f "$KERNEL" ]]; then
    echo "Guest kernel Image not found: $KERNEL" >&2
    exit 1
fi

if [[ ! -f "$DISK" ]]; then
    echo "Guest disk image not found: $DISK" >&2
    exit 1
fi

exec sudo "$QEMU_BIN" \
    -nographic \
    -cpu host \
    -machine "virt,gic-version=3,its=off,kernel-data-start=${KDATA_START},kernel-data-size=${KDATA_SIZE},kernel-data-memdev=${KDATA_MEMDEV},kernel-data-uncached=${KERNEL_DATA_UNCACHED}" \
    -smp "$SMP" \
    -m "$MEM" \
    -object "memory-backend-ram,id=${KDATA_MEMDEV},size=${KDATA_SIZE}" \
    -enable-kvm \
    -kernel "$KERNEL" \
    -append "root=${ROOT_DEV} nokaslr nowatchdog rw console=ttyAMA0 earlycon=pl011,0x09000000 loglevel=8 ignore_loglevel ${EXTRA_APPEND}" \
    -global virtio-mmio.ioeventfd=off \
    -serial mon:stdio \
    -monitor none \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_FWD}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -drive "if=none,file=${DISK},id=hd0,file.locking=off" \
    -device virtio-blk-device,drive=hd0
