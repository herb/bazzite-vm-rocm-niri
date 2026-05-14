# Persist qemu Unix User in Image

## Context
The `qemu` system user (UID 107) was missing after a `bootc rebase`, breaking libvirt/qemu functionality in the VM. This user is required by `qemu-kvm` and `libvirtd` to run VMs with proper privileges. In OSTree/bootc-based immutable images, `/etc/passwd` is generated per-deployment from `/usr/lib/sysusers.d/` entries via `systemd-sysusers`.

## Alternatives Considered
1. **useradd in build.sh** — Would create the user at build time, but the resulting `/etc/passwd` entry would live in the OSTree commit's immutable /etc. On `bootc rollback` or fresh deploy it would still be present, but this is not the standard way to declare system users in bootc images. Rejected in favor of sysusers.d.
2. **Rely on qemu RPM's sysusers.d file** — The Fedora `qemu` package ships its own `qemu.conf` in `/usr/lib/sysusers.d/`. However, the bazzite base image may strip or not ship this file, and the user observed it was missing. Explicitly providing our own copy is safer.
3. **`systemd-sysusers` call in build.sh** — Pre-generating the user entry at build time is redundant when the sysusers.d file will be processed at deployment. Cleaner to just ship the config.

## Rationale
Using `sysusers.d` is the standard, documented mechanism for declaring system users in Fedora Atomic/bootc images. `systemd-sysusers` processes these files on every deployment, ensuring the user exists in `/etc/passwd` with a stable UID 107. This mirrors how bazzite-dx handles system file overlays (via `system_files/` directory copied into `/`).

## Requirements
- The `qemu` user must exist at UID 107 on every boot/deployment
- The approach must survive `bootc rebase` and `bootc rollback`
- Minimal change to existing build structure

## Technical Approach
1. Create a `sysusers.d` config file at `build_files/usr/lib/sysusers.d/qemu.conf` declaring the qemu user
2. Add a `cp` command in `build.sh` to copy the entire `usr/` tree from the build context (`/ctx/usr/.`) into `/usr/.` — this is the pattern used by bazzite-dx for overlaying system files

## Files Affected
- **Created**: `build_files/usr/lib/sysusers.d/qemu.conf`
- **Modified**: `build_files/build.sh` — add file copy step before `systemctl enable libvirtd`
