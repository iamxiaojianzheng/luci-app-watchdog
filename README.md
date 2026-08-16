<h1 align="center">
  🛡️ OpenWrt Watchdog (luci-app-watchdog)
</h1>

<p align="center">
  <strong>High-performance, Modular Security Watchdog Plugin for OpenWrt Routers</strong>
</p>

<p align="center">
  <img src="https://views.whatilearened.today/views/github/iamxiaojianzheng/luci-app-watchdog.svg">
  <a href="https://openwrt.org"><img alt="OpenWrt" src="https://img.shields.io/badge/OpenWrt-%E2%89%A519.07-ff0000?logo=openwrt&logoColor=white"></a>
  <a href="https://github.com/iamxiaojianzheng/luci-app-watchdog/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/iamxiaojianzheng/luci-app-watchdog?color=blue"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-Apache%202.0-green.svg"></a>
</p>

<p align="center">
  <a href="README_CN.md">中文文档</a> | <strong>English</strong>
</p>

---

## Overview

`luci-app-watchdog` is a production-grade, highly optimized security watchdog plugin designed for OpenWrt devices. It actively monitors Web management console logins and SSH connections, automatically guarding against brute-force attacks by dynamically managing firewall IP blacklists (`nftables` / `iptables`).

---

## Key Features

- **Modular Unix Architecture**: Completely refactored with clean separation of concern modules (`config`, `firewall`, `log_monitor`, `blacklist`, `attribution`, `utils`).
- **Dual Firewall Engine**: Transparently supports OpenWrt 24.10+ `nftables` (`fw4`) and legacy `iptables` (`fw3` / `ipset`).
- **Zero-Downtime Unban**: RPCD API gateway allows instant blacklist removal directly from LuCI without restarting the daemon service.
- **Process Protection**: Fixed process killing logic using strict PID matching to prevent miskilling OpenWrt system hardware watchdogs.
- **Modern LuCI UX**: Features a card-based status dashboard, live log viewer with syntax color highlighting, auto-scroll, and real-time filter search.
- **Dual Package Support**: Fully compatible with both `.ipk` (`opkg`) and `.apk` (`apk-tools`) package managers.

---

## Quick One-Click Installation

Run either of the following commands in your OpenWrt SSH terminal:

**Via curl:**
```bash
curl -fsSL https://raw.githubusercontent.com/iamxiaojianzheng/luci-app-watchdog/main/install.sh | sh
```

**Via wget:**
```bash
wget -O - https://raw.githubusercontent.com/iamxiaojianzheng/luci-app-watchdog/main/install.sh | sh
```

---

## Manual Compilation

Add `luci-app-watchdog` to your OpenWrt SDK or source tree:

```bash
# Clone the repository into your OpenWrt package directory
git clone https://github.com/iamxiaojianzheng/luci-app-watchdog package/luci-app-watchdog

# Select the package in menuconfig
make menuconfig
# Navigate to: LuCI ---> 3. Applications ---> <*> luci-app-watchdog

# Compile the package
make package/luci-app-watchdog/compile V=s
```

---

## Architecture Overview

```
watchdog/files/
├── watchdog.init          # procd init service script with strict PID safety
├── watchdog-call.libexec  # RPCD API gateway (status, del_black, clear_log, etc.)
└── watchdog/              # Modular backend daemon
    ├── watchdog           # Lightweight main entrypoint (< 50 lines)
    └── lib/
        ├── utils.sh        # High-performance string manipulation & lock helpers
        ├── config.sh       # UCI configuration parser
        ├── firewall.sh     # Firewall abstraction driver (nftables/iptables strategy pattern)
        ├── log_monitor.sh  # Event stream engine for web & ssh login monitoring
        ├── blacklist.sh    # Blacklist store & firewall set synchronization
        └── attribution.sh  # IP Geo/Attribution engine with in-memory caching
```

---

## License

Distributed under the [Apache License 2.0](LICENSE).
