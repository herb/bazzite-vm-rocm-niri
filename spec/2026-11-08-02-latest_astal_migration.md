# Migrate Astal to a post-`lang/gjs` snapshot

## Context

The dotfiles cross-repository PRD
`spec/2026-11-08-04-ags_latest_astal_migration.md` in the dotfiles checkout
recommends advancing Astal from
`7b4d37603c11d2f84338a5da35b1f0676935eb57` to the researched snapshot
`b7aaf4ce69ebb3c5b1818d524e04b23bc755a97d` while keeping AGS at
`bbee2f18939f1ec7ff720e717cf305e73635628f`. This PRD records only the image
half of that plan (Phase C); the dotfiles application correction and the
cross-repository runtime acceptance remain owned by the dotfiles PRD.

The previous image pin (`spec/2026-11-08-01-pin_astal_ags_build_revisions.md`)
pinned Astal to the direct parent of the upstream `chore: cleanup lang`
commit `9b67eb5cb8235374c958c27ad960adf0a953592a`, because that tree still
shipped `lang/gjs`. The replacement snapshot was built after that removal and
has no `lang/gjs` directory, so the image can no longer install the deprecated
Astal JavaScript payload.

The snapshot does add a native build dependency: WirePlumber now requires
`pkgconfig(libpipewire-0.3)` in addition to `wireplumber-0.5`. AGS v3.1.2 is
still the current release and is unchanged by this migration.

## End criteria

1. `Containerfile.bazzite` clones Astal at exactly
   `b7aaf4ce69ebb3c5b1818d524e04b23bc755a97d` and AGS at exactly
   `bbee2f18939f1ec7ff720e717cf305e73635628f`, retaining the full-SHA
   assertion helper.
2. The builder installs `pipewire-devel`, and the WirePlumber library builds
   against the base image's `pkgconfig(libpipewire-0.3)`.
3. The obsolete `lang/gjs` Meson setup/install and the final
   `/usr/share/astal/gjs` copy are removed. The final image is asserted to
   have no `/usr/share/astal/gjs` directory.
4. All existing native coverage is preserved: `lib/astal/io`,
   `lib/astal/gtk4`, the WirePlumber, Network, Battery, Bluetooth, Apps,
   PowerProfiles, MPRIS, Notifd, and Brightness service libraries, the eleven
   sonames, the eleven typelibs, the Notifd schema, `gtk4-layer-shell` and its
   unversioned symlink, AGS/Gnim payload, `/usr/share/ags/js`, and `ldconfig`.
5. `verify-container.sh` gains displayless GObject metadata assertions for the
   audio default properties and the shared endpoint setter, the Network
   proxy/device property contract, a Notifd schema lookup, and AGS
   `ags/gtk4` / `ags/gtk4/jsx-runtime` export checks. Loader, cold-cache,
   timeout, sentinel, `ldd`, AGS help, and failure paths remain fail-closed.
6. A full local Bazzite image build and a fresh-container verifier/lint run
   succeed, with evidence recorded here.
7. No commit, push, image publication, deployment, rpm-ostree change, or
   reboot is part of this task.

## Alternatives considered

- **Retain the pre-removal pin.** Keeps the deprecated JS payload and forgoes
  the upstream Network/audio/brightness fixes; rejected as the permanent
  state, though it remains a valid rollback position.
- **Remove native Astal libraries.** Rejected: AGS GTK4 and the bar still
  consume the native GI libs and typelibs.
- **Vendor or re-add `lang/gjs`.** Rejected: upstream deliberately removed the
  deprecated wrappers and directs GJS consumers to Gnim; vendoring would add
  an unowned compatibility layer.
- **Add a multi-version compatibility adapter.** Rejected: the same endpoint
  default setter exists at both researched Astal pins, so no adapter is
  needed for audio selection.
- **Follow floating Astal `HEAD`.** Rejected: the earlier build break was
  caused by a floating clone; an immutable SHA keeps the build reproducible.

## Rationale

`b7aaf4ce69ebb3c5b1818d524e04b23bc755a97d` is the researched immutable
snapshot from the dotfiles PRD. It contains every native library the image
builds today and removes only the deprecated language tree. AGS
`bbee2f18939f1ec7ff720e717cf305e73635628f` is unchanged, so the AGS/Gnim
payload and the existing bundler contract do not move.

`pipewire-devel` was verified against the actual build base rather than the
Fedora release named in earlier notes: the local `ghcr.io/ublue-os/bazzite:stable`
image is Bazzite `45.20261105` (Fedora 45), and
`dnf5 repoquery --whatprovides 'pkgconfig(libpipewire-0.3)'` returns
`pipewire-devel-1.6.11-1.fc45.x86_64` (plus `i686` and older `1.6.9` builds).

## Requirements

- Astal and AGS revisions are fetched by full SHA and checked with
  `rev-parse`; the clone fails if the checkout differs.
- The builder remains `/out`-staged; development headers, pkg-config data,
  VAPI, source checkouts, and build RPMs do not reach the final image.
- Native library and typelib names remain unchanged; no tray, UDEV-rule, or
  AstalIO removal is introduced.
