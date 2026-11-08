# Pin Astal and AGS source revisions in the Bazzite image build

## Context

GitHub Actions run `42390037556` failed building `Containerfile.bazzite` at
the `astal-gjs` meson setup step (line 64):

```
ERROR: Neither directory '/tmp/astal/lang/gjs/build' nor directory
'/tmp/astal/lang/gjs' exist.
```

The builder clones `https://github.com/aylur/astal.git` with `--depth 1`, so
it follows upstream `HEAD`. Upstream commit `9b67eb5cb8235374c958c27ad960adf0a953592a`
(`chore: cleanup lang`, 2026-11-06) removed `lang/gjs`, which this image
still installs to `/usr/share/astal/gjs`. The same repository SHA `e9228ee`
succeeded in run `42260027502` because that build compiled a pre-removal
Astal `HEAD`; the build is now non-reproducible and fails as soon as the
upstream clone cache is invalidated.

The `ags` clone at line 67 also follows upstream `HEAD` and is equally
non-reproducible. Bluefin is unaffected because `Containerfile.bluefin`
does not build Astal or AGS.

## End criteria

1. Astal and AGS sources are pinned to full, verified commit SHAs in
   `Containerfile.bazzite`.
2. The pinned Astal revision contains `lang/gjs`, and the pinned AGS
   revision is compatible with it and with the existing runtime verifier.
3. A complete local Bazzite image build succeeds.
4. Local image rootfs/container inspection confirms:
   - Astal GJS TypeScript sources under `/usr/share/astal/gjs`;
   - Astal shared libraries, soname/symlink chains, and typelibs;
   - expected AGS artifacts under `/usr/share/ags` and `/usr/bin/ags`;
   - the existing `build_files/common/verify-container.sh bazzite` smoke
     checks (GJS imports, AGS bundle runtime, loader checks, `ldd`) pass.
5. Evidence is recorded in this PRD.

## Alternatives considered

- **Remove the Astal GJS build and verifier checks.** Rejected: AGS configs
  import the Astal GJS package; dropping it would remove functionality and
  weaken existing acceptance checks.
- **Track a new upstream Astal branch/tag.** Rejected: no post-removal
  Astal revision ships `lang/gjs`; only a pre-removal revision preserves the
  current packaging contract.
- **Vendor the Astal GJS sources or add a patches layer.** Rejected:
  larger scope and an ongoing maintenance burden compared with pinning the
  last known-good revision.
- **Keep floating clones and rely on build cache.** Rejected: this is the
  root cause; a cold runner or invalidated cache fails the build.

## Rationale

Astal `7b4d37603c11d2f84338a5da35b1f0676935eb57` is the direct parent of the
`chore: cleanup lang` removal commit. It contains `lang/gjs` and the Astal
library sources that the image already builds and verifies. The successful
2026-11-06 build demonstrably compiled `lang/gjs` from this pre-removal tree
and produced artifacts matching `verify-container.sh`.

AGS `bbee2f18939f1ec7ff720e717cf305e73635628f` is the current upstream
`HEAD`, tagged `v3.1.2` (version 3.1.2). It has been unchanged since
2026-04-09, so every recent successful build, including the 2026-11-06 run,
cloned exactly this revision. It is therefore the known-good AGS revision
for the pinned Astal tree and the existing AGS packaging checks.

Both revisions are fetched by full SHA with a shallow fetch, then verified
with `rev-parse`, so the build cannot silently float to a different commit.

## Requirements

- `Containerfile.bazzite` must clone Astal at
  `7b4d37603c11d2f84338a5da35b1f0676935eb57` and AGS at
  `bbee2f18939f1ec7ff720e717cf305e73635628f`.
- The clone step must fail if the checked-out SHA differs from the pin.
- Runtime packaging must remain `/out`-staged; the builder `/usr` must not be
  copied into the final image.
- Existing `build_files/common/verify-container.sh` checks must remain
  unchanged and pass.
- No commit, push, or pull request is part of this task.

## Technical approach

Replace each floating `git clone --depth 1` with an explicit
init/remote/fetch-by-SHA/checkout sequence and a SHA assertion. Keep the
existing build and install commands and the `/out` staging prefix unchanged.

## Files affected

- `Containerfile.bazzite`
- `spec/2026-11-08-01-pin_astal_ags_build_revisions.md` (this PRD)

## Issues & Resolutions

### Upstream Astal removed `lang/gjs`

- **Issue:** the floating `git clone --depth 1` picked up
  `9b67eb5cb8235374c958c27ad960adf0a953592a` (`chore: cleanup lang`), which
  deleted `lang/gjs`, so the `meson setup` step failed before the image could
  be built.
- **Resolution:** added a `clone_pinned` shell helper to the builder `RUN`
  that initializes an empty repository, fetches one exact full SHA with
  `--depth 1`, checks it out detached, and asserts `rev-parse HEAD` equals
  the requested pin. Astal is pinned to
  `7b4d37603c11d2f84338a5da35b1f0676935eb57` (direct parent of the removal),
  and AGS is pinned to `bbee2f18939f1ec7ff720e717cf305e73635628f`
  (v3.1.2, upstream `HEAD` since 2026-04-09).

