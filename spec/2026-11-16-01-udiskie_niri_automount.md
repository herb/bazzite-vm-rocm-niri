# udiskie automount for niri hosts

## Context

Removable media on the niri hosts (`cinta` and `bix`) is not automounted in
the niri session. On `cinta` a Kingston DataTraveler attached through the
CalDigit TS4 dock is detected by the kernel and udisks2, but nothing mounts it:
`udisks2` is running while `udiskie` is absent from the image. The earlier
recommendation for this gap was `udiskie --automount --no-tray`, started with
the login session and reacting to hotplug, with no `/etc/fstab` entries and no
hub-specific configuration. The user now wants that installed at image level
rather than layered onto hosts by hand.

KDE's automounter (KDED / Solid) is the usual provider on Plasma but it is not
used here: the niri session deliberately does not start the KDE stack, so the
image must supply a user-level automounter for niri only.

Source for the recommendation above: T3 thread
`f2f6bdc1-1718-438f-aa29-041ddc46b741` (read-only recovery from the local T3
state database; not re-verified against a live session in this task).

## Alternatives considered

- **`/etc/fstab` or systemd mount units per device.** Rejected: device- and
  hub-specific, and it bypasses the desktop-session lifecycle.
- **Hub-specific or DataTraveler-specific udev/udiskie rules.** Rejected: the
  requirement is generic removable-media automount, not one device.
- **Start KDE's KDED/Solid automounter under niri.** Rejected: pulls the Plasma
  stack into the niri session, which the niri design deliberately avoids.
- **Tray icon (`--tray`).** Rejected: requires a tray host and a display at
  startup; no tray is needed for automount.
- **Run udiskie as a system service.** Rejected: udiskie is a per-user
  daemon; it needs the user session, not the system manager.

## Rationale

udiskie is the smallest per-user automounter that talks to udisks2 over D-Bus
and needs no desktop shell. Shipping it in the image keeps `cinta` and `bix`
identical and reproducible. Following the existing `services/bazzite/` pattern
(`swayidle.service`, `plasma-polkit-agent.service`) keeps lifecycle and wiring
consistent with the rest of the niri session.

## Requirements

1. The Bazzite/niri image installs `udiskie` and `udisks2` explicitly. Both
   packages are already present in the base image (`udisks2` on the host is
   2.11.2); the explicit install makes the dependency visible in `build.sh`.
2. A session-scoped user unit `services/bazzite/udiskie.service` starts udiskie
   with the niri session (`PartOf`/`After`/`Requisite=graphical-session.target`),
   restarts on failure, and stops with the session.
3. `build.sh` wires it with `systemctl --global add-wants niri.service
   udiskie.service`, the same pattern used for mako, swayidle, and the polkit
   agent.
4. The chosen flags are `--automount --no-tray`. Notifications keep the upstream
   default (on; `mako` provides the notification daemon). The password prompt
   keeps the upstream default (`builtin:gui`), which is only invoked to unlock
   LUKS devices, not at daemon start. No `/etc/fstab` entries and no
   device-specific config are added.
5. The Bluefin image does not get the unit or its niri wiring.
6. `verify-container.sh` gains checks for the bazzite branch (package, CLI,
   Python import, unit contents, niri wiring, startup probe) and a negative
   check on the bluefin branch. Bluefin is not assumed to lack the udiskie
   package upstream; only the custom unit and its wiring are asserted absent.

## Technical approach

- `build_files/bazzite/build.sh`: add `udiskie` and `udisks2` to the existing
  niri `dnf5 install`, and add `systemctl --global add-wants niri.service
  udiskie.service`.
- `services/bazzite/udiskie.service`: user unit, `ExecStart=/usr/bin/udiskie
  --automount --no-tray`, `Restart=on-failure`, `TimeoutStopSec=5sec`, lifecycle
  matching `swayidle.service` and `plasma-polkit-agent.service`.
- `build_files/common/verify-container.sh`: bazzite branch checks the packages,
  `/usr/bin/udiskie` executable, `--help` lists `--automount` and `--no-tray`,
  the Python `udiskie` module imports, the unit file's flags, the niri
  `.wants` symlink, and a mock-D-Bus startup probe if feasible. The probe uses
  a private `dbus-daemon` with a fake UDisks2 service on its own socket; it does
  not touch the host system bus, host devices, or real disks.
- `README.md`: a short usage note (udiskie starts with the niri session, mounts
  removable media under `/run/media/$USER/`, unlock prompt is the GUI).

## Files affected

- `spec/2026-11-16-01-udiskie_niri_automount.md` (this PRD, created)
- `build_files/bazzite/build.sh` (modify)
- `services/bazzite/udiskie.service` (create)
- `build_files/common/verify-container.sh` (modify)
- `README.md` (modify, usage note)

## End criteria

1. `build.sh` installs `udiskie` and `udisks2` and adds the niri `.wants` line
   for `udiskie.service`.
