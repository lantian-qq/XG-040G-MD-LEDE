#!/bin/bash
#=================================================
# XG-040G-MD (Nokia) OpenWrt 编译脚本
# 基于 coolsnowwolf/lede (Lean's LEDE)
# 参考: https://github.com/xuxin1955/Actions
#=================================================

set -e

# ==================== 配置区域 ====================

# 源码仓库 (coolsnowwolf/lede)
REPO_URL="https://github.com/coolsnowwolf/lede.git"
REPO_BRANCH="master"

# 设备配置
DEVICE_NAME="nokia_xg-040g-md"
TARGET="airoha"
SUBTARGET="an7581"

# 编译线程 (默认使用 CPU 核心数)
THREADS=$(nproc 2>/dev/null || echo 4)

# 工作目录
WORK_DIR="$(pwd)/openwrt_build"
OPENWRT_DIR="${WORK_DIR}/openwrt"

# 时区
TZ="Asia/Shanghai"

# ==================== 颜色输出 ====================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# ==================== 系统依赖安装 ====================

install_dependencies() {
    step "安装编译依赖..."
    
    # 检测系统类型
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y \
            ack antlr3 asciidoc autoconf automake autopoint binutils \
            bison build-essential bzip2 ccache clang cmake cpio curl \
            device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
            g++-multilib git gnutls-dev gperf haveged help2man intltool \
            jq lib32gcc-s1 libc6-dev-i386 libelf-dev libfuse-dev libglib2.0-dev \
            libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev \
            libncursesw5-dev libpython3-dev libreadline-dev libssl-dev libtool \
            lrzsz msmtp nano ninja-build p7zip p7zip-full patch pkgconf \
            python3 python3-pip python3-ply python3-pyelftools python3-setuptools \
            qemu-utils rsync scons squashfs-tools subversion swig texinfo \
            uglifyjs unzip vim wget xmlto xxd zlib1g-dev || true
    elif command -v yum &> /dev/null; then
        sudo yum groupinstall -y "Development Tools"
        sudo yum install -y \
            ack antlr3 asciidoc autoconf automake autopoint binutils \
            bison bzip2 clang cmake cpio curl device-tree-compiler ecj \
            flex gawk gcc gcc-c++ git gnutls-devel gperf haveged help2man \
            intltool libcap-devel libtool libxml2-devel lrzlz make msmtp \
            nano ncurses-devel ninja-build openssl-devel p7zip p7zip-plugins \
            patch python3-devel python3-pip python3-ply python3-setuptools \
            qemu-utils rsync scons subversion swig texinfo uglifyjs unzip \
            vim wget xxd zlib-devel || true
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy --needed --noconfirm \
            ack antlr3 asciidoc autoconf automake autopoint binutils \
            bison build-essential bzip2 clang cmake cpio curl device-tree-compiler \
            ecj fastjar flex gawk gcc gettext git glib2 gmp grep help2man \
            intltool jq lib32-glibc libelf libfuse libtool lrzlz make nano \
            ninja openssl p7zip patch python python-pip python-ply python-setuptools \
            qemu-user-static rsync scons subversion swig texinfo unzip vim wget \
            xxd zlib || true
    fi
    
    info "依赖安装完成"
}

# ==================== 安装 mkbootimg ====================

install_mkbootimg() {
    step "安装 mkbootimg..."
    
    if command -v mkbootimg &> /dev/null; then
        info "mkbootimg 已安装"
        return
    fi
    
    # 下载预编译的 mkbootimg
    MKBOOTIMG_URL="https://github.com/xuxin1955/depend_ubuntu2204_openwrt/releases/download/ubuntu_26.04_LTS_mkbootimg/mkbootimg_34.0.5-12build1_all.deb"
    
    if [[ -f /etc/debian_version ]]; then
        wget -q "${MKBOOTIMG_URL}" -O /tmp/mkbootimg.deb
        sudo dpkg -i /tmp/mkbootimg.deb || sudo apt-get install -f -y
        rm -f /tmp/mkbootimg.deb
    else
        warn "非 Debian 系统，请手动安装 mkbootimg"
        warn "或从 https://github.com/nicso/mkbootimg 获取源码编译"
    fi
    
    if command -v mkbootimg &> /dev/null; then
        info "mkbootimg 安装成功"
    else
        warn "mkbootimg 可能未正确安装，继续编译..."
    fi
}

# ==================== 克隆源码 ====================

clone_source() {
    step "克隆 coolsnowwolf/lede 源码..."
    
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"
    
    if [ -d "openwrt" ]; then
        info "源码目录已存在，更新中..."
        cd openwrt
        git pull origin "${REPO_BRANCH}"
    else
        git clone "${REPO_URL}" -b "${REPO_BRANCH}" openwrt
        cd openwrt
    fi
    
    git log --oneline -1
    info "源码准备完成"
}

