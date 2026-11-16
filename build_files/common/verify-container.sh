#!/bin/bash

set -euo pipefail

flavor="${1:-}"
case "$flavor" in
    bazzite|bluefin) ;;
    *)
        printf 'usage: %s bazzite|bluefin\n' "$0" >&2
        exit 2
        ;;
esac

packages=(
    qemu libvirt libvirt-client libvirt-daemon-kvm
    libvirt-daemon-config-network qemu-kvm virt-manager edk2-ovmf
    atop guestfs-tools jq rsync wireguard-tools
)
for package in "${packages[@]}"; do
    rpm -q "$package" >/dev/null
done
for executable in virsh qemu-img qemu-system-x86_64 virt-customize atop jq rsync wg wg-quick; do
    test -x "/usr/bin/$executable"
done
test -f /usr/lib/systemd/system/libvirtd.service
test -f /usr/lib/sysusers.d/qemu.conf
grep -Eq '^u qemu 107([[:space:]]|$)' /usr/lib/sysusers.d/qemu.conf
grep -Eq '^g qemu 107([[:space:]]|$)' /usr/lib/sysusers.d/qemu.conf

case "$flavor" in
    bazzite)
        for package in rocm-opencl rocm-hip rocm-clinfo rocm-smi niri hyprlock brscan5 udiskie udisks2; do
            rpm -q "$package" >/dev/null
        done
        rpm -q gjs gtk4-layer-shell >/dev/null
        # udiskie: automounter CLI, its Python module, and the custom user unit
        # wired to niri. The CLI must advertise the flags the unit depends on.
        test -x /usr/bin/udiskie
        /usr/bin/udiskie --version >/dev/null
        /usr/bin/udiskie --help | grep -Fq -- '--automount'
        /usr/bin/udiskie --help | grep -Fq -- '--no-tray'
        python3 -c 'import udiskie.udisks2, udiskie.automount' >/dev/null
        test -f /usr/lib/systemd/user/udiskie.service
        grep -Fxq 'ExecStart=/usr/bin/udiskie --automount --no-tray' \
            /usr/lib/systemd/user/udiskie.service
        grep -Fxq 'PartOf=graphical-session.target' /usr/lib/systemd/user/udiskie.service
        grep -Fxq 'Requisite=graphical-session.target' /usr/lib/systemd/user/udiskie.service
        test -L /etc/systemd/user/niri.service.wants/udiskie.service
        test "$(readlink -f /etc/systemd/user/niri.service.wants/udiskie.service)" = \
            "/usr/lib/systemd/user/udiskie.service"
        test -L /usr/lib64/libgtk4-layer-shell.so
        test -e /usr/lib64/libgtk4-layer-shell.so.0
        test "$(readlink -f /usr/lib64/libgtk4-layer-shell.so)" = \
            "$(readlink -f /usr/lib64/libgtk4-layer-shell.so.0)"
        test -x /usr/bin/ags
        test -d /usr/share/ags/js/lib
        test -f /usr/share/ags/js/lib/index.ts
        test -f /usr/share/ags/js/node_modules/gnim/dist/gnim.gresource
        # Astal removed its deprecated lang/gjs tree; the image must not ship it.
        test ! -e /usr/share/astal/gjs
        for soname in \
            libastal-4.so.4 libastal-io.so.0 libastal-wireplumber.so.0 \
            libastal-network.so.0 libastal-battery.so.0 libastal-mpris.so.0 \
            libastal-bluetooth.so.0 libastal-apps.so.0 libastal-power-profiles.so.0 \
            libastal-notifd.so.0 libastal-brightness.so.0; do
            test -e "/usr/lib64/${soname}"
            test -L "/usr/lib64/${soname}"
            test -L "/usr/lib64/${soname%.*}"
        done
        for typelib in \
            Astal-4.0 AstalIO-0.1 AstalWp-0.1 AstalNetwork-0.1 \
            AstalBattery-0.1 AstalMpris-0.1 AstalBluetooth-0.1 \
            AstalApps-0.1 AstalPowerProfiles-0.1 AstalNotifd-0.1 AstalBrightness-0.1; do
            test -f "/usr/lib64/girepository-1.0/${typelib}.typelib"
        done
        # Query GObject metadata for the API contract the bar relies on. This
        # probe imports typelibs only; it never constructs a service or opens
        # a display, session bus, system bus, or device.
        smoke_dir="$(mktemp -d)"
        trap 'rm -rf -- "$smoke_dir"' EXIT
        cat > "$smoke_dir/astal-api-contract.js" <<'EOF'
