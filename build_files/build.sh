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
    gnome-keyring-pam \
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

# ---------------------------------------------------------------------------
# Keyring / secrets — unlock gnome-keyring at SDDM login so libsecret
# consumers (ProtonVPN, KeePassXC, browsers, etc.) don't prompt for a
# password.  Both gnome-keyring and kwallet coexist peacefully via different
# D-Bus names (org.freedesktop.secrets vs org.kde.kwalletd5); when not
# running Plasma, kwalletd never starts.
# ---------------------------------------------------------------------------
for pam_file in /etc/pam.d/sddm /etc/pam.d/sddm-autologin; do
    if [ -f "$pam_file" ] && ! grep -q "pam_gnome_keyring\.so" "$pam_file" 2>/dev/null; then
        sed -i '/^auth.*include/a\auth        optional     pam_gnome_keyring.so' "$pam_file"
        sed -i '/^session.*include/a\session     optional     pam_gnome_keyring.so auto_start' "$pam_file"
    fi
done