# ==================== DIY 自定义 ====================

diy_p1() {
    step "执行 DIY Part 1..."
    
    cd "${OPENWRT_DIR}"
    
    # 修改默认 IP
    sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate 2>/dev/null || true
    
    info "DIY Part 1 完成"
}

diy_p2() {
    step "执行 DIY Part 2 (添加插件)..."
    
    cd "${OPENWRT_DIR}"
    
    # TurboACC 加速
    info "添加 TurboACC..."
    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh 2>/dev/null && \
        bash add_turboacc.sh 2>/dev/null || warn "TurboACC 添加失败"
    rm -f add_turboacc.sh
    
    # 温度状态插件
    info "添加温度状态插件..."
    git clone --depth 1 https://github.com/gSpotx2f/luci-app-temp-status package/luci-app-temp-status 2>/dev/null || true
    git clone --depth 1 https://github.com/gSpotx2f/luci-app-cpu-perf package/luci-app-cpu-perf 2>/dev/null || true
    
    # OpenClash
    info "添加 OpenClash..."
    git clone --depth 1 https://github.com/vernesong/OpenClash.git package/luci-app-openclash 2>/dev/null || true
    
    info "DIY Part 2 完成"
}

# ==================== 更新 Feeds ====================

update_feeds() {
    step "更新和安装 feeds..."
    
    cd "${OPENWRT_DIR}"
    
    ./scripts/feeds update -a
    ./scripts/feeds install -a -f
    
    info "Feeds 更新完成"
}

# ==================== 生成配置 ====================

generate_config() {
    step "生成编译配置..."
    
    cd "${OPENWRT_DIR}"
    
    # 清理旧配置
    rm -f .config
    
    # 生成最小配置
    cat > .config << 'EOF'
# ==================== 目标设备 ====================
CONFIG_TARGET_airoha=y
CONFIG_TARGET_airoha_an7581=y
CONFIG_TARGET_PROFILE="DEVICE_nokia_xg-040g-md"
CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md=y

# ==================== PON 支持 ====================
# Airoha PON 驱动 (xPON for AN7581)
CONFIG_PACKAGE_kmod-airoha-pon=y
CONFIG_PACKAGE_kmod-airoha-xpon-en757x=y

# ==================== Airoha NPU ====================
CONFIG_PACKAGE_airoha-en7581-npu-firmware=y
CONFIG_PACKAGE_airoha-en7581-mt7996-npu-firmware=y
CONFIG_PACKAGE_airoha-en8811h-firmware=y
CONFIG_PACKAGE_kmod-phy-airoha-en8811h=y
CONFIG_PACKAGE_luci-app-airoha-npu=y

# ==================== LuCI 支持 ====================
CONFIG_PACKAGE_luci=y
CONFIG_LUCI_AUTOREMOVE=y
CONFIG_LUCI_INCLUDE_acme=y
CONFIG_LUCI_INCLUDE_freeradius2=y
CONFIG_LUCI_INCLUDE_haproxy=y
CONFIG_LUCI_INCLUDE_rpcd=y

# LuCI 中文语言包
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y

# LuCI 主题
CONFIG_PACKAGE_luci-theme-bootstrap=y

# ==================== 网络工具 ====================
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_luci-app-commands=y

# ==================== 防火墙 ====================
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y

# ==================== 网络管理 ====================
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-i18n-ddns-zh-cn=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y
CONFIG_PACKAGE_luci-app-vlmcsd=y

# ==================== 文件共享 ====================
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y

# ==================== 磁盘管理 ====================
CONFIG_PACKAGE_luci-app-diskman=y

# ==================== 代理工具 ====================
CONFIG_PACKAGE_luci-app-openclash=y

# ==================== 系统监控 ====================
CONFIG_PACKAGE_luci-app-temp-status=y
CONFIG_PACKAGE_luci-app-cpu-perf=y
CONFIG_PACKAGE_luci-app-turboacc=y

# ==================== 其他功能 ====================
CONFIG_PACKAGE_luci-app-nlbwmon=y
CONFIG_PACKAGE_luci-i18n-nlbwmon-zh-cn=y
CONFIG_PACKAGE_luci-app-accesscontrol=y
CONFIG_PACKAGE_luci-app-attendedsysupgrade=y
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_luci-app-openvpn=y
CONFIG_PACKAGE_luci-i18n-openvpn-zh-cn=y
EOF
    
    # 使用 defconfig 生成完整配置
    make defconfig
    
    info "配置生成完成"
}

# ==================== 下载软件包 ====================