2. `services/bazzite/udiskie.service` exists with `--automount --no-tray` and
   the shared graphical-session lifecycle.
3. `bash -n` and `git diff --check` pass; `systemd-analyze verify` (or the
   equivalent check) passes for the new unit.
4. `verify-container.sh bazzite` and `verify-container.sh bluefin` in a fresh
   container exit 0 with the new checks (parent runs the full image build and
   container checks after my edits).
5. Probe evidence: udiskie starts against the mock UDisks2 bus and stays alive
   (or the limitation is recorded in Issues & Resolutions).
6. No commit, push, host service change, host device access, host system-bus
   access, or real disk mount.

## Issues & Resolutions

_(appended as work proceeds)_

- **Issue:** Fedora `udiskie` 2.7.0 (noarch, `python3-udiskie`) ships no
  systemd user unit, so a custom unit is required.
  - **Resolution:** `services/bazzite/udiskie.service` added, modeled on
    `swayidle.service` and `plasma-polkit-agent.service`.
- **Issue:** the upstream defaults for `--automount` and `--notify` are already
  on, and `--tray` is off; the PRD flag set still needed to be confirmed.
  - **Resolution:** confirmed from the installed `cli.py` defaults:
    `automount: True`, `notify: True`, `tray: False`, `password_prompt:
    builtin:gui`. The unit keeps `--automount --no-tray` as the explicit
    contract. `--help` lists both flags.
- **Issue:** a `--help` check does not prove automount works.
  - **Resolution:** added a mock-UDisks2 startup probe (private
    `dbus-daemon` session bus, no host bus, no devices, no real disks). It
    verifies that udiskie connects, calls `GetManagedObjects` and the
    `Manager.Version` property, stays alive for 8 s, and logs no traceback. It
    does not prove real automount. Probe ran locally in a rootless
    `ghcr.io/ublue-os/bazzite:stable` container: `UDISKIE_STARTUP_PROBE_OK`,
    exit 0.
- **Issue:** `systemd-analyze verify` cannot resolve `graphical-session.target`
  in a plain container.
  - **Resolution:** verified with stub `graphical-session.target` plus the
    installed `/usr/bin/udiskie`: exit 0.
- **Issue:** bind-mounting a host file into rootless podman failed with
  `Permission denied`.
  - **Resolution:** pipe the script over stdin instead. No repo change needed.
- **Limitation:** the in-build verifier covers the package, CLI, module import,
  unit contents, niri wiring, and the mock startup. It does not cover real
  device hotplug or a real UDisks2 daemon. Parent preflight shows real
  `udisksd --disable-modules` runs in a rootless container with no device
  objects, so a separate runtime script can use it. That script is optional and
  is not part of the in-build verifier.
- **Limitation:** the bazzite niri `.wants` symlink check and the full
  `verify-container.sh bazzite` / `bluefin` runs need the full image build;
  parent runs them after this delta.
- **Scope note:** the Kingston / CalDigit TS4 detection on `cinta` was not
  re-verified on a live host (no host device access in this task). That
  observation comes from the recovered T3 thread only.

- **Correction (Requirement 1):** the original plan text states that both
  `udiskie` and `udisks2` are already in the base image. That is only partly
  true. `udisks2` is present (host `rpm -q udisks2`: 2.11.2). `udiskie` is not:
  host `rpm -q udiskie` reports not installed. The earlier `dnf5 install
  udiskie udisks2` ran only inside a throwaway test container, not in the
  untouched base image. The explicit `udisks2 udiskie` install in `build.sh`
  is therefore a real addition for `udiskie` and a declared dependency for
  `udisks2`. The original plan text is unchanged above.
- **Mandatory end criteria (user, not optional):** a full local
  `Containerfile.bazzite` build, then a run and mount of the built image in a
  container, plus runtime checks, must all pass. This is a required end
  criterion, not optional. The runtime checks include the real `udisksd`
  daemon smoke planned by the parent, and the bazzite/bluefin
  `verify-container.sh` runs in fresh containers. The full build has not been
  run by this delegate; the parent runs it on the final candidate.
- **Hardening of the embedded startup probe (follow-up):** the probe now uses
  `tempfile.TemporaryDirectory` (no leaked workdir); the `udiskie` child and
  the private `dbus-daemon` are terminated and waited on in `finally`, so a
  setup, bus, or wait exception cannot orphan them; `ok` requires a clean
  udiskie exit code 0 after the SIGTERM; and udiskie is spawned only after
  `on_name_acquired` fires for `org.freedesktop.UDisks2`, removing the
  registration race. The 10 s name-acquisition guard fails closed.
- **Deviation (exit status):** the follow-up asked for `ok` to require exit
  code 0. Measured: udiskie exits -15 (killed by SIGTERM) and exits 1 on
  SIGINT; it installs no SIGTERM handler, so exit 0 is not reachable through
  our SIGTERM. The probe now requires `exit == -SIGTERM`, the status we
  caused. systemd's default `SuccessExitStatus` also treats SIGTERM death as
  a clean stop. A non-SIGTERM status, traceback, or early exit still fails.
