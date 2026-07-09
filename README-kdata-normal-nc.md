# QEMU kernel-data Normal-NC experiment

This branch is based on QEMU 8.2.0 and adds an ARM `virt` machine experiment for placing the guest kernel data range in a separate memory backend. The intended use is to pair it with an arm64 KVM kernel that accepts a new `KVM_MEM_UNCACHED` memslot flag and maps that slot with Stage-2 Normal Non-Cacheable attributes.

## What changed

- Adds ARM `virt` machine properties for a dedicated guest kernel data region:
  - `kernel-data-start=<addr>`
  - `kernel-data-size=<size>`
  - `kernel-data-memdev=<memory-backend-id>`
  - `kernel-data-uncached=on|off`
- Splits the configured kernel data GPA range out of normal system RAM and maps it from a separate QEMU `MemoryRegion` backed by the selected memory backend.
- Adds a QEMU memory-region flag that is carried into KVM memslot creation.
- When `kernel-data-uncached=on`, QEMU passes `KVM_MEM_UNCACHED` in `KVM_SET_USER_MEMORY_REGION` for the kernel data memslot.

## Required kernel side

This QEMU branch requires a kernel that defines and accepts:

```c
#define KVM_MEM_UNCACHED (1UL << 2)
```

On arm64 KVM, the matching experiment maps that memslot as Stage-2 Normal Non-Cacheable (`MT_S2_NORMAL_NC`). Without the matching kernel support, QEMU will fail with `KVM_SET_USER_MEMORY_REGION: Invalid argument` when `kernel-data-uncached=on` is used.

Kernel branch used for testing:

- `qmyyxtl/GVM-ARM-KERNEL`, branch `openeuler-base-kdata`

## Example

```bash
qemu-system-aarch64 \
  -nographic \
  -cpu host \
  -machine virt,gic-version=3,its=off,\
kernel-data-start=0x427b0000,\
kernel-data-size=0x4e0000,\
kernel-data-memdev=kdata,\
kernel-data-uncached=on \
  -smp 4 \
  -m 4G \
  -object memory-backend-ram,id=kdata,size=0x4e0000 \
  -enable-kvm \
  -kernel /path/to/Image \
  -append "root=/dev/vda2 nokaslr rw console=ttyAMA0 earlycon=pl011,0x09000000" \
  -serial mon:stdio \
  -monitor none
```

QEMU prints a line like this when the split is active:

```text
kernel data RAM split at 0x427b0000+0x4e0000
```

## Test result

With the matching arm64 KVM Normal-NC kernel, the guest boots successfully to login with `kernel-data-uncached=on`.

## Launcher script

A launcher matching the tested setup is provided at:

```bash
scripts/run-kdata-normal-nc.sh
```

Common overrides:

```bash
QEMU_BIN=./build/qemu-system-aarch64 \
KERNEL=/path/to/Image \
DISK=/path/to/rootfs.qcow2 \
KERNEL_DATA_UNCACHED=on \
scripts/run-kdata-normal-nc.sh
```

Set `KERNEL_DATA_UNCACHED=off` to keep the same split memory layout without requesting the uncached KVM memslot flag.

## Patch files

The minimal patches are also included for review:

- `patches/qemu/0001-arm-virt-split-kernel-data-RAM-into-dedicated-backen.patch`
- `patches/qemu/0002-kvm-pass-uncached-flag-for-kernel-data-memslot.patch`
- `patches/kernel/0001-KVM-arm64-support-normal-NC-userspace-memory-slots.patch`
