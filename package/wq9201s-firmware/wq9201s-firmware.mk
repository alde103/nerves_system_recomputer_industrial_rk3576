################################################################################
#
# wq9201s-firmware — WuQi WQ9201S firmware and board settings
#
################################################################################

# From Seeed's wq9201s-wifi-bt-dkms 2.2.3.94-2 (seeed_armbian_extension,
# deb_source branch). That repository is several GB, so the files are
# downloaded one by one from the pinned commit.
WQ9201S_FIRMWARE_VERSION = f07752459afa9c522a438bf9983c2abc3847579d
WQ9201S_FIRMWARE_URL = https://raw.githubusercontent.com/Seeed-Studio/seeed_armbian_extension/$(WQ9201S_FIRMWARE_VERSION)/wq9201s-wifi-bt-dkms
WQ9201S_FIRMWARE_SITE = $(WQ9201S_FIRMWARE_URL)/firmwares
WQ9201S_FIRMWARE_FILES = \
	wq9201_fw_bt_1_1_uart.bin \
	wq9201_fw_dtop_1_1_sdio.bin \
	wq9201_fw_wifi_1_1_sdio.bin \
	wq9201_oem_1_1_0366.bin \
	wq9201_phy_1_1_4366_0102.bin
WQ9201S_FIRMWARE_SOURCE = wq9201_fw_wifi_1_1_sdio.bin
# wq_wlan_settings.ini is Seeed's board file for this module: fw_sys=5
# (WiFi + BT firmware download), single antenna shared with BT.
WQ9201S_FIRMWARE_EXTRA_DOWNLOADS = \
	$(addprefix $(WQ9201S_FIRMWARE_SITE)/,$(filter-out $(WQ9201S_FIRMWARE_SOURCE),$(WQ9201S_FIRMWARE_FILES))) \
	$(WQ9201S_FIRMWARE_URL)/configs/wq_wlan_settings.ini \
	$(WQ9201S_FIRMWARE_URL)/debian/copyright
WQ9201S_FIRMWARE_LICENSE = PROPRIETARY
WQ9201S_FIRMWARE_LICENSE_FILES = copyright
WQ9201S_FIRMWARE_REDISTRIBUTE = NO

# Plain files, not an archive: copy them in instead of extracting.
define WQ9201S_FIRMWARE_EXTRACT_CMDS
	$(foreach f,$(WQ9201S_FIRMWARE_FILES) wq_wlan_settings.ini copyright,
		cp $(WQ9201S_FIRMWARE_DL_DIR)/$(f) $(@D)/
	)
endef

# The driver reads its firmware and settings from /lib/firmware.
define WQ9201S_FIRMWARE_INSTALL_TARGET_CMDS
	$(foreach f,$(WQ9201S_FIRMWARE_FILES) wq_wlan_settings.ini,
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/$(f)
	)
endef

$(eval $(generic-package))
