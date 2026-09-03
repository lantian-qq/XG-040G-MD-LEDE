# Nokia XG-040G-MD OpenWrt 自动编译指南

## 设备信息

| 项目 | 值 |
|------|-----|
| 设备型号 | Nokia XG-040G-MD |
| SoC | Airoha AN7581 (ARM Cortex-A53, aarch64) |
| OpenWrt Target | `airoha/an7581` |
| 设备 Profile | `nokia_xg-040g-md` |
| 分区方案 | UBI (SNAND, 128k block, 2048 page) |
| Kernel Image | 8MB |
| Rootfs Image | ~129MB |

## 文件说明

```
.github/workflows/xg-040g-md.yml  ← GitHub Actions 工作流（核心脚本）
diy-p1.sh                          ← 第一阶段自定义脚本（源码修改）
diy-p2.sh                          ← 第二阶段自定义脚本（配置修改）
README.md                          ← 本文件
```

## 快速开始

### 方法一：Fork 后自动编译

1. **Fork 本仓库**到你自己的 GitHub 账号
2. 进入 Fork 后的仓库 → `Actions` 选项卡
3. 选择 `Build Nokia XG-040G-MD Firmware` 工作流
4. 点击 `Run workflow`，可选参数：
   - **ssh_enable**: 是否启用 SSH（调试用，生产环境关闭）
   - **build_luci**: 是否编译 LuCI（推荐开启）
   - **custom_packages**: 额外的软件包，空格分隔
   - **keep_config**: 是否复用上次编译的 .config
5. 等待编译完成（首次约 2-3 小时），在 Artifacts 或 Releases 中下载固件

### 方法二：本地编译

```bash
# 1. 克隆 Lean 的 LEDE 源码
git clone --depth 1 https://github.com/coolsnowwolf/lede.git
cd lede

# 2. 更新 feeds
sed -i 's/#src-git helloworld/src-git helloworld/' feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a

# 3. 生成配置（交互式选择 Nokia XG-040G-MD）
make menuconfig
# Target System → Airoha
# Subtarget → AN7581 / AN7566 / AN7551
# Target Profile → Nokia XG-040G-MD

# 4. 编译
make -j$(nproc) || make -j1 V=s
```

## 生成的固件文件

编译完成后，固件位于 `bin/targets/airoha/an7581/` 目录：

| 文件 | 用途 |
|------|------|
| `openwrt-airoha-an7581-nokia_xg-040g-md-sysupgrade.tar` | 系统升级包（OpenWrt→OpenWrt） |
| `openwrt-airoha-an7581-nokia_xg-040g-md-factory-kernel.bin` | 原厂系统刷机 - 内核 |
| `openwrt-airoha-an7581-nokia_xg-040g-md-factory-rootfs.bin` | 原厂系统刷机 - 根文件系统 |

## Nokia XG-040G-MD 刷机方法

### 原厂系统刷机（首次刷入）

设备使用 UBI 分区方案，需要通过 SSH/Telnet 进入原厂系统后刷入：

```bash
# 1. 通过 SSH/Telnet 进入设备
ssh root@192.168.1.1

# 2. 上传固件文件
scp openwrt-airoha-an7581-nokia_xg-040g-md-factory-kernel.bin root@192.168.1.1:/tmp/
scp openwrt-airoha-an7581-nokia_xg-040g-md-factory-rootfs.bin root@192.168.1.1:/tmp/

# 3. 写入 UBI
ubiattach -m 2 -d 1
ubiformat /dev/ubi1 -f /tmp/openwrt-...-factory-rootfs.bin
ubiupdatevol /dev/ubi1_0 /tmp/openwrt-...-factory-kernel.bin

# 4. 设置启动参数并重启
fw_setenv bootargs "console=ttyS0,115200 rootfstype=ubifs ubi.mtd=2 root=ubi0:rootfs"
reboot
```

> ⚠️ **注意**：刷机有风险，操作需谨慎。不同固件版本的刷机方法可能不同，请参考设备对应的 OpenWrt Wiki 或社区指南。

### OpenWrt 系统升级

```bash
# 在已安装 OpenWrt 的设备上
luci → 系统 → 备份/升级 → 上传 sysupgrade.tar 文件
```

## Issue #14116 分析

### 问题概述

[Issue #14116](https://github.com/coolsnowwolf/lede/issues/14116) 报告 `kmod-airoha-xpon-en757x` 在 Linux 6.18 内核下编译失败。

### 根本原因

1. **`-Werror=implicit-function-declaration`**：`src/phy.c` 中调用了 `pma_dbg_reg_dump`、`normal_rx_bist_check` 等函数，这些函数在 `en7581.c` 中定义但 `phy.c` 中缺少声明
2. **`-Werror=missing-prototypes`**：`ecnt_scu.c` 等 BSP 模块中数十个函数缺少原型声明
3. **其他**：`-Werror=format`（jiffies 使用 `%x`）、`enum-int-mismatch`、`unused-variable`

### 当前状态

- **Issue 状态**：Open（未修复）
- **影响范围**：`airoha-pon` 包（commit `f7fd86e`）
- **是否影响本工作流**：**暂不影响**。该 commit 目前不属于 master 分支的任何分支，`airoha-pon` 包尚未合入 master

### 修复建议

当 `airoha-pon` 被合入 master 后，在 `diy-p1.sh` 中启用以下修复：

1. **添加缺失的函数声明**：在 `src/phy.c` 的 include 区域添加 `pma_dbg_reg_dump` 和 `normal_rx_bist_check` 的声明
2. **放宽编译警告**：在 Makefile 中添加 `-Wno-error=missing-prototypes -Wno-error=implicit-function-declaration`
3. **修复格式化警告**：将 `jiffies` 的 `%x` 格式改为正确的类型匹配

## 自定义编译

### 添加软件包

在 `diy-p1.sh` 中添加：

```bash
# 克隆第三方包
git clone https://github.com/xxx/yyy package/yyy
```

### 修改默认配置

在 `diy-p2.sh` 中使用 sed 修改 `.config`：

```bash
# 启用某功能
sed -i 's/# CONFIG_PACKAGE_xxx is not set/CONFIG_PACKAGE_xxx=y/' .config

# 禁用某功能
sed -i 's/CONFIG_PACKAGE_xxx=y/# CONFIG_PACKAGE_xxx is not set/' .config
```

### 常用软件包参考

| 包名 | 说明 |
|------|------|
| `luci` | LuCI Web 管理界面 |
| `helloworld` | 科学上网（需 helloworld feed） |
| `luci-app-openvpn` | OpenVPN 客户端 |
| `luci-app-vlmcsd` | KMS 服务 |
| `luci-app-dockerman` | Docker 管理 |
| `nano` | 文本编辑器 |
| `tmux` | 终端复用器 |

## 常见问题

### Q: 编译报磁盘空间不足？
A: GitHub Actions 免费 runner 只有 14GB 可用空间。工作流已包含空间清理步骤。如果仍然不够，可以：
   - 减少编译的软件包
   - 使用 `keep_config` 避免重复编译
   - 启用 ccache 加速

### Q: 如何查看编译日志？
A: 在 Actions 页面点击具体的工作流运行记录，展开各步骤查看日志。编译失败时加 `V=s` 会有详细输出。

### Q: 如何定时自动编译？
A: 工作流已配置每周日自动编译（`schedule` 触发）。也可以在 Actions 页面手动触发。

### Q: 固件刷入后无法启动？
A: 请确认：
   1. 设备型号确实是 Nokia XG-040G-MD
   2. 刷机命令正确
   3. 分区表匹配（UBI 方案）
   4. 如有串口，连接串口查看启动日志