### Local build and image verification

Evidence captured on 2026-11-08:

- Build command:
  `/usr/bin/podman build --pull=newer --tag localhost/bazzite-vm-rocm-niri:ci-astal-pin --file Containerfile.bazzite .`
- Build exit status: `0` (`BUILD_EXIT=0`).
- Image ID:
  `55864a892468b2a5d7925ec57889f957ad7066292fdaa1997d9ee9c6ef5c0740`
- Image size: `15,623,100,049` bytes.
- Both builder-stage steps executed rather than reusing cache; the log shows
  `Project name: astal-gjs`, the `lang/gjs` installs to
  `/out/usr/share/astal/gjs`, `Project name: ags`, `Installing ags to
  /out/usr/bin`, and `AGS_BUNDLE_RUNTIME_OK exports=22`.
- `bootc container lint` completed with 10 checks passed, 1 skipped, and 4
  pre-existing base-image warnings (`/boot` extlinux, `/run` and `/tmp`
  runtime content, `/var/log/dnf5.log`, and `/var` tmpfiles content).

Rootfs inspection used `podman unshare` because rootless `podman image
mount` requires a user namespace:

```
podman unshare bash /tmp/opencode/inspect-bazzite-rootfs.sh
```

Results (`ROOTFS_INSPECTION_OK`, exit 0, image unmounted afterwards):

- `/usr/share/astal/gjs` contains all 20 expected GJS files, including
  `index.ts`, `_astal.ts`, `binding.ts`, `overrides.ts`, `variable.ts`, and
  the `gtk3/` and `gtk4/` trees. The mounted `index.ts` SHA-256
  (`61421d87...f25a60`) matches the pinned Astal source blob.
- `/usr/share/ags/js/lib/index.ts` SHA-256 (`43474de4...e8fdc4b`) matches the
  pinned AGS source blob; `/usr/share/ags/js/node_modules/gnim/dist/gnim.gresource`
  is present (200,353 bytes); `/usr/bin/ags` is an x86-64 dynamically linked
  ELF executable.
- All 11 expected Astal shared libraries exist, each has a versioned file, a
  soname symlink, and an unversioned symlink. For example:
  `libastal-4.so.4 -> libastal-4.so.4.0.0` and
  `libastal-4.so -> libastal-4.so.4`; equivalent chains were verified for
  IO, WirePlumber, Network, Battery, MPRIS, Bluetooth, Apps,
  PowerProfiles, Notifd, and Brightness.
- All 11 expected typelibs exist under
  `/usr/lib64/girepository-1.0/` (`Astal-4.0` through
  `AstalBrightness-0.1`), with non-zero sizes.
- `/usr/lib64/libgtk4-layer-shell.so -> libgtk4-layer-shell.so.0` resolves to
  `libgtk4-layer-shell.so.1.3.0`.
- `/usr/bin/verify-container.sh` is installed and its SHA-256 matches
  `build_files/common/verify-container.sh`.

Clean-container runtime verification:

```
podman run --name verify-bazzite-ci-astal-pin --entrypoint /usr/bin/bash \
  localhost/bazzite-vm-rocm-niri:ci-astal-pin \
  -c '/usr/bin/verify-container.sh bazzite'
```

- Exit status `0`; output:
  `Gjs-Console-Message: ... AGS_BUNDLE_RUNTIME_OK exports=22`.
- A second container inspection confirmed `gjs` imports all Astal typelibs
  (`GJS_TYPELIB_IMPORTS_OK`), `ldd` reports no missing dependencies for any
  Astal library, `ags --version` reports `ags version 3.1.0`, `ags --help`
  succeeds, and the cold-cache AGS bundle smoke prints
  `AGS_BUNDLE_RUNTIME_OK exports=22` (`CONTAINER_INSPECTION_OK`).
- Builder-only payload is absent from the final image: no `/usr/include/astal`,
  Astal VAPI/`.pc` files, `/tmp/astal`, or `/tmp/ags`. The builder-only RPMs
  `vala`, `valadoc`, `golang`, `npm`, `wireplumber-devel`, and `gtk4-devel`
  are not installed. Expected runtime RPMs `gjs-1.90.1-1.fc45`,
  `gtk4-layer-shell-1.3.0-3.fc45`, and `libsoup3-3.8.1-1.fc45` are present.

### Residual risks and notes

- The Astal pin is a pre-removal snapshot. It preserves current packaging but
  will not receive post-2026-11-01 Astal fixes. A future migration should
  replace the removed `lang/gjs` package, at which point the pin can move
  forward.
- Upstream AGS `v3.1.2` embeds `3.1.0` in `cli/version`, so `ags --version`
  reports 3.1.0 even though `package.json` and the tag are 3.1.2. This is an
  upstream metadata quirk, not a packaging error.
- The local build pulled `ghcr.io/ublue-os/bazzite:stable` on 2026-11-08, the
  same floating base tag used by CI, so base-image drift remains a CI
  variable outside this fix.
