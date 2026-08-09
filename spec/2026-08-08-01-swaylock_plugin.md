# swaylock-plugin

## Context
The user requested the latest stable `swaylock-plugin` be installed in the bazzite image. `swaylock-plugin` (mstoeckl/swaylock-plugin) is a fork of swaylock whose lock-screen background is pluggable: any wallpaper program that speaks `wlr-layer-shell` (swaybg, mpvpaper, shaderbg, ...) can render behind the lock UI via `--command`. Latest stable is **v1.8.7** (released 2026-07-10).

The image currently installs upstream `swaylock` via dnf (`build_files/build.sh`), and `services/swayidle.service` invokes `swaylock -f`.

## Alternatives Considered
- **Install from an RPM/COPR**: Rejected — no Fedora/COPR package exists; it is source-only (AUR, FreeBSD ports).
- **Keep dnf `swaylock` and add `swaylock-plugin` alongside**: Rejected — the "plugin" in the name refers to pluggable background programs, not an add-on to upstream swaylock. It is a drop-in superset fork; running upstream swaylock alongside provides no value.
- **Build in the final stage**: Rejected — bloats the final image with build deps. The repo convention is multi-stage builds (see `ags-builder`).

## Rationale
`swaylock-plugin` is CLI-compatible with upstream swaylock (a superset), so replacing it is safe: symlinking `/usr/bin/swaylock -> swaylock-plugin` makes the existing `swayidle.service` (`swaylock -f`) and any user configs use the fork without editing call sites. Removing the dnf `swaylock` package avoids an rpm file conflict with the symlink. Built with PAM (`pam-devel`), so no setuid is required, and the install provides `/etc/pam.d/swaylock-plugin` (the PAM service name is hardcoded to `swaylock-plugin` in `pam.c`).

Fedora 44 ships `wayland-protocols` 1.47–1.49, satisfying the meson `>=1.47` requirement.

## Requirements
- Image builds successfully locally (`just build`).
- `swaylock-plugin` v1.8.7 binary at `/usr/bin/swaylock-plugin` in the final image.
- `/usr/bin/swaylock` is a symlink to `/usr/bin/swaylock-plugin`.
- `/etc/pam.d/swaylock-plugin` present; `rpm -q swaylock` reports not installed.
- `swaylock-plugin --help` exits 0 and lists plugin flags (`--command`, `--grace`).
- `ldd /usr/bin/swaylock-plugin` shows no missing libraries.
- Running `swaylock-plugin` headless (no compositor) fails gracefully rather than crashing.
- No build deps leak into the final image (multi-stage).

## Technical Approach
1. **Containerfile** — add a dedicated `swaylock-builder` stage (pattern: `ags-builder`):
   - `FROM ghcr.io/ublue-os/bazzite:stable`
   - Install build deps: `meson ninja-build git-core gcc wayland-devel wayland-protocols-devel libxkbcommon-devel cairo-devel gdk-pixbuf2-devel pam-devel systemd-devel`
   - `git clone --depth 1 --branch v1.8.7 https://github.com/mstoeckl/swaylock-plugin.git /tmp/swaylock-plugin`
   - `meson setup --prefix /usr build /tmp/swaylock-plugin && meson install -C build --destdir /tmp/swaylock-install`
   - Final stage: `COPY --from=swaylock-builder /tmp/swaylock-install/ /` — copies only the installed artifacts (binaries, pam file, man page, completions).
2. **build_files/build.sh**:
   - Remove `swaylock \` from the niri dnf5 install block.
   - Add `ln -sf /usr/bin/swaylock-plugin /usr/bin/swaylock`.
3. **Verification**: build locally, run a container from the image, run the requirement checks.

## Files Affected
- `Containerfile` — add `swaylock-builder` stage + final-stage COPY
- `build_files/build.sh` — remove `swaylock`, add symlink

## Issues & Resolutions

### `COPY --from=swaylock-builder` could not find the installed files
**Issue**: First build failed at the final-stage `COPY --from=swaylock-builder /tmp/swaylock-install/ /` with `copier: stat: "/tmp/swaylock-install": no such file or directory`, even though `meson install` reported writing there.

**Root cause**: The builder's `RUN` step uses `--mount=type=tmpfs,dst=/tmp`. The tmpfs is scoped to that single RUN instruction and is wiped when it completes, so nothing written under `/tmp` (including `--destdir /tmp/swaylock-install`) survives into the image layer for the later `COPY`.

**Resolution**: Staged the install at a persistent path instead — `meson install ... --destdir /swaylock-install` and `COPY --from=swaylock-builder /swaylock-install/ /`. The clone/build still run under `/tmp` (ephemeral, keeps the layer lean), but the staged artifacts persist. Rebuild succeeded.

### Verified (container from locally built image)
- `/usr/bin/swaylock -> /usr/bin/swaylock-plugin` symlink resolves correctly.
- `rpm -q swaylock` → not installed.
- `/etc/pam.d/swaylock-plugin` present; `pam.c` compiled (PAM backend, no setuid needed).
- `swaylock-plugin --version` → `v1.8.7`; `--help` exit 0 and lists plugin flags `--command`, `--command-each`, `--grace`, `--pointer-hysteresis`.
- `ldd /usr/bin/swaylock-plugin` → no missing libraries.
- Headless run (no compositor) exits 1 with `Unable to connect to the compositor` — graceful, no crash — both via the binary and via the `swaylock` symlink (what `swayidle.service` executes).

