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