- `-Dcli=false` remains for MPRIS, Notifd, and Brightness, and Brightness
  remains on its existing `LOGIND` backend.
- The verifier must not initialize a display, construct a service, register a
  notification or secret-agent service, select an audio device, or connect to
  a host/user bus.

## Technical approach

- Replace the Astal SHA and the pin comment; keep `clone_pinned` and the AGS
  SHA unchanged.
- Add `pipewire-devel` next to `wireplumber-devel` in the builder `dnf5`
  install.
- Delete the `meson setup`/`meson install` pair for `/tmp/astal/lang/gjs` and
  the final `COPY` of `/out/usr/share/astal/gjs/`.
- In `verify-container.sh`, replace the stale `index.ts` requirement with an
  absence assertion for `/usr/share/astal/gjs`, then add a metadata-only GJS
  probe before the existing loader exercise. The probe imports only
  `AstalWp` and `AstalNetwork` typelibs and uses
  `GObject.Object.find_property`/`GObject.type_name` against GI classes, so no
  instance is constructed.
- Extend the existing AGS cold-cache bundle smoke to import `ags/gtk4` and
  `ags/gtk4/jsx-runtime`, assert the `Astal`, `Gtk`, and `Gdk` exports, and
  keep the `AGS_BUNDLE_RUNTIME_OK` sentinel. `ags/gtk4/app` is deliberately
  not imported because it calls `Gtk.init()` and needs a display.

## Files affected

- `Containerfile.bazzite`
- `build_files/common/verify-container.sh`
- `spec/2026-11-08-02-latest_astal_migration.md` (this PRD)

## Evidence

### Builder stage

Command (run from the image repository root):

```sh
podman build --pull=newer --target ags-builder \
  --tag localhost/bazzite-vm-rocm-niri:latest-astal-api-builder \
  --file Containerfile.bazzite .
```

- Exit status: `0` (`BUILDER_BUILD_EXIT=0`).
- Builder image ID: `1f4784b4f7f252beb7efe3613a309b753a28ede245ab41b0597f50ca4ce9e703`.
- `pipewire-devel-1.6.11-1.fc45.x86_64` installed from the base's Fedora 45
  repositories; WirePlumber Meson reports
  `Run-time dependency libpipewire-0.3 found: YES 1.6.11`.
- Astal projects built: `astal-io`, `astal-4`, `astal_wireplumber`,
  `astal-network`, `astal-battery`, `astal-bluetooth`, `astal-apps`,
  `astal-power-profiles`, `astal-mpris`, `astal-notifd`,
  `astal-brightness`; there is no `astal-gjs` project.
- The staged API probe against the builder's `/out` typelibs passed every
  audio/Network property assertion and failed only at the Notifd schema
  lookup, which is expected in the builder because schemas are compiled into
  the final image.

### Final image

Command (run from the image repository root):

```sh
podman build --pull=newer \
  --tag localhost/bazzite-vm-rocm-niri:latest-astal-api-candidate \
  --file Containerfile.bazzite .
```

- Exit status: `0` (`BUILD_EXIT=0`), log
  `/tmp/opencode/astal-migration/build-candidate.log` (1,395 lines).
- Image ID: `1b0645578a7ca0916130bb8e82c96ec9d6d41ce5287fca9c70faba2b38ca45ee`.
- Size: `15,623,207,010` bytes.
- The final build `RUN` executed `/ctx/verify-container.sh bazzite` and printed
  `ASTAL_API_CONTRACT_OK` and
  `AGS_BUNDLE_RUNTIME_OK exports=22 gtk4=Astal,Gdk,Gtk jsx=4`.
- `bootc container lint` during the build: 10 checks passed, 1 skipped, and the
  4 pre-existing base-image warnings (`/boot` extlinux, `/run`/`/tmp` runtime
  content, `/var/log/dnf5.log`, and `/var` tmpfiles content).

### Clean-container verification

```sh
podman run --rm --network=none --name verify-bazzite-latest-astal-api \
  --entrypoint /usr/bin/bash \
  localhost/bazzite-vm-rocm-niri:latest-astal-api-candidate \
  -c 'env -u GI_TYPELIB_PATH -u GI_GIR_PATH -u LD_LIBRARY_PATH \
      -u PKG_CONFIG_PATH /usr/bin/verify-container.sh bazzite'
```

- Exit status: `0` (`VERIFY_EXIT=0`), log
  `/tmp/opencode/astal-migration/verify-candidate.log`.
- Output tail:
  `Gjs-Console-Message: ASTAL_API_CONTRACT_OK` followed by
  `Gjs-Console-Message: AGS_BUNDLE_RUNTIME_OK exports=22 gtk4=Astal,Gdk,Gtk jsx=4`.
- A separate `bootc container lint` in a fresh container also exited `0`
  (`LINT_EXIT=0`) with the same 10-passed/1-skipped/4-warning result.
- The installed `/usr/bin/verify-container.sh` SHA-256
  `e51a4c8e733808a228f9419636ff14d7abbfb4ebc8c63405aa0a9b73545e76e8` matches
  the repository copy.

