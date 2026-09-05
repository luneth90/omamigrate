# OmaMigrate

[English](README.md) | **简体中文**

> Omarchy Linux 全系统应用、配置、服务与 AI 凭据一键迁移与环境瞬移工具。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Omarchy%20%7C%20Arch%20Linux-blue?logo=archlinux)](https://omarchy.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](CHANGELOG.md)
[![Architecture](https://img.shields.io/badge/Arch-x86__64%20%7C%20aarch64-orange)](#跨硬件架构智能兼容)

---

## 项目背景

传统的点对点配置同步工具（如基于 Git 的 UI 插件）通常只能同步基础的用户配置文件（`~/.config/hypr`）。当您拿到一台新电脑时，依然面临繁重的手动配置成本：
- 手动重新安装几十个 GUI 桌面软件与开发应用；
- 手动重新配置主流代理服务（**sing-box**、**Mihomo / Clash Verge**、**v2rayA**、**daed** 等）及定时器；
- 手动重新登录所有的 **AI 命令行工具**（Claude Code、OpenAI Codex、Antigravity `agy`、xAI Grok）；
- **邮件与定时自动化服务** 因缺少 GPG 密钥、`pass` 密码库或用户 systemd 定时器而无法工作；
- 新老电脑用户名不同（如从 `alice` 变成 `bob`）时，因配置中残留的绝对路径报错。

**OmaMigrate** 专为彻底解决上述痛点而生，提供一套工业级的**全系统生态一键迁移引擎**：

```
[ 老电脑 (源机器) ]                                      [ 新电脑 (目标机器) ]
  ├── 显式应用清单 (自动过滤硬件驱动)                     ├── 差异化静默补齐安装 (yay/pacman)
  ├── 代理生态 (sing-box/Mihomo/Clash/v2rayA/daed) === LocalSend 隔空 / ===> ├── 还原系统服务并自启定时器
  ├── 邮件客户端配置、GPG与pass密码库     迁移归档包 (tar)    ├── 还原 GPG 密钥与密码库
  ├── AI 全套登录 Session (Claude/Agy)                    ├── 继承登录态，免扫码免登录
  └── 桌面环境与终端配置                                  └── 自动纠偏用户名路径并热重载
```

---

## 核心技术特性

### 1. 跨硬件架构智能兼容 (ARM64 ↔ x86_64)
- 自动提取当前机器显式安装的应用清单（`pacman -Qqe`）。
- **智能硬件黑名单过滤**：自动剔除 Apple Silicon (Asahi Linux) 或特定机型的底层驱动与内核（如 `linux-asahi`, `m1n1`, `uboot`, `speakersafetyd`）。
- **效果**：无论老电脑是 **M 系列 Mac (aarch64)**，新电脑是 **Intel/AMD PC (x86_64)** 还是相反，在新机器上执行还原时，都会由新机在线拉取专为新机 CPU 编译的二进制包，绝无架构冲突。

### 2. 全主流代理生态深度支持 (Multi-Proxy Ready)
无论您偏好系统级常驻守护进程还是 GUI 桌面客户端，均可无缝打包还原并在新机自动唤醒自启：
- **系统核心服务 (Daemon & Transparent Proxy)**：
  - **sing-box**：自动备份还原 `/etc/sing-box/` 规则配置、安全组权限（`640 root:sing-box`）、自动轮换脚本及 `sing-box.service` / timer 定时器。
  - **Mihomo (原 Clash.Meta)**：完整备份 `/etc/mihomo/` 系统核心配置、`~/.config/mihomo/` 用户配置与 `mihomo.service`。
  - **v2rayA / Xray / v2ray**：完整备份 `/etc/v2raya/`、`/etc/xray/`、`/etc/v2ray/` 与对应后台服务并自启。
  - **daed / daed-next**：支持基于 eBPF 的高性能透明代理配置 `/etc/daed/` 与后台常驻服务。
- **桌面 GUI 代理客户端**：
  - **Clash Verge / Clash Verge Rev** (`~/.config/clash-verge`, `~/.config/clash-verge-rev`)
  - **Clash Nyanpasu** (`~/.config/clash-nyanpasu`)
  - **Mihomo Party** (`~/.config/mihomo-party`)
  - **Flclash** (`~/.config/flclash`)
  - **NekoBox / Nekoray / Matsuri** (`~/.config/nekoray`, `~/.config/Matsuri`)
  - 完整保留订阅节点、分流规则组、模式切换与本地缓存，新机开箱即连。
- **终端与全局代理辅助**：
  - 自动备份与还原 **Proxychains-ng**（`~/.proxychains`、`/etc/proxychains.conf`）与终端代理函数。

### 3. 邮件客户端与定时自动化工作流完整迁移
- **主流邮件客户端无缝迁移**：
  - **桌面客户端（Thunderbird 等）**：完整打包并还原 `~/.thunderbird/` 用户 Profile、账户配置、离线邮箱缓存与本地凭证环，新机打开即用，无需重新配置 IMAP/SMTP 账户。
  - **终端/CLI 客户端**：完整支持 `Himalaya`、`Aerc`、`Neomutt` 等命令行邮件客户端配置目录。
- **凭据与密钥库安全继承**：
  - 完整打包 **GPG 密钥库**（`~/.gnupg`）与 **Unix 密码管理器**（`~/.password-store`），确保通过 `pass show` 调取的应用密码在新机即刻可用。
- **自动化工作流与后台定时器**：
  - 自动保留 `~/.local/bin/` 里的邮件管理/分类/清理脚本（例如基于 `agy` 或各类模型的自动化工具）。
  - 自动注册并激活对应的 `systemd --user` 每日定时器。

### 4. AI 模型工具与系统 Keyring 免扫码登录 (Zero-Login)
- **Linux 桌面 Secret Service 密钥库完整同步**：
  - 自动备份与还原 **Linux 系统 Keyring** (`~/.local/share/keyrings/`)，完整包含 **Google Antigravity (`agy`)**、**VS Code**、**GitHub CLI** 与 Chrome 等应用在 Secret Service 中托管的 OAuth Token 与机密。
- **主流 AI 开发工具登录态与 Session 全量迁移**：
  - **Google Antigravity (`agy`)** (`~/.gemini/antigravity-cli/` 及系统 Keyring)
  - **OpenAI Codex** (`~/.codex/auth.json`, `~/.codex/config.toml`)
  - **Claude Code** (`~/.claude.json`, `~/.claude/`)
  - **xAI Grok** (`~/.grok/auth.json`)
  - **GitHub CLI (`gh`)** (`~/.config/gh/hosts.yml`)
- 新电脑还原后直接继承登录态，开箱即用。

> [!TIP]
> **最佳实践建议（系统登录密码）**：
> 强烈建议在新电脑上安装系统时，设置与老电脑**相同的用户登录密码**。
> - **原理解析**：Linux 桌面（SDDM/GDM 等）的 PAM 认证模块会在开机登录时，自动使用登录密码静默解锁系统密钥环（Keyring）。若新老密码一致，`agy`、VS Code、GitHub CLI 等工具可实现真正的零弹窗、免扫码无缝衔接。
> - **若新电脑设置了不同密码**：首次启动 `agy` 或 VS Code 时，桌面会弹窗提示一次“输入密码以解锁登录密钥环”，输入老电脑的原密码即可解密；后续可通过系统密钥管理工具（如 `seahorse`）将密钥环密码同步为新密码。

### 5. 跨用户名绝对路径智能自适应
- 如果老机器用户名是 `alice`，新机器用户名是 `bob`，还原引擎会自动检测并批量将配置文件（`.codex`, `.claude.json`, `antigravity-cli`, `git/config`）中的硬编码旧路径动态替换为新主机的 `$HOME`。

### 6. 完全幂等、高容错的还原引擎
- **拦截 root 误触**：开头严格检测并拒绝以 `sudo` 运行，防止把家目录文件所有权污染为 `root:root`。
- **自动解 pacman 锁**：自动检测并清理因网络超时中断遗留的 `/var/lib/pacman/db.lck` 锁。
- **只读覆盖保护**：在覆盖前自动对家目录执行 `u+w` 赋权，彻底消除 Git pack 只读文件导致的 `Permission denied` 报错。
- **断点续跑**：若因网络波动中断，随时重复运行 `./restore.sh`，自动从断点继续，绝不报错或损坏已有配置。

---

## 快速使用指南

### 第一步：在老电脑上一键打包

在终端执行：

```bash
omamigrate export
```

*(过程中会提示输入一次 `sudo` 密码以安全读取 `/etc/sing-box/config.json`)*。

打包完成后，在主目录生成 `~/omarchy-migration.tar.gz`。

---

### 第二步：传输到新电脑

**方式 A：LocalSend 局域网隔空快传（推荐）**
```bash
omamigrate send
```
两台电脑都打开 LocalSend，直接将压缩包隔空投送到新电脑的 `~/Downloads`。

**方式 B：局域网终端 SCP 传输**
```bash
scp ~/omarchy-migration.tar.gz 新用户名@新电脑IP:~/Downloads/
```

---

### 第三步：在新电脑上一键还原

在新电脑上直接执行：

```bash
omamigrate restore ~/Downloads/omarchy-migration.tar.gz
```

*若新电脑尚未安装 omamigrate 命令，也完全可以裸执行压缩包内置的原生引擎：*

```bash
mkdir -p ~/omarchy-restore && tar -xzf ~/Downloads/omarchy-migration.tar.gz -C ~/omarchy-restore
cd ~/omarchy-restore && ./restore.sh
```

还原引擎会自动补齐缺失的应用软件、恢复各类凭据与服务、重映射路径并秒级重载桌面。

---

## Omarchy 桌面插件集成

将 OmaMigrate 接入您的 Omarchy 桌面环境：

1. **软链接至 Omarchy 插件库**：
   ```bash
   ln -s ~/Projects/omamigrate ~/.config/omarchy/plugins/omamigrate
   omarchy-shell shell rescanPlugins
   ```
2. **软链接命令行至全局 PATH**：
   ```bash
   ln -s ~/Projects/omamigrate/bin/omamigrate ~/.local/bin/omamigrate
   ```
3. **绑定桌面全局快捷键**（编辑 `~/.config/hypr/bindings.lua`）：
   ```lua
   o.bind("SUPER + SHIFT + M", "OmaMigrate", "omarchy-shell shell summon omamigrate '{}'")
   ```

---

## 自动化测试

项目内置了自动化语法与执行完整性检查脚本：

```bash
./tests/test_syntax.sh
```

---

## 开源协议

基于 MIT License 开源 © 2026 OmaMigrate 项目组
