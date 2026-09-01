# Shared JSON, Sync, and WireGuard Tools

## Context

The Bazzite and Bluefin images share a common hypervisor baseline. Host
operations also require `jq` for structured data processing, `rsync` for file
synchronization, and `wireguard-tools` for WireGuard interface management.

## Requirements

- Install `jq`, `rsync`, and `wireguard-tools` in both Bazzite and Bluefin.
- Verify all three RPMs during each image build.
- Verify `jq`, `rsync`, `wg`, and `wg-quick` in clean runtime containers for
  both image flavors.
- Keep the package installation and verification centralized in the shared
  image layer.

## Technical Approach

Add the packages to `build_files/common/install-hypervisor.sh`. Extend the
shared build-time and runtime package contracts with the package names and
their expected executables. Since both Containerfiles execute the shared
installer and verifiers, no flavor-specific changes are needed.

## Files Affected

- `build_files/common/install-hypervisor.sh`
- `build_files/common/verify-hypervisor.sh`
- `build_files/common/verify-container.sh`
- this spec

## Verification

- Run Bash syntax checks and ShellCheck on the shared scripts.
- Run `just --fmt --check` and whitespace validation.
- Run `just verify-images` to rebuild and verify both images in clean Podman
  containers.
