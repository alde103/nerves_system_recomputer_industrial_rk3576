#!/bin/sh
#
# Reproducibly build the committed vendor U-Boot for the reComputer Industrial
# RK3576, in a Docker container, the way Seeed's Armbian image builds it:
# Radxa's next-dev-v2024.10 U-Boot plus Seeed's board defconfig, device tree
# and patches, with Rockchip's DDR init, boost, usbplug and BL31 blobs from
# armbian/rkbin (there is no open-source DRAM init or BL31 for the RK3576).
#
# The vendor U-Boot is used rather than mainline because Seeed carries this
# board's device tree, MAC-from-EEPROM and Maskrom/rockusb fixes there.
#
# Produces, in uboot/:
#   u-boot-rockchip.bin      idbloader (DDR init + boost + SPL, packed by
#                            rkbin's boot_merger) at the start, U-Boot FIT
#                            at 0x7F8000. fwup's `complete` task writes it at
#                            sector 64 on the eMMC, which puts the FIT at
#                            sector 16384 (8 MiB), where the SPL loads it.
#   u-boot.config            The U-Boot .config, kept for review.
#   rk3576_spl_loader_v1.03.102.bin
#                            The Maskrom loader for `rkdeveloptool db`.
#
# The build adds the Nerves environment on top of Seeed's defconfig: env on
# the boot block device (the eMMC) at 0xF00000, 128 KiB, shared with
# fwup/nerves_runtime (see uboot/uboot.env and fwup_include/fwup-common.conf).
#
# Usage:
#   scripts/build-uboot.sh            build and verify
#   scripts/build-uboot.sh --verify   check the committed bootloader files
#
set -e

UBOOT_REPO="https://github.com/radxa/u-boot.git"
UBOOT_COMMIT="39cd993e5d6296635438e84f4576b3a9bf76f86e" # next-dev-v2024.10
SEEED_REPO="https://github.com/Seeed-Studio/armbian-build.git"
SEEED_COMMIT="f6792bab262dbc074ed2c0af81722ea7e7236754"
RKBIN_REPO="https://github.com/armbian/rkbin.git"
RKBIN_COMMIT="30eb694ecb4afa1ca3ec1e4c5e477a81f7004e7e"
# The blob versions Seeed's Armbian image ships (rockchip64_common.inc pins
# DDR v1.08 because v1.09 failed to boot some RK3576 boards).
DDR_BIN="rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin"
BL31_ELF="rk35/rk3576_bl31_v1.20.elf"
BOOST_BIN="rk35/rk3576_boost_v1.02.bin"
USBPLUG_BIN="rk35/rk3576_usbplug_v1.03.bin"
LOADER_BIN="rk35/rk3576_spl_loader_v1.03.102.bin"
UBOOT_DEFCONFIG="recomputer-rk3576-industrial_defconfig"
UBOOT_BOARD="recomputer-rk3576-industrial"

# Pinned by digest for the same reason the sources are pinned by commit: the
# bookworm tag moves, and a toolchain that changes underneath makes the output
# unexplainable.
BUILD_IMAGE="debian:bookworm@sha256:813017f3d62be4b5891a7acca6a01bdcd4b8513daa81b1ab99d3a50385b26931"

SYSTEM_DIR=$(cd "$(dirname "$0")/.." && pwd)
UBOOT_DIR=$SYSTEM_DIR/uboot

# The U-Boot FIT sits at sector 16384 (8 MiB) on the eMMC and the bin is
# written at sector 64, so inside the bin it starts at (16384 - 64) * 512.
FIT_OFFSET=$(((16384 - 64) * 512))

# What fwup, fw_env.config and nerves_runtime rely on. Without these U-Boot
# keeps its environment somewhere else, never sees nerves_fw_active and the
# A/B revert silently stops working.
REQUIRED_CONFIG='CONFIG_ENV_IS_IN_BLK_DEV=y
CONFIG_ENV_OFFSET=0xF00000
CONFIG_ENV_SIZE=0x20000
CONFIG_DEFAULT_DEVICE_TREE="rk3576-recomputer-industrial"
CONFIG_CMD_BOOTI=y
CONFIG_CMD_FAT=y
CONFIG_CMD_FS_GENERIC=y'

