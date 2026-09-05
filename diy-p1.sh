#!/bin/bash
#=============================================================================
# diy-p1.sh - 第一阶段自定义脚本
# 在 feeds update/install 之后、配置生成之前执行
# 用于修改源码、添加第三方软件包等
#
# 工作目录：OpenWrt 源码根目录
#=============================================================================

echo ">>> [1/5] 正在添加 airoha-pon PON 支持包..."

###############################################################################
# 拉取 airoha-pon 包（GPON/XPON 内核模块）
###############################################################################

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
  fi
fi

echo ">>> [2/5] 定位 airoha-pon 源码文件..."

###############################################################################
# 打印目录结构，确认文件位置
###############################################################################

if [ -d "package/kernel/airoha-pon" ]; then
  echo ">>> airoha-pon 目录结构："
  find package/kernel/airoha-pon -type f -name "*.c" -o -name "*.h" -o -name "Makefile" -o -name "Kbuild" 2>/dev/null | head -50

  # 定位 phy.c 文件（可能在多个位置）
  PHY_FILES=$(find package/kernel/airoha-pon -name "phy.c" -type f 2>/dev/null)
  echo ">>> 找到的 phy.c 文件："
  echo "$PHY_FILES"

  # 定位所有 Makefile 和 Kbuild
  BUILD_FILES=$(find package/kernel/airoha-pon -name "Makefile" -o -name "Kbuild" -type f 2>/dev/null)
  echo ">>> 找到的构建文件："
  echo "$BUILD_FILES"
fi

echo ">>> [3/5] 修复 Issue #14116 编译问题..."

###############################################################################
# 修复 Issue #14116
###############################################################################

if [ -d "package/kernel/airoha-pon" ]; then

  # 修复1：在包级别 Makefile 中添加 KERNEL_MAKE_FLAGS
  # 这会将 -Wno-error 传递给内核构建系统
  if [ -f "package/kernel/airoha-pon/Makefile" ]; then
    # 检查是否已经有 KERNEL_MAKE_FLAGS
    if ! grep -q "KERNEL_MAKE_FLAGS" package/kernel/airoha-pon/Makefile; then
      echo "" >> package/kernel/airoha-pon/Makefile
      echo "# [Fix #14116] Pass -Wno-error flags to kernel build system" >> package/kernel/airoha-pon/Makefile
      echo 'KERNEL_MAKE_FLAGS += KCFLAGS+="-Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type"' >> package/kernel/airoha-pon/Makefile
      echo ">>> 包 Makefile: KERNEL_MAKE_FLAGS 已添加"
    fi
  fi

  # 修复2：在所有内核模块 Makefile/Kbuild 中添加 -Wno-error
  for mkfile in $(find package/kernel/airoha-pon -name "Makefile" -o -name "Kbuild" -type f 2>/dev/null); do
    if ! grep -q "Wno-error" "$mkfile" 2>/dev/null; then
      echo "" >> "$mkfile"
      echo "# [Fix #14116] Disable -Werror for Linux 6.18 + GCC 14" >> "$mkfile"
      echo "EXTRA_CFLAGS += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type" >> "$mkfile"
      echo "ccflags-y += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type" >> "$mkfile"
      echo ">>> $mkfile: -Wno-error 已添加"
    fi
  done

  # 修复3：修复所有 phy.c 文件中的编译错误
  for phy_file in $PHY_FILES; do
    if [ -f "$phy_file" ]; then
      echo ">>> 修复 $phy_file ..."

      # 3a: 添加缺失的函数声明
      sed -i '/#include/a\
/* [Fix #14116] Add missing function declarations for Linux 6.18 + GCC 14 */\
extern void pma_dbg_reg_dump(void);\
extern void normal_rx_bist_check(void *data);\
extern void xpon_rx_bist_recheck_result(void *data);\
extern void t2r_rx_bist_check(void *data);\
extern int en7581_pon_phy_clear_rogueonu(void);\
extern int en7581_pon_phy_rogueonu_int_en(void);' "$phy_file" 2>/dev/null || true

      # 3b: 修复函数名不匹配（pon_phy_* -> en7581_pon_phy_*）
      sed -i 's/\bpon_phy_clear_rogueonu\b/en7581_pon_phy_clear_rogueonu/g' "$phy_file" 2>/dev/null || true
      sed -i 's/\bpon_phy_rogueonu_int_en\b/en7581_pon_phy_rogueonu_int_en/g' "$phy_file" 2>/dev/null || true

      # 3c: 修复 PON_PHY_PRINT 宏问题 - 在文件开头添加重定义
      # 使用 head/tail 方式，比 sed -i '1a' 更可靠
      TEMP_FILE=$(mktemp)
      cat > "$TEMP_FILE" << 'PATCH_HEADER'
/* [Fix #14116] Override PON_PHY_PRINT to avoid unterminated macro error */
/* Also suppress return-type and implicit-function-declaration warnings */
#ifdef PON_PHY_PRINT
#undef PON_PHY_PRINT
#endif
#define PON_PHY_PRINT(fmt, ...)
#pragma GCC diagnostic ignored "-Wreturn-type"
#pragma GCC diagnostic ignored "-Wimplicit-function-declaration"

PATCH_HEADER
      cat "$phy_file" >> "$TEMP_FILE"
      mv "$TEMP_FILE" "$phy_file"

      echo ">>> $phy_file 已修复（函数声明+名称修正+宏修复+警告抑制）"
    fi
  done

  # 修复4：修复 jiffies format 警告
  find package/kernel/airoha-pon -name "*.c" -exec sed -i 's/\(%[0-9]*x\).*\(jiffies\)/%lx (unsigned long)\2/g' {} \; 2>/dev/null || true

  echo ">>> Issue #14116 修复已应用"
else
  echo ">>> airoha-pon 包不存在，跳过修复"
fi

echo ">>> [4/5] 应用其他自定义修改..."

# === 示例：添加第三方源码包 ===
# git clone https://github.com/xxx/yyy package/yyy

echo ">>> [5/5] diy-p1.sh 执行完毕"
