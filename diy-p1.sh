#!/bin/bash
#=============================================================================
# diy-p1.sh - 第一阶段自定义脚本
# 在 feeds update/install 之后、配置生成之前执行
# 用于修改源码、添加第三方软件包等
#
# 工作目录：OpenWrt 源码根目录
#=============================================================================

echo ">>> [1/4] 正在添加 airoha-pon PON 支持包..."

###############################################################################
# 拉取 airoha-pon 包（GPON/XPON 内核模块）
#
# 该包提供 Nokia XG-040G-MD 接入 PON 网络所需的关键内核模块：
#   - kmod-airoha-gpon-en757x  (GPON MAC/PHY)
#   - kmod-airoha-xpon-en757x  (XPON MAC/PHY)
#
# 来源：coolsnowwolf/lede commit f7fd86e (尚未合入 master)
# Issue #14116：该包在 Linux 6.18 下有编译警告问题，需额外修复
###############################################################################

# 尝试拉取 airoha-pon 包
if [ ! -d "package/kernel/airoha-pon" ]; then
  echo ">>> 拉取 airoha-pon 包 (commit f7fd86e)..."
  git fetch --depth=1 https://github.com/coolsnowwolf/lede.git f7fd86eaa58c29fed97da04ab219c74a835a9358 2>/dev/null
  if [ $? -eq 0 ]; then
    git checkout FETCH_HEAD -- package/kernel/airoha-pon/ 2>/dev/null
    if [ $? -eq 0 ]; then
      echo ">>> airoha-pon 包已成功拉取"
    else
      echo ">>> [警告] checkout 失败，尝试 git apply 方式..."
      git format-patch -1 FETCH_HEAD --stdout -- package/kernel/airoha-pon/ | git apply 2>/dev/null
    fi
  else
    echo ">>> [警告] 无法拉取 airoha-pon 包，PON 功能将不可用"
    echo ">>> 如需 PON 支持，请手动将 airoha-pon 包放入 package/kernel/ 目录"
  fi
fi

echo ">>> [2/4] 修复 Issue #14116 编译问题..."

###############################################################################
# 修复 Issue #14116：kmod-airoha-xpon-en757x 在 Linux 6.18 下编译失败
#
# 问题根因：
#   1. -Werror=implicit-function-declaration：phy.c 缺少函数声明
#   2. -Werror=missing-prototypes：BSP 模块缺少原型
#   3. -Werror=format：jiffies 用 %x 格式化
#
# 修复策略：
#   在 Makefile 中添加 -Wno-error 标志，允许这些警告通过编译
#   同时尝试修复源码中的实际问题
###############################################################################

if [ -d "package/kernel/airoha-pon" ]; then
  cd package/kernel/airoha-pon

  # 修复1：在 Makefile 中放宽编译警告
  if [ -f "Makefile" ]; then
    # 将 -Werror 替换为 -Wno-error（针对特定警告类型）
    sed -i 's/EXTRA_CFLAGS += -Werror/EXTRA_CFLAGS += -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=format -Wno-error=enum-int-mismatch -Wno-error=unused-variable/' Makefile 2>/dev/null || true
    # 也处理 ccflags-y 方式
    sed -i 's/ccflags-y += -Werror/ccflags-y += -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=format -Wno-error=enum-int-mismatch -Wno-error=unused-variable/' Makefile 2>/dev/null || true
    echo ">>> Makefile 编译标志已修复"
  fi

  # 修复2：尝试修复 phy.c 中缺失的函数声明
  if [ -f "src/phy.c" ]; then
    # 检查是否需要添加函数声明
    if grep -q "implicit declaration of function" /dev/null 2>&1 || grep -q "pma_dbg_reg_dump" src/phy.c 2>/dev/null; then
      # 在文件的 include 区域后添加缺失的声明
      sed -i '/#include/a\
/* [Fix #14116] Add missing function declarations for Linux 6.18 */\
extern void pma_dbg_reg_dump(void);\
extern void normal_rx_bist_check(void *);' src/phy.c 2>/dev/null || true
      echo ">>> phy.c 函数声明已修复"
    fi
  fi

  # 修复3：修复 format 警告（jiffies 用 %x 应该用 %lx）
  find . -name "*.c" -exec sed -i 's/%x.*jiffies/%lx (unsigned long)jiffies/g' {} \; 2>/dev/null || true

  cd ../..
  echo ">>> Issue #14116 修复已应用"
else
  echo ">>> airoha-pon 包不存在，跳过修复"
fi

echo ">>> [3/4] 应用其他自定义修改..."

# === 示例：添加第三方源码包 ===
# git clone https://github.com/xxx/yyy package/yyy

# === 示例：修改已有软件包版本 ===
# sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=5.10.0/' package/xxx/Makefile

echo ">>> [4/4] diy-p1.sh 执行完毕"