download_packages() {
    step "下载软件包..."
    
    cd "${OPENWRT_DIR}"
    
    make download -j"${THREADS}" || make download -j1
    
    # 清理下载失败的文件
    find dl -type f -size 0 -delete 2>/dev/null || true
    find dl -type f -name '*.part' -delete 2>/dev/null || true
    
    info "下载完成"
    du -sh dl
}

# ==================== 编译固件 ====================

compile_firmware() {
    step "开始编译固件 (线程数: ${THREADS})..."
    
    cd "${OPENWRT_DIR}"
    
    # 清理之前可能的失败编译
    make clean 2>/dev/null || true
    
    # 编译
    if make -j"${THREADS}"; then
        info "编译成功!"
    else
        warn "编译失败，尝试单线程编译..."
        make -j1 V=s
        if [ $? -eq 0 ]; then
            info "单线程编译成功!"
        else
            error "编译失败，请检查错误日志"
            exit 1
        fi
    fi
}

# ==================== 整理输出 ====================

organize_output() {
    step "整理编译产物..."
    
    cd "${OPENWRT_DIR}"
    
    # 查找固件目录
    FIRMWARE_DIR=$(find bin/targets -maxdepth 2 -type d | head -1)
    
    if [ -z "${FIRMWARE_DIR}" ] || [ ! -d "${FIRMWARE_DIR}" ]; then
        error "未找到固件目录"
        exit 1
    fi
    
    cd "${FIRMWARE_DIR}"
    
    # 删除 packages 目录节省空间
    rm -rf packages
    
    # 创建输出目录
    OUTPUT_DIR="${WORK_DIR}/output_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${OUTPUT_DIR}"
    
    # 复制固件文件
    cp -f *.bin "${OUTPUT_DIR}/" 2>/dev/null || true
    cp -f *.img.gz "${OUTPUT_DIR}/" 2>/dev/null || true
    cp -f *.manifest "${OUTPUT_DIR}/" 2>/dev/null || true
    cp -f *.md5sums "${OUTPUT_DIR}/" 2>/dev/null || true
    cp -f config-* "${OUTPUT_DIR}/" 2>/dev/null || true
    cp -f feeds.conf.default "${OUTPUT_DIR}/" 2>/dev/null || true
    cp -f .config "${OUTPUT_DIR}/" 2>/dev/null || true
    
    info "固件已整理到: ${OUTPUT_DIR}"
    
    # 显示固件信息
    echo ""
    echo "=========================================="
    echo "  XG-040G-MD 固件编译完成"
    echo "=========================================="
    echo ""
    ls -lh "${OUTPUT_DIR}"
    echo ""
    echo "固件位置: ${OUTPUT_DIR}"
    echo "管理地址: 192.168.10.1"
    echo "默认账号: root / 无密码"
    echo ""
}

# ==================== 主函数 ====================

show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -d, --deps          仅安装依赖"
    echo "  -c, --clone         仅克隆源码"
    echo "  -s, --setup         完整设置 (依赖+克隆+DIY+feeds+配置)"
    echo "  -b, --build         仅编译 (需要先运行 --setup)"
    echo "  -f, --full          完整流程 (依赖+克隆+DIY+feeds+配置+编译)"
    echo "  -t, --threads N     设置编译线程数 (默认: CPU核心数)"
    echo ""
}

main() {
    local mode="full"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--deps)
                mode="deps"
                shift
                ;;
            -c|--clone)
                mode="clone"
                shift
                ;;
            -s|--setup)
                mode="setup"
                shift
                ;;
            -b|--build)
                mode="build"
                shift
                ;;
            -f|--full)
                mode="full"
                shift
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            *)
                error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "=========================================="
    echo "  XG-040G-MD (Nokia) OpenWrt 编译脚本"
    echo "  基于 coolsnowwolf/lede (Lean's LEDE)"
    echo "=========================================="
    echo ""
    echo "设备: ${DEVICE_NAME}"
    echo "目标: ${TARGET}/${SUBTARGET}"
    echo "线程: ${THREADS}"
    echo "模式: ${mode}"
    echo ""
    
    case "${mode}" in
        deps)
            install_dependencies
            install_mkbootimg
            ;;
        clone)
            clone_source
            ;;
        setup)
            install_dependencies
            install_mkbootimg
            clone_source
            diy_p1
            diy_p2
            update_feeds
            generate_config
            ;;
        build)
            download_packages
            compile_firmware
            organize_output
            ;;
        full)
            install_dependencies
            install_mkbootimg
            clone_source
            diy_p1
            diy_p2
            update_feeds
            generate_config
            download_packages
            compile_firmware
            organize_output
            ;;
    esac
    
    info "完成!"
}

# 执行主函数
main "$@"
