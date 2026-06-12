# Add `wlopm` to built image

## Context
The user requested adding `wlopm` — a wlroots output power management tool — to the container image. It fits alongside the existing WM utilities (`brightnessctl`, `swayidle`, etc.) used with the niri Wayland compositor.

## Alternatives considered
- Installing via a separate `dnf5 install` line. Rejected: cleaner to add to the existing block.
- Using `pip` or `cargo` install. Rejected: `wlopm` is available as a Fedora RPM package via `dnf`.

## Rationale
`wlopm` provides display power management (on/off/toggle) for wlroots-based compositors like niri. Adding it to the existing niri/WM package block keeps the build organized.

## Requirements
- `wlopm` RPM must be installed in the final image.

## Technical approach
Add `wlopm` to the existing `dnf5 install -y \` block for niri/WM packages in `build_files/build.sh`.

## Files affected
- `build_files/build.sh` — add `wlopm` to the package list.
