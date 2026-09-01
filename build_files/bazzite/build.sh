#!/bin/bash

set -ouex pipefail

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
# Note: bazzite:stable no longer ships iwd at all (removed ~Aug 2026);
# NetworkManager now uses the stock wpa_supplicant wifi backend, so the
# old mask/unmask workaround here was removed with it.
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
    gphoto2 \
    waybar \
    wlopm \
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
# GStreamer — phonto (GPU-accelerated video wallpaper)
# gstreamer1-vaapi is obsolete; VA-API support merged into
# gstreamer1-plugins-bad-free as of GStreamer 1.28.
# ---------------------------------------------------------------------------
dnf5 install -y \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free

# ---------------------------------------------------------------------------
# Scanner — brscan5 for Brother USB scanners (SANE backend)
# Brother's driver is not in any Fedora repo; download the RPM directly.
# ---------------------------------------------------------------------------
dnf5 install -y gtk2
curl -Lo /tmp/brscan5.rpm \
    "https://download.brother.com/welcome/dlf104036/brscan5-1.6.2-0.x86_64.rpm"
mkdir -p /var/opt
rpm -Uvh --nosignature --nodigest /tmp/brscan5.rpm
rm -f /tmp/brscan5.rpm

# Brother's RPM creates these unowned links in %post, but they do not survive
# the bootc image build. Recreate the complete link chains in immutable /usr.
for library in \
    libLxBsDeviceAccs.so.1.0.0 \
    libLxBsNetDevAccs.so.1.0.0 \
    libLxBsScanCoreApi.so.3.2.6 \
    libLxBsUsbDevAccs.so.1.0.0; do
    link1="${library%.*}"
    link2="${link1%.*}"
    ln -sfn "/opt/brother/scanner/brscan5/${library}" "/usr/lib64/${library}"
    ln -sfn "/usr/lib64/${library}" "/usr/lib64/${link1}"
    ln -sfn "/usr/lib64/${link1}" "/usr/lib64/${link2}"
    test -e "/usr/lib64/${link2}"
done

# /opt is now a real (immutable) directory in the image. The RPM's postinst
# creates /etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg as a symlink
# to /opt/brother/... which would be read-only at runtime. Replace it with
# a regular file so brsaneconfig5 can write network scanner config.
rm /etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg
cp /opt/brother/scanner/brscan5/brsanenetdevice.cfg \
   /etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg

# ---------------------------------------------------------------------------
# COPR: sdegler/hyprland — hyprlock (GPU-accelerated screen locker)
# ---------------------------------------------------------------------------
dnf5 -y copr enable sdegler/hyprland
dnf5 install -y hyprlock

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

# ---------------------------------------------------------------------------
# Final cleanup — remove dnf cache to shrink final image layers
# ---------------------------------------------------------------------------
dnf5 clean all
