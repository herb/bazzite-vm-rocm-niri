#!/bin/bash

set -euo pipefail

flavor="${1:-}"
case "$flavor" in
    bazzite|bluefin) ;;
    *)
        printf 'usage: %s bazzite|bluefin\n' "$0" >&2
        exit 2
        ;;
esac

packages=(
    qemu libvirt libvirt-client libvirt-daemon-kvm
    libvirt-daemon-config-network qemu-kvm virt-manager edk2-ovmf
    atop guestfs-tools jq rsync wireguard-tools
)
for package in "${packages[@]}"; do
    rpm -q "$package" >/dev/null
done
for executable in virsh qemu-img qemu-system-x86_64 virt-customize atop jq rsync wg wg-quick; do
    test -x "/usr/bin/$executable"
done
test -f /usr/lib/systemd/system/libvirtd.service
test -f /usr/lib/sysusers.d/qemu.conf
grep -Eq '^u qemu 107([[:space:]]|$)' /usr/lib/sysusers.d/qemu.conf
grep -Eq '^g qemu 107([[:space:]]|$)' /usr/lib/sysusers.d/qemu.conf

case "$flavor" in
    bazzite)
        for package in rocm-opencl rocm-hip rocm-clinfo rocm-smi niri hyprlock brscan5; do
            rpm -q "$package" >/dev/null
        done
        test -x /usr/bin/ags
        test -d /opt/brother/scanner/brscan5
        test -f /usr/lib/systemd/user/ags.service
        test -f /usr/lib/systemd/user/swayidle.service
        ;;
    bluefin)
        grep -Eq '^ID="?bluefin"?([[:space:]]|$)' /etc/os-release
        for package in rocm-opencl rocm-hip rocm-clinfo rocm-smi niri hyprlock brscan5; do
            if rpm -q "$package" >/dev/null 2>&1; then
                printf 'unexpected Bazzite package in Bluefin image: %s\n' "$package" >&2
                exit 1
            fi
        done
        test ! -e /usr/lib/systemd/user/ags.service
        test ! -e /usr/lib/systemd/user/plasma-polkit-agent.service
        test ! -e /usr/lib/systemd/user/swayidle.service
        test ! -e /opt/brother/scanner/brscan5
        ;;
esac
