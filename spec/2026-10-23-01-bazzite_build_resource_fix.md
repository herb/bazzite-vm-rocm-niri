# Reduce Bazzite AGS Build Artifacts

**Date**: 2026-10-23
**Status**: In progress

## Context

The Bazzite Containerfile currently copies the build stage's entire `/usr` into the runtime image. This captures builder dependencies and creates a large final image layer. CI also disables swap while building and only configures `/mnt/buildah-tmp` for a later push step, making build resource failures harder to diagnose.

## Alternatives considered

- Keep copying all of builder `/usr`: rejected because it imports unrelated build tools and operating-system content into the final layer.
- Build AGS/Astal with a different runtime prefix: rejected because bootc expects these runtime files beneath `/usr`, not `/usr/local` or a staging-only path.
- Change the CI build action or broadly restructure the workflow: rejected; the existing Buildah action can accept the needed temp environment and the changes should remain narrowly scoped.
- Disable swap to recover storage: rejected; preserve swap and instead monitor memory, swap, disk, and inode pressure during image build.

## Rationale

Install AGS and Astal into persistent `/out` using `DESTDIR=/out` while retaining their `/usr` runtime prefix. Expose staged pkg-config, GObject Introspection, and shared-library paths only in the builder for dependent compilations. Copy only runtime payloads into the final image, explicitly provide runtime package dependencies, and exercise the built image with headless GJS and ELF checks. Preserve the existing Buildah workflow and Bazzite/Bluefin separation.

## Requirements

- Preserve Astal components `io`, `gtk4`, `gjs`, `wireplumber`, `network`, `battery`, `mpris`, `bluetooth`, `apps`, `powerprofiles`, `notifd`, and `brightness`.
- Use `/usr` as the runtime prefix and copy only the AGS executable, Astal runtime libraries and symlinks, required typelibs, GJS data, and runtime schema/assets; do not copy the builder's full `/usr` or expose `/out` at runtime.
- Keep all runtime shared-library dependencies resolvable without importing the builder's WirePlumber package variant or relying on builder-only environment variables.
- Extend repeatable container verification for AGS execution, all expected GI namespaces, staged assets, and native-library resolution; test GJS with cold loader cache before refreshing the cache.
- Preserve the full existing Bazzite configuration and scanner checks, and leave Bluefin behavior unchanged.
- Preserve CI swap, set `TMPDIR=/mnt/buildah-tmp` for the Build Image step, and emit bounded periodic memory/swap/disk/inode diagnostics through the build/final commit, with cleanup and best-effort OOM evidence.
- Build the complete local Bazzite image, pass existing verification and bootc lint, run the resulting image in a container, and record reproducible results and image identity.

## Technical approach

Use Meson's `DESTDIR=/out` install convention after configuration with `--prefix /usr`. Set temporary `PKG_CONFIG_PATH`, `GI_TYPELIB_PATH`, and `LD_LIBRARY_PATH` for subsequent Astal/AGS builds. In the final stage, explicitly install only runtime dependencies via the existing package manager, then selectively copy staged runtime files. Expand `verify-container.sh` with Bazzite-only assertions and smoke tests. Add a small workflow resource-monitor script if needed so periodic diagnostics survive step boundaries and are cleaned up reliably.

## Files affected

- `Containerfile.bazzite`
- `.github/workflows/build.yml`
- `build_files/common/verify-container.sh`
- `build_files/common/` resource-monitor helper (if needed)
- `spec/2026-10-23-01-bazzite_build_resource_fix.md`

## Issues & Resolutions

### Builder Vala metadata lookup

The first local image build failed when compiling Astal GTK4: `valac` could not find the Astal IO VAPI installed under `/out/usr/share/vala/vapi`. The compiler searches its normal `/usr/share/vala/vapi` and `/usr/share/gir-1.0` directories, and the pkg-config/GI/library/include paths alone do not alter those searches. The builder now creates symlinks in those builder-only metadata search directories to VAPI and GIR files under `/out`; this keeps later source builds functional without copying builder `/usr` into the runtime image. Rebuild verification is in progress.

### Astal MPRIS dependencies and runtime SONAME links

