#!/bin/bash

set -ouex pipefail

dnf5 install -y \
    qemu \
    libvirt \
    libvirt-client \
    libvirt-daemon-kvm \
    libvirt-daemon-config-network \
    qemu-kvm \
    virt-manager \
    edk2-ovmf \
    atop \
    guestfs-tools \
    jq \
    rsync \
    wireguard-tools

# Install immutable image assets copied into the scratch build context.
cp -avf /ctx/usr/. /usr/.

systemctl enable libvirtd.service
