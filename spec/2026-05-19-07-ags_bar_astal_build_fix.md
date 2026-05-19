# Build Missing Astal Service Libraries for AGS Bar

**Date**: 2026-05-19
**Status**: Implemented, image rebuilt, verified

## Goal

Fix `ags-bar` failing at runtime with `Typelib file for namespace 'AstalWp' (any version) not found` by building all required Astal service libraries, and pre-build additional useful libraries for future bar customization.

## Background

The AGS (Aylur's GTK Shell) bar config at `~/.config/ags/app.ts` imports three GObject Introspection namespaces that were not being built:

- `gi://AstalWp` — WirePlumber audio volume/mute
- `gi://AstalNetwork` — NetworkManager WiFi/Ethernet
- `gi://AstalNotifd` — Notification daemon

The Containerfile's `ags-builder` stage only built three Astal components: `lib/astal/io`, `lib/astal/gtk4`, and `lang/gjs`. All service sub-libraries under `lib/` (wireplumber, network, notifd, battery, mpris, etc.) were omitted.

## Execution

### Round 1: Add missing builds

**Change**: `Containerfile:44-48` — Replaced 3 explicit meson build steps with a loop over 9 libraries:

```
wireplumber network notifd battery mpris bluetooth brightness apps powerprofiles
```

**Problem discovered**: `tray` depends on `appmenu-glib-translator`, which is not packaged in Fedora 44. Dropped from the loop.

### Round 2: Rebuild and verify

**Problem discovered**: `AstalNotifd` and `AstalBrightness` typelibs missing from the built image. Investigation showed:

- Both libraries have `cli=true` by default in their `meson_options.txt`
- The CLI sub-build depends on `quarrel-0.1` (`lib/quarrel/`), an internal CLI argument-parsing library
- Since quarrel is not built, `meson setup` fails when resolving `dependency('quarrel-0.1')`
- The `&&` chain in the loop caused the entire loop to break, leaving only the libraries built *before* the failure present

**Resolution**: Split into two loops (`Containerfile:45-52`):

```dockerfile
# Libraries without CLI dependency issues
for lib in wireplumber network battery mpris bluetooth apps powerprofiles; do \
    meson setup --prefix /usr /tmp/astal/lib/$lib/build /tmp/astal/lib/$lib && \
    meson install -C /tmp/astal/lib/$lib/build; \
done && \
# Libraries that default to cli=true requiring quarrel-0.1 (not built)
for lib in notifd brightness; do \
    meson setup --prefix /usr /tmp/astal/lib/$lib/build /tmp/astal/lib/$lib -Dcli=false && \
    meson install -C /tmp/astal/lib/$lib/build; \
done
```

### Round 3: Final verification

**Result**: All 11 Astal typelibs present in `localhost/bazzite-vm-rocm-niri:latest`:

| Namespace | Source Library | For Bar? |
|---|---|---|
| `AstalWp-0.1` | `lib/wireplumber` | ✅ Volume widget |
| `AstalNetwork-0.1` | `lib/network` | ✅ WiFi widget |
| `AstalNotifd-0.1` | `lib/notifd` | ✅ Notifications |
| `AstalBattery-0.1` | `lib/battery` | Future |
| `AstalMpris-0.1` | `lib/mpris` | Future |
| `AstalBluetooth-0.1` | `lib/bluetooth` | Future |
| `AstalBrightness-0.1` | `lib/brightness` | Future |
| `AstalApps-0.1` | `lib/apps` | Future |
| `AstalPowerProfiles-0.1` | `lib/powerprofiles` | Future |
| `Astal-4.0` | `lib/astal/io` | ✅ Core |
| `AstalIO-0.1` | `lib/astal/io` | ✅ Core |

## Files Changed

- `Containerfile` — Added meson build steps for 9 Astal service libraries, with `-Dcli=false` workaround for `notifd` and `brightness`

## Skipped Libraries

| Library | Reason |
|---|---|
| `tray` | Requires `appmenu-glib-translator`, not in Fedora 44 |
| `auth` | PAM auth agent (pkexec-like), not useful for bar |
| `greet` | Display manager greeter, not relevant |
| `quarrel` | Internal CLI parser, required by notifd/brightness CLIs but not by the bar |
| `cava` | Audio visualizer, needs `libcava`, not installed |
| `hyprland`, `river` | WM-specific (we use niri) |

## Build Verification

```
podman build --tag localhost/bazzite-vm-rocm-niri:latest --file Containerfile .
bootc container lint  →  Passed (10 checks, 0 failures, 3 known warnings)
```

Image passes `bootc container lint` and all requested typelibs are present in `/usr/lib64/girepository-1.0/`.
