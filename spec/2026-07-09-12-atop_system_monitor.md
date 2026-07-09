# atop System Monitor

## Context
The user requested that `atop` — a standard Linux system performance monitoring tool — be installed in the container image. This is useful for diagnosing CPU, memory, disk, and process activity inside VMs spawned from this image.

## Alternatives Considered
- **Install via rpm-ostree layering at runtime**: Rejected because this is an image build, not a running system.
- **Create a dedicated system-monitor section in build.sh**: Over-engineered for a single package; better to group with an existing install block.

## Rationale
`atop` is in the default Fedora repositories and requires no special configuration. Adding it to the VM/virtualization install block is the least disruptive change — those packages are general system utilities any VM operator would want.

## Requirements
- `atop` binary must be available inside the built image at `/usr/bin/atop`.
- The image must build successfully with no errors.

## Technical Approach
Append `atop \` to the existing `dnf5 install` block for VM/virtualization packages in `build_files/build.sh`, immediately before the final `guestfs-tools` entry.

## Files Affected
- `build_files/build.sh` — add `atop` to the package list

## Issues & Resolutions

### CI Runner Disk Space Exhaustion

**Issue**: After the atop install (and general image growth from prior additions like ROCm, QEMU, Niri), the GitHub Actions CI began failing during the `push-to-registry` step with `no space left on device`. The error occurred when Buildah tried to store blob data at `/var/tmp/container_images_storage...` during the push.

**Root cause**: Standard GitHub-hosted runners (`ubuntu-24.04`) have an 84 GB OS disk with only ~14 GB guaranteed free after pre-installed tools. The combined size of:
- Pulling the bazzite:stable base image
- Buildah's temporary blob storage during build and push
- The final image layers (ROCm, QEMU, Niri, etc.)

exceeded the available free space. This is a hard disk capacity limit on the Azure DS2_v2 VM backing the runner, not a daily/weekly/monthly quota.

**Resolution (three changes)**:

1. **Free more disk space before the build** — switched from `ublue-os/remove-unwanted-software` to `jlumbroso/free-disk-space@main` with all removal options enabled (dotnet, android, haskell, codeql, docker-images, large-packages). This recovers ~10–15 GB additional space.

2. **Clean dnf cache inside the image** — added `dnf5 clean all` at the end of `build.sh`. This removes `/var/cache/libdnf5/` and `/var/cache/dnf/` from the final image layers, reducing the pushed image size by hundreds of MiB.

3. **Redirect Buildah temporary storage to `/mnt`** — the runner has a 14 GB temp disk mounted at `/mnt` that is mostly idle. Add a step to pre-create a world-writable directory (`/mnt/buildah-tmp`, `chmod 1777`) and set `TMPDIR=/mnt/buildah-tmp` on the push step only (the build step didn't need it, and setting `TMPDIR=/mnt` directly on it caused a `permission denied` error since `/mnt` is root-owned).
