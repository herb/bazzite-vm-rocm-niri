# Niri Window Manager on bazzite-vm-rocm-niri

## Context

The user wants to use niri, a scrollable-tiling Wayland compositor, as the window
manager on their custom bazzite-based VM image. The reference project at
`gabeklavans/bazzite-niri` removes KDE Plasma entirely and installs GDM, but that
approach was deemed too risky for the first pass.

## Alternatives Considered

1. **Remove Plasma + GDM** — The reference project's approach. Rejected because
   it risks breaking graphical login, and removing Plasma aggressively could
   cascade-remove SDDM.
2. **Remove Plasma selectively + keep SDDM** — Better, but still risky for v1.
   Left as a future step after niri stability is confirmed.

## Rationale

Adding niri alongside Plasma is the safest first step. SDDM already handles
session discovery via `/usr/share/wayland-sessions/*.desktop` files, and
Fedora's niri package ships `niri.desktop`, `niri.service`, and
`niri-shutdown.target` by default. No display manager changes or Plasma removal
is needed. If niri has issues, the user simply logs into Plasma.

## Requirements

- niri must appear as a selectable session in SDDM.
- Basic desktop UX must work: terminal, app launcher, status bar, wallpaper,
  notifications, polkit authentication, screen locking, and X11 app support.
- The `niri.service` systemd user unit must start companion services (mako,
  swayidle, polkit agent) automatically.

## Non-Requirements (for v1)

- No KDE Plasma packages are removed.
- No display manager is changed (SDDM stays).
- No niri configuration file is shipped beyond the upstream defaults.

## Post-Build Change: Default Session

After initial build and feedback, SDDM was configured to default to Niri by
writing `/etc/sddm.conf.d/niri-default.conf` during the build. Plasma remains
selectable via the session button on the login screen.

## Technical Approach

### Files Created

- `services/plasma-polkit-agent.service` — systemd user unit to start the KDE
  polkit authentication agent outside of a Plasma session.
- `services/swayidle.service` — systemd user unit for idle management tied to
  niri's power-off-monitors action.

### Files Modified

- `Containerfile` — add `COPY services /usr/lib/systemd/user/` so custom user
  services are included.
- `build_files/build.sh` — append a niri block that:
  - Installs niri + companion packages
  - Installs portal/keyring/polkit packages that niri expects
  - Wires `mako.service`, `swayidle.service`, and
    `plasma-polkit-agent.service` as wants of `niri.service`

### Packages Installed

```
niri alacritty fuzzel waybar mako swayidle swaylock swaybg
xwayland-satellite xdg-desktop-portal-gtk xdg-desktop-portal-gnome
gnome-keyring nautilus polkit-kde
```

### Service Wiring

```bash
systemctl --global add-wants niri.service mako.service
systemctl --global add-wants niri.service swayidle.service
systemctl --global add-wants niri.service plasma-polkit-agent.service
```

## Files Affected

| File | Action |
|------|--------|
| `Containerfile` | Add `COPY services /usr/lib/systemd/user/` |
| `build_files/build.sh` | Append ~30-line niri block including SDDM default config |
| `services/plasma-polkit-agent.service` | **Create** |
| `services/swayidle.service` | **Create** |

## End Criterion

The image builds cleanly with `podman build` (no errors).
