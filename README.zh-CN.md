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
- 手动重新配置 **sing-box** 代理核心、轮换脚本与系统级定时器；
- 手动重新登录所有的 **AI 命令行工具**（Claude Code、OpenAI Codex、Antigravity `agy`、xAI Grok）；
- **AI 邮箱自动清理系统**（`icloud-mail-triage`）因缺少 GPG 密钥与 `pass` 密码库而鉴权失败；
- 新老电脑用户名不同（如从 `xiaowei` 变成 `luneth90`）时，因配置中残留的绝对路径报错。

**OmaMigrate** 专为彻底解决上述痛点而生，提供一套工业级的**全系统生态一键迁移引擎**：

```
[ 老电脑 (源机器) ]                                      [ 新电脑 (目标机器) ]
  ├── 显式应用清单 (自动过滤硬件驱动)                     ├── 差异化静默补齐安装 (yay/pacman)
  ├── sing-box 核心配置与系统定时器   === LocalSend 隔空 / ===> ├── 还原系统服务并自启定时器
  ├── 邮箱清理脚本、GPG密钥与pass库       迁移归档包 (tar)    ├── 还原 GPG 密钥与密码库
  ├── AI 全套登录 Session (Claude/Agy)                    ├── 继承登录态，免扫码免登录
  └── 桌面环境与终端配置                                  └── 自动纠偏用户名路径并热重载
```

---

## 核心技术特性

### 1. 跨硬件架构智能兼容 (ARM64 ↔ x86_64)
- 自动提取当前机器显式安装的应用清单（`pacman -Qqe`）。
- **智能硬件黑名单过滤**：自动剔除 Apple Silicon (Asahi Linux) 或特定机型的底层驱动与内核（如 `linux-asahi`, `m1n1`, `uboot`, `speakersafetyd`）。
- **效果**：无论老电脑是 **M 系列 Mac (aarch64)**，新电脑是 **Intel/AMD PC (x86_64)** 还是相反，在新机器上执行还原时，都会由新机在线拉取专为新机 CPU 编译的二进制包，绝无架构冲突。

### 2. 系统级网络服务与节点轮换 (`sing-box`)
- 自动提取并还原 `/etc/sing-box/config.json`，确保 `640 root:sing-box` 安全组权限。
- 备份 `/usr/local/bin/sing-box-node-rotate` 轮换脚本。
- 新机还原后自动激活并启动 `sing-box.service` 与 `sing-box-node-rotate.timer`。

### 3. AI 自动化工作流完整复原 (iCloud 邮箱清理)
- 完整备份 `~/.local/bin/icloud-mail-triage` 自动化清理脚本（支持 Agy Gemini 3.8 Flash High 或 Claude）。
- 完整打包 **GPG 密钥库**（`~/.gnupg`）与 **Unix 密码管理器**（`~/.password-store`），确保 `pass show` 密码提取在新机即刻可用。
- 自动注册并激活 `systemd --user` 每日定时器（`icloud-mail-triage.timer`）。

### 4. AI 模型工具免扫码登录 (Zero-Login)
- 完整打包主流 AI 开发工具的登录 Session 与授权 Token：
  - **Claude Code** (`~/.claude.json`, `~/.claude/`)
  - **OpenAI Codex** (`~/.codex/auth.json`, `~/.codex/config.toml`)
  - **Google Antigravity (`agy`)** (`~/.gemini/antigravity-cli/`)
  - **xAI Grok** (`~/.grok/auth.json`)
  - **GitHub CLI (`gh`)** (`~/.config/gh/hosts.yml`)
- 新电脑还原后直接处于已登录状态，开箱即用。

### 5. 跨用户名绝对路径智能自适应
- 如果老机器用户名是 `xiaowei`，新机器用户名是 `luneth90`，还原引擎会自动检测并批量将配置文件（`.codex`, `.claude.json`, `antigravity-cli`, `git/config`）中的硬编码旧路径动态替换为新主机的 `$HOME`。

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
   ln -s ~/Projects/omamigrate ~/.config/omarchy/plugins/luneth90.omamigrate
   omarchy-shell shell rescanPlugins
   ```
2. **软链接命令行至全局 PATH**：
   ```bash
   ln -s ~/Projects/omamigrate/bin/omamigrate ~/.local/bin/omamigrate
   ```
3. **绑定桌面全局快捷键**（编辑 `~/.config/hypr/bindings.lua`）：
   ```lua
   o.bind("SUPER + SHIFT + M", "OmaMigrate", "omarchy-shell shell summon luneth90.omamigrate '{}'")
   ```

---

## 自动化测试

项目内置了自动化语法与执行完整性检查脚本：

```bash
./tests/test_syntax.sh
```

---

## 开源协议

基于 MIT License 开源 © 2026 [luneth90](https://github.com/luneth90)
