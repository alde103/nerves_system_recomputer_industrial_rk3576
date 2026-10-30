# nerves_system_recomputer_industrial_rk3576 v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A generic (vendor-neutral, no Valiot content) Nerves system for the Seeed reComputer Industrial RK3576 that builds offline into a flashable `.fw`/`.img` (Maskrom-ready). It runs Seeed's vendor kernel and vendor U-Boot and supports the board's onboard hardware, WiFi included.

**Architecture:** Fork `isaiahdw/nerves_system_sige5` @ `v0.2.0`, which has the same boot topology: eMMC-only, bootloader at sector 64, A/B with auto-revert, Nerves env at 15 MB.
- Kernel: swap the mainline kernel for `Seeed-Studio/linux-rockchip@rk3576-industrial`, using the config approach from `isaiahdw/nerves_system_rock_4d`.
- Bootloader: swap the mainline U-Boot for Radxa's vendor U-Boot plus Seeed's Industrial patches.
- Cleanup: strip the Sige5-only features (NPU, OP-TEE, GPU, Broadcom WiFi).

The Valiot variant (`valiot_system_recomputer_industrial_rk3576`) will be a fork of this repo, following the R11xx pattern (`alde103/nerves_system_recomputer_r11xx` → `valiot/valiot_system_recomputer_r11xx`). It is a separate plan.

**Tech Stack:** Nerves system (Buildroot via `nerves_system_br` 1.35.3), aarch64 Nerves toolchain 15.3, fwup, vendor Linux 6.1.172, Radxa U-Boot `next-dev-v2024.10`, rkbin blobs, Docker (U-Boot build).

