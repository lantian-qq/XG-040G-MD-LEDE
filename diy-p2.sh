#!/bin/bash
#=============================================================================
# diy-p2.sh - 第二阶段自定义脚本
# 在 make defconfig 之前执行（已通过 workflow 手动写入 .config）
# 用于修改 .config 配置项
#
# 工作目录：OpenWrt 源码根目录
#=============================================================================

# === 示例：修改默认配置 ===
# sed -i 's/CONFIG_PACKAGE_xxx=y/# CONFIG_PACKAGE_xxx is not set/' .config

# === Nokia XG-040G-MD 特有配置 ===
# 基本信息已在 workflow 中通过 cat >> .config 写入
# 这里可以做更精细的调整

# 确保 helloworld 被启用（科学上网插件）
sed -i 's/# CONFIG_PACKAGE_helloworld is not set/CONFIG_PACKAGE_helloworld=y/' .config 2>/dev/null || true
sed -i 's/CONFIG_PACKAGE_helloworld is not set/CONFIG_PACKAGE_helloworld=y/' .config 2>/dev/null || true

# === 针对 Nokia XG-040G-MD 的额外包 ===
# 该设备使用 AN7581 SoC（aarch64），支持以下可选功能：
#   - kmod-sfp: SFP 光模块支持
#   - kmod-phy-aeonsemi-as21xxx: Aeonsemi SFP PHY
#   - kmod-i2c-gpio: I2C GPIO 驱动
#   - kmod-iio-richtek-rtq6056: 电源管理 IIO 驱动

# 如需启用，取消注释以下行：
# sed -i 's/# CONFIG_PACKAGE_kmod-sfp is not set/CONFIG_PACKAGE_kmod-sfp=y/' .config
# sed -i 's/# CONFIG_PACKAGE_kmod-phy-aeonsemi-as21xxx is not set/CONFIG_PACKAGE_kmod-phy-aeonsemi-as21xxx=y/' .config

echo ">>> diy-p2.sh 执行完毕"
