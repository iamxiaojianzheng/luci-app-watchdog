#!/bin/sh
#
# OpenWrt Security Watchdog One-Click Installer & Manager
# Repository: https://github.com/iamxiaojianzheng/luci-app-watchdog
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_OWNER="iamxiaojianzheng"
REPO_NAME="luci-app-watchdog"
GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_openwrt() {
    if [ ! -f /etc/openwrt_release ]; then
        error "This script is intended for OpenWrt devices only!"
        exit 1
    fi
}

detect_pkg_manager() {
    if command -v opkg >/dev/null 2>&1; then
        PKG_CMD="opkg"
        PKG_EXT="ipk"
    elif command -v apk >/dev/null 2>&1; then
        PKG_CMD="apk"
        PKG_EXT="apk"
    else
        error "Neither opkg nor apk package manager was found on this system!"
        exit 1
    fi
    info "Detected package manager: $PKG_CMD ($PKG_EXT)"
}

detect_arch() {
    SYS_ARCH=""
    if [ "$PKG_CMD" = "opkg" ]; then
        SYS_ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | grep -v -E 'all|noarch' | tail -n 1 || echo "")
    fi
    if [ -z "$SYS_ARCH" ]; then
        SYS_ARCH=$(uname -m 2>/dev/null || echo "")
    fi
    info "Detected system architecture: ${SYS_ARCH:-generic}"
}

install_deps() {
    info "Checking and installing required dependencies..."
    if [ "$PKG_CMD" = "opkg" ]; then
        opkg update >/dev/null 2>&1 || true
        for pkg in curl bash tar; do
            if ! opkg list-installed | grep -q "^$pkg "; then
                info "Installing dependency: $pkg"
                opkg install "$pkg" || warn "Failed to install $pkg via opkg"
            fi
        done
    elif [ "$PKG_CMD" = "apk" ]; then
        apk update >/dev/null 2>&1 || true
        for pkg in curl bash tar; do
            info "Ensuring dependency: $pkg"
            apk add "$pkg" >/dev/null 2>&1 || warn "Failed to install $pkg via apk"
        done
    fi
}

install_plugin() {
    local raw_proxy="${GITHUB_PROXY:-$1}"
    local PROXY=""
    if [ -n "$raw_proxy" ] && echo "$raw_proxy" | grep -qE '^https?://'; then
        PROXY="${raw_proxy%/}/"
        info "Using specified GitHub proxy: $PROXY"
    else
        info "No proxy configured. (To use proxy: 'export GITHUB_PROXY=...' or 'curl ... | GITHUB_PROXY=... sh')"
    fi

    info "Fetching latest release information from GitHub..."
    local latest_json
    latest_json=$(curl -sL --connect-timeout 10 -H "User-Agent: OpenWrt-Installer" "$GITHUB_API" 2>/dev/null || echo "")

    # 1. 提取所有可能的 GitHub Release 资源下载链接 (IPK, APK, tar.gz, zip)
    local raw_urls
    raw_urls=$(echo "$latest_json" | grep -oE 'https://github\.com/[^"]+/releases/download/[^"]+' || echo "")

    # 2. 如果 API 受到 Rate Limit 限制或无返回，降级从网页 HTML 中提取
    if [ -z "$raw_urls" ]; then
        info "GitHub API restricted or returned empty, fetching via release page HTML..."
        local page_html
        page_html=$(curl -sL --connect-timeout 10 -H "User-Agent: Mozilla/5.0" "${PROXY}https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest" 2>/dev/null || echo "")
        raw_urls=$(echo "$page_html" | grep -oE '/iamxiaojianzheng/luci-app-watchdog/releases/download/[^"'\'' >]+' | sed 's|^|https://github.com|' || echo "")
    fi

    local raw_url=""
    # 优先筛选符合当前 CPU 架构的资源
    if [ -n "$SYS_ARCH" ]; then
        raw_url=$(echo "$raw_urls" | grep -i "$SYS_ARCH" | head -n 1 || echo "")
    fi
    # 查找带有 all 架构的通用安装包
    if [ -z "$raw_url" ]; then
        raw_url=$(echo "$raw_urls" | grep -i "all" | head -n 1 || echo "")
    fi
    # 查找 tar.gz 打包合集
    if [ -z "$raw_url" ]; then
        raw_url=$(echo "$raw_urls" | grep -i '\.tar\.gz' | head -n 1 || echo "")
    fi
    # 备选：拿第一个匹配到的任何资产链接
    if [ -z "$raw_url" ]; then
        raw_url=$(echo "$raw_urls" | head -n 1 || echo "")
    fi

    if [ -z "$raw_url" ]; then
        warn "No remote release binary found. Attempting local installation..."
        install_local
        return
    fi

    local download_url
    if echo "$raw_url" | grep -qE '^https?://'; then
        download_url="${PROXY}${raw_url}"
    else
        download_url="${PROXY}https://github.com${raw_url}"
    fi

    info "Downloading release asset: $download_url"
    local tmp_dir="/tmp/watchdog_installer_$$"
    mkdir -p "$tmp_dir"

    if echo "$download_url" | grep -q '\.tar\.gz'; then
        local tar_file="${tmp_dir}/package.tar.gz"
        curl -sL -o "$tar_file" "$download_url"

        if [ ! -s "$tar_file" ] || grep -qi "<html" "$tar_file" 2>/dev/null; then
            error "Failed to download release archive! File is empty or HTML error page."
            warn "Please check if GITHUB_PROXY is working or remove GITHUB_PROXY and retry."
            rm -rf "$tmp_dir"
            exit 1
        fi

        info "Extracting release archive..."
        tar -zxf "$tar_file" -C "$tmp_dir" 2>/dev/null || tar -xf "$tar_file" -C "$tmp_dir"
        
        batch_install_dir "$tmp_dir"
    else
        local pkg_file="${tmp_dir}/watchdog.${PKG_EXT}"
        curl -sL -o "$pkg_file" "$download_url"

        if [ ! -s "$pkg_file" ] || grep -qi "<html" "$pkg_file" 2>/dev/null; then
            error "Failed to download release package! File is empty or HTML error page."
            warn "Please check if GITHUB_PROXY is working or remove GITHUB_PROXY and retry."
            rm -rf "$tmp_dir"
            exit 1
        fi

        info "Installing standalone package..."
        batch_install_files "$pkg_file"
    fi

    rm -rf "$tmp_dir"
}

