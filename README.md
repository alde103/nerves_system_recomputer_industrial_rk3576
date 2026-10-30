# Nerves System for the Seeed reComputer Industrial RK3576

A [Nerves](https://nerves-project.org) system for the
[Seeed reComputer Industrial RK3576](https://www.seeedstudio.com/reComputer-Industrial-RK3576-0864-p-7015.html):
a DIN-rail industrial PC on the Rockchip RK3576 (4x Cortex-A72 + 4x
Cortex-A53), with soldered eMMC, 2x Gigabit Ethernet, 2x RS485/RS232 through a
WCH CH344 USB UART, CAN-FD, isolated DI/DO, an RTC, WiFi (WQ9201S on SDIO) and
an M.2 slot for 4G.

It runs Seeed's vendor kernel
([linux-rockchip `rk3576-industrial`](https://github.com/Seeed-Studio/linux-rockchip/tree/rk3576-industrial),
6.1) and Radxa's vendor U-Boot with Seeed's Industrial patches, so the board's
device tree and drivers are the ones Seeed ships and supports.

**Status: not yet verified on hardware.** The image builds and its layout is
checked by `scripts/verify-system.sh`; boot, OTA and peripherals still need a
board.

## Scope

This system carries what the board's own hardware needs: kernel drivers, the
device tree, the bootloader, and the WiFi driver and firmware. Userspace tools
(can-utils, iproute2, MQTT brokers, tunnels...) belong in your application or in
a derived system.

Not supported: NPU, GPU/video, Bluetooth, LoRa, NVMe and OP-TEE.

## Hardware

| Feature | Driver | Notes |
| --- | --- | --- |
| eMMC | `sdhci-of-dwcmshc` | `mmcblk0`, boot device |
| Ethernet x2 | stmmac, RTL8211F + Maxio MAE0621A PHYs | `eth0`, `eth1` |
| RS485/RS232 x2 | `cdc-acm` (CH344, CDC-ACM compliant) | `/dev/ttyACM*` |
| CAN-FD | `rk3576_canfd` | `can0` |
| WiFi | `wq_wlan` (out-of-tree, `package/wq9201s-wifi`) | loaded at boot by `load-board-modules` |
| RTC | `rtc-pcf8563` / `rtc-pcf85063` | |
| Watchdog | SoC `dw_wdt` | |
| Console | `ttyFIQ0`, 1500000 baud | CH343P on USB-C1 |

## Boot architecture

The RK3576 boot ROM loads `u-boot-rockchip.bin` from sector 64 of the eMMC
(idbloader with DDR init and SPL, then the U-Boot FIT at 8 MiB). U-Boot reads
the Nerves environment at 15 MiB and boots slot A or B from the FAT partition
with automatic revert. See `fwup_include/fwup-common.conf` for the layout and
`uboot/README.md` for how the bootloader is built.

## Building

```sh
mix deps.get
mix compile
```

### Using in an application

```elixir
# in deps():
{:nerves_system_recomputer_industrial_rk3576,
 path: "../nerves_system_recomputer_industrial_rk3576",
 runtime: false, nerves: [compile: true], targets: :recomputer_industrial_rk3576}
```

Then `export MIX_TARGET=recomputer_industrial_rk3576` for every mix command.

## Flashing

The first install goes over USB in Maskrom mode with `rkdeveloptool`; see
[docs/flashing.md](docs/flashing.md). Later updates go through `mix upload` or
NervesHub.

## Credits

Forked from [nerves_system_sige5](https://github.com/isaiahdw/nerves_system_sige5)
by Isaiah, which shares this board's SoC and boot layout. The vendor kernel
configuration follows
[nerves_system_rock_4d](https://github.com/isaiahdw/nerves_system_rock_4d).