The next full build showed Astal MPRIS requires `libsoup-3.0`; without `libsoup3-devel`, its Meson configure failed, and the existing library loop continued to later components. The builder now installs that dependency, `set -e` makes a failed library build stop immediately, and the final image explicitly installs `libsoup3` for runtime. The image also emitted `ldconfig` warnings that copied Astal SONAME names were regular files, so the final stage now recreates SONAME and unversioned symlinks from each versioned library before refreshing the loader cache. Verification now asserts the symlink types. These changes await another full build.

The subsequent build satisfied `libsoup-3.0` but found Astal MPRIS's default CLI also depends on `quarrel-0.1`. Since this project only needs the MPRIS library, it now joins `notifd` and `brightness` with `-Dcli=false`. The component loops explicitly exit on Meson setup, install, or metadata-exposure failures so a missing library cannot be hidden by a later successful loop iteration. Another full build is required.

Correction: `set -e` by itself does not guarantee early exit for failed commands inside an `&&` list in a loop, so the explicit `|| exit 1` checks are the fail-fast mechanism for those loops.

## Verification Evidence

### Full local Bazzite build

Command (exit 0):

```sh
TMPDIR="$HOME/.cache/bazzite-build-resource-fix/tmp" \
  podman build --pull=never \
    --tag localhost/bazzite-vm-rocm-niri:ags-out-staging \
    --file Containerfile.bazzite .
```

Build log: `/tmp/opencode/bazzite-ags-out-build.log`. The in-build `verify-hypervisor.sh` and `verify-container.sh bazzite` passed; `bootc container lint` reported 9 checks passed, 1 skipped, and 4 warnings (nonempty `/boot`, runtime `/run`/`/tmp`, log files, and `/var` tmpfiles/content).

The third attempt completed after adding `libsoup3-devel`, disabling the unused MPRIS CLI (its `quarrel-0.1` dependency is not built), and restoring SONAME symlinks before `ldconfig`.

### Running-image verification

Started and left running:

```sh
podman run --detach --name bazzite-ags-out-staging-smoke \
  --entrypoint /usr/bin/sleep \
  localhost/bazzite-vm-rocm-niri:ags-out-staging infinity
podman exec bazzite-ags-out-staging-smoke /usr/bin/verify-container.sh bazzite
```

Both commands passed. The repeatable verifier cold-removes `/etc/ld.so.cache`, imports all expected Astal/Gtk GI namespaces in GJS with `GI_TYPELIB_PATH` and `LD_LIBRARY_PATH` unset, then rebuilds the cache only after that cold-cache test. An additional cold-cache check imported `Astal`, `AstalIO`, `AstalWp`, `AstalNetwork`, `AstalBattery`, `AstalMpris`, `AstalBluetooth`, `AstalApps`, `AstalPowerProfiles`, `AstalNotifd`, `AstalBrightness`, and `Gtk`, and ran `ldd` over 22 Astal library paths; all imports succeeded and no native dependencies were missing. `/usr/bin/ags --help` passed and `--version` printed `ags version 3.1.0`.

Checked runtime assets and layout: AGS JS library and gnim resource, Astal GJS modules, notifd schema and compiled schema, all 11 expected Astal typelibs, all expected shared-library files and real unversioned/SONAME symlinks, and no `/out` or `/usr/local/bin/ags` runtime paths. Runtime RPMs include `gjs-1.88.1-2.fc44`, `gtk4-layer-shell-1.3.0-1.fc44`, and `libsoup3-3.6.6-10.fc44`; the existing `terra-wireplumber` and `terra-wireplumber-libs` 0.5.17 packages remain in the final image rather than being copied from the Fedora build stage. Existing hypervisor, Brother scanner, ROCm, Niri, and service checks passed.

No graphical Wayland session was started or claimed; runtime validation is headless and does not prove UI behavior in a live desktop session.

### Image and layer identity

