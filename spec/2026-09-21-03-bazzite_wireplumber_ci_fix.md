# Bazzite WirePlumber CI build fix

## Context

Two consecutive CI builds failed in the `ags-builder` stage while installing
`wireplumber-devel`. The current `ghcr.io/ublue-os/bazzite:stable` base image
contains `terra-wireplumber`, while Fedora's `wireplumber-devel` requires the
matching Fedora `wireplumber` package. Those packages conflict. Removing the
existing version locks is necessary, but no longer sufficient after the base
image began shipping the Terra package.

## Alternatives considered

- Remove `wireplumber-devel` and omit Astal's WirePlumber integration. Rejected
  because the image intentionally builds the complete Astal service library set.
- Keep the Terra package and find a Terra-provided development package. Rejected
  because the enabled repositories do not provide one and the existing build
  depends on Fedora's development metadata.
- Use `--skip-broken`. Rejected because it can silently omit a required build
  dependency and produce an incomplete AGS installation.
- Allow DNF to replace the conflicting package with the matching Fedora build.
  Selected because the builder already removes the Bazzite WirePlumber locks and
  intentionally needs the Fedora package family for compilation.

## Rationale

Adding `--allowerasing` to the builder's DNF transaction makes the intended
replacement explicit. DNF removes `terra-wireplumber` and installs matching
`wireplumber`, `wireplumber-libs`, and `wireplumber-devel` packages at the same
version, preserving the Astal build requirements.

## Requirements

- The Bazzite AGS builder dependency transaction succeeds with the current
  Bazzite stable base image.
- Fedora `wireplumber`, `wireplumber-libs`, and `wireplumber-devel` are installed
  at a matching version in the builder.
- The complete Bazzite image builds locally.
- A container created from the resulting image reports the expected WirePlumber
  packages and matching versions.
- Existing unrelated working-tree changes are preserved.

## Technical approach

1. Add `--allowerasing` to the `dnf5 install` command in `Containerfile.bazzite`.
2. Update the Astal dependency documentation with the Terra/Fedora conflict.
3. Build the complete Bazzite image locally with Podman.
4. Create a disposable container from that image and verify the installed RPM
   package names, versions, architecture, and package ownership.

## Files affected

- `Containerfile.bazzite`
- `spec/2026-05-17-06-astal_devel_deps.md`
- `spec/2026-09-21-03-bazzite_wireplumber_ci_fix.md`

## Validation

- Full local build succeeded:
  `bazzite-vm-rocm-niri:ci-wireplumber-fix`.
- `bootc container lint` passed 10 checks and reported only the base image's
  existing nonempty `/boot`, runtime-directory, and `/var` warnings.
- A container created from the image reported matching
  `wireplumber-0.5.17-1.fc44`, `wireplumber-libs-0.5.17-1.fc44`, and
  `wireplumber-devel-0.5.17-1.fc44` packages on `x86_64`.
- `terra-wireplumber` was absent, RPM ownership checks passed for the runtime
  library and pkg-config file, and `verify-container.sh bazzite` passed.