**Spec:** Linear FCON-16 (https://linear.app/valiot/issue/FCON-16), plus these chat decisions from 2026-10-29:
- The base is sige5 v0.2.0.
- Align on `nerves_system_br` 1.35.3 (option A).
- Build a generic system first and a Valiot fork after it.

## Global Constraints

**Repository**
- Repo: `alde103/nerves_system_recomputer_industrial_rk3576`, at local path `/home/alde/Documents/Elixir/Nerves/repos/nerves_system_recomputer_industrial_rk3576`.
- Remote `upstream` = `https://github.com/isaiahdw/nerves_system_sige5.git`.

**Naming**
- `@app :nerves_system_recomputer_industrial_rk3576`.
- Module `NervesSystemRecomputerIndustrialRk3576.MixProject`.
- `@github_organization "alde103"`.
- `VERSION` = `0.1.0`.
- `BR2_NERVES_SYSTEM_NAME="nerves_system_recomputer_industrial_rk3576"`.
- `NERVES_FW_PLATFORM` = `"recomputer_industrial_rk3576"`.
- `NERVES_FW_AUTHOR` = `"The Nerves Project Authors"`.

**What goes in this system**
- **No Valiot content.** This system carries only what the board's onboard hardware needs: kernel drivers, the device tree, the bootloader, and the WiFi driver plus its firmware.
- Userspace tools are left to the variants: can-utils, iproute2, mosquitto, frpc, cloudflared, etc.
- Erlang stays at `nerves_system_br`'s default; the Valiot fork pins OTP 28.

**Dependency versions**
- `{:nerves_system_br, "1.35.3", runtime: false}`.
- `{:nerves_toolchain_aarch64_nerves_linux_gnu, "~> 15.3.0", runtime: false}`.

**Kernel**
- Source: `https://github.com/Seeed-Studio/linux-rockchip/archive/d9204f086ffd10f613927f57973605a6c205c73e.tar.gz` (6.1.172).
- DTB: `rockchip/rk3576-recomputer-industrial`.

**U-Boot**
- Source: `radxa/u-boot` @ `39cd993e5d6296635438e84f4576b3a9bf76f86e`.
- Seeed patches, defconfig and DTS: `Seeed-Studio/armbian-build` @ `f6792bab262dbc074ed2c0af81722ea7e7236754`.
- Blobs from `armbian/rkbin` @ `30eb694ecb4afa1ca3ec1e4c5e477a81f7004e7e`. These are the versions Seeed's Armbian image ships:
  - DDR: `rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin`
  - BL31: `rk35/rk3576_bl31_v1.20.elf`
  - boost: `rk35/rk3576_boost_v1.02.bin`
  - usbplug: `rk35/rk3576_usbplug_v1.03.bin`
  - Maskrom loader: `rk35/rk3576_spl_loader_v1.03.102.bin`

**WiFi driver**
- Source: `Seeed-Studio/seeed_armbian_extension` @ `f07752459afa9c522a438bf9983c2abc3847579d`, directory `wq9201s-wifi-bt-dkms`.
- The driver is GPL-2; the firmware is redistributable.

**Boot layout** (unchanged from sige5)
- `u-boot-rockchip.bin` is written at sector 64.
- The FIT sits at absolute 8 MiB, which is offset `0x7F8000` inside the bin.
- The U-Boot env sits at 15 MiB (`0xF00000`, 128 KiB) on `mmc 0`, the eMMC.

**Console**
- `ttyFIQ0` at 1500000, through the CH343P on USB-C1.

**Licensing**
- The repo stays GPL-2.0-or-later, inherited from sige5.
- Keep `LICENSES/` and `NOTICE` accurate for every committed binary.

**Process rules**
- CHANGELOG headings use semver (`## v0.1.0`), never "Unreleased".
- GitHub Actions runners are `X64`/`ARM64`, never `ubuntu-latest`.
- All code, comments and commits are in English.
- End each commit with the session attribution lines.

**Out of scope**
- NPU, GPU/video, Bluetooth, LoRa, NVMe, 4G bring-up and OP-TEE.

## Review Focus

1. **eMMC not enumerating as `mmcblk0`.** The vendor `rk3576.dtsi` has no `mmc` aliases. Without them, `erlinit` mounts, `fw_env.config` and fwup paths all break. Task 2 asserts that the DTB aliases `mmc0` to the eMMC (`sdhci`) node.
2. **Vendor U-Boot keeping its environment somewhere other than eMMC `0xF00000`.** That silently disables A/B revert. Task 3 asserts `CONFIG_ENV_IS_IN_MMC=y`, `CONFIG_ENV_OFFSET=0xF00000`, `CONFIG_ENV_SIZE=0x20000` and `CONFIG_SYS_MMC_ENV_DEV=0` in the built U-Boot config.
3. **The DTB file name or console drifting between files.** The files are `fwup.conf`, `fwup-ops.conf`, `uboot.env`, `extlinux-{a,b}.conf` and `erlinit.config`. Drift means no serial console, or an unbootable slot after the first OTA. Task 2 adds a consistency check.
4. **`wq_wlan.ko` built against a different kernel release than the one shipped.** The module then refuses to load. Task 4 compares its `vermagic` with the kernel release.
5. **The image layout off by a sector**, with the idblock or FIT misplaced. The board then stays in Maskrom. Task 5 checks the `RKNS` magic at byte 32768 and the FIT magic `d00dfeed` at 8 MiB of the generated `.img`.

---

### Task 1: Bootstrap the repo from sige5 v0.2.0 and strip Sige5-only features

**Files:**
- Create:
  - the repo at the path above, as a clone of sige5 `v0.2.0`
  - `docs/superpowers/plans/2026-10-29-nerves-system-recomputer-industrial-rk3576.md` (this plan)
  - `scripts/verify-system.sh`
- Modify: `mix.exs`, `VERSION`, `nerves_defconfig`, `Config.in`, `external.mk`, `post-build.sh`, `fwup_include/fwup-common.conf`, `README.md`, `CHANGELOG.md`, `NOTICE`, `.gitignore`
- Delete:
  - `package/{brcmfmac43752-firmware,librknnrt,rknpu-driver,optee-key}`
  - `optee/`, `tools/`, `docs/research/`
  - `linux/00*.patch`
  - `rootfs_overlay/etc/modprobe.d/brcmfmac.conf`
  - `scripts/regen-signing-requirements.py`, `scripts/signing-requirements.txt`

**Interfaces:**
- Produces: `scripts/verify-system.sh <artifact_dir> [image]`.
  - `--static` runs only the source-tree checks: `check_defconfig_clean` and `check_names_consistent`.
  - The script exits non-zero on the first failed check and prints `ok <check>` for each pass.
  - Later tasks add these check functions: `check_kernel_config SYMBOL VALUE`, `check_target_file PATH`, `check_dtb_alias ALIAS COMPATIBLE_SUBSTRING`, `check_names_consistent`, `check_module_vermagic MODULE`, `check_image_layout IMAGE`.
  - `<artifact_dir>` is `.nerves/artifacts/nerves_system_recomputer_industrial_rk3576-portable-0.1.0`, the Buildroot output dir (`build/`, `target/`, `images/`).

- [ ] **Step 1:** Clone and set up remotes:
  - `git clone -b v0.2.0 https://github.com/isaiahdw/nerves_system_sige5.git nerves_system_recomputer_industrial_rk3576`
  - `git remote rename origin upstream`
  - `git checkout -b main`
- [ ] **Step 2: Write the failing check.** Create `scripts/verify-system.sh` with `check_defconfig_clean`. It fails if `nerves_defconfig` mentions any of `RKNPU|LIBRKNNRT|OPTEE|BRCMFMAC|MESA3D|GLMARK2|STRESS_NG|KMSCUBE|ALSA`. Run it → FAIL.
- [ ] **Step 3:** Rename and strip:
  - Rename everything listed under Naming in Global Constraints. In `mix.exs` set the description to `"Nerves system for the Seeed reComputer Industrial RK3576"`; also update `VERSION`, `BR2_NERVES_SYSTEM_NAME`, and the platform and author in `fwup-common.conf`.
  - Bump `nerves_system_br` to `1.35.3`.
  - Remove the deleted packages from `Config.in` and from `nerves_defconfig`. That covers NPU, OP-TEE, `optee-key`, Mesa, glmark2, stress-ng, kmscube, ALSA, the brcmfmac firmware, and `LIBP11`, which only `optee-key` needed.
  - Remove their stale-checks from `external.mk`. Keep the generic `nerves-discard-if-stale` machinery and the linux patch hash.
  - Remove the bootloader/TA variant block from `post-build.sh`. Keep the `ops.fw` and `fwup_include` steps.
- [ ] **Step 4:** Update the docs:
  - Rewrite `README.md`: the board, a flashing summary, and credit to upstream.
  - Write `CHANGELOG.md` with a `## v0.1.0` heading.
  - Update `NOTICE`: drop the OP-TEE and NPU rows.
  - Copy this plan into `docs/superpowers/plans/`.
- [ ] **Step 5: Verify.**
  - `scripts/verify-system.sh --static` prints `ok check_defconfig_clean`.
  - `mix deps.get` resolves `nerves_system_br 1.35.3`.
  - `mix nerves.system.lint nerves_defconfig` passes.
- [ ] **Step 6: Commit** `Bootstrap from nerves_system_sige5 v0.2.0 for the reComputer Industrial RK3576`.

### Task 2: Seeed vendor kernel, Industrial DTB and console

**Files:**
- Create: `linux/0001-dts-rk3576-recomputer-industrial-nerves-fixups.patch`, `linux/industrial.config`
- Modify:
  - `nerves_defconfig`
  - `linux/nerves.config`: replace it with rock_4d's vendor-kernel version, adapted
  - `fwup.conf`, `fwup-ops.conf`, `extlinux-a.conf`, `extlinux-b.conf`
  - `uboot/uboot.env`: `fdtfile` and `console`
  - `rootfs_overlay/etc/erlinit.config`: `-c ttyFIQ0`
  - `scripts/verify-system.sh`

**Interfaces:**
- Consumes: `scripts/verify-system.sh` (Task 1).
- Produces:
  - DTB `rk3576-recomputer-industrial.dtb` in `images/`.
  - The kernel release string in `build/linux-custom/include/config/kernel.release`. Task 4 reads it.

- [ ] **Step 1: Write the failing checks** in `verify-system.sh`:
  - DTB aliases:
    - `check_dtb_alias mmc0 dwcmshc`: the eMMC, which is the `sdhci` node.
    - `check_dtb_alias mmc1 dw-mshc`: the `sdio` node used by the WiFi.
  - `check_kernel_config` for each of these, grouped by what needs them:
    - Serial: `CONFIG_USB_ACM=y`
    - CAN: `CONFIG_CAN=y`, `CONFIG_CAN_RAW=y`, `CONFIG_CAN_BCM=y`, `CONFIG_CAN_GW=y`, `CONFIG_CANFD_RK3576=y`
    - Ethernet PHY: `CONFIG_REALTEK_PHY=y`
    - RTC and watchdogs: `CONFIG_RTC_DRV_PCF85063=y`, `CONFIG_RTC_DRV_PCF8563=y`, `CONFIG_DW_WATCHDOG=y`, `CONFIG_WATCHDOG_NOWAYOUT=y`
    - Storage: `CONFIG_F2FS_FS=y`, `CONFIG_SQUASHFS=y`, `CONFIG_MMC_SDHCI_OF_DWCMSHC=y`
    - Networking: `CONFIG_IP_MULTIPLE_TABLES=y`, `CONFIG_TUN=y`
    - WiFi: `CONFIG_CFG80211=m`
  - `check_names_consistent`:
    - `rk3576-recomputer-industrial` is the only DTB basename in `fwup.conf`, `fwup-ops.conf`, `uboot/uboot.env` and `extlinux-{a,b}.conf`.
    - `ttyFIQ0` is the console in `uboot.env`, `extlinux-{a,b}.conf` and `erlinit.config`.
- [ ] **Step 2:** Run `check_names_consistent` → FAIL, because the files still carry the sige5 names.
- [ ] **Step 3:** Configure the kernel:
  - In `nerves_defconfig`:
    - `BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION` as in Global Constraints
    - `BR2_LINUX_KERNEL_USE_DEFCONFIG=y` and `BR2_LINUX_KERNEL_DEFCONFIG="rockchip_linux"`
    - config fragments `linux/nerves.config` and `linux/industrial.config`
    - `BR2_LINUX_KERNEL_INTREE_DTS_NAME="rockchip/rk3576-recomputer-industrial"`
    - `BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_1=y`
  - `linux/nerves.config`: rock_4d's file minus the Mali, AIC8800, HDMI fbcon and `ROCKCHIP_MTD_VENDOR_STORAGE` lines.
  - `linux/industrial.config`: the board symbols from Step 1, plus `CONFIG_USB_SERIAL_OPTION=m` and `CONFIG_USB_NET_QMI_WWAN=m` for the 4G slot.
- [ ] **Step 4:** Write the DTS patch against `rk3576-recomputer-industrial.dts`:
  - `aliases { mmc0 = &sdhci; mmc1 = &sdio; }`
  - `&wdt { status = "okay"; }`
- [ ] **Step 5:** Rename the DTB in the fwup, extlinux and `uboot.env` files. Set the console to `ttyFIQ0` in `uboot.env`, both extlinux files and `erlinit.config`.
- [ ] **Step 6: Verify.**
  - `mix compile` succeeds. This is the first full build, about 1–2 h.
  - `scripts/verify-system.sh .nerves/artifacts/nerves_system_recomputer_industrial_rk3576-portable-0.1.0` prints `ok` for every check from Step 1.
- [ ] **Step 7: Commit** `Boot Seeed's vendor 6.1 kernel with the Industrial device tree`.

### Task 3: Vendor U-Boot with the Nerves environment

**Files:**
- Modify:
  - `scripts/build-uboot.sh` (rewrite)
  - `uboot/uboot.env` (memory layout)
  - `uboot/README.md`, `NOTICE`
  - `LICENSES/LICENSE.rockchip-rkbin`: refresh it from armbian/rkbin
- Replace:
  - `uboot/u-boot-rockchip.bin`
  - `uboot/rk3576_spl_loader_v1.09.108.bin` → `uboot/rk3576_spl_loader_v1.03.102.bin`
- Delete: `uboot/u-boot-rockchip.variant`

**Interfaces:**
- Produces:
  - `uboot/u-boot-rockchip.bin`: idbloader at offset 0, FIT at `0x7F8000`. `fwup.conf` already writes this file at sector 64.
  - `uboot/u-boot.config`: the U-Boot `.config` the script built, committed so it can be reviewed.
  - `uboot/rk3576_spl_loader_v1.03.102.bin`, for `rkdeveloptool db`.

- [ ] **Step 1: Write the failing check.** Add it to the script's self-verification, which runs after every build. It checks that:
  - `uboot/u-boot.config` contains `CONFIG_ENV_IS_IN_MMC=y`, `CONFIG_ENV_OFFSET=0xF00000`, `CONFIG_ENV_SIZE=0x20000`, `CONFIG_SYS_MMC_ENV_DEV=0` and `CONFIG_DEFAULT_DEVICE_TREE="rk3576-recomputer-industrial"`;
  - bytes 0–3 of the bin are `RKNS`;
  - the bytes at `0x7F8000` are `d0 0d fe ed`.
- [ ] **Step 2:** Run the check against the current sige5 bin → FAIL: there is no `u-boot.config`, and the device tree is the wrong one.
- [ ] **Step 3:** Rewrite `scripts/build-uboot.sh`. It runs in Docker on `debian:bookworm`, pinned by digest the same way sige5 does. Steps:
  1. Clone radxa/u-boot at the pinned commit.
  2. Copy `patch/u-boot/legacy/u-boot-radxa-rk35xx/defconfig/recomputer-rk3576-industrial_defconfig` into `configs/`, and `.../dt/rk3576-recomputer-industrial.dts` into `arch/arm/dts/`.
  3. Apply `board_recomputer-rk3576-industrial/*.patch`, then `u-boot-radxa-rk35xx-v2024.10/*.patch`, in order.
  4. Append the Nerves env options from Step 1 to `.config` and run `olddefconfig`.
  5. Run `make BL31=<rkbin BL31> spl/u-boot-spl.bin u-boot.dtb u-boot.itb`.
  6. Build `idbloader.img` with rkbin's `tools/boot_merger` from `RK3576MINIALL.ini`. Substitute boost, DDR, usbplug and `FlashBoot=spl/u-boot-spl.bin` exactly as Armbian's `rockchip64_common.inc` does for `rk3576`.
  7. Pack `u-boot-rockchip.bin` as the idbloader, zero-padded to `0x7F8000`, followed by `u-boot.itb`.
  8. Copy the `.config` to `uboot/u-boot.config` and the Maskrom loader to `uboot/`.
- [ ] **Step 4:** Update `uboot/uboot.env`:
  - Replace the mainline memory layout with the vendor one: `scriptaddr=0x40500000`, `pxefile_addr_r=0x40600000`, `kernel_addr_r=0x40400000`, `fdt_addr_r=0x48300000`, `fdtoverlay_addr_r=0x48200000`, `ramdisk_addr_r=0x4a200000`.
  - Set `bootcmd=run nerves_init nerves_boot`, with the vendor `distro_bootcmd` as the fallback in place of `bootflow scan`.
- [ ] **Step 5: Verify.**
  - `scripts/build-uboot.sh` exits 0 and its self-check passes.
  - `mix compile` rebuilds `images/` with the new bin.
- [ ] **Step 6: Commit** `Build Seeed's vendor U-Boot with the Nerves environment on eMMC`.

### Task 4: WQ9201S WiFi driver

**Files:**
- Create:
  - `package/wq9201s-wifi/{Config.in,wq9201s-wifi.mk,wq9201s-wifi.hash}`
  - `rootfs_overlay/usr/sbin/load-board-modules`
- Modify: `Config.in`, `nerves_defconfig`, `external.mk`, `rootfs_overlay/etc/erlinit.config`, `scripts/verify-system.sh`, `NOTICE`

**Interfaces:**
- Consumes: the kernel release from Task 2.
- Produces:
  - `/lib/modules/<release>/updates/wq_wlan.ko`
  - `/lib/firmware/wq9201_*.bin` and `/lib/firmware/wq_wlan_settings.ini`
  - `load-board-modules`, which erlinit runs via `--pre-run-exec`. It runs `modprobe wq_wlan` in the background, because the module has no modalias autoload.

- [ ] **Step 1: Write the failing checks:**
  - `check_module_vermagic wq_wlan`: its `vermagic` starts with the contents of `kernel.release`.
  - `check_target_file` for `/lib/firmware/wq9201_fw_wifi_1_1_sdio.bin`, `/lib/firmware/wq_wlan_settings.ini` and `/usr/sbin/load-board-modules`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Write the package:
  - `wq9201s-wifi.mk` uses the `kernel-module` infra with a GitHub archive of the pinned commit.
  - `WQ9201S_WIFI_MODULE_SUBDIRS = wq9201s-wifi-bt-dkms/src/wifi/rwnx_drv`.
  - Licenses: `GPL-2.0` for the driver and `PROPRIETARY` for the firmware, with `WQ9201S_WIFI_LICENSE_FILES = wq9201s-wifi-bt-dkms/debian/copyright`.
  - A post-install hook copies `firmwares/*.bin` and `configs/wq_wlan_settings.ini` to `$(TARGET_DIR)/lib/firmware/`.
  - Add the hash, and add the stale-check entry to `external.mk` following the existing pattern.
- [ ] **Step 4:** Enable `BR2_PACKAGE_WQ9201S_WIFI=y` and wire `load-board-modules` into `erlinit.config` via `--pre-run-exec`.
- [ ] **Step 5: Verify.** `mix compile` succeeds, and `scripts/verify-system.sh <artifact_dir>` passes every check so far.
- [ ] **Step 6: Commit** `Add the WQ9201S WiFi driver and firmware`.

### Task 5: Flashable image, Maskrom procedure and artifact

**Files:**
- Modify: `docs/flashing.md` (rewrite for the Industrial), `scripts/verify-system.sh`, `CHANGELOG.md`, `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `nerves_system_recomputer_industrial_rk3576-portable-0.1.0-<checksum>.tar.gz` via `mix nerves.artifact`.

- [ ] **Step 1: Write the failing check.** `check_image_layout IMAGE` asserts:
  - bytes `RKNS` at offset 32768;
  - `d0 0d fe ed` at 8 MiB;
  - `nerves_fw_active=a` inside the 128 KiB at 15 MiB.
- [ ] **Step 2:** Build a smoke image in a throwaway project outside the repo:
  1. `mix nerves.new smoke`, with the system as a `path:` dep using `targets: :recomputer_industrial_rk3576, nerves: [compile: true]`.
  2. `MIX_TARGET=recomputer_industrial_rk3576 mix firmware`.
  3. `fwup -a -d smoke.img -i smoke.fw -t complete`.
  4. `check_image_layout smoke.img` must pass. If it fails, fix the cause in `fwup.conf` or `build-uboot.sh`, not in the check.
- [ ] **Step 3:** Rewrite `docs/flashing.md`:
  1. Switch the boot-mode DIP switch to Maskrom.
  2. Connect USB-C0 (OTG) to the host.
  3. `rkdeveloptool db uboot/rk3576_spl_loader_v1.03.102.bin`
  4. `rkdeveloptool wl 0 smoke.img`
  5. `rkdeveloptool rd`
  6. Switch the DIP switch back to normal.

  Later updates go through `mix upload` or NervesHub. Mark the DIP switch and USB-C0 steps "to confirm on hardware".
- [ ] **Step 4:** `mix nerves.artifact` produces the tarball. **Stop and ask the user** before creating `alde103/nerves_system_recomputer_industrial_rk3576` on GitHub, pushing, tagging `v0.1.0` or uploading the release asset.
- [ ] **Step 5: Commit** `Document Maskrom flashing and verify the eMMC image layout`.

---

## Follow-up plans (not in this one)

- **`valiot_system_recomputer_industrial_rk3576`:** a fork of this repo with this repo as `upstream`.
  - Pin `BR2_PACKAGE_ERLANG_28=y`.
  - Add the packages Valiot uses from the R11xx set: can-utils, libsocketcan, socketcand, iproute2, mosquitto, avahi, bridge-utils, iperf3, libcgroup, mbedtls, nmap, tcpdump, traceroute, unixodbc, cairo, libp11, frpc and cloudflared-bin.
  - Valiot branding, release `v0.1.0-valiot.1`.
- **R11xx to `nerves_system_br` 1.35.3** (the other half of option A):
  - Bump the generic `alde103/nerves_system_recomputer_r11xx`, then merge it into `valiot_system_recomputer_r11xx`.
  - Pin OTP 28 in the Valiot one.
- **Hardware bring-up** (FCON-16 phases 2–3 and 5):
  - First Maskrom flash.
  - How the vendor U-Boot behaves with the Nerves env and `bootcmd`.
  - `ttyACM*` mapping.
  - CAN-FD and the 120 Ω termination.
  - WiFi with `VintageNetWiFi`.
  - Watchdog policy: PCF8563T vs SoC `wdt` for `nerves_heart`.
  - RTC, and MACs from the EEPROM.
- **ValiotOS target** (FCON-16 phase 4): `:recomputer_industrial_rk3576` in `firmware/mix.exs`, plus serial and GPIO config.
