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
        for package in rocm-opencl rocm-hip rocm-clinfo rocm-smi niri hyprlock brscan5; do
            rpm -q "$package" >/dev/null
        done
        rpm -q gjs gtk4-layer-shell >/dev/null
        test -L /usr/lib64/libgtk4-layer-shell.so
        test -e /usr/lib64/libgtk4-layer-shell.so.0
        test "$(readlink -f /usr/lib64/libgtk4-layer-shell.so)" = \
            "$(readlink -f /usr/lib64/libgtk4-layer-shell.so.0)"
        test -x /usr/bin/ags
        test -d /usr/share/ags/js/lib
        test -f /usr/share/ags/js/lib/index.ts
        test -f /usr/share/ags/js/node_modules/gnim/dist/gnim.gresource
        test -f /usr/share/astal/gjs/index.ts
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
        # Exercise the system loader without its cache before rebuilding it.
        rm -f /etc/ld.so.cache
        env -u GI_TYPELIB_PATH -u LD_LIBRARY_PATH /usr/bin/gjs -c '
            ["Astal", "AstalIO", "AstalWp", "AstalNetwork", "AstalBattery",
             "AstalMpris", "AstalBluetooth", "AstalApps", "AstalPowerProfiles",
             "AstalNotifd", "AstalBrightness", "Gtk"].forEach(name => imports.gi[name]);
        '

        # Exercise AGS bundling and GJS imports with a cold loader cache.
        smoke_dir="$(mktemp -d)"
        trap 'rm -rf -- "$smoke_dir"' EXIT
        cat > "$smoke_dir/ags-runtime.ts" <<'EOF'
import * as ags from "ags";
import AstalIO from "gi://AstalIO?version=0.1";
import AstalMpris from "gi://AstalMpris?version=0.1";

const exports = Object.keys(ags).length;
if (!exports || !AstalIO || !AstalMpris) {
    throw new Error(`AGS or Astal modules unavailable (exports=${exports})`);
}
console.log(`AGS_BUNDLE_RUNTIME_OK exports=${exports}`);
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
        ;;
esac
