# Ship grim for niri screenshots

## Context
The screenshot backend on cinta cannot use niri's GNOME-compatible screenshot
D-Bus API with multiple monitors. A dotfiles-side shim will call `/usr/bin/grim`
to capture the desktop via Wayland screencopy.

## Alternatives considered
- Distrobox: does not provide the required host executable.
- Shared package layer: would add a workstation utility to Bluefin unnecessarily.

## Rationale
The existing Bazzite niri package list is the right place for a host Wayland tool.
The screenshot shim belongs in dotfiles and is outside this change.

## Requirements
- Install the `grim` RPM in the final Bazzite image.
- Verify `rpm -q grim`, `command -v grim` returning `/usr/bin/grim`, and a
  successful `grim -h` inside a locally built container before committing.
- Fast-forward main and verify the resulting GitHub Actions runs.

## Technical approach
Add `grim` to the existing niri RPM transaction and check it in the Bazzite
container contract. Build and verify with `just build-image bazzite`.

## Files affected
- `build_files/bazzite/build.sh`
- `build_files/common/verify-container.sh`

## Issues & Resolutions
The first build installed grim but failed the literal lookup assertion:
Fedora 45 symlinks `/usr/sbin` to `/usr/bin`, and the image's default PATH
searches `/usr/sbin` first. The verifier now checks the canonical path. The
local smoke test also checks the literal lookup with `/usr/bin` first on PATH.
The RPM path and the image's PATH are unchanged.