- Candidate tag: `localhost/bazzite-vm-rocm-niri:ags-out-staging`
- Image ID: `979e16e131d0d7a76df4d9c26765ef3bafe895a3d34f8a8d1e75bbdc5c91ac23`
- Image digest: `sha256:667129bbcce448738b41f3ab39dad4a33edfee8139c13b4ee9955f82388e853e`
- Named running test container: `bazzite-ags-out-staging-smoke`, ID `7b444fadb18f04859c73b59592b74114ecfbf96e085616bf0924e6d98484cd8d`
- Local image size changed from 27,675,765,945 bytes (`localhost/bazzite-vm-rocm-niri:latest`) to 16,043,155,445 bytes for the candidate, a reduction of 11,632,610,500 bytes. The prior whole-builder `/usr` copy layer was 11.7 GB; candidate runtime artifact-copy layers are about 26.4 MB, plus a 168 MB package/dependency layer.

### Static and scope checks

Passed: `bash -n build_files/common/verify-container.sh .github/scripts/monitor-build-resources.sh`; Python/PyYAML parse of `.github/workflows/build.yml`; `just --unstable --fmt --check -f Justfile`; `git diff --check`; resource-monitor process-group smoke test; and Astal SONAME-link creation smoke test. Bluefin Containerfile/build scripts were not changed, and the added verification logic is restricted to the Bazzite case. No CI run or publication was performed. `actionlint` and `shellcheck` are not installed locally.

## Implementation Outcome

Local implementation and all requested prepublication Bazzite build/container checks completed successfully. The final verification was repeated in the still-running named container after this PRD evidence was added. The local candidate was not pushed or published.

### Review remediation R1-F01: GTK4 layer-shell preload

The independent runtime review found that `ags run ... --gtk 4` exited successfully while emitting an `LD_PRELOAD` warning: `/usr/lib64/libgtk4-layer-shell.so` was missing. The runtime RPM provides `libgtk4-layer-shell.so.0` but not the unversioned development linker name; the prior builder `/usr` copy had accidentally supplied it.

The final image now creates only the runtime symlink `/usr/lib64/libgtk4-layer-shell.so -> libgtk4-layer-shell.so.0`, and the verifier checks that it resolves to the package-provided SONAME. The Bazzite verifier now creates a private temporary TypeScript entry point, runs `timeout 30 ags run ... --gtk 4` with builder variables unset and the loader cache removed, requires `AGS_BUNDLE_RUNTIME_OK`, and fails on any dynamic-loader/preload warning. Its exit trap removes the temporary entry point and captured output.

The full local rebuild passed (log `/tmp/opencode/bazzite-ags-layer-shell-fix-build.log`); `bootc container lint` again reported 9 checks passed, 1 skipped, and 4 warnings. Both the image-build smoke and the subsequent run in the new `bazzite-ags-layer-shell-remediation-smoke` container printed `AGS_BUNDLE_RUNTIME_OK exports=22` without loader warnings. The existing `bazzite-ags-out-staging-smoke` container was left untouched.

Remediation image: `localhost/bazzite-vm-rocm-niri:ags-layer-shell-fix`, image ID `f210b7446a46d20b96956433f102ff1f4b67e5852f1d847cbcdeb6c32077438e`, digest `sha256:80987b6f60f0ae7441fbe2b6eb860bc2cb514462247a5a0ecbe4a21db17af72c`, size 16,043,162,249 bytes. New running test container ID: `b148edf940c1ed916753f1751920ee3b7516194386e996839fa92af7f79564db`.

Reproduction commands (all exited 0):

```sh
TMPDIR="$HOME/.cache/bazzite-build-resource-fix/tmp" \
  podman build --pull=never \
    --tag localhost/bazzite-vm-rocm-niri:ags-layer-shell-fix \
    --file Containerfile.bazzite .
podman run --detach --name bazzite-ags-layer-shell-remediation-smoke \
  --entrypoint /usr/bin/sleep \
  localhost/bazzite-vm-rocm-niri:ags-layer-shell-fix infinity
podman exec bazzite-ags-layer-shell-remediation-smoke \
  /usr/bin/verify-container.sh bazzite
```

The final verifier output included `AGS_BUNDLE_RUNTIME_OK exports=22`; the parent reproduction's `LD_PRELOAD` warning did not recur. The new RPM is `gtk4-layer-shell-1.3.0-1.fc44.x86_64`, and the created unversioned link resolves to the packaged `.so.0` target. Build output is at `/tmp/opencode/bazzite-ags-layer-shell-fix-build.log`.
