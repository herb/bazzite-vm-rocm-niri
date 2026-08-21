# Remove Obsolete iwd Unmask Workaround (Upstream Dropped iwd)

## Context
CI began failing during the `build.sh` RUN step with:

```
+ rm -f /etc/systemd/system/iwd.service /usr/etc/systemd/system/iwd.service
+ systemctl enable iwd
Failed to enable unit: Unit iwd.service does not exist
Error: building at STEP "RUN ... /ctx/build.sh && rm -rf /ctx": exit status 1
```

The failure appeared without any changes to this repo — the cause was a new push to the base image `ghcr.io/ublue-os/bazzite:stable`.

This repo carried an iwd workaround since 2026-05-14 (see `spec/2026-05-14-02-iwd_mask_wifi_fix.md`): the base image masked `iwd.service` while simultaneously configuring NetworkManager with `wifi.backend=iwd`, a contradiction that broke WiFi after rebase. Our fix removed the mask files and enabled iwd.

## Investigation
1. Checked the **local** (2-week-old) `bazzite:stable`: `iwd-1000.3.10-1.fc44.bazzite.x86_64` installed, mask present only at `/etc/systemd/system/iwd.service`, real unit at `/usr/lib/systemd/system/iwd.service`. Build worked against this image — confirming CI pulled something newer.
2. Pulled the **fresh** `bazzite:stable` locally (image `305a749cde4b`, ~25h old at time of check):
   - `rpm -q iwd` → **package iwd is not installed**
   - No `iwd.service` anywhere (`/etc`, `/usr/etc`, `/usr/lib`)
   - `/etc/NetworkManager/conf.d/iwd.conf` (**the `wifi.backend=iwd` config**) is gone
   - Stock backend now shipped: `wpa_supplicant-2.11-9.fc44` + `NetworkManager-wifi-1.56.1-2.fc44`; remaining NM conf.d files are unrelated (connectivity, MAC randomization, nvme-nbft)

## Root Cause
Upstream bazzite resolved their own mask/backend contradiction differently than we did: they **removed the `iwd` package entirely** along with the NetworkManager iwd-backend config, falling back to the stock `wpa_supplicant` backend. With no `iwd.service` in the image, our unconditional `systemctl enable iwd` fails under `set -euox pipefail`.

## Alternatives Considered
1. **Install iwd ourselves** (`dnf5 install iwd` + ship our own `wifi.backend=iwd` conf) — rejected: fights upstream's chosen direction, adds a package they deliberately dropped, and gains nothing since wpa_supplicant is a fully functional NM backend.
2. **Make the enable tolerant** (`systemctl enable iwd || true` or existence check) — rejected: leaves dead workaround code in place forever, masking future base-image drift instead of surfacing it.
3. **Delete the obsolete block entirely** — chosen: matches upstream reality; WiFi now works out of the box with the base image's own consistent configuration.

## Requirements
- Image build must succeed against current `ghcr.io/ublue-os/bazzite:stable`
- WiFi must remain functional on deployed systems after rebase
- Build script must not reference units that may not exist in the base

## Resolution
Removed the entire "Enable WiFi (iwd)" block from `build_files/build.sh` (the two `rm -f` mask removals and `systemctl enable iwd`), replacing it with a comment explaining that bazzite:stable no longer ships iwd and NetworkManager now uses the stock wpa_supplicant backend. No other sections were touched.

## Verification
1. `shellcheck build_files/build.sh` — clean.
2. Full local build `just build` against the freshly pulled base — **completed successfully**: all packages installed (VM stack, ROCm, niri session, GStreamer, brscan5, hyprlock), `bootc container lint` passed (10 checks passed, same 3 pre-existing warnings), final image committed as `localhost/image-template:latest` (`f84693c6b7ef`).
3. Build log confirms the script now flows directly from the ROCm install into the virtualization services block (`cp -avf /ctx/usr/. /usr/.`, `systemctl enable libvirtd`) with no iwd step.

## Impact on Deployed Systems
After rebasing to images built from this point, machines get NetworkManager + wpa_supplicant instead of iwd. This is upstream-supported and self-consistent (no mask, no forced backend). If a specific NIC ever misbehaves under wpa_supplicant, reintroduce iwd deliberately with its own backend config rather than resurrecting this workaround.

## Files Affected
- **Modified**: `build_files/build.sh` — deleted obsolete iwd unmask/enable block (~lines 29–35)

## Issues & Resolutions

### Issue 1: Base image pull exceeds default tool timeout
- **Problem**: First `podman pull ghcr.io/ublue-os/bazzite:stable` (11.7 GB) hit the 10-minute command timeout mid-download.
- **Resolution**: Re-ran the pull with a larger timeout; podman resumed using the already-downloaded layers and completed.
