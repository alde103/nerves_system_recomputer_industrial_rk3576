################################################################################
#
# wq9201s-wifi — WuQi WQ9201S SDIO WiFi driver (wq_wlan)
#
################################################################################

# Seeed's wq9201s-wifi-bt-dkms 2.2.3.94-2, from the deb_source branch of
# Seeed-Studio/seeed_armbian_extension. That repository is several GB, so
# neither a git clone nor a GitHub archive is a practical download: the
# GPL-2 driver source is kept in src/ (src/common and src/wifi/rwnx_drv,
# unmodified, minus IDE files and the unused kernel_patch/ and configs/). The
# proprietary firmware is package/wq9201s-firmware.
WQ9201S_WIFI_VERSION = 2.2.3.94-2
WQ9201S_WIFI_SITE = $(WQ9201S_WIFI_PKGDIR)/src
WQ9201S_WIFI_SITE_METHOD = local
WQ9201S_WIFI_LICENSE = GPL-2.0-or-later
WQ9201S_WIFI_LICENSE_FILES = copyright

WQ9201S_WIFI_DEPENDENCIES = wq9201s-firmware

# The same build Seeed's dkms.conf runs: the all-in-one wq_wlan.ko from
# wifi/rwnx_drv, which reaches ../../common for shared headers.
WQ9201S_WIFI_MODULE_SUBDIRS = wifi/rwnx_drv

$(eval $(kernel-module))
$(eval $(generic-package))
