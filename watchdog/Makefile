include $(TOPDIR)/rules.mk

PKG_NAME:=watchdog
PKG_VERSION:=1
PKG_RELEASE:=6

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Routing Security Watchdog for OpenWrt
	DEPENDS:=+curl +bash
endef

define Package/$(PKG_NAME)/description
	Routing Security Watchdog for OpenWrt  @iamxiaojianzheng  <xjz.jiahe@gmail.com>
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/watchdog
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/watchdog.config $(1)/etc/config/watchdog
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/watchdog.init $(1)/etc/init.d/watchdog
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(CURDIR)/files/watchdog-call.libexec $(1)/usr/libexec/watchdog-call
	$(INSTALL_DIR) $(1)/usr/share/watchdog
	$(CP) -a $(CURDIR)/files/watchdog/* $(1)/usr/share/watchdog/
	chmod +x $(1)/usr/share/watchdog/watchdog
	chmod +x $(1)/usr/share/watchdog/lib/*.sh 2>/dev/null || true
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