const { Gio, GObject } = imports.gi;

imports.gi.versions.AstalWp = "0.1";
imports.gi.versions.AstalNetwork = "0.1";

const AstalWp = imports.gi.AstalWp;
const AstalNetwork = imports.gi.AstalNetwork;

const READABLE = GObject.ParamFlags.READABLE;
const WRITABLE = GObject.ParamFlags.WRITABLE;

function typeName(cls) {
    return GObject.type_name(cls.$gtype);
}

function expectReadable(cls, name) {
    const label = `${typeName(cls)}.${name}`;
    const spec = cls.find_property(name);
    if (!spec) throw new Error(`${label} is missing`);
    if (!(spec.flags & READABLE)) throw new Error(`${label} is not readable`);
    return spec;
}

function expectProperty(cls, name, valueType, writable) {
    const label = `${typeName(cls)}.${name}`;
    const spec = expectReadable(cls, name);
    const actualType = GObject.type_name(spec.value_type);
    if (actualType !== valueType) {
        throw new Error(`${label} has type ${actualType}, expected ${valueType}`);
    }
    if (!!(spec.flags & WRITABLE) !== writable) {
        throw new Error(`${label} writable=${!!(spec.flags & WRITABLE)}, expected ${writable}`);
    }
}

function expectMethod(cls, name) {
    if (typeof cls.prototype[name] !== "function") {
        throw new Error(`${typeName(cls)}.${name}() is missing`);
    }
}

// Audio defaults are read-only on every supported Astal revision; selecting a
// default goes through the shared Endpoint setter.
expectProperty(AstalWp.Audio, "default-speaker", "AstalWpEndpoint", false);
expectProperty(AstalWp.Audio, "default-microphone", "AstalWpEndpoint", false);
expectProperty(AstalWp.Endpoint, "is-default", "gboolean", true);
expectMethod(AstalWp.Endpoint, "set_is_default");
expectMethod(AstalWp.Endpoint, "get_is_default");

// The wifi/wired proxies are always present and read-only; hardware absence is
// reported by a null device property instead of a null proxy object.
expectProperty(AstalNetwork.Network, "wifi", "AstalNetworkWifi", false);
expectProperty(AstalNetwork.Network, "wired", "AstalNetworkWired", false);
expectProperty(AstalNetwork.Wifi, "device", "NMDeviceWifi", false);
expectProperty(AstalNetwork.Wired, "device", "NMDeviceEthernet", false);
expectProperty(AstalNetwork.AccessPoint, "bssid", "gchararray", false);
expectProperty(AstalNetwork.AccessPoint, "active", "gboolean", false);
expectReadable(AstalNetwork.AccessPoint, "connections");

if (!Gio.SettingsSchemaSource.get_default()?.lookup("io.astal.notifd", true)) {
    throw new Error("compiled io.astal.notifd schema is missing");
}

console.log("ASTAL_API_CONTRACT_OK");
EOF
        env -u GI_TYPELIB_PATH -u LD_LIBRARY_PATH /usr/bin/gjs \
            "$smoke_dir/astal-api-contract.js"

        # Exercise the system loader without its cache before rebuilding it.
        rm -f /etc/ld.so.cache
        env -u GI_TYPELIB_PATH -u LD_LIBRARY_PATH /usr/bin/gjs -c '
            ["Astal", "AstalIO", "AstalWp", "AstalNetwork", "AstalBattery",
             "AstalMpris", "AstalBluetooth", "AstalApps", "AstalPowerProfiles",
             "AstalNotifd", "AstalBrightness", "Gtk"].forEach(name => imports.gi[name]);
        '

        # Exercise AGS bundling and GJS imports with a cold loader cache.
        cat > "$smoke_dir/ags-runtime.ts" <<'EOF'
import * as ags from "ags";
import * as gtk4 from "ags/gtk4";
import * as jsxRuntime from "ags/gtk4/jsx-runtime";
import AstalIO from "gi://AstalIO?version=0.1";
import AstalMpris from "gi://AstalMpris?version=0.1";

const agsExports = Object.keys(ags).length;
const gtk4Exports = Object.keys(gtk4);
const jsxExports = Object.keys(jsxRuntime);

