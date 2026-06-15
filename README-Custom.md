====================================================================
 亚瑟 (JDCloud AX1800 Pro) Daed + Lucky 终极定制修改全集存档
====================================================================

--------------------------------------------------------------------
【文件 1】.github/workflows/WRT-CORE.yml (作用：重塑 CI 编译环境)
--------------------------------------------------------------------
定位到 `jobs: core: steps:` 下面的 `Initialization Environment` 及其前置步骤。
将原有初始化代码【替换】为以下内容：

      - name: Checkout Projects
        uses: actions/checkout@main

      # 强行拉起最新版 Go 环境 (daed 后端刚需)
      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22.x'

      # 强行拉起最新版 Node.js (daed 前端刚需)
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Initialization Environment
        env:
          DEBIAN_FRONTEND: noninteractive
        run: |
          sudo -E apt -yqq purge firefox
          sudo -E apt -yqq update
          sudo -E apt -yqq full-upgrade
          sudo -E apt -yqq autoremove --purge
          sudo -E apt -yqq autoclean
          sudo -E apt -yqq clean
          # 补齐 eBPF 需要的 clang llvm 工具链，并调用在线初始化脚本
          sudo -E apt -yqq install dos2unix libfuse-dev clang llvm
          sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
          sudo -E systemctl daemon-reload
          sudo -E timedatectl set-timezone "Asia/Shanghai"

          sudo mkdir -p /mnt/build_wrt
          sudo chown $USER:$USER /mnt/build_wrt
          sudo ln -s /mnt/build_wrt $GITHUB_WORKSPACE/wrt


--------------------------------------------------------------------
【文件 2】Scripts/Packages.sh (作用：精准拉取官方源码)
--------------------------------------------------------------------
定位到文件末尾的 `UPDATE_VERSION` 函数之前。
将以下内容【追加】进去：

# 科学与网络增强神级插件
UPDATE_PACKAGE "luci-app-daed" "QiuSimons/luci-app-daed" "kix"
UPDATE_PACKAGE "luci-app-lucky" "gdy666/luci-app-lucky" "main"


--------------------------------------------------------------------
【文件 3】Config/GENERAL.txt (作用：强制激活固件打包)
--------------------------------------------------------------------
定位到 `#增加插件` 的列表区域。
将以下内容【追加】进去：

CONFIG_PACKAGE_luci-app-daed=y
CONFIG_PACKAGE_luci-app-lucky=y


--------------------------------------------------------------------
【文件 4】Config/IPQ60XX-WIFI-NO.txt (作用：剔除多余机型，极限瘦身)
--------------------------------------------------------------------
将文件原有内容【全部清空并替换】为以下精简版代码：

#设备平台
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq60xx=y

#设备列表 (仅保留亚瑟 jdcloud_re-ss-01)
CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y

#WIFI驱动
CONFIG_PACKAGE_kmod-ath=n
CONFIG_PACKAGE_kmod-ath11k=n
CONFIG_PACKAGE_kmod-ath11k-ahb=n
CONFIG_PACKAGE_kmod-ath11k-pci=n
CONFIG_PACKAGE_ath11k-firmware-ipq6018=n
CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt=n
CONFIG_PACKAGE_ath11k-firmware-qcn9074=n
CONFIG_PACKAGE_ath11k-firmware-qcn9074-ddwrt=n


--------------------------------------------------------------------
【文件 5】Scripts/Settings.sh (作用：底层魔改、DTS规避、12M扩容)
--------------------------------------------------------------------
修改点 A：找到原本处理无 WiFi 版设备树的地方，【替换】为精准版：

	#无WIFI配置调整Q6大小 (独家精准狙击版)
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		# 仅针对 jdcloud 的设备树进行无 Wi-Fi 替换，避免误伤其他机器引起 DTC 编译报错
		find $DTS_PATH -type f -name '*jdcloud*' -exec sed -i 's/ipq6018.dtsi/ipq6018-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully for jdcloud!"
	fi

修改点 B：在此文件的最末尾，【追加】以下核心扩容与提权代码：

# =========================================================
# 以下为 daed 专属 eBPF 内核注入与 亚瑟专属 12MB 分区扩容逻辑
# =========================================================

echo "Injecting eBPF and kernel configs for daed..."
# 1. 基础内核调试与 eBPF 支持
cat >> ./.config <<EOF
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
EOF

# 2. 强行往高通平台默认内核配置中注入更深层的 BPF 机制
TARGET_CONFIG_DEFAULT=$(find target/linux/qualcommax/ -maxdepth 2 -type f -name "config-default" 2>/dev/null)
if [ -n "$TARGET_CONFIG_DEFAULT" ]; then
    for conf in $TARGET_CONFIG_DEFAULT; do
        cat >> "$conf" <<EOF
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_CGROUPS=y
CONFIG_KPROBES=y
CONFIG_NET_INGRESS=y
CONFIG_NET_EGRESS=y
CONFIG_NET_CLS_ACT=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_KPROBE_EVENTS=y
CONFIG_BPF_EVENTS=y
CONFIG_NET_SCH_BPF=y
EOF
    done
    echo "eBPF kernel configurations injected successfully!"
fi

# 3. 精准修改京东云系列机型的内核分区大小为 12MB，绝不触碰 emmc-common 避免误伤其他机器
IMAGE_FILE=$(find target/linux/qualcommax/image/ -type f -name "ipq60xx.mk" 2>/dev/null)
if [ -f "$IMAGE_FILE" ]; then
    echo "Expanding kernel size to 12MB ONLY for JDCloud devices..."
    # 利用换行符 \n，将 KERNEL_SIZE 强行注入到特定机型的定义下方
    sed -i 's/define Device\/jdcloud_re-ss-01/define Device\/jdcloud_re-ss-01\n  KERNEL_SIZE := 12288k/g' $IMAGE_FILE
    sed -i 's/define Device\/jdcloud_re-cs-02/define Device\/jdcloud_re-cs-02\n  KERNEL_SIZE := 12288k/g' $IMAGE_FILE
    sed -i 's/define Device\/jdcloud_re-cs-07/define Device\/jdcloud_re-cs-07\n  KERNEL_SIZE := 12288k/g' $IMAGE_FILE
fi
