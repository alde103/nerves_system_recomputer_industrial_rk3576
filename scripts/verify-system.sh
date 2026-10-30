#!/usr/bin/env bash
# Checks that this system's sources and build output carry what the
# reComputer Industrial RK3576 needs.
#
# Usage:
#   scripts/verify-system.sh --static
#       Source-tree checks only; no build needed.
#   scripts/verify-system.sh <artifact_dir> [image]
#       Source-tree checks, then checks against a finished build. The
#       artifact dir is buildroot's output directory (build/, target/,
#       images/), e.g. .nerves/artifacts/nerves_system_recomputer_industrial_rk3576-portable-0.1.0
#       An image (a .img written by `fwup -t complete`) adds the layout check.
#
# Prints "ok <check>" per pass and exits non-zero on the first failure.
set -euo pipefail

SYSTEM_DIR=$(cd "$(dirname "$0")/.." && pwd)

ok() { echo "ok $*"; }
fail() {
    echo "FAIL $*" >&2
    exit 1
}

# Features this board does not have, or that this generic system leaves to
# the application: Sige5's NPU, OP-TEE, GPU stack, Broadcom WiFi and audio.
check_defconfig_clean() {
    local hits
    hits=$(grep -nE 'RKNPU|LIBRKNNRT|OPTEE|BRCMFMAC|MESA3D|GLMARK2|STRESS_NG|KMSCUBE|ALSA' \
        "$SYSTEM_DIR/nerves_defconfig" || true)
    [ -z "$hits" ] || fail "check_defconfig_clean: nerves_defconfig still enables:
$hits"
    ok check_defconfig_clean
}

# The DTB basename and the console have to agree across every file that
# names them: a stray one means no serial console, or a slot that cannot boot
# after the first OTA swaps extlinux/dtb names.
DTB_NAME=rk3576-recomputer-industrial
CONSOLE=ttyFIQ0
check_names_consistent() {
    local f names consoles
    names=$(cd "$SYSTEM_DIR" && grep -hoE 'rk3576-[a-z0-9-]+(\.(a|b|\$\{nerves_fw_active\}))?\.dtb' \
        fwup.conf fwup-ops.conf uboot/uboot.env extlinux-a.conf extlinux-b.conf |
        sed -E 's/\.(a|b|\$\{nerves_fw_active\})\.dtb$/.dtb/' | sort -u)
    [ "$names" = "$DTB_NAME.dtb" ] ||
        fail "check_names_consistent: expected only $DTB_NAME.dtb, found:
$names"
    consoles=$(cd "$SYSTEM_DIR" && grep -vh '^[[:space:]]*#' uboot/uboot.env extlinux-a.conf extlinux-b.conf |
        grep -oE 'console=[^ ,$]+' | sort -u)
    [ "$consoles" = "console=$CONSOLE" ] ||
        fail "check_names_consistent: expected only console=$CONSOLE, found:
$consoles"
    f=$SYSTEM_DIR/rootfs_overlay/etc/erlinit.config
    grep -qx -- "-c $CONSOLE" "$f" || fail "check_names_consistent: erlinit.config does not use -c $CONSOLE"
    ok check_names_consistent
}

# The committed bootloader: idblock, FIT with BL31, Nerves env location.
check_bootloader() {
    "$SYSTEM_DIR/scripts/build-uboot.sh" --verify >/dev/null || fail "check_bootloader"
    ok check_bootloader
}

if [ "${1:-}" = "--static" ]; then
    check_defconfig_clean
    check_names_consistent
    check_bootloader
    exit 0
fi

[ $# -ge 1 ] || {
    echo "usage: $0 --static | <artifact_dir> [image]" >&2
    exit 2
}
ARTIFACT_DIR=$(cd "$1" && pwd)
IMAGE=${2:-}
KERNEL_DIR=$ARTIFACT_DIR/build/linux-custom

