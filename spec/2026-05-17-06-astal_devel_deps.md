# Astal build deps — wireplumber, NetworkManager, json-glib, gudev

## Context

The `ags-builder` stage in `Containerfile` builds Astal (GJS library) and AGS
(GTK shell) from source.  The four additional `-devel` packages are required so
that Astal can offer the full set of sub-libraries:

| Astal sub-library | pkg-config key | Depends on |
|---|---|---|
| `astal/wireplumber` | `wireplumber-0.5` | Audio device control (volume, sinks, sources) |
| `astal/network` | `libnm` | NetworkManager connection state, WiFi scanning |
| `astal/battery` (also `astal/greet`) | `json-glib-1.0` | JSON parsing across multiple Astal modules |
| `astal/greet` | `gudev-1.0` | Device enumeration (displays, input) |

## Rationale

- Astal modules are Vala introspectable libraries; compilation requires the
  corresponding C headers and pkg-config files at build time.
- `wireplumber-libs` is **versionlocked** in `bazzite:stable` at a custom git
  build (`0.5.12-1.fc44.bazzite.0.0.git...`), which blocks `dnf5 install` of
  the Fedora `wireplumber-devel` because the locked version doesn't exist in
  standard repos.  The fix is to lift the lock before installing.
- The other three packages install cleanly — `NetworkManager-libnm` is also
  versionlocked but the `-devel` matches the locked version.

## Requirements

- Astal wireplumber, network, json, and gudev sub-libraries compile without
  missing-header errors in the `ags-builder` stage.
- pkg-config visibility for all four libraries in the build environment.
- No regressions in the existing Astal IO, GTK4, or GJS builds.
- The final image builds and passes `bootc container lint`.

## Files affected

- `Containerfile` — added four packages to `dnf5 install` in `ags-builder`
  stage; added `dnf5 versionlock delete` for `wireplumber{-libs,}`.
- `spec/2026-05-17-06-astal_devel_deps.md` — this PRD.

## End criteria

- ✅ `wireplumber-devel-0.5.14` installed (after versionlock lift)
- ✅ `NetworkManager-libnm-devel-1.56.0` installed
- ✅ `json-glib-devel-1.10.8` installed
- ✅ `libgudev-devel-238` installed
- ✅ pkg-config confirms `wireplumber-0.5`, `libnm`, `json-glib-1.0`, `gudev-1.0`
- ✅ Astal + AGS compile successfully
- ✅ Image builds and passes `bootc container lint`
