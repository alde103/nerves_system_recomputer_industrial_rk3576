# Changelog

## v0.1.0

Initial release, forked from
[nerves_system_sige5](https://github.com/isaiahdw/nerves_system_sige5) v0.2.0.

- Seeed's vendor kernel (linux-rockchip `rk3576-industrial`, 6.1) with the
  reComputer Industrial device tree.
- Radxa's vendor U-Boot with Seeed's Industrial patches, keeping the Nerves
  environment on the eMMC at 15 MiB for A/B updates with automatic revert.
- WQ9201S WiFi driver and firmware.
- Built on `nerves_system_br` 1.35.3.
- Removed the Sige5-only NPU, GPU, OP-TEE, Broadcom WiFi and audio support.
