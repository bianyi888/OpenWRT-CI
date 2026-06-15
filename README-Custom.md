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