- **Fix (timer):** a first run emitted `Source ID ... was not found` because
  the alive-phase timer had already fired. The alive-phase `source_remove` was
  dropped; the name-acquisition timer is still removed on success.
- **Evidence:** extracted embedded probe run in a rootless
  `ghcr.io/ublue-os/bazzite:stable` container with no host bus:
  `UDISKIE_STARTUP_PROBE_OK`, exit 0, `exit=-15`, no leftover `udiskie` or
  `dbus-daemon` processes. The failure paths (name not acquired, socket never
   appears, orphan on exception) were not exercised by a forced-failure run.

## Final Verification Evidence

The parent completed the mandatory build and container checks on 2026-11-16.
Implementation was delegated to Claude Haiku 5.5; the parent reviewed the
changes and independently verified the built image.

### Full local image build

```bash
TMPDIR="$HOME/.cache/udiskie-image-build/tmp" \
  podman build --pull=never \
    --tag localhost/bazzite-vm-rocm-niri:udiskie-candidate \
    --file Containerfile.bazzite \
    --logfile /tmp/opencode/udiskie-image-verification/final-build.log .
```

Exit 0, including the hypervisor verifier, Bazzite verifier, embedded udiskie
startup probe, and bootc lint. The existing cached Bazzite base was used; this
does not claim a registry refresh or a build against a newer base image.

- Image ID: `7a8d38c040f989906feea607187bd324f70b962cd54463f23d1250dd4b78466c`
- Digest: `sha256:d9fc4837e56b42bf19986a05c9be18825683484221f2780032c9d94eebde73eb`
- Size: 15,680,893,025 bytes.
- Installed: `udiskie-2.7.0-1.fc45.noarch`, `udisks2-2.11.2-1.fc45.x86_64`.
- bootc lint: 10 passed, 1 skipped, 4 warnings (nonempty `/boot`, runtime
  `/run`/`/tmp` content, dnf log, and `/var` content/tmpfiles declarations).

### Built-image checks

All checks passed using fresh rootless containers without host devices or
host D-Bus mounts:

- `/usr/bin/verify-container.sh bazzite` passed in the final image, including
  `ASTAL_API_CONTRACT_OK`, `AGS_BUNDLE_RUNTIME_OK`, and
  `UDISKIE_STARTUP_PROBE_OK`. The probe observed one `GetManagedObjects` call,
  one `Manager.Version` read, eight seconds of liveness, and expected SIGTERM
  termination. Evidence: `final-container.log`.
- `SYSTEMD_UNIT_PATH=/usr/lib/systemd/user:/etc/systemd/user systemd-analyze
  verify udiskie.service` passed against the actual installed units, without
  stub targets. `udiskie --version` reports 2.7.0.
- A created container's root filesystem was mounted with `podman unshare`
  and `podman mount`. The udiskie executable, user unit, and niri wants symlink
  were checked directly; the filesystem was then unmounted and that container
  removed. Evidence: `final-rootfs.log`, `UDISKIE_MOUNTED_ROOTFS_OK`.
- A private system D-Bus and real `udisksd --disable-modules` were started in
  the final image. The exact service command plus `--verbose` connected to
  UDisks2 2.11.2, stayed alive for eight seconds, and stopped with SIGTERM.
  Evidence: `final-real-udisks.log`, `UDISKIE_REAL_UDISKS_STARTUP_OK`. The daemon
  logged a harmless missing `/dev/zram0` warning in the isolated container.
- Separate simulated coldplug and hotplug cases exposed a removable FAT
  filesystem over private D-Bus. Both caused the shipped udiskie executable
  to call `org.freedesktop.UDisks2.Filesystem.Mount` for the simulated device.
  A mock notification daemon stood in for mako so the unchanged service flags
  could run without a display. Evidence: `final-coldplug.log` and
  `final-hotplug.log`, both `UDISKIE_AUTOMOUNT_REQUEST_OK`.
- The updated Bluefin branch passed against the existing local
  `localhost/bluefin-hypervisor:latest` image. Bluefin was not rebuilt because
  its image inputs did not change. Evidence: `final-bluefin.log`.
- `bash -n`, ShellCheck (cached `docker.io/koalaman/shellcheck:stable` container),
  and `git diff --check` passed for the changed shell scripts.

Logs and the standalone real-daemon/mock-device test harness are retained in
`/tmp/opencode/udiskie-image-verification/`. Test containers were removed; the
candidate image remains available locally. Nothing was committed, pushed,
published, deployed, or changed on cinta/bix.

### Verification Limits

The real-daemon test had no block devices. The simulated cases prove automount
policy and D-Bus mount requests, not kernel filesystem mounts or physical USB
hotplug. Real niri login/logout, polkit authorization, GUI notifications, and
LUKS prompts still need validation on a booted host. No host disks or host
system bus were exposed to these tests.
