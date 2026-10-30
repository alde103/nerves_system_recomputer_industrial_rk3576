# U-Boot boot chain

The RK3576 boot ROM loads U-Boot straight from the eMMC (or over USB in
Maskrom mode). U-Boot therefore ships inside the fwup image and lands on the
eMMC with everything else:

| Blob                  | Location                  | Contents                                    |
| --------------------- | ------------------------- | ------------------------------------------- |
| `u-boot-rockchip.bin` | eMMC, sector 64           | idblock (DDR init + boost + SPL) + FIT (U-Boot proper + BL31) at 8 MB |
| `uboot-env.bin`       | eMMC, 15 MB (0xF00000)    | Nerves environment (built from `uboot.env`) |

The committed `u-boot-rockchip.bin` is the same vendor U-Boot Seeed's Armbian
image ships: Radxa's `next-dev-v2024.10` tree with Seeed's
`recomputer-rk3576-industrial_defconfig`, device tree and patches, plus the
Rockchip rkbin blobs (DDR init v1.08, boost v1.02, BL31 v1.20 — there is no
open-source DRAM init or BL31 for this SoC). On top of Seeed's defconfig the
build adds the Nerves environment: `CONFIG_ENV_IS_IN_BLK_DEV=y`,
`CONFIG_ENV_OFFSET=0xF00000`, `CONFIG_ENV_SIZE=0x20000`. The block device is
the one the boot ROM booted from, which is the eMMC. `u-boot.config` is the
resulting U-Boot configuration, committed so it can be reviewed.

Rebuild it with `scripts/build-uboot.sh` (Docker); `scripts/build-uboot.sh
--verify` checks the committed files. Its inputs are pinned - U-Boot, Seeed's
armbian-build and armbian/rkbin by commit, and the container by image digest -
but the build is not reproducible: the container installs Debian packages from
moving repositories and no build epoch is fixed. Pinned inputs make the output
explainable, not byte-identical.

Licensing of the committed binaries: U-Boot itself is GPL-2.0-or-later
(corresponding source: the pinned commit of https://github.com/radxa/u-boot
plus the patches and script named above). The DDR-init, boost and BL31
components inside `u-boot-rockchip.bin` and all of
`rk3576_spl_loader_v1.03.102.bin` are Rockchip proprietary blobs from
[armbian/rkbin](https://github.com/armbian/rkbin), redistributable per
`LICENSES/LICENSE.rockchip-rkbin`.

## Boot and automatic revert

U-Boot runs the `nerves_init`/`nerves_boot` scripts from the environment
block and boots the active slot's `Image.<slot>` + dtb directly
(`root=PARTUUID=<slot GUID>`). Automatic revert follows the standard
Nerves model:

- U-Boot: with `nerves_fw_autovalidate=0`, new firmware boots once
  (`booted` 0→1) leaving `nerves_fw_validated=0`. If the next boot still
  sees `validated=0`, U-Boot boots the other slot.
- Application: calls `Nerves.Runtime.validate_firmware()` once healthy
  (sets `validated=1`), or the update reverts.

If `nerves_boot` ever fails, `bootcmd` falls through to `sysboot`, which boots
`extlinux/extlinux.conf` from the FAT partition. A missing or corrupt
environment block makes U-Boot fall back to its compiled-in default
environment, whose `distro_bootcmd` finds the same extlinux config.

## uboot.env — the shared firmware/boot environment

`uboot.env` is compiled into `uboot-env.bin` and written raw at 15 MB
(`UBOOT_ENV_OFFSET`, see `fwup_include/fwup-common.conf` and
`rootfs_overlay/etc/fw_env.config`). It is a single fw_env block shared by
three parties: U-Boot reads it to pick the boot slot, `nerves_runtime`/
`fwup` read and write the `nerves_fw_*` firmware metadata, and `boardid`
reads the serial number.

## Flashing

See [docs/flashing.md](../docs/flashing.md). `rk3576_spl_loader_v1.03.102.bin`
is the RK3576 Maskrom download loader `rkdeveloptool db` needs; the SoC is the
same across RK3576 boards, so the loader is board-agnostic.
