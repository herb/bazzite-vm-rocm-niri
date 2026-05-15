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
# Enable WiFi (iwd) — bazzite:stable masks iwd by default but
# NetworkManager expects it as the wifi.backend
# ---------------------------------------------------------------------------
# Remove mask inherited from base image (present in both /etc/ and /usr/etc/)
rm -f /etc/systemd/system/iwd.service /usr/etc/systemd/system/iwd.service
systemctl enable iwd

# ---------------------------------------------------------------------------
# Enable virtualization services
# ---------------------------------------------------------------------------
# Copy pre-seeded system files into the image
cp -avf /ctx/usr/. /usr/.

systemctl enable libvirtd

# ---------------------------------------------------------------------------
# Niri window manager — adds as parallel session alongside Plasma
# (No Plasma packages are removed in this v1.)
# ---------------------------------------------------------------------------

dnf5 install -y \
    niri \
    alacritty \
    fuzzel \
    waybar \
    mako \
    swayidle \
    swaylock \
    swaybg \
    xwayland-satellite \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-gnome \
    gnome-keyring \
    nautilus \
    polkit-kde

# Wire companion services to start automatically with niri
systemctl --global add-wants niri.service mako.service
systemctl --global add-wants niri.service swayidle.service
systemctl --global add-wants niri.service plasma-polkit-agent.service

# Set Niri as the default SDDM session (Plasma still selectable via session button)
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/niri-default.conf << 'EOF'
[Autologin]
Session=niri.desktop
EOF
