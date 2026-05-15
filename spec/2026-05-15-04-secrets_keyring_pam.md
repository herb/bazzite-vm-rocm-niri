# Secrets management: gnome-keyring PAM integration for Niri sessions

## Context

The custom Bazzite image adds Niri as an alternative window manager alongside
KDE Plasma.  Applications in the Niri session that use the Secret Service API
(`org.freedesktop.secrets`) — e.g.  ProtonVPN, KeePassXC, Chromium-based
browsers — require an unlocked keyring.  Without PAM integration, these apps
prompt for a keyring password or fail outright.

The base Bazzite image ships both `gnome-keyring` (the daemon) and KDE's
`kwallet`.  They coexist peacefully via different D-Bus names:
`org.freedesktop.secrets` (gnome-keyring) vs `org.kde.kwalletd5` (KWallet).
When not running Plasma, kwalletd never starts, so there is no bus contention.

However, two gaps exist in the current build:

1. The `gnome-keyring-pam` package (which provides `pam_gnome_keyring.so`) is
   not explicitly installed.
2. The SDDM PAM config files (`sddm` and `sddm-autologin`) do not include
   `pam_gnome_keyring.so`, so the keyring is not unlocked at login.

## Requirements

- Install `gnome-keyring-pam` package in the image.
- Add `auth optional pam_gnome_keyring.so` and
  `session optional pam_gnome_keyring.so auto_start` to SDDM's PAM config
  (both `sddm` and `sddm-autologin`).
- Both keyring implementations coexist — no kwallet removal, no bus conflict.

## Technical approach

### Package installation

Add `gnome-keyring-pam` to the existing `dnf5 install` block in
`build_files/build.sh` that installs Niri companion packages.

### PAM config patching

Rather than overwriting the base image's PAM files (which may contain
distribution-specific modules), use `sed` to insert lines only when
`pam_gnome_keyring.so` is not already present.  The two lines are:

```
auth        optional     pam_gnome_keyring.so
session     optional     pam_gnome_keyring.so auto_start
```

These are inserted after the `auth include` and `session include` lines
respectively, which is the standard position for optional PAM modules.
Both `/etc/pam.d/sddm` and `/etc/pam.d/sddm-autologin` are patched.

## Files affected

- `build_files/build.sh` — two additions:
  1. `gnome-keyring-pam` in the package list (~line 61)
  2. PAM patch block at end of file (~line 76+)

## End criteria

- `gnome-keyring-pam` is installed in the image.
- Both `/etc/pam.d/sddm` and `/etc/pam.d/sddm-autologin` contain the two
  `pam_gnome_keyring.so` lines.
- The image builds successfully.