if (!agsExports || !AstalIO || !AstalMpris) {
    throw new Error(`AGS or Astal modules unavailable (exports=${agsExports})`);
}
for (const name of ["Astal", "Gtk", "Gdk"]) {
    if (!gtk4[name]) {
        throw new Error(`ags/gtk4 export ${name} is missing`);
    }
}
if (!jsxExports.length) {
    throw new Error("ags/gtk4/jsx-runtime exports are missing");
}
console.log(
    `AGS_BUNDLE_RUNTIME_OK exports=${agsExports} gtk4=${gtk4Exports.join(",")} jsx=${jsxExports.length}`,
);
EOF

        smoke_status=0
        env -u GI_TYPELIB_PATH -u LD_LIBRARY_PATH -u GI_GIR_PATH -u PKG_CONFIG_PATH \
            timeout 30 /usr/bin/ags run "$smoke_dir/ags-runtime.ts" --gtk 4 \
            >"$smoke_dir/output.log" 2>&1 || smoke_status=$?
        if [[ "$smoke_status" -ne 0 ]]; then
            cat "$smoke_dir/output.log" >&2
            printf 'AGS runtime smoke failed with status %s\n' "$smoke_status" >&2
            exit "$smoke_status"
        fi
        if grep -Eiq 'ld\.so:|cannot be preloaded|error while loading shared libraries|undefined symbol' \
            "$smoke_dir/output.log"; then
            cat "$smoke_dir/output.log" >&2
            printf 'AGS runtime smoke emitted a dynamic-loader warning\n' >&2
            exit 1
        fi
        if ! grep -Fq 'AGS_BUNDLE_RUNTIME_OK' "$smoke_dir/output.log"; then
            cat "$smoke_dir/output.log" >&2
            printf 'AGS runtime smoke sentinel missing\n' >&2
            exit 1
        fi
        cat "$smoke_dir/output.log"

        ldconfig
        /usr/bin/ags --help >/dev/null
        for library in /usr/lib64/libastal-*.so.*; do
            if ldd "$library" | grep -q 'not found'; then
                printf 'unresolved runtime dependency in %s\n' "$library" >&2
                ldd "$library" >&2
                exit 1
            fi
        done
        test -d /opt/brother/scanner/brscan5
        test -f /usr/lib/systemd/user/ags.service
        test -f /usr/lib/systemd/user/swayidle.service

        # Start the shipped udiskie against a private dbus-daemon hosting a fake
        # UDisks2 (no host bus, devices, or disks). Proves connect, startup
        # calls, liveness, and clean exit; it does not prove real automount.
        cat > "$smoke_dir/udiskie-startup-probe.py" <<'EOF'
import os
import signal
import subprocess
import sys
import tempfile

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.freedesktop.UDisks2"
MANAGER_PATH = "/org/freedesktop/UDisks2/Manager"
ROOT_PATH = "/org/freedesktop/UDisks2"
ALIVE_SECONDS = 8
MANAGER_VERSION = "2.11.2"

XML = """
<node>
  <interface name="org.freedesktop.DBus.ObjectManager">
    <method name="GetManagedObjects">
      <arg type="a{oa{sa{sv}}}" name="objects" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.UDisks2.Manager">
    <property name="Version" type="s" access="read"/>
  </interface>
</node>
"""

counts = {"GetManagedObjects": 0, "Version": 0}


def on_method(conn, sender, path, iface, method, params, invocation):
    if method == "GetManagedObjects":
        counts["GetManagedObjects"] += 1
        invocation.return_value(GLib.Variant("(a{oa{sa{sv}}})", ({},)))
    else:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def on_get_property(conn, sender, path, iface, name):
    if iface == "org.freedesktop.UDisks2.Manager" and name == "Version":
        counts["Version"] += 1
        return GLib.Variant("s", MANAGER_VERSION)
    return None