### Payload inspection

`podman run` of a read-only inspection script exited `0`
(`CONTAINER_INSPECTION_OK`), confirming:

- `/usr/share/astal` (and therefore `/usr/share/astal/gjs`) is absent.
- All eleven Astal sonames exist with versioned and unversioned symlink
  chains, for example `libastal-4.so.4 -> libastal-4.so.4.0.0`,
  `libastal-io.so.0 -> libastal-io.so.0.1.0`, through
  `libastal-brightness.so.0 -> libastal-brightness.so.0.1.0`.
- All eleven typelibs exist and are non-empty
  (`Astal-4.0` through `AstalBrightness-0.1`).
- `/usr/share/ags/js/lib/index.ts` exists, `/usr/bin/ags` is executable, and
  `gnim.gresource` is present at `200,353` bytes.
- `io.astal.notifd.gschema.xml` and the compiled `gschemas.compiled` cache
  exist.
- `libgtk4-layer-shell.so -> libgtk4-layer-shell.so.0 ->
  libgtk4-layer-shell.so.1.3.0`.
- Runtime `pipewire-libs-1.6.11-1.fc45.x86_64` owns
  `/usr/lib64/libpipewire-0.3.so.0`; `pipewire-devel`, `wireplumber-devel`,
  `vala`, `valadoc`, `golang`, `npm`, `gtk4-devel`, and
  `gobject-introspection-devel` are absent from the final image, as are
  `/usr/include/astal`, Astal VAPI/GIR files, `/tmp/astal`, and `/tmp/ags`.

### Static checks

- `bash -n build_files/common/verify-container.sh`: exit `0`.
- `shellcheck` (`koalaman/shellcheck:stable`) on the verifier: exit `0`.
- `git diff --check`: exit `0`.

## Issues & Resolutions

### Base image is Fedora 45, not Fedora 44/43

- **Issue:** earlier notes referenced Fedora 43/44 package pages, and the
  Containerfile's build-stage comment still says Fedora 44.
- **Resolution:** queried the actual local build base
  (`ghcr.io/ublue-os/bazzite:stable`, Bazzite `45.20261105`, Fedora 45).
  `pipewire-devel-1.6.11-1.fc45` is available for
  `pkgconfig(libpipewire-0.3)`, matching the installed
  `pipewire-libs-1.6.11-1.fc45`. The stale build-stage comment is left
  untouched to keep this change scoped to the pin migration.

### The new Astal tree has no `lang/gjs`

- **Issue:** the previous pin existed solely to keep `lang/gjs`; cloning the
  newer snapshot with the old Meson steps would fail exactly like upstream
  `HEAD` did.
- **Resolution:** removed the `lang/gjs` build and payload copy, and made the
  verifier assert the directory's absence. The companion dotfiles PRD
  establishes that the application consumes AGS/Gnim rather than that payload.

### Runtime introspection does not expose GIR nullability

- **Issue:** the final image ships typelibs but not GIR XML, and
  `GIRepository`/`GObject` do not expose a practical nullability query in the
  installed GJS 1.90.
- **Resolution:** the runtime probe asserts property presence, value type,
  and read/write flags; the companion dotfiles PRD and its Phase D session
  gate cover actual null-device behavior. Nullability is documented here as a
  limitation rather than guessed at runtime. The valadoc-generated GIR also
  marks `Network.wifi`/`wired` writable even though the runtime GObject
  property is read-only, so the GIR is not a reliable property-flag source
   here; the verifier uses the installed typelib's runtime metadata instead.

## Parent Review and Publication Authority

- Parent reviewed the complete implementation delta and independently ran
  `/usr/bin/verify-container.sh bazzite` in a fresh network-disabled candidate
  container, exit 0, with both success sentinels. Log:
  `/tmp/opencode/astal-parent-candidate-verify.log`.
- Parent bundled all four updated dotfiles battery/fingerprint renders with
  `ags bundle ... --gtk 4` in network-disabled old and new image containers;
  both matrix commands exited 0. Logs:
  `/tmp/opencode/astal-old-full-app-bundle.log` and
  `/tmp/opencode/astal-new-full-app-bundle.log`. These are bundle/API checks,
  not graphical session or device-action acceptance.
- Parent `bash -n` and `git diff --check` passed. Independent full dotfiles
  lint, mypy (401 files), and all 251 Bazel test targets passed.
- User separately authorized committing/pushing this image-repo change to
  main, monitoring CI, then `sudo rpm-ostree update` on bix and cinta after
  successful CI. This supersedes criterion 7 for the parent only; delegate
  publication remained prohibited. Reboot and updated AGS deployment are
  not authorized at this stage.

### Delegate Completion Status Correction

- **Issue:** the delegate ended with a background-build message, and parent
  incorrectly reported that as a still-running build without final evidence.
- **Resolution:** after the user flagged the mismatch, parent checked the
  process list, final build log and candidate image identity directly. The
  local build had succeeded at 2026-11-09 00:00 UTC. No new CI run existed
  because publication had not happened. Parent then independently verified
  the candidate as recorded above.
