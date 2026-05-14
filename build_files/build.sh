#!/bin/bash

set -ouex pipefail

# ---------------------------------------------------------------------------
# VM / virtualization packages
# ---------------------------------------------------------------------------
dnf5 install -y \
    qemu \
    libvirt \
    libvirt-client \
    libvirt-daemon-kvm \
    libvirt-daemon-config-network \
    qemu-kvm \
    virt-manager \
    edk2-ovmf \
    guestfs-tools

# ---------------------------------------------------------------------------
# ROCm — replaces mesa-libOpenCL with AMD's compute stack
# ---------------------------------------------------------------------------
dnf5 swap -y mesa-libOpenCL rocm-opencl
dnf5 install -y \
    rocm-hip \
    rocm-clinfo \
    rocm-smi

# ---------------------------------------------------------------------------
# Enable virtualization services
# ---------------------------------------------------------------------------
# Copy pre-seeded system files into the image
cp -avf /ctx/usr/. /usr/.

systemctl enable libvirtd
