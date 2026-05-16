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
    brightnessctl \
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

# ---------------------------------------------------------------------------
# AGS (Aylur's GTK Shell) — customizable widget shell for the desktop
# Installed from solopasha/hyprland COPR (referenced by AGS wiki for Fedora)
# ---------------------------------------------------------------------------
dnf5 config-manager addrepo --copr solopasha/hyprland
dnf5 install -y aylurs-gtk-shell2

# Wire companion services to start automatically with niri
systemctl --global add-wants niri.service mako.service
systemctl --global add-wants niri.service swayidle.service
systemctl --global add-wants niri.service plasma-polkit-agent.service

# Set Niri as the default session in plasmalogin (native DM in bazzite:stable)
# and SDDM (belt-and-suspenders if deployed on a system using SDDM).
cat > /etc/plasmalogin.conf.d/niri.conf << 'EOF'
[Autologin]
Session=niri.desktop
EOF

mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/niri-default.conf << 'EOF'
[Autologin]
Session=niri.desktop
EOF

# ---------------------------------------------------------------------------
# Keyring / secrets — unlock gnome-keyring at login so libsecret consumers
# (ProtonVPN, KeePassXC, browsers, etc.) don't prompt for password.
# The base image's plasmalogin PAM already includes pam_gnome_keyring.so in
# /usr/lib/pam.d/plasmalogin{,-autologin}.  We add SDDM PAM files here for
# setups that swap SDDM in.
#
# Both gnome-keyring and kwallet coexist via different D-Bus names
# (org.freedesktop.secrets vs org.kde.kwalletd5); outside Plasma, kwalletd
# never starts, so there is no bus conflict.
# ---------------------------------------------------------------------------
mkdir -p /etc/pam.d

cat > /etc/pam.d/sddm << 'EOF'
#%PAM-1.0
auth        include      system-auth
auth        optional     pam_gnome_keyring.so
account     include      system-auth
password    include      system-auth
session     include      system-auth
session     optional     pam_gnome_keyring.so auto_start
EOF

cat > /etc/pam.d/sddm-autologin << 'EOF'
#%PAM-1.0
auth        required     pam_env.so
auth        required     pam_permit.so
auth        optional     pam_gnome_keyring.so
account     include      system-auth
password    include      system-auth
session     include      system-auth
session     optional     pam_gnome_keyring.so auto_start
EOF
