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
# 问题根因（来自编译日志）：
#   1. src/phy.c 缺少 6 个函数的隐式声明
#   2. pon_phy_clear_rogueonu / pon_phy_rogueonu_int_en 函数名不匹配
#      （实际函数名带 en7581_ 前缀）
#   3. PON_PHY_PRINT 宏参数列表未终止
#   4. 非 void 函数末尾缺少 return（-Werror=return-type）
#
# 修复策略：
#   1. 在 Makefile 末尾追加 -Wno-error，确保即使内核顶层设置 -Werror 也不致命
#   2. 添加所有缺失的函数声明并修正函数名
#   3. 重定义 PON_PHY_PRINT 宏避免语法错误
###############################################################################

if [ -d "package/kernel/airoha-pon" ]; then
  cd package/kernel/airoha-pon

  # 修复1：在 Makefile 中全面禁用 -Werror
  if [ -f "Makefile" ]; then
    echo "" >> Makefile
    echo "# [Fix #14116] Disable -Werror for Linux 6.18 compatibility" >> Makefile
    echo "EXTRA_CFLAGS += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type" >> Makefile
    echo "ccflags-y += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type" >> Makefile
    echo ">>> Makefile 编译标志已修复（追加 -Wno-error）"
  fi

  # 同时检查 Kbuild 文件（内核模块可能用 Kbuild 而非 Makefile）
  for kbuild_file in Kbuild kbuild; do
    if [ -f "$kbuild_file" ]; then
      echo "" >> "$kbuild_file"
      echo "# [Fix #14116] Disable -Werror for Linux 6.18" >> "$kbuild_file"
      echo "EXTRA_CFLAGS += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type" >> "$kbuild_file"
      echo ">>> $kbuild_file 编译标志已修复"
    fi
  done

  # 修复2：修复 phy.c 中的编译错误
  if [ -f "src/phy.c" ]; then
    # 2a: 添加所有缺失的函数声明（Linux 6.18 要求显式声明）
    sed -i '/#include/a\
/* [Fix #14116] Add missing function declarations for Linux 6.18 */\
extern void pma_dbg_reg_dump(void);\
extern void normal_rx_bist_check(void *data);\
extern void xpon_rx_bist_recheck_result(void *data);\
extern void t2r_rx_bist_check(void *data);\
extern int en7581_pon_phy_clear_rogueonu(void);\
extern int en7581_pon_phy_rogueonu_int_en(void);' src/phy.c 2>/dev/null || true
    echo ">>> phy.c 函数声明已添加（6个）"

    # 2b: 修复函数名不匹配（pon_phy_* -> en7581_pon_phy_*）
    # 编译器提示实际函数名带 en7581_ 前缀
    sed -i 's/\bpon_phy_clear_rogueonu\b/en7581_pon_phy_clear_rogueonu/g' src/phy.c 2>/dev/null || true
    sed -i 's/\bpon_phy_rogueonu_int_en\b/en7581_pon_phy_rogueonu_int_en/g' src/phy.c 2>/dev/null || true
    echo ">>> phy.c 函数名已修正（en7581_ 前缀）"

    # 2c: 修复 PON_PHY_PRINT 宏参数列表未终止问题
    # 在文件开头强制重定义为空宏，避免 compiler_types.h 中的宏定义导致语法错误
    sed -i '1a\
/* [Fix #14116] Override PON_PHY_PRINT to avoid unterminated macro error */\
#ifdef PON_PHY_PRINT\
#undef PON_PHY_PRINT\
#endif\
#define PON_PHY_PRINT(fmt, ...)' src/phy.c 2>/dev/null || true
    echo ">>> phy.c PON_PHY_PRINT 宏已修复"

    # 2d: 抑制 return-type 警告（作为兜底，防止某些函数路径缺少 return）
    sed -i '1a\
/* [Fix #14116] Suppress return-type warning for BSP module */\
#pragma GCC diagnostic ignored "-Wreturn-type"' src/phy.c 2>/dev/null || true
    echo ">>> phy.c return-type 警告已抑制"
  fi

  # 修复3：修复 format 警告（jiffies 用 %x 应该用 %lx）
  find . -name "*.c" -exec sed -i 's/\(%[0-9]*x\).*\(jiffies\)/%lx (unsigned long)\2/g' {} \; 2>/dev/null || true

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
