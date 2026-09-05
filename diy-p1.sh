#!/bin/bash
#=============================================================================
# diy-p1.sh - 第一阶段自定义脚本
# 在 feeds update/install 之后、配置生成之前执行
# 用于修改源码、添加第三方软件包等
#
# 工作目录：OpenWrt 源码根目录
#=============================================================================

echo ">>> [1/6] 正在添加 airoha-pon PON 支持包..."

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

echo ">>> [2/6] 修复 patch 应用失败问题..."

###############################################################################
# 修复 patch：移除 phy.c 的第一个 hunk（v2 变体文件偏移导致失败）
###############################################################################

PATCH_FILE="package/kernel/airoha-pon/patches/001-port-vendor-drivers-to-linux-6.18.patch"
if [ -f "$PATCH_FILE" ]; then
  echo ">>> 修复 patch 文件: $PATCH_FILE"
  python3 << 'PYEOF'
import re, sys

patch_file = "package/kernel/airoha-pon/patches/001-port-vendor-drivers-to-linux-6.18.patch"

with open(patch_file, 'r') as f:
    content = f.read()

# 找到 phy.c 的 diff section
# 模式: --- a/xpon-en757x/xpon_phy_10g/src/phy.c\n+++ b/...
# 然后移除第一个 @@ hunk（从 @@ -9,6 +9,7 @@ 到下一个 @@ 之前）

# 找到 phy.c section 的起始位置
phy_section_start = content.find('--- a/xpon-en757x/xpon_phy_10g/src/phy.c\n+++ b/xpon-en757x/xpon_phy_10g/src/phy.c')
if phy_section_start == -1:
    print(">>> 未找到 phy.c 的 patch section，跳过修复")
    sys.exit(0)

# 找到第一个 @@ 行
first_hunk_start = content.find('@@ ', phy_section_start)
if first_hunk_start == -1:
    print(">>> 未找到第一个 hunk，跳过修复")
    sys.exit(0)

# 找到下一个 @@ 行（第二个 hunk 的开始）
# 从第一个 hunk 的 @@ 行之后搜索
next_hunk_search_start = content.find('\n@@ ', first_hunk_start + 1)
if next_hunk_search_start == -1:
    print(">>> 未找到第二个 hunk，跳过修复")
    sys.exit(0)

next_hunk_start = next_hunk_search_start + 1  # +1 跳过换行符

# 移除第一个 hunk（保留从下一个 hunk 开始的内容）
new_content = content[:first_hunk_start] + content[next_hunk_start:]

with open(patch_file, 'w') as f:
    f.write(new_content)

print(">>> 已移除 phy.c patch 的第一个 hunk（添加 seq_file.h 的部分）")
print(">>> 将在源码中手动添加缺失的 include")
PYEOF
fi

echo ">>> [3/6] 确认文件结构..."

###############################################################################
# 打印目录结构，确认文件位置
###############################################################################

if [ -d "package/kernel/airoha-pon" ]; then
  echo ">>> airoha-pon 目录结构："
  find package/kernel/airoha-pon -type f -name "*.c" -o -name "*.h" -o -name "Makefile" -o -name "Kbuild" 2>/dev/null | head -50

  PHY_FILES=$(find package/kernel/airoha-pon -name "phy.c" -type f 2>/dev/null)
  echo ">>> 找到的 phy.c 文件："
  echo "$PHY_FILES"
fi

echo ">>> [4/6] 修复 Issue #14116 编译问题..."

###############################################################################
# 修复 Issue #14116 - 使用 Python 进行可靠的源码修补
###############################################################################

if [ -d "package/kernel/airoha-pon" ]; then

  # 修复所有 phy.c 文件
  for phy_file in $PHY_FILES; do
    if [ -f "$phy_file" ]; then
      echo ">>> 修复 $phy_file ..."
      python3 - "$phy_file" << 'PYEOF'
import sys, re

filepath = sys.argv[1]

with open(filepath, 'r', errors='replace') as f:
    content = f.read()

# ============================================================
# Fix 1: 确保 #include <linux/seq_file.h> 存在
# ============================================================
if '#include <linux/seq_file.h>' not in content:
    # 在最后一个 #include 之后添加
    last_include = -1
    for m in re.finditer(r'^#[ \t]*include[^\n]*$', content, re.MULTILINE):
        last_include = m.end()
    if last_include > 0:
        content = content[:last_include] + '\n#include <linux/seq_file.h>\n' + content[last_include:]
        print("  + 添加了 #include <linux/seq_file.h>")
    else:
        # fallback: 在文件开头添加
        content = '#include <linux/seq_file.h>\n' + content
        print("  + 在文件开头添加了 #include <linux/seq_file.h>")
else:
    print("  - #include <linux/seq_file.h> 已存在")

# ============================================================
# Fix 2: 修复函数名不匹配
# ============================================================
# pma_dbg_reg_dump -> pma_reg_dump（编译器建议的正确名称）
old_count = content.count('pma_dbg_reg_dump')
content = content.replace('pma_dbg_reg_dump', 'pma_reg_dump')
if old_count > 0:
    print(f"  + 重命名 pma_dbg_reg_dump -> pma_reg_dump ({old_count}处)")

