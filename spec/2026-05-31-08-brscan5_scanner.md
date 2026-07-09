# Brother brscan5 Scanner Driver for USB Scanning

## Context

The user wants to use a Brother USB paper scanner from the VM. Brother's SANE
backend (`brscan5`) is required for USB scanner detection. This is a
proprietary driver that Brother distributes only from their website — it is
**not** available in RPM Fusion or any other Fedora repository.

## Alternatives Considered

1. **RPM Fusion non-free** — Initially assumed to contain `brscan5`. CI
   confirmed `No match for argument: brscan5`. RPM Fusion does not carry this
   package.

2. **Use generic `sane-backends`** — The base `sane-backends` package supports
   many scanners via USB vendor/product IDs, but Brother scanners typically
   require the proprietary `brscan5` binary blob for full functionality.
   Rejected as unreliable.

3. **Download RPM at build time (selected)** — `curl` the RPM directly from
   Brother's official CDN and install it with `dnf5`. Simple, no vendoring
   needed, and always fetches the intended version.

## Rationale

Brother's official RPM is the only reliable source for `brscan5`. Downloading
it at build time with `curl` avoids vendoring a binary blob in the repo while
keeping the build self-contained. The RPM requires `gtk2` as a runtime library,
so `gtk2` is installed first.

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
- The RPM is not vendored in the repo — fetched at build time

## Technical Approach

Install `gtk2` (required by brscan5 on Fedora 40+), then download and install
the RPM from Brother. The Brother RPM lacks proper embedded digests, so
`rpm -Uvh` with `--nosignature` is used instead of `dnf5 install`:

```bash
dnf5 install -y gtk2
curl -Lo /tmp/brscan5.rpm \
    "https://download.brother.com/welcome/dlf104036/brscan5-1.6.2-0.x86_64.rpm"
rpm -Uvh --nosignature /tmp/brscan5.rpm
rm -f /tmp/brscan5.rpm
```

The RPM URL (`dlf104036`) is the stable Brother CDN path for the x86_64
variant of brscan5 1.6.2-0, as documented in the AUR and Void Linux package
sources. The `--nosignature` flag is required because Brother does not GPG-sign
their RPMs.

## Files Affected

| File | Action |
|------|--------|
| `build_files/build.sh` | Replace dnf repo install with curl + dnf5 local RPM install |

## End Criterion

The image builds cleanly and `brscan5` is present in the installed RPM list
(`rpm -q brscan5`).