fail() {
    echo "FAIL $*" >&2
    exit 1
}

# fit_images BIN: the names of the images in the FIT inside BIN, one per line.
fit_images() {
    python3 -I - "$1" "$FIT_OFFSET" <<'EOF'
import struct, sys

blob = open(sys.argv[1], "rb").read()[int(sys.argv[2]):]
_, _, off_struct = struct.unpack(">III", blob[:12])
path, pos = [], off_struct
while True:
    (token,) = struct.unpack(">I", blob[pos:pos + 4]); pos += 4
    if token == 1:  # FDT_BEGIN_NODE
        name = blob[pos:blob.index(b"\0", pos)].decode(); pos += (len(name) + 4) & ~3
        path.append(name)
        if path[1:-1] == ["images"]:
            print(name)
    elif token == 2:  # FDT_END_NODE
        path.pop()
    elif token == 3:  # FDT_PROP
        (length,) = struct.unpack(">I", blob[pos:pos + 4]); pos += 8 + ((length + 3) & ~3)
    elif token == 9:  # FDT_END
        break
EOF
}

verify() {
    bin=$UBOOT_DIR/u-boot-rockchip.bin
    config=$UBOOT_DIR/u-boot.config
    [ -f "$config" ] || fail "no $config"
    echo "$REQUIRED_CONFIG" | while IFS= read -r line; do
        grep -qxF "$line" "$config" || fail "u-boot.config lacks $line"
    done
    [ "$(head -c 4 "$bin")" = "RKNS" ] || fail "u-boot-rockchip.bin does not start with an RKNS idblock"
    [ "$(od -An -tx1 -j "$FIT_OFFSET" -N4 "$bin" | tr -d ' ')" = "d00dfeed" ] ||
        fail "u-boot-rockchip.bin has no FIT at $(printf 0x%X "$FIT_OFFSET")"
    # The FIT carries BL31 split into atf-N images. make_fit_atf.sh still
    # writes a FIT, configuration and all, when that split fails, and the SPL
    # then has no BL31 to run.
    images=$(fit_images "$bin")
    for image in uboot fdt atf-1; do
        echo "$images" | grep -qx "$image" ||
            fail "u-boot-rockchip.bin's FIT has no $image image (has: $(echo $images))"
    done
    echo "ok bootloader: RKNS idblock, FIT at $(printf 0x%X "$FIT_OFFSET"), env at 0xF00000 on the boot device"
}

if [ "${1:-}" = "--verify" ]; then
    verify
    exit 0
fi

# Everything below runs in the container. In this heredoc host expansion
# still happens, so \$ defers a variable to the container.
docker run --rm -i -v "$UBOOT_DIR":/out "$BUILD_IMAGE" bash -s <<CONTAINER_SCRIPT
set -e
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git make gcc \
    gcc-aarch64-linux-gnu bison flex libssl-dev bc python3 python3-dev \
    python3-setuptools python3-pyelftools swig device-tree-compiler \
    ca-certificates patch >/dev/null
# The vendor tree's decode_bl31.py, which splits BL31 into the FIT's atf-N
# images, asks for python2 but runs fine on python3. Bookworm has no python2.
ln -s /usr/bin/python3 /usr/local/bin/python2