batch_install_dir() {
    local target_dir="$1"
    info "Installing extracted components in strict dependency order..."
    
    if [ "$PKG_CMD" = "opkg" ]; then
        local ipk_files
        ipk_files=$(find "$target_dir" -type f -name "*.ipk" 2>/dev/null | tr '\n' ' ')
        if [ -n "$ipk_files" ]; then
            info "Batch installing all IPK packages simultaneously..."
            opkg install --force-reinstall $ipk_files || {
                warn "Simultaneous install failed, retrying in strict dependency order..."
                
                # 1. 核心守护包
                local core_pkg
                core_pkg=$(find "$target_dir" -type f -name "watchdog_*.ipk" ! -name "luci-*" 2>/dev/null | head -n 1 || echo "")
                [ -n "$core_pkg" ] && { info " -> Step 1/3: Installing $(basename "$core_pkg")"; opkg install --force-reinstall "$core_pkg" || true; }

                # 2. LuCI 主程序界面包
                local app_pkg
                app_pkg=$(find "$target_dir" -type f -name "luci-app-watchdog_*.ipk" 2>/dev/null | head -n 1 || echo "")
                [ -n "$app_pkg" ] && { info " -> Step 2/3: Installing $(basename "$app_pkg")"; opkg install --force-reinstall "$app_pkg" || true; }

                # 3. 语言包
                local i18n_pkg
                i18n_pkg=$(find "$target_dir" -type f -name "luci-i18n-watchdog-*.ipk" 2>/dev/null | head -n 1 || echo "")
                [ -n "$i18n_pkg" ] && { info " -> Step 3/3: Installing $(basename "$i18n_pkg")"; opkg install --force-reinstall "$i18n_pkg" || true; }
            }
        else
            warn "No .ipk files found in extracted archive."
        fi
    else
        local apk_files
        apk_files=$(find "$target_dir" -type f -name "*.apk" 2>/dev/null | tr '\n' ' ')
        if [ -n "$apk_files" ]; then
            info "Installing discovered APK packages..."
            apk add --allow-untrusted $apk_files
        else
            warn "No .apk files found in extracted archive."
        fi
    fi
}

batch_install_files() {
    if [ "$PKG_CMD" = "opkg" ]; then
        opkg install --force-reinstall "$@"
    else
        apk add --allow-untrusted "$@"
    fi
}

install_local() {
    info "Searching for local ipk / apk packages..."
    batch_install_dir "/tmp"
}

post_install() {
    info "Configuring and starting Watchdog service..."
    /etc/init.d/watchdog stop 2>/dev/null || true
    command -v fuser >/dev/null 2>&1 && fuser -k -9 /tmp/watchdog/watchdog.lock 2>/dev/null || true
    rm -f /tmp/watchdog/watchdog.pid /tmp/watchdog/watchdog.lock /tmp/watchdog/logread.fifo 2>/dev/null || true

    /etc/init.d/watchdog enable 2>/dev/null || true
    /etc/init.d/watchdog restart 2>/dev/null || true

    info "Clearing LuCI cache & restarting rpcd/uhttpd..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true

    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN} OpenWrt Watchdog Plugin installed successfully!      ${NC}"
    echo -e "${GREEN} Access it via LuCI: Services -> Watch Dog            ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
}

main() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}     OpenWrt Watchdog One-Click Installer            ${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    check_openwrt
    detect_pkg_manager
    detect_arch
    install_deps
    install_plugin
    post_install
}

main "$@"