def main():
    with tempfile.TemporaryDirectory(prefix="udiskie-probe-") as workdir:
        sock = os.path.join(workdir, "bus")
        env = dict(os.environ)
        env["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=" + sock
        env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + sock
        env["XDG_RUNTIME_DIR"] = workdir
        env["HOME"] = workdir
        env.pop("DISPLAY", None)
        env.pop("WAYLAND_DISPLAY", None)

        bus_proc = None
        udiskie = None
        try:
            bus_proc = subprocess.Popen(
                ["dbus-daemon", "--session", "--nofork", "--address=unix:path=" + sock],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            for _ in range(100):
                if os.path.exists(sock):
                    break
                GLib.usleep(20000)
            else:
                raise RuntimeError("private dbus-daemon socket never appeared")

            os.environ.update(env)
            conn = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            node = Gio.DBusNodeInfo.new_for_xml(XML)
            om = node.lookup_interface("org.freedesktop.DBus.ObjectManager")
            mg = node.lookup_interface("org.freedesktop.UDisks2.Manager")
            conn.register_object(ROOT_PATH, om, on_method, None, None)
            conn.register_object(MANAGER_PATH, mg, on_method, on_get_property, None)

            # Spawn udiskie only after the fake owns the name, so its startup
            # calls cannot race registration.
            name_loop = GLib.MainLoop()
            acquired = []

            def on_name_acquired(_conn, name, _data=None):
                acquired.append(name)
                name_loop.quit()

            timeout = GLib.timeout_add_seconds(10, name_loop.quit)
            Gio.bus_own_name_on_connection(
                conn, BUS_NAME, Gio.BusNameOwnerFlags.NONE, on_name_acquired, None)
            name_loop.run()
            GLib.source_remove(timeout)
            if acquired != [BUS_NAME]:
                raise RuntimeError("fake UDisks2 name was not acquired")

            log_path = os.path.join(workdir, "udiskie.log")
            with open(log_path, "w") as log:
                udiskie = subprocess.Popen(
                    ["/usr/bin/udiskie", "--automount", "--no-tray"],
                    env=env, stdout=log, stderr=subprocess.STDOUT,
                )
                alive_loop = GLib.MainLoop()
                GLib.timeout_add_seconds(ALIVE_SECONDS, alive_loop.quit)
                alive_loop.run()
                alive = udiskie.poll() is None
                if alive:
                    udiskie.send_signal(signal.SIGTERM)
                exit_code = udiskie.wait(timeout=10)

            with open(log_path) as log:
                output = log.read()
            print(output)
            # udiskie has no SIGTERM handler, so a clean stop is death by SIGTERM
            # (-15), which systemd also treats as success by default.
            ok = (alive and exit_code == -signal.SIGTERM
                  and counts["GetManagedObjects"] >= 1 and counts["Version"] >= 1
                  and "Traceback" not in output)
            print("counts=%r alive=%r exit=%r" % (counts, alive, exit_code))
            if ok:
                print("UDISKIE_STARTUP_PROBE_OK")
                return 0
            print("UDISKIE_STARTUP_PROBE_FAILED", file=sys.stderr)
            return 1
        finally:
            if udiskie is not None and udiskie.poll() is None:
                udiskie.kill()
                udiskie.wait(timeout=10)
            if bus_proc is not None and bus_proc.poll() is None:
                bus_proc.terminate()
                bus_proc.wait(timeout=10)


if __name__ == "__main__":
    sys.exit(main())
EOF
        probe_output="$smoke_dir/udiskie-probe.log"
        python3 "$smoke_dir/udiskie-startup-probe.py" >"$probe_output" 2>&1 || {
            cat "$probe_output" >&2
            printf 'udiskie startup probe failed\n' >&2
            exit 1
        }
        cat "$probe_output"
        grep -Fq 'UDISKIE_STARTUP_PROBE_OK' "$probe_output"
        ;;
    bluefin)
        grep -Eq '^ID="?bluefin"?([[:space:]]|$)' /etc/os-release
        for package in rocm-opencl rocm-hip rocm-clinfo rocm-smi niri hyprlock brscan5; do
            if rpm -q "$package" >/dev/null 2>&1; then
                printf 'unexpected Bazzite package in Bluefin image: %s\n' "$package" >&2
                exit 1
            fi
        done
        test ! -e /usr/lib/systemd/user/ags.service
        test ! -e /usr/lib/systemd/user/plasma-polkit-agent.service
        test ! -e /usr/lib/systemd/user/swayidle.service
        test ! -e /opt/brother/scanner/brscan5
        # Only the custom unit and its niri wiring are asserted absent; the
        # upstream udiskie package is not assumed to be missing from Bluefin.
        test ! -e /usr/lib/systemd/user/udiskie.service
        test ! -e /etc/systemd/user/niri.service.wants/udiskie.service
        ;;
esac
