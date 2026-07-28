# Restore brscan5 Runtime Library Links

## Context

The Bazzite image containing brscan5 1.6.2 deploys the Brother libraries under
`/opt/brother/scanner/brscan5`, but the RPM-generated `libLxBs*.so` links under
`/usr/lib64` are absent after deployment. `libsane-brother5.so` consequently
cannot load `libLxBsScanCoreApi.so.3`, and SANE cannot enumerate the USB
scanner.

The previous image retained these links. Recreating the four SONAME links in a
temporary library directory restored `brother5:bus5;dev2` discovery and allowed
`scanimage -A` to open the ADS-1700W successfully.

## Alternatives Considered

- Configure airscan as the primary backend: rejected because the scanner's WSD
  service is unreliable after sleep and during multi-page scans.
- Repair the links at runtime with Ansible: rejected because the immutable
  image owns both the RPM installation and `/usr/lib64`.
- Depend on the RPM post-install script: rejected because its generated links
  are demonstrably absent from the deployed image.

## Rationale

Recreate the same link chains as Brother's RPM post-install script immediately
after installing the RPM. This keeps the proprietary libraries in `/opt`, puts
only links in `/usr/lib64`, and makes the image self-contained.

## Requirements

1. Create versioned and SONAME links for all four `libLxBs` runtime libraries.
2. Fail the image build if the links do not resolve.
3. Keep brscan5 USB as the supported scanner backend.

## Technical Approach

After `rpm -Uvh`, loop over Brother's four private libraries. For each library,
create the fully versioned `/usr/lib64` link to `/opt`, then derive and create
the two abbreviated link names exactly as the RPM post-install script does.

## Files Affected

- `build_files/build.sh` - repair and verify brscan5 runtime links.
- `Containerfile` - make `build_files` content invalidate Buildah's RUN cache.

## Verification

1. Build the image and ensure `bootc container lint` passes.
2. Deploy and reboot `bix` into the new image.
3. Confirm `scanimage -L` lists a `brother5:` ADS-1700W device without a
   `libLxBsScanCoreApi.so.3` error.
4. Confirm `scanimage -d '<advertised brother5 device>' -A` succeeds.

## Issues & Resolutions

### Supplying only the first missing library did not restore USB access

**Issue**: A temporary `libLxBsScanCoreApi.so.3` link removed the loader error,
but opening a guessed USB identifier still returned `Invalid argument`.

**Resolution**: Recreated SONAME links for all four private Brother libraries
and used the exact identifier returned by `scanimage -L`. The backend then
opened successfully and exposed its duplex ADF and hardware-processing options.

### Published image reused the pre-fix build script output

**Issue**: Image `9809d056` carried revision label `4105e7f`, but its custom
rootfs diff before final metadata was the same cached result as pre-fix image
`87eff1ad`. `build_files` was exposed to the build step only through a bind
mount from the `ctx` stage. Buildah did not include that mounted content in the
RUN cache key, so the updated link-repair code never executed.

**Resolution**: Copy the `ctx` stage into `/ctx` before running `build.sh`, then
remove `/ctx` in the same RUN step. The COPY layer digest now changes whenever
`build_files` changes and invalidates downstream cached output.

### Local image verification

Built `localhost/bazzite-vm-rocm-niri:brscan5-verify` from scratch with
`podman build --no-cache --pull=newer`. The resulting container resolves all
five required SONAMEs to `/opt/brother/scanner/brscan5`, loads
`libLxBsScanCoreApi.so.3` and `libsane-brother5.so.1.0.7` through `ctypes.CDLL`
without an error, retains `brother5` in `/etc/sane.d/dll.conf`, and does not
contain the temporary `/ctx` build context.

### rpm-ostree layering removed the unowned links

**Issue**: The corrected image `6b395b39` and its unlayered base commit
`d1bb363c` contain all expected `libLxBs` link chains. The booted deployment
`9a601f32` adds the layered `gphoto2` package. Comparing those commits shows
that rpm-ostree deleted every unowned `libLxBs` link under `/usr/lib` and
`/usr/lib64` while recomposing `/usr`; the RPM-owned libraries under `/opt`
and `libsane-brother5` links remain.

**Conclusion**: The installed image is correct, but image-created links under
`/usr` are not durable across rpm-ostree package layering. The durable fix is
to make the links RPM-owned (for example, with a small compatibility RPM), or
to eliminate package layering by baking all requested packages such as
`gphoto2` into the image. Merely recreating unowned links in `build.sh` cannot
survive a later layered package transaction.

### gphoto2 baked into the image to eliminate layering

**Fix**: Moved `gphoto2` from an explicit `rpm-ostree install` on the booted
host into `build_files/build.sh` as a base image package. Staged
`rpm-ostree uninstall gphoto2` on the current boot so that the next deployment
has zero layered packages and no `/usr` recomposition.

**Verification**: Built `localhost/bazzite-vm-rocm-niri:gphoto2-baked` locally
with `podman build --no-cache --pull=newer`. The resulting container installs
both `gphoto2` and `brscan5`, resolves all four `libLxBs` SONAME chains into
`/opt/brother/scanner/brscan5`, loads all five libraries through
`ctypes.CDLL`, enables `brother5` in `/etc/sane.d/dll.conf`, and cleans up
the temporary `/ctx` build context.
