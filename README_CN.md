<h1 align="center">
  🛡️ OpenWrt Watchdog 看门狗安全守护插件 (luci-app-watchdog)
</h1>

<p align="center">
  <strong>高效率、规范化、模块化的 OpenWrt 路由器登录与安全防护插件</strong>
</p>

<p align="center">
  <img src="https://views.whatilearened.today/views/github/iamxiaojianzheng/luci-app-watchdog.svg">
  <a href="https://openwrt.org"><img alt="OpenWrt" src="https://img.shields.io/badge/OpenWrt-%E2%89%A519.07-ff0000?logo=openwrt&logoColor=white"></a>
  <a href="https://github.com/iamxiaojianzheng/luci-app-watchdog/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/iamxiaojianzheng/luci-app-watchdog?color=blue"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-Apache%202.0-green.svg"></a>
</p>

<p align="center">
  <strong>中文文档</strong> | <a href="README.md">English</a>
</p>

---

## 插件简介

`luci-app-watchdog` 是一款为 OpenWrt 路由器量身打造的高性能安全防护插件。能够实时监控 Web 管理后台与 SSH 登录状态，自动识别爆破与非法登录行为，并通过动态防火墙黑名单（适配 `nftables` 与 `iptables`）对攻击 IP 进行秒级封禁。

---

## 核心特性

- **模块化 Unix 架构**：彻底抛弃原本的 18KB 单体混杂脚本，重构为单一职责的模块库（`config`, `firewall`, `log_monitor`, `blacklist`, `attribution`, `utils`），结构严密易维护。
- **双防火墙引擎**：透明适配 OpenWrt 24.10+ 原生 `nftables` (`fw4`) 与旧版 `iptables` (`fw3` / `ipset`)。
- **零卡顿解封**：基于 RPCD API 网关，解封/修改黑名单即时生效，无需重启后台守护进程。
- **内核看门狗保护**：修复精准 PID 检索，彻底解决旧版本停止服务时误杀死 OpenWrt 系统硬件看门狗（`ubox watchdog`）引发崩溃重启的问题。
- **现代 LuCI 视图**：卡片式运行状态仪表盘，带日志语法颜色高亮、实时搜索过滤、自动滚动与日志下载。
- **双包管理器兼容**：全面支持 `.ipk` (`opkg`) 与新版 `.apk` (`apk-tools`) 安装包。

---

## 一键极速安装

在路由器的 SSH 终端中直接运行以下任一命令：

**使用 curl 命令：**
```bash
curl -fsSL https://raw.githubusercontent.com/iamxiaojianzheng/luci-app-watchdog/main/install.sh | sh
```

**使用 wget 命令：**
```bash
wget -O - https://raw.githubusercontent.com/iamxiaojianzheng/luci-app-watchdog/main/install.sh | sh
```

---

## 源码编译指南

将项目源码集成至 OpenWrt SDK 或编译树：

```bash
# 克隆仓库至 package 目录
git clone https://github.com/iamxiaojianzheng/luci-app-watchdog package/luci-app-watchdog

# 配置编译项
make menuconfig
# 进入路径: LuCI ---> 3. Applications ---> <*> luci-app-watchdog

# 执行编译
make package/luci-app-watchdog/compile V=s
```

---

## 规范项目架构

```
watchdog/files/
├── watchdog.init          # procd init 服务启动脚本 (具备精确 PID 匹配)
├── watchdog-call.libexec  # RPCD API 网关 (状态查询、解封、清空日志等)
└── watchdog/              # 模块化后台守护程序
    ├── watchdog           # 极简主程序入口 (< 50 行)
    └── lib/
        ├── utils.sh        # 高性能字符串与互斥锁辅助库
        ├── config.sh       # UCI 配置解析器
        ├── firewall.sh     # 防火墙抽象驱动 (nftables/iptables 策略模式)
        ├── log_monitor.sh  # Web & SSH 登录日志事件引擎
        ├── blacklist.sh    # 黑名单存储与防火墙集合同步
        └── attribution.sh  # IP 归属地查询与内存 Hash 缓存引擎
```

---

## 开源协议

本项目采用 [Apache License 2.0](LICENSE) 开源协议。
