# Shared Bazzite and Bluefin Images

## Context

The repository currently builds `bazzite-vm-rocm-niri`, a custom Bazzite
bootc image used for workstation hosts and libvirt k3s hypervisors. A new
Bluefin host will be added to the fleet as a k3s hypervisor. Stock Bluefin does
not provide the complete virtualization and monitoring package contract that
the Ansible k3s playbook assumes, while the current image repository already
contains most of that contract.

## Alternatives Considered

1. Create a separate Bluefin image repository. Rejected because it duplicates
   signing, CI, disk-image, package verification, and shared hypervisor
   maintenance.
2. Parameterize the existing Containerfile and build script with a flavor
   variable. Rejected because the current build is tightly coupled to Bazzite,
   AGS/Astal, ROCm, Niri, scanner drivers, and workstation services.
3. Use one repository with separate image definitions and a small common
   hypervisor layer. Selected because it shares the stable contract while
   isolating upstream-base and image-specific behavior.

## Rationale

The repository will remain the source of two independently publishable images:

- `ghcr.io/<owner>/bazzite-vm-rocm-niri`
- `ghcr.io/<owner>/bluefin-hypervisor`

The existing Bazzite package identity and behavior remain compatible. Bluefin
will be based on `ghcr.io/ublue-os/bluefin:stable` and will receive only the
common hypervisor baseline plus explicitly justified Bluefin-specific changes.

## Background

The current architecture is:

- `Containerfile` uses Bazzite as the final image and as the AGS builder.
- `build_files/build.sh` installs virtualization packages, then mixes ROCm,
  Niri, scanner, Hyprlock, PAM, and desktop customization.
- `.github/workflows/build.yml` builds and publishes one image named after the
  repository.
- `.github/workflows/build-disk.yml` converts that one image to disk artifacts.
- `Justfile` builds the one Containerfile and runs bootc-image-builder locally.
- Ansible `server/k3s.yaml` expects libvirt, QEMU, guestfs tooling, OVMF, and
  atop on the immutable hypervisor.

The implementation separates the shared hypervisor contract from the Bazzite
workstation contract, adds a minimal Bluefin image, and makes CI/local/disk
operations flavor-aware.

Prerequisites:

- GitHub Actions and GHCR package publication are enabled for the public repo.
- The existing Cosign signing secret remains configured in GitHub Actions.
- Local Podman has enough disk space to build both large images sequentially.
- Bluefin x86-64 hardware exposes `/dev/kvm` for post-boot validation.

## Requirements

- Preserve the Bazzite image name, tags, and existing custom packages.
- Publish a separate Bluefin hypervisor package.
- Share virtualization packages, qemu sysusers configuration, libvirtd
  enablement, and package/capability verification.
- Verify both images locally inside clean Podman containers.
- Verify shared packages and image-specific packages separately.
- Ensure Bluefin does not inherit repository-specific Bazzite customizations.
- Build flavors in separate GitHub-hosted standard-runner matrix jobs.
- Keep disk builds explicit and short-retention.
- Keep build and signing credentials out of image contexts.

## Technical Approach

Create separate `Containerfile.bazzite` and `Containerfile.bluefin` files.
Place the common installer, qemu sysusers asset, and verifier under
`build_files/common/`. Place the current Bazzite-only script under
`build_files/bazzite/`, and add a minimal Bluefin script under
`build_files/bluefin/`. Keep Bazzite services under `services/bazzite/`.

The shared verifier will check RPMs, executable paths, libvirt service state,
qemu sysusers declarations, and OVMF. A flavor-aware container verifier will
add positive image-specific checks and Bluefin contamination checks.

GitHub Actions will use a matrix with independent Bazzite and Bluefin jobs.
The existing Bazzite GHCR package name remains unchanged; Bluefin publishes as
`bluefin-hypervisor`. Local commands will require an explicit flavor for image
selection, and disk builds will select the published image explicitly.

## Implementation Phases

### Phase 1: Extract Shared Hypervisor Layer

Goal: both image definitions can install and validate the same host contract.

Files:

- `build_files/common/install-hypervisor.sh`
- `build_files/common/verify-hypervisor.sh`
- `build_files/common/usr/lib/sysusers.d/qemu.conf`

Verification:

- Shell syntax checks pass.
- The scripts contain no secrets or host-specific values.
- The verifier fails when a required package/path/service is absent.

Stopping point: the common scripts are complete and independently reviewable.

### Phase 2: Split Image Definitions