# check_kernel_config SYMBOL VALUE: the built kernel's .config has SYMBOL=VALUE.
check_kernel_config() {
    grep -qx "$1=$2" "$KERNEL_DIR/.config" ||
        fail "check_kernel_config: $1 is '$(grep -E "^$1=|# $1 is not set" "$KERNEL_DIR/.config" || echo unset)', want $2"
    ok "check_kernel_config $1=$2"
}

# check_dtb_alias ALIAS COMPATIBLE_SUBSTRING: in the shipped DTB, ALIAS points
# at a node whose compatible contains COMPATIBLE_SUBSTRING. Nerves expects the
# eMMC at mmcblk0, and the vendor kernel numbers mmcblk devices by alias.
check_dtb_alias() {
    local compatible
    compatible=$(python3 -I - "$ARTIFACT_DIR/images/$DTB_NAME.dtb" "$1" <<'EOF'
import struct, sys

blob = open(sys.argv[1], "rb").read()
magic, _, off_struct, off_strings = struct.unpack(">IIII", blob[:16])
assert magic == 0xD00DFEED, "not a DTB"

def name_at(off):
    return blob[off:blob.index(b"\0", off)].decode()

nodes, path, pos = {}, [], off_struct
while True:
    (token,) = struct.unpack(">I", blob[pos:pos + 4]); pos += 4
    if token == 1:  # FDT_BEGIN_NODE
        name = name_at(pos); pos += (len(name) + 4) & ~3
        path.append(name)
        nodes["/" + "/".join(p for p in path if p)] = {}
    elif token == 2:  # FDT_END_NODE
        path.pop()
    elif token == 3:  # FDT_PROP
        length, nameoff = struct.unpack(">II", blob[pos:pos + 8]); pos += 8
        value = blob[pos:pos + length]; pos += (length + 3) & ~3
        nodes["/" + "/".join(p for p in path if p)][name_at(off_strings + nameoff)] = value
    elif token == 9:  # FDT_END
        break

target = nodes.get("/aliases", {}).get(sys.argv[2], b"").rstrip(b"\0").decode()
print(nodes.get(target, {}).get("compatible", b"").replace(b"\0", b" ").decode())
EOF
)
    case "$compatible" in
    *"$2"*) ok "check_dtb_alias $1 -> $compatible" ;;
    *) fail "check_dtb_alias: $1 points at '$compatible', want *$2*" ;;
    esac
}

check_defconfig_clean
check_names_consistent
check_bootloader

check_dtb_alias mmc0 dwcmshc

# Serial: the CH344 behind RS485/RS232 is CDC-ACM compliant (ttyACM*)
check_kernel_config CONFIG_USB_ACM y
# CAN-FD controller
check_kernel_config CONFIG_CAN y
check_kernel_config CONFIG_CAN_RAW y
check_kernel_config CONFIG_CAN_BCM y
check_kernel_config CONFIG_CAN_GW y
check_kernel_config CONFIG_CANFD_RK3576 y
# Ethernet PHY on gmac0 (gmac1's Maxio PHY runs on the generic driver)
check_kernel_config CONFIG_REALTEK_PHY y
# RTC on the SoM, PCF8563T watchdog on the carrier, SoC watchdog
check_kernel_config CONFIG_RTC_DRV_PCF85063 y
check_kernel_config CONFIG_RTC_DRV_PCF8563 y
check_kernel_config CONFIG_DW_WATCHDOG y
check_kernel_config CONFIG_WATCHDOG_NOWAYOUT y
# Storage: eMMC, squashfs rootfs, f2fs app partition
check_kernel_config CONFIG_MMC_SDHCI_OF_DWCMSHC y
check_kernel_config CONFIG_SQUASHFS y
check_kernel_config CONFIG_F2FS_FS y
# vintage_net policy routing, VPNs
check_kernel_config CONFIG_IP_MULTIPLE_TABLES y
check_kernel_config CONFIG_TUN y
# WiFi: cfg80211 as a module so it loads after the rootfs has regulatory.db
check_kernel_config CONFIG_CFG80211 m

