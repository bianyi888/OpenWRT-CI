#!/bin/bash

PKG_PATH="$GITHUB_WORKSPACE/$WRT_DIR/package/"

#预置HomeProxy数据
if [ -d *"homeproxy"* ]; then
	echo " "

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	rm -rf ./$HP_PATH/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/
	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

	cd .. && rm -rf ./$HP_RULE/

	cd $PKG_PATH && echo "homeproxy date has been updated!"
fi

#修改argon主题字体和颜色
if [ -d *"luci-theme-argon"* ]; then
    echo " "
    cd ./luci-theme-argon/

    # 1. 首先把所有文件恢复到官方原版状态，擦除之前可能修改过的字体、颜色、透明度等
    git checkout ./luci-app-argon-config/root/etc/config/argon 2>/dev/null || true
    git checkout *.css *.less 2>/dev/null || true

    # 2. 精准修改：仅将背景模式从默认的 'none' (纯色/官方图片) 替换为 'bing' (必应每日壁纸)
    # 保持官方默认的 0.2 毛玻璃透明度、600 字体粗细和经典极光蓝颜色不变
    sed -i "s/mode 'none'/mode 'bing'/" ./luci-app-argon-config/root/etc/config/argon

    cd $PKG_PATH && echo "theme-argon has been restored to official with Bing wallpaper enabled!"
fi

#修改aurora菜单式样
if [ -d *"luci-theme-aurora"* ]; then
    echo " "
    cd ./luci-theme-aurora/

    # ----------------------------------------------------
    # 1. 配色升级：将原版略显生硬的蓝色，升级为高级的「冰岛极光绿」
    #    主色（Active）：#2d746d (松石绿)  |  辅色（Hover）：#3b948a
    # ----------------------------------------------------
    find ./ -name "*.css" -o -name "*.less" | xargs sed -i "
        s/#007aff/#2d746d/g;
        s/#0051a8/#1b4b46/g;
        s/#4794ff/#3b948a/g;
    "

    # 如果你更喜欢「深邃莫兰迪紫/粉」色系，可以把上面的替换行删掉，改用下面这三行：
    # find ./ -name "*.css" -o -name "*.less" | xargs sed -i "
    #     s/#007aff/#7a67ee/g;
    #     s/#0051a8/#5c4cc4/g;
    #     s/#4794ff/#9382ff/g;
    # "

    # ----------------------------------------------------
    # 2. 字体现代化：告别死板的旧字体，注入苹果/现代系统无衬线高级字体族
    # ----------------------------------------------------
    find ./ -name "*.css" -o -name "*.less" | xargs sed -i "
        s/font-family:[^;]*/font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif/g
    "

    # ----------------------------------------------------
    # 3. 质感微调：让卡片和登录框的阴影（Box-shadow）更柔和，边缘更细腻
    # ----------------------------------------------------
    find ./ -name "*.css" | xargs sed -i "
        s/box-shadow: 0 4px 12px rgba(0,0,0,.05)/box-shadow: 0 8px 24px rgba(45,116,109,.06)/g;
        s/box-shadow:0 4px 12px rgba(0,0,0,.05)/box-shadow: 0 8px 24px rgba(45,116,109,.06)/g;
        s/border-radius: 4px/border-radius: 8px/g;
        s/border-radius:4px/border-radius: 8px/g;
    "

    cd $PKG_PATH && echo "luci-theme-aurora has been beautifully remixed!"
fi

#修改qca-nss-drv启动顺序
NSS_DRV="../feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
	echo " "

	sed -i 's/START=.*/START=85/g' $NSS_DRV

	cd $PKG_PATH && echo "qca-nss-drv has been fixed!"
fi

#修改qca-nss-pbuf启动顺序
NSS_PBUF="./kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
	echo " "

	sed -i 's/START=.*/START=86/g' $NSS_PBUF

	cd $PKG_PATH && echo "qca-nss-pbuf has been fixed!"
fi

#修复TailScale配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile")
if [ -f "$TS_FILE" ]; then
	echo " "

	sed -i '/\/files/d' $TS_FILE

	cd $PKG_PATH && echo "tailscale has been fixed!"
fi

#修复Rust编译失败
RUST_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile")
if [ -f "$RUST_FILE" ]; then
	echo " "

	sed -i 's/ci-llvm=true/ci-llvm=false/g' $RUST_FILE

	cd $PKG_PATH && echo "rust has been fixed!"
fi

#修复DiskMan编译失败
DM_FILE="./luci-app-diskman/applications/luci-app-diskman/Makefile"
if [ -f "$DM_FILE" ]; then
	echo " "

	sed -i '/ntfs-3g-utils /d' $DM_FILE

	cd $PKG_PATH && echo "diskman has been fixed!"
fi

#修复luci-app-netspeedtest相关问题
if [ -d *"luci-app-netspeedtest"* ]; then
	echo " "

	cd ./luci-app-netspeedtest/

	sed -i '$a\exit 0' ./netspeedtest/files/99_netspeedtest.defaults
	sed -i 's/ca-certificates/ca-bundle/g' ./speedtest-cli/Makefile

	cd $PKG_PATH && echo "netspeedtest has been fixed!"
fi