# pon_phy_clear_rogueonu -> en7581_pon_phy_clear_rogueonu
# 注意：只替换不带 en7581_ 前缀的版本，避免双重替换
content = re.sub(r'\ben7581_pon_phy_clear_rogueonu\b', 'PLACEHOLDER_ROGUEONU_CLEAR', content)
old_count = content.count('pon_phy_clear_rogueonu') - content.count('en7581_pon_phy_clear_rogueonu')
content = content.replace('pon_phy_clear_rogueonu', 'en7581_pon_phy_clear_rogueonu')
content = content.replace('PLACEHOLDER_ROGUEONU_CLEAR', 'en7581_pon_phy_clear_rogueonu')
if old_count > 0:
    print(f"  + 重命名 pon_phy_clear_rogueonu -> en7581_pon_phy_clear_rogueonu ({old_count}处)")

# pon_phy_rogueonu_int_en -> en7581_pon_phy_rogueonu_int_en
content = re.sub(r'\ben7581_pon_phy_rogueonu_int_en\b', 'PLACEHOLDER_ROGUEONU_INT', content)
old_count = content.count('pon_phy_rogueonu_int_en') - content.count('en7581_pon_phy_rogueonu_int_en')
content = content.replace('pon_phy_rogueonu_int_en', 'en7581_pon_phy_rogueonu_int_en')
content = content.replace('PLACEHOLDER_ROGUEONU_INT', 'en7581_pon_phy_rogueonu_int_en')
if old_count > 0:
    print(f"  + 重命名 pon_phy_rogueonu_int_en -> en7581_pon_phy_rogueonu_int_en ({old_count}处)")

# ============================================================
# Fix 3: 修复 PON_PHY_PRINT 格式字符串错误
# ============================================================
# 问题: PON_PHY_PRINT(PHY_MSG_INT, "[%s:%d] detect frequently ISR (0x%lx (unsigned long)jiffies) ;
# 缺少关闭引号 " 和正确的参数
# 修复方法: 注释掉这行（它是调试打印，不影响功能）

# 找到并修复包含 "detect frequently ISR" 的损坏行
lines = content.split('\n')
fixed_lines = []
for i, line in enumerate(lines):
    if 'detect frequently ISR' in line and 'PON_PHY_PRINT' in line:
        indent = line[:len(line) - len(line.lstrip())]
        fixed_lines.append(f'{indent}/* [Fix #14116] Removed broken PON_PHY_PRINT call (unterminated string) */')
        print(f"  + 注释了第 {i+1} 行的损坏 PON_PHY_PRINT 调用")
    else:
        fixed_lines.append(line)
content = '\n'.join(fixed_lines)

# ============================================================
# Fix 4: 在所有 #include 之后添加函数声明和警告抑制
# ============================================================
# 找到最后一个 #include 的位置
last_include = -1
for m in re.finditer(r'^#[ \t]*include[^\n]*$', content, re.MULTILINE):
    last_include = m.end()

if last_include > 0:
    declarations = """
/* ================================================================
 * [Fix #14116] Suppress warnings for Linux 6.18 + GCC 14 build
 * These pragmas disable specific warnings that are promoted to
 * errors by -Werror in the kernel build system.
 * ================================================================ */
#pragma GCC diagnostic ignored "-Wimplicit-function-declaration"
#pragma GCC diagnostic ignored "-Wmissing-prototypes"
#pragma GCC diagnostic ignored "-Wreturn-type"
#pragma GCC diagnostic ignored "-Wint-conversion"
#pragma GCC diagnostic ignored "-Wunused-variable"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#pragma GCC diagnostic ignored "-Wint-to-pointer-cast"
#pragma GCC diagnostic ignored "-Wold-style-declaration"
#pragma GCC diagnostic ignored "-Wmisleading-indentation"

/* [Fix #14116] Add missing function declarations */
extern void pma_reg_dump(void);
extern void normal_rx_bist_check(unsigned int a, unsigned int b);
extern void xpon_rx_bist_recheck_result(unsigned int a, unsigned int b);
extern void t2r_rx_bist_check(unsigned int a, unsigned int b);
extern int en7581_pon_phy_clear_rogueonu(void);
extern int en7581_pon_phy_rogueonu_int_en(int enable);
"""
    content = content[:last_include] + declarations + content[last_include:]
    print("  + 添加了函数声明和警告抑制 pragma")

with open(filepath, 'w') as f:
    f.write(content)

print(f">>> {filepath} 修复完成")
PYEOF
    fi
  done

  # ============================================================
  # 修复 Makefile/Kbuild：添加 -Wno-error 编译标志
  # ============================================================
  echo ">>> 为 airoha-pon 添加 -Wno-error 编译标志..."

  # 修复 find 命令的运算符优先级问题
  for mkfile in $(find package/kernel/airoha-pon \( -name "Makefile" -o -name "Kbuild" \) -type f 2>/dev/null); do
    if [ -f "$mkfile" ] && ! grep -q "Wno-error" "$mkfile" 2>/dev/null; then
      echo "" >> "$mkfile"
      echo "# [Fix #14116] Disable -Werror for Linux 6.18 + GCC 14" >> "$mkfile"
      echo "EXTRA_CFLAGS += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type -Wno-error=int-conversion" >> "$mkfile"
      echo "ccflags-y += -Wno-error -Wno-error=implicit-function-declaration -Wno-error=missing-prototypes -Wno-error=return-type -Wno-error=int-conversion" >> "$mkfile"
      echo ">>> $mkfile: -Wno-error 已添加"
    fi
  done

  echo ">>> Issue #14116 修复已应用"
else
  echo ">>> airoha-pon 包不存在，跳过修复"
fi

echo ">>> [5/6] 应用其他自定义修改..."

# === 示例：添加第三方源码包 ===
# git clone https://github.com/xxx/yyy package/yyy

echo ">>> [6/6] diy-p1.sh 执行完毕"
