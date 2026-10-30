# Flashing a reComputer Industrial RK3576

The board boots only from its soldered eMMC, so the first install goes over
USB in Maskrom mode with `rkdeveloptool`. After that, updates go over the
network like on any Nerves device:

```sh
mix firmware && mix upload <device-ip>   # or through NervesHub
```

## First install (Maskrom)

> **To confirm on hardware:** the boot-mode switch and USB-C port named in
> steps 1 and 2 come from Seeed's documentation and have not been checked on a
> board yet.

Build a raw disk image from the firmware:

```sh
MIX_TARGET=recomputer_industrial_rk3576 mix firmware
fwup -a -d smoke.img -i _build/recomputer_industrial_rk3576_dev/nerves/images/<app>.fw -t complete
```

Then:

1. Power the board off and set the boot-mode DIP switch to Maskrom.
2. Connect USB-C0 (the OTG port) to the host with a USB-C data cable and
   power the board on. `rkdeveloptool ld` should list a Maskrom device.
3. Load the download helper:

   ```sh
   rkdeveloptool db uboot/rk3576_spl_loader_v1.03.102.bin
   ```

4. Write the whole image to the eMMC:

   ```sh
   rkdeveloptool wl 0 smoke.img
   ```

5. Reboot:

   ```sh
   rkdeveloptool rd
   ```

6. Power off, set the DIP switch back to normal boot, and power on.

The image is much smaller than the eMMC. That's fine: on the first boot
`/usr/sbin/expand-app-fs` rewrites the GPT and grows the application
partition to fill the disk.

Maskrom is also the recovery path: the boot ROM always runs first, so a board
with a broken eMMC image can always be reflashed this way.

## Serial console

The debug console is `ttyFIQ0` on UART0 at 1500000 baud 8N1, reachable over
the CH343P USB-serial bridge on USB-C1. U-Boot, the kernel and IEx all use it.

```sh
picocom -b 1500000 /dev/ttyACM0   # or whichever port the CH343P shows up as
```

## Layout

See `fwup_include/fwup-common.conf`:

| Offset | Contents |
| --- | --- |
| sector 64 (32 KiB) | `u-boot-rockchip.bin`: idblock (DDR init + SPL) |
| 8 MiB | U-Boot FIT (U-Boot + BL31), the second half of the same file |
| 15 MiB | Nerves U-Boot environment (128 KiB) |
| 16 MiB | p1 boot (FAT), p2 rootfs A, p3 rootfs B, p4 application (f2fs) |

`scripts/verify-system.sh <artifact_dir> <image>` checks an image against
this layout.
