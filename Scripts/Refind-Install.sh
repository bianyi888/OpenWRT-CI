#!/bin/bash
# Download one verified build for the firmware; install Arthur's runtime UI.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WRT_DIR=${1:?OpenWrt source directory required}
WRT_DIR=$(cd "$WRT_DIR" && pwd)
if grep -q '^CONFIG_aarch64=y' "$WRT_DIR/.config"; then
    ARCH=arm64
elif grep -q '^CONFIG_x86_64=y' "$WRT_DIR/.config"; then
    ARCH=amd64
else
    echo 'Unsupported reF1nd target architecture; refusing to guess.' >&2
    exit 1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sh "$ROOT/Scripts/refind/root/usr/libexec/momo-refind-download" "${REFIND_VERSION:-latest}" "$ARCH" "$TMP"
# Cross-built executable: inspect its ELF header instead of executing on the runner.
readelf -h "$TMP/sing-box" > "$TMP/elf-header"
case "$ARCH" in
    arm64) grep -q 'Machine:.*AArch64' "$TMP/elf-header";;
    amd64) grep -q 'Machine:.*Advanced Micro Devices X86-64' "$TMP/elf-header";;
esac
readelf -l "$TMP/sing-box" > "$TMP/elf-program"
if grep -q 'Requesting program interpreter' "$TMP/elf-program"; then
    grep -q 'Requesting program interpreter: /lib/ld-musl-' "$TMP/elf-program"
fi
if [ "${WRT_CONFIG:-}" = IPQ60XX-WIFI-NO ]; then
    mkdir -p "$WRT_DIR/files"
    cp -a "$ROOT/Scripts/refind/root/." "$WRT_DIR/files/"
    chmod 755 "$WRT_DIR/files/usr/libexec/momo-refind" \
        "$WRT_DIR/files/usr/libexec/momo-refind-download" \
        "$WRT_DIR/files/usr/libexec/rpcd/momo.refind"
fi
install -Dm755 "$TMP/sing-box" "$WRT_DIR/files/usr/bin/sing-box"
install -Dm600 "$TMP/release-meta.json" "$WRT_DIR/files/etc/momo/refind-core/current.json"
echo 'Preinstalled verified reF1nd core:'
cat "$TMP/release-meta.json"