Goal: Bazzite preserves its current customization while Bluefin receives only
the hypervisor baseline.

Files:

- `Containerfile.bazzite`
- `Containerfile.bluefin`
- `build_files/bazzite/build.sh`
- `build_files/bluefin/build.sh`
- `services/bazzite/*`

Verification:

- Both Containerfiles pass syntax/build parsing.
- Bazzite-specific assets are not copied into the Bluefin context.
- Both definitions invoke the common verifier.

Stopping point: each image can be built independently.

### Phase 3: Local Container Verification

Goal: prove packages and files exist in running containers, not merely in build
logs.

Files:

- `build_files/common/verify-container.sh`
- `Justfile`

Verification:

- Build Bazzite and Bluefin sequentially.
- Create a Podman container from each image.
- Run shared and flavor-specific assertions inside each container.
- Remove containers on success and failure.

Stopping point: `just verify-images` passes for both images.

### Phase 4: CI and Disk Workflows

Goal: publish and sign both packages independently and make disk builds
explicit.

Files:

- `.github/workflows/build.yml`
- `.github/workflows/build-disk.yml`
- `disk_config/iso-bazzite.toml`
- `disk_config/iso-bluefin.toml`

Verification:

- Pull requests build both flavors without push/sign permissions.
- Default-branch builds publish expected package/tag combinations.
- Disk builds select one flavor and do not run on the daily schedule.

Stopping point: both public packages have independently verified signed tags.

### Phase 5: Boot and Rollout Validation

Goal: validate Bluefin as a real k3s hypervisor before Ansible enrollment.

Verification:

- Boot Bluefin and verify bootc, `/var/home`, qemu identity, libvirtd, KVM,
  OVMF, SELinux, atop, and reboot persistence.
- Create and destroy a disposable libvirt VM and network.
- Deploy by date tag or digest, preserving rollback to the prior image.

Stopping point: the Bluefin host passes hypervisor validation and has a
recorded rollback digest.

## Files Affected

- `Containerfile` renamed to `Containerfile.bazzite`
- `Containerfile.bluefin`
- `build_files/common/install-hypervisor.sh`
- `build_files/common/verify-hypervisor.sh`
- `build_files/common/verify-container.sh`
- `build_files/common/usr/lib/sysusers.d/qemu.conf`
- `build_files/bazzite/build.sh`
- `build_files/bluefin/build.sh`
- `services/bazzite/ags.service`
- `services/bazzite/plasma-polkit-agent.service`
- `services/bazzite/swayidle.service`
- `Justfile`
- `.github/workflows/build.yml`
- `.github/workflows/build-disk.yml`
- `disk_config/iso-bazzite.toml`
- `disk_config/iso-bluefin.toml`
- `README.md`
- this PRD

## Issues & Resolutions

### Local YAML Parser Availability

The development environment does not include Ruby, so Ruby-based workflow YAML
validation was unavailable. Python's installed PyYAML package was used instead;
both workflow files parsed successfully. Shell syntax, ShellCheck, Justfile
formatting, and whitespace validation also passed.

## Acceptance Criteria

- Existing Bazzite consumers can continue pulling the existing package name.
- Bluefin builds from the Bluefin stable base with the shared hypervisor
  contract.
- Both images pass bootc lint and local Podman container verification.
- Bazzite-specific customizations remain in Bazzite only.
- Both public GHCR packages build and sign independently in CI.
- Disk builds are manually flavor-selected and do not retain daily large
  artifacts.

## Issues & Resolutions

### Review Follow-up

The review identified several fail-open or stale local workflow paths. Local
image and disk recipes now require `bazzite` or `bluefin`, reject unknown
flavors, and select the matching ISO configuration. The disk workflow remains
manual and flavor-selected; its ARM option was removed because the current
package and scanner contracts are x86-64-specific. Bluefin runtime verification
now rejects the Bazzite ROCm, Niri, Hyprlock, scanner, and user-service assets.
The unused preliminary Bazzite stage was also removed.

Verification:

- Direct Podman builds of both Containerfiles pass bootc lint.
- Named containers created from both images pass shared package/path/service
  checks and flavor-specific positive/negative checks.
- Justfile syntax and shell validation pass.

### Final Isolation Follow-up

The final verification review found that the Bluefin negative contract omitted
the Bazzite-specific `swayidle.service` unit. The verifier now rejects that
unit alongside AGS and the Plasma polkit agent. The disk workflow also uses
the only selectable runner directly instead of retaining an unreachable ARM
fallback expression.
