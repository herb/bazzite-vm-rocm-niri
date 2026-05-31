# Brother brscan5 Scanner Driver for USB Scanning

## Context

The user wants to use a Brother USB paper scanner from the VM. Brother's SANE
backend (`brscan5`) is required for USB scanner detection. The bazzite base
image enables RPM Fusion non-free by default, which provides `brscan5` as a
first-party package — no manual RPM download or repository setup is needed.

## Alternatives Considered

1. **Download RPM from Brother website** — Brother distributes `brscan5` as a
   standalone RPM. This would require embedding the RPM in the build context or
   fetching it at build time. Rejected because RPM Fusion non-free already
   packages it, which is simpler and receives updates.

2. **Use generic `sane-backends`** — The base `sane-backends` package supports
   many scanners via USB vendor/product IDs, but Brother scanners typically
   require the proprietary `brscan5` binary blob for full functionality.
   Rejected as unreliable.

3. **Add `sane-backends-drivers-scanners`** — RPM Fusion's broader scanner
   driver package adds many vendor backends, but doesn't include brscan5
   specifically. Not sufficient on its own.

## Rationale

Adding `brscan5` via `dnf5 install` in `build.sh` is the simplest, most
maintainable approach. RPM Fusion non-free is already enabled in the base
image, so no extra repository configuration is needed. The install follows the
same pattern as every other package group in the build script.

## Requirements

- `brscan5` must be installed in the final image
- The scanner must be detectable via `scanimage -L` or SANE-compatible scanning
  applications when a Brother USB scanner is connected and passed through

## Non-Requirements

- No SANE configuration changes (`/etc/sane.d/`) are shipped — brscan5's
  post-install script handles USB device detection
- No scanner-specific udev rules are added — brscan5 ships its own
- No network scanner discovery (brscan5 also supports network scanning, but
  only USB is requested)

## Technical Approach

Add a single package install block in `build_files/build.sh` following the
existing section conventions:

```bash
# Scanner — brscan5 for Brother USB scanners (SANE backend)
dnf5 install -y \
    brscan5
```

No other files need modification. The package is available from RPM Fusion
non-free repos already configured in the bazzite base image.

## Files Affected

| File | Action |
|------|--------|
| `build_files/build.sh` | Add 4-line brscan5 install block after GStreamer section |

## End Criterion

The image builds cleanly and `brscan5` is present in the installed RPM list
(`rpm -q brscan5`).
