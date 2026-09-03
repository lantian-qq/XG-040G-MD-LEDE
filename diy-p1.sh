#!/bin/bash
#=============================================================================
# diy-p1.sh - 第一阶段自定义脚本
# 在 feeds update/install 之后、配置生成之前执行
# 用于修改源码、添加第三方软件包等
#
# 工作目录：OpenWrt 源码根目录
#=============================================================================

# === 示例：添加第三方源码包 ===
# git clone https://github.com/xxx/yyy package/yyy

# === 示例：修改已有软件包版本 ===
# sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=5.10.0/' package/xxx/Makefile

# === Issue #14116 修复（当 airoha-pon 被合入 master 后启用）===
# 如果 package/kernel/airoha-pon 目录存在，需要修复 Linux 6.18 编译问题
# 修复方向：
#   1. 在 src/phy.c 中添加缺失的函数声明
#   2. 为 ecnt_scu.c 等模块添加 missing-prototypes 兼容
#   3. 修复 jiffies 的 %x 格式化警告
#
# if [ -d "package/kernel/airoha-pon" ]; then
#   echo ">>> [Fix #14116] Patching airoha-pon for Linux 6.18 compatibility..."
#   cd package/kernel/airoha-pon
#
#   # 修复1：在 phy.c 中添加 pma_dbg_reg_dump 和 normal_rx_bist_check 声明
#   # 在文件头部（include 之后）添加缺失的函数声明
#   sed -i '/#include/a\
#   /* Fix: Add missing function declarations for Linux 6.18 -Werror */\
#   extern void pma_dbg_reg_dump(void);\
#   extern void normal_rx_bist_check(void *);' src/phy.c
#
#   # 修复2：为 bsp 模块禁用 strict 警告（在 Makefile 中）
#   sed -i 's/EXTRA_CFLAGS += -Werror/EXTRA_CFLAGS += -Wno-error=missing-prototypes -Wno-error=implicit-function-declaration/' Makefile
#
#   cd ../..
# fi

echo ">>> diy-p1.sh 执行完毕"
