#!/bin/bash

set -eu

packages=(
    qemu
    libvirt
    libvirt-client
    libvirt-daemon-kvm
    libvirt-daemon-config-network
    qemu-kvm
    virt-manager
    edk2-ovmf
    atop
    guestfs-tools
    jq
    rsync
    wireguard-tools
)

for package in "${packages[@]}"; do
    rpm -q "$package" >/dev/null
done

for executable in virsh qemu-img qemu-system-x86_64 virt-customize atop jq rsync wg wg-quick; do
    test -x "/usr/bin/$executable"
done

test -f /usr/lib/systemd/system/libvirtd.service
systemctl is-enabled libvirtd.service >/dev/null
test -f /usr/lib/sysusers.d/qemu.conf
grep -Eq '^u qemu 107([[:space:]]|$)' /usr/lib/sysusers.d/qemu.conf
grep -Eq '^g qemu 107([[:space:]]|$)' /usr/lib/sysusers.d/qemu.conf

ovmf_path=''
for candidate in \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd \
    /usr/share/edk2/ovmf/OVMF_CODE_4M.fd; do
    if test -f "$candidate"; then
        ovmf_path="$candidate"
        break
    fi
done
test -n "$ovmf_path"