# fetch REPO COMMIT DIR [PATH...]: one commit, and only PATHs of it when
# given. rkbin and armbian-build are large and only a few files are needed.
fetch() {
    repo=\$1 commit=\$2 dir=\$3
    shift 3
    git init -q "\$dir"
    git -C "\$dir" remote add origin "\$repo"
    if [ \$# -gt 0 ]; then
        git -C "\$dir" sparse-checkout set --no-cone "\$@"
    fi
    git -C "\$dir" fetch -q --depth 1 --filter=blob:none origin "\$commit"
    git -C "\$dir" checkout -q FETCH_HEAD
}
fetch $UBOOT_REPO $UBOOT_COMMIT /u-boot
fetch $SEEED_REPO $SEEED_COMMIT /seeed /patch/u-boot/legacy/
fetch $RKBIN_REPO $RKBIN_COMMIT /rkbin '/rk35/rk3576_*' /rk35/RK3576MINIALL.ini /tools/boot_merger

# Seeed's board files and patches, applied the way Armbian does: the defconfig
# and dt overlay directories copied in, then every patch from both patch
# directories and the board's own, in file-name order. A patch whose context
# has drifted (rk3566-Add-rk3566-to-soc-name, which predates the rk3576 line)
# gets patch's fuzz, as Armbian's patcher allows.
LEGACY=/seeed/patch/u-boot/legacy
cp \$LEGACY/u-boot-radxa-rk35xx/defconfig/* /u-boot/configs/
cp \$LEGACY/u-boot-radxa-rk35xx/dt/* /u-boot/arch/arm/dts/
for p in \$(ls \$LEGACY/u-boot-radxa-rk35xx/*.patch \
             \$LEGACY/u-boot-radxa-rk35xx-v2024.10/*.patch \
             \$LEGACY/u-boot-radxa-rk35xx/board_$UBOOT_BOARD/*.patch |
         awk -F/ '{ print \$NF "\t" \$0 }' | sort | cut -f2); do
    echo "applying \${p#\$LEGACY/}"
    git -C /u-boot apply --whitespace=nowarn "\$p" ||
        patch -d /u-boot -p1 -F3 -N --no-backup-if-mismatch -i "\$p"
done

cd /u-boot
make $UBOOT_DEFCONFIG
# Nerves environment: on the boot block device (rockchip_get_bootdev, the
# eMMC) at 15 MiB, shared with fwup/nerves_runtime/fw_env.config. booti,
# FAT and the generic load command are what nerves_boot in uboot.env uses.
cat >> .config <<'EOF'
CONFIG_ENV_IS_IN_BLK_DEV=y
CONFIG_ENV_OFFSET=0xF00000
CONFIG_ENV_SIZE=0x20000
CONFIG_CMD_BOOTI=y
CONFIG_CMD_FAT=y
CONFIG_CMD_FS_GENERIC=y
EOF
make olddefconfig

cp /rkbin/$BL31_ELF bl31.elf
make -j\$(nproc) CROSS_COMPILE=aarch64-linux-gnu- BL31=/rkbin/$BL31_ELF \
    spl/u-boot-spl.bin u-boot.dtb u-boot.itb

# idbloader: DDR init, boost and SPL packed with rkbin's boot_merger, with the
# same substitutions Armbian's rockchip64_common.inc makes for rk3576.
cp /rkbin/rk35/RK3576MINIALL.ini rk3576.ini
sed -i -e "s|FlashBoost=.*\$|FlashBoost=/rkbin/$BOOST_BIN|" \
    -e "s|Path1=.*rk3576_ddr.*\$|Path1=/rkbin/$DDR_BIN|" \
    -e "s|Path1=.*rk3576_usbplug.*\$|Path1=/rkbin/$USBPLUG_BIN|" \
    -e "s|FlashData=.*\$|FlashData=/rkbin/$DDR_BIN|" \
    -e "s|FlashBoot=.*\$|FlashBoot=spl/u-boot-spl.bin|" \
    -e "s|IDB_PATH=.*\$|IDB_PATH=idbloader.img|" rk3576.ini
/rkbin/tools/boot_merger rk3576.ini

# One file for fwup: the idbloader zero-padded up to the FIT's offset.
dd if=/dev/zero of=u-boot-rockchip.bin bs=1 count=0 seek=$FIT_OFFSET 2>/dev/null
dd if=idbloader.img of=u-boot-rockchip.bin conv=notrunc 2>/dev/null
cat u-boot.itb >> u-boot-rockchip.bin

cp u-boot-rockchip.bin /out/u-boot-rockchip.bin
cp .config /out/u-boot.config
cp /rkbin/$LOADER_BIN /out/
chown \$(stat -c %u:%g /out) /out/u-boot-rockchip.bin /out/u-boot.config /out/\$(basename $LOADER_BIN)
CONTAINER_SCRIPT

verify
