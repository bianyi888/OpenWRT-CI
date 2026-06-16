#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY & Gemini-Matrix

# ==================== 【0. 基础环境定义与流控函数】 ====================
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "
	echo "--------------------------------------------------------"
	echo "正在处理外部扩展包: $PKG_NAME 来自库: $PKG_REPO ($PKG_BRANCH)"
	echo "--------------------------------------------------------"

	# 第一步：全面排查并物理剔除官方 feeds 树中由于重名或版本陈旧可能引发死锁冲突的目录
	for NAME in "${PKG_LIST[@]}"; do
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "[冲突隔离] 已强行物理切除上游源冲突目录: $DIR"
			done <<< "$FOUND_DIRS"
		fi
	done

	# 第二步：纯净克隆指定分支的第三方软件仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git"

	# 第三步：针对不同仓库组织架构进行降维对齐加工
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "[追新警告] 未找到 $PKG_NAME 的 Makefile 编译母盘，跳过自动追新！"
		return
	fi

	echo -e "\n[自动追新] 正在对核心软件 $PKG_NAME 进行上游发布探测..."

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo " -> 固件内置版本: $OLD_VER | 哈希: $OLD_HASH"
		echo " -> 上游最新版本: $NEW_VER | 哈希: $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "[版本升级] 成功：$PKG_FILE 已完美同步升至最新版！"
		else
			echo "[版本追踪] 提示：$PKG_FILE 已经是最新，无需重复升级。"
		fi
	done
}


# ==================== 【1. 主流第三方高定主题与插件矩阵拉取】 ====================
echo -e "\n>>> 开始构建第三方高定插件生态流..."

UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "gecoosac luci-app-timewol luci-app-wolplus"
UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"
UPDATE_PACKAGE "luci-app-lucky" "gdy666/luci-app-lucky" "main"


# ==================== 【2. 核心网络引擎主动追新控制】 ====================
UPDATE_VERSION "sing-box"


# ==================== 【3. 本地高定闭环核心注入与降维打击补丁】 ====================
echo -e "\n------------------------------------------------------------"
echo ">>> [Core-Setup] 开始进行官方源脏数据切除与本地黄金级资产注入..."
echo "------------------------------------------------------------"

# 1. 物理清障：强行核平 feeds 官方源中与 dae/daed 冲突、或由于过时导致编译死锁的壳包
rm -rf ../feeds/luci/applications/luci-app-{passwall*,mosdns,dockerman,dae*,bypass*}
rm -rf ../feeds/packages/net/{v2ray-geodata,dae*,daed*}

# 2. 全量注入：从你的本地代码库（$GITHUB_WORKSPACE/package）克隆注入满血高定包全家桶
#    这其中完美包含：luci-app-dae (带中文包及 ccache 补丁)、dae 优化内核、v2ray-geodata 完整套件
if [ -d "$GITHUB_WORKSPACE/package" ]; then
	cp -r $GITHUB_WORKSPACE/package/* ./
	echo "[本地注入] 成功：本地自定义专属软件包矩阵（包含 v2ray-geodata 体系）已全量注入编译区！"
fi

# 3. 补丁替换：精准定位并应用你深度魔改的 daed/Makefile（PGO画像反馈 + 极致内联优化）
if [ -f "$GITHUB_WORKSPACE/patches/daed/Makefile" ]; then
	echo "[补丁导航] 检测到自定义 patches/daed/Makefile，开始精确切入..."
	REAL_DAED_MAKEFILE=$(find ./ ../feeds/packages/ -maxdepth 4 -type f -wholename "*/daed/Makefile" 2>/dev/null | head -n 1)
	if [ -n "$REAL_DAED_MAKEFILE" ]; then
		cp -f "$GITHUB_WORKSPACE/patches/daed/Makefile" "$REAL_DAED_MAKEFILE"
		echo "[补丁注入] 成功：已将魔改的 PGO+pnpm 编译母盘强制替换至 -> $REAL_DAED_MAKEFILE"
	fi
fi

# 4. 全局跨核心路径双向对齐守护补丁
#    利用高级流式文本编辑器（sed）在 sbwml 严谨的 v2ray-geodata/Makefile 编译安装宏中直接编织织入软连接。
#    确保固件生成时，/usr/share/dae/ 和 /usr/share/daed/ 完美指向带哈希校验的官方规则库，从根源上斩断运行期资产丢失引发的恐慌。
GEODATA_MAKEFILE="./v2ray-geodata/Makefile"
if [ -f "$GEODATA_MAKEFILE" ]; then
	echo "[路径对齐] 正在为自定义 v2ray-geodata 织入跨代理核心全兼容多向软连接兼容补丁..."
	
	# 在 geoip.dat 的标准安装动作后追加向 dae 和 daed 安装路径的硬核软连接建立
	sed -i '/usr\/share\/v2ray\/geoip.dat/a \\t\$(INSTALL_DIR) \$(1)\/usr\/share\/dae\n\t\$(LN) ..\/v2ray\/geoip.dat \$(1)\/usr\/share\/dae\/geoip.dat\n\t\$(INSTALL_DIR) \$(1)\/usr\/share\/daed\n\t\$(LN) ..\/v2ray\/geoip.dat \$(1)\/usr\/share\/daed\/geoip.dat' "$GEODATA_MAKEFILE"
	
	# 在 geosite.dat 的标准安装动作后追加同步对齐软连接
	sed -i '/usr\/share\/v2ray\/geosite.dat/a \\t\$(INSTALL_DIR) \$(1)\/usr\/share\/dae\n\t\$(LN) ..\/v2ray\/geosite.dat \$(1)\/usr\/share\/dae\/geosite.dat\n\t\$(INSTALL_DIR) \$(1)\/usr\/share\/daed\n\t\$(LN) ..\/v2ray\/geosite.dat \$(1)\/usr\/share\/daed\/geosite.dat' "$GEODATA_MAKEFILE"
	
	echo "[路径对齐] 成功：双向跨组件软连接路由补丁已完美灌注进 v2ray-geodata 编译树！"
fi

echo -e ">>> [Core-Setup] 本地高定链路降维打击补丁已全部组装完成并成功锁死！\n"


# ==================== 【4. 引入私有扩展脚本执行控制】 ====================
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	echo "[私有扩展] 执行自定义用户专属扩展 PRIVATE.sh 脚本中..."
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

echo "========================================================"
echo "Packages.sh 核心整合任务已全量完工！系统现在处于绝对极速、纯净构建就绪状态！"
echo "========================================================"
