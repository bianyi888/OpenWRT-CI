include $(TOPDIR)/rules.mk

PKG_NAME:=fn-knock
PKG_VERSION:=2.5.2
PKG_RELEASE:=1

PKG_SOURCE:=fn-knock_2.5.2-1_aarch64_cortex-a53.ipk
PKG_SOURCE_URL:=https://github.com/kci-lnk/fn-knock-turborepo/releases/download/v2.5.2/
PKG_HASH:=skip

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/fn-knock
  SECTION:=net
  CATEGORY:=Network
  TITLE:=fn-knock security gateway (Rust+Go)
  URL:=https://github.com/kci-lnk/fn-knock-turborepo
endef

define Build/Compile
	true
endef

define Package/fn-knock/install
	$(INSTALL_DIR) $(1)
	mkdir -p $(PKG_BUILD_DIR)/ipk-tmp
	tar xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)/ipk-tmp
	tar xzf $(PKG_BUILD_DIR)/ipk-tmp/data.tar.gz -C $(1)
endef

$(eval $(call BuildPackage,fn-knock))
