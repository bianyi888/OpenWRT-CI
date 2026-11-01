# 亚瑟 momo 的 reF1nd 内核管理

在 `QCA-ALL` 的 `IPQ60XX-WIFI-NO` 固件中，进入 **服务 → Momo → reF1nd 内核**。
页面提供当前版本、上一版、目标版本、更新、回退和操作日志。
`latest` 选择 `reF1nd/sing-box-releases` 最新正式发布；也支持完整标签，例如
`v1.14.4-reF1nd`。测试版和其他仓库的构建不接受。

首次使用前请确保 momo 能正常运行且有有效的运行配置。更新时会短暂中断代理。
更新程序先下载 ARM64 musl 资产，使用 GitHub 发布资产的 SHA-256 digest 校验，
检查二进制实际版本，并用候选内核检查 `/etc/momo/run/config.json`。
通过后才停止 momo、原子替换 `/usr/bin/sing-box` 并重新启动。
启动检查等待服务就绪，并要求 procd 实例 PID 在连续 10 秒检查内保持稳定。
这属于进程健康检查，不代表所有节点或外网连接都已经测试通过。

启动失败会尝试恢复原内核并重启 momo。成功切换后才更新上一版备份，保留一份，
因此回退按钮也能切回刚才使用的版本。内核放在持久化 overlay 中，普通重启后保留。
重刷固件后以该固件预装版本为准，不把旧二进制自动加入 sysupgrade 保留清单，
避免跨系统版本恢复不兼容的可执行文件。额外需要候选内核、备份和替换文件的存储空间。

更新任务由单独的 rpcd 执行插件后台运行，不受网页请求超时或关闭页面影响。
ACL 将状态读取和写入操作分开；不会开放通用命令执行权限。
日志位于 `/var/log/momo-refind.log`，上一版位于 `/etc/momo/refind-core/previous`。
若断电或任务被强制终止，查看日志及 `/etc/momo/refind-core/.stage.*` 中保留的
`original` 备份；不要在未排查时删除。可在 ttyd 中以 root 手动恢复：

```sh
/etc/init.d/momo stop
# 将下方路径替换为实际保留的 original 文件路径
cp /etc/momo/refind-core/.stage.XXXXXX/original /usr/bin/.sing-box.refind-new
chmod 755 /usr/bin/.sing-box.refind-new
mv /usr/bin/.sing-box.refind-new /usr/bin/sing-box
/etc/init.d/momo start
```

固件 CI 使用同一个下载程序，检查摘要、ELF 架构和 musl 动态加载器（静态构建也允许）。
下载、校验或架构检查失败时终止编译，不退回 glibc 或 feeds 的另一个版本。
CI 可通过 `REFIND_VERSION` 环境变量固定完整发布标签，默认 `latest`。
其他支持的 ARM64/x86-64 固件沿用校验后的内核预装流程，只有亚瑟配置安装此管理页面。

Zashboard 保持上游版本；内核更新从 momo 页面操作，不接管 Zashboard 的 `/upgrade`。

## 验证

```sh
python3 -m unittest discover -s Tests -v
node Tests/test_refind_ui.js
```

离线集成测试覆盖摘要错误、下载失败、架构选择、路径异常、配置不兼容、启动失败恢复、
更新与回退、并发锁、CI 文件安装和 LuCI 操作逻辑。
尚需在实际亚瑟设备上完成刷机、rpcd 接口和联网更新验收。
