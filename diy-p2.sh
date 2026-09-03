#!/bin/bash
#=============================================================================
# diy-p2.sh - 第二阶段自定义脚本
# 在 make defconfig 之前执行（已通过 workflow 手动写入 .config）
# 用于修改 .config 配置项
#
# 工作目录：OpenWrt 源码根目录
#=============================================================================

echo ">>> diy-p2.sh 开始执行..."

# === 确保 helloworld 被启用（科学上网插件）===
sed -i 's/# CONFIG_PACKAGE_helloworld is not set/CONFIG_PACKAGE_helloworld=y/' .config 2>/dev/null || true
sed -i 's/CONFIG_PACKAGE_helloworld is not set/CONFIG_PACKAGE_helloworld=y/' .config 2>/dev/null || true

# === PON 相关配置 ===
# 如果 airoha-pon 包存在，启用 PON 内核模块
if [ -d "package/kernel/airoha-pon" ]; then
  echo ">>> 启用 PON 内核模块..."
  # 启用 GPON 模块（适用于大多数 PON 网络）
  echo "CONFIG_PACKAGE_kmod-airoha-gpon-en757x=y" >> .config
  # 启用 XPON 模块（适用于 XGSPON/10G-PON 网络）
  echo "CONFIG_PACKAGE_kmod-airoha-xpon-en757x=y" >> .config
  echo ">>> PON 模块已加入配置"
else
  echo ">>> [注意] airoha-pon 包不存在，PON 功能不可用"
  echo ">>> 如需 PON 支持，请确保 diy-p1.sh 成功拉取了 airoha-pon 包"
fi

# === Nokia XG-040G-MD 推荐的额外包 ===
# 该设备使用 AN7581 SoC（aarch64），支持以下可选功能：
#   - kmod-sfp: SFP 光模块支持
#   - kmod-phy-aeonsemi-as21xxx: Aeonsemi SFP PHY
#   - kmod-i2c-gpio: I2C GPIO 驱动
#   - kmod-iio-richtek-rtq6056: 电源管理 IIO 驱动

# 如需启用，取消注释以下行：
# sed -i 's/# CONFIG_PACKAGE_kmod-sfp is not set/CONFIG_PACKAGE_kmod-sfp=y/' .config
# sed -i 's/# CONFIG_PACKAGE_kmod-phy-aeonsemi-as21xxx is not set/CONFIG_PACKAGE_kmod-phy-aeonsemi-as21xxx=y/' .config

echo ">>> diy-p2.sh 执行完毕"
