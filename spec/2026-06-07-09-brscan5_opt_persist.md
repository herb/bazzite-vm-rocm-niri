# Persist brscan5 Across bootc Deployments via Immutable /opt

## Context

The `brscan5` RPM from Brother installs all driver files to `/opt/brother/`. On
Bazzite (and Fedora bootc derivatives), `/opt` is a symlink to `/var/opt` to
make it mutable for runtime use. However, `bootc deploy` preserves the host's
`/var/` tree verbatim — it is **not** updated from the image. This means any
files written to `/opt/` (→ `/var/opt/`) during the container build are lost on
deployment.

This was discovered when `scanimage -L` returned no Brother scanner after
deploying an image that had brscan5 installed. The files existed in the image
but never made it to the running system.

## Research

### bootc project documentation

The bootc project explicitly documents this issue in discussion #1038:
[github.com/bootc-dev/bootc/discussions/1038](https://github.com/bootc-dev/bootc/discussions/1038)

> *"Some systems like FCOS make /opt a symlink to /var/opt — it's a writable,
> persistent directory. For bootc systems that are derivation points like fedora
> bootc we ship /opt as a regular directory."*

The recommended fix from bootc upstream:

> *"By shipping such content in a derived container build it will 'just work'
> in general to install RPMs that install to /opt as part of a container build
> — but the directory is read-only at runtime."*

### Universal Blue / ublue-os template

The ublue-os image-template (which this project is based on) provides the
exact workaround as a commented-out stanza:

```
### [IM]MUTABLE /opt
## Uncomment the following line if one desires to make /opt immutable and be
## able to be used by the package manager.
# RUN rm /opt && mkdir /opt
```

Source: [ublue-os/image-template](https://github.com/ublue-os/bazzite/blob/c3eb1b9f39432dfba3b8f5a1811d106d10974e2f/Containerfile)

### Additional sources

- Fedora Magazine article on bootc desktops confirms `/var` is immutable after
  initial install: [Building your own Atomic (bootc) Desktop](https://fedoramagazine.org/building-your-own-atomic-bootc-desktop/)
- Ryan Daniels' bootc tips confirms `/var` contents are lost on subsequent
  deploys: [Tips to install RPMs in bootc image builds](https://ryandaniels.ca/blog/tips-to-install-rpm-packages-in-bootc-image-builds/)
- Bazzite documentation thread on Universal Blue Discourse explicitly links
  to the `rm /opt && mkdir /opt` workaround: [Universal Blue Discourse #11578](https://universal-blue.discourse.group/t/when-can-you-call-something-bazzite/11578/15)

### Local host verification

On this host:
```
/opt -> var/opt   (symlink, confirmed)
/var/opt/brother/scanner/brscan5/   (brscan5 files — only contents in /opt/)
```

Only brscan5 uses `/opt` on this system. No other RPMs (Chrome, Docker Desktop,
etc.) are installed to `/opt`.

## Alternatives Considered

1. **Install brscan5 after deployment (day-2)** — Could install the RPM on the
   running system at first boot. Rejected because it defeats the purpose of
   image-based updates and requires manual management per machine.

2. **Install to `/usr` instead of `/opt`** — Would require extracting the RPM
   contents and manually relocating them, plus fixing hardcoded paths in
   brscan5's binaries. Overly invasive for a proprietary binary blob.

3. **RPM spec tweak to install elsewhere** — Not possible without the source
   SRPM, which Brother does not provide.

4. **`bootc usr-overlay` + `dnf reinstall` at first boot** — Works but is a
   fragile workaround that must be run on every deployment.

5. **Make `/opt` immutable (selected)** — The upstream-recommended approach.
   Simple, reliable, and the only change needed is uncommenting one line in the
   Containerfile.

## Root Cause

1. `/opt` → `/var/opt` (symlink) in the base image
2. brscan5 RPM writes to `/opt/brother/` → resolves to `/var/opt/brother/`
3. Files exist in the image but in `/var/`, which is **mutable state** preserved
   from the host during `bootc deploy`
4. The running system's `/var/` has no `brother/` directory → scanner driver
   is missing

## Requirements

- brscan5 driver files must survive a `bootc upgrade` reboot
- `rpm -q brscan5` must show the package installed
- `/opt/brother/scanner/brscan5/` must contain all driver files (libraries,
   binaries, model data, config)
- The scanner must be detectable via SANE after deployment

## Technical Approach

### Step 1: Make `/opt` a real directory in the image

Uncomment the existing `RUN rm /opt && mkdir /opt` directive in the Containerfile
before the `build.sh` RUN directive. This converts `/opt` from a symlink to a
regular directory in the image layer. Files written there during build survive
deployment because they're part of the image root filesystem (not `/var/`).

### Step 2: Fix runtime config write

brscan5's RPM postinst creates a symlink:
```
/etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg -> /opt/brother/scanner/brscan5/brsanenetdevice.cfg
```

The `brsaneconfig5` tool writes to this file (e.g., `brsaneconfig5 -a
name=... ip=...`). With immutable `/opt`, writing through this symlink would
fail. The fix is to replace the symlink with a regular file copy in `/etc/opt/`
(which is mutable, as part of `/etc/`'s 3-way merge in ostree):

```bash
rm /etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg
cp /opt/brother/scanner/brscan5/brsanenetdevice.cfg \
   /etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg
```

The other symlinks (`brscan5.ini`, `models/`) are read-only and safe.

### Step 3: Build and verify

Build the image with `just build`, then verify inside the container that
brscan5 files exist at `/opt/brother/` and the package is registered.

## Files Affected

| File | Action |
|------|--------|
| `Containerfile:93` | Uncomment `RUN rm /opt && mkdir /opt` |
| `build_files/build.sh` | After `rpm -Uvh`, replace brsanenetdevice.cfg symlink with a real file |

## End Criteria

1. Image builds cleanly with `just build`
2. `podman run --rm localhost/image-template:latest rpm -q brscan5` returns
   the installed package
3. `podman run --rm localhost/image-template:latest ls /opt/brother/scanner/brscan5/`
   shows all driver files (libraries, binaries, models, config)
4. `/opt/brother/scanner/brscan5/brsanenetdevice.cfg` is present in the image
5. `/etc/opt/brother/scanner/brscan5/brsanenetdevice.cfg` is a regular file
   (not a symlink) in the image
