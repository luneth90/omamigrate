# OmaMigrate

**English** | [简体中文](README.zh-CN.md)

> One-click whole-system ecosystem & environment migration tool for Omarchy Linux — seamlessly teleport your apps, configs, systemd daemons, sing-box proxy, and AI credentials to any new machine.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Omarchy%20%7C%20Arch%20Linux-blue?logo=archlinux)](https://omarchy.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](CHANGELOG.md)
[![Architecture](https://img.shields.io/badge/Arch-x86__64%20%7C%20aarch64-orange)](#hardware-agnostic-portability)

---

## Overview

Traditional dotfiles sync tools (such as Git-based UI sync widgets) only copy basic configuration files (`~/.config/hypr`). When setting up a new computer, you are still left with hours of manual work:
- Re-installing dozens of GUI applications and CLI packages;
- Re-configuring network proxy services (**sing-box**, **Mihomo / Clash Verge**, **v2rayA**, **daed**, etc.) and system timers;
- Re-authenticating all your **AI developer tools** (Claude Code, OpenAI Codex, Antigravity `agy`, Grok);
- Repairing broken automated services or email clients due to missing GPG keys or `pass` password stores;
- Manually fixing broken absolute paths when your username on the new machine differs from the old machine.

**OmaMigrate** solves this by providing a unified, cross-architecture **whole-system state migration engine**:

```
[ Old Omarchy Machine ]                                   [ New Omarchy Machine ]
  ├── Explicit Packages (Filtered)                          ├── Auto-install Packages (yay/pacman)
  ├── Proxy Ecosystem (sing-box/Mihomo/Clash/v2rayA/daed) === LocalSend / ===> ├── Restore Services & Auto-enable Timers
  ├── Mail Profiles & Pass/GPG Keys     Archive (tar)       ├── Restore GPG Keys & Password Store
  ├── AI Sessions (Claude/Codex/Agy)                        ├── Zero-Login AI Session Recovery
  └── Desktop & Hyprland Configs                            └── Auto-adapt Username Paths & Reload
```

---

## Core Capabilities

### 1. Hardware-Agnostic Package Portability
- Extracts your complete list of explicitly installed applications (`pacman -Qqe`).
- **Smart Driver Blacklisting**: Automatically excludes Apple Silicon (Asahi Linux) and vendor-specific kernel drivers (`linux-asahi`, `m1n1`, `uboot`, `speakersafetyd`).
- **Result**: You can migrate freely between an **Apple Silicon Mac (aarch64)** and an **Intel/AMD PC (x86_64)** without package manager conflicts. On the target machine, `yay` and `pacman` dynamically download the binaries natively compiled for that architecture.

### 2. Universal Mainstream Proxy Ecosystem Support (Multi-Proxy Ready)
Whether you prefer background daemons or modern GUI desktop clients, OmaMigrate handles end-to-end migration and automatic activation:
- **System Daemons & Transparent Proxies**:
  - **sing-box**: Preserves `/etc/sing-box/` rule configurations, `640 root:sing-box` group permissions, node auto-rotation scripts, and systemd service/timer units.
  - **Mihomo (formerly Clash.Meta)**: Restores `/etc/mihomo/` system configurations, `~/.config/mihomo/` user configurations, and `mihomo.service`.
  - **v2rayA / Xray / v2ray**: Restores `/etc/v2raya/`, `/etc/xray/`, `/etc/v2ray/`, and enables corresponding background systemd services.
  - **daed / daed-next**: Migrates eBPF-based high-performance transparent proxy configurations (`/etc/daed/`) and daemon services.
- **Desktop GUI Clients**:
  - **Clash Verge / Clash Verge Rev** (`~/.config/clash-verge`, `~/.config/clash-verge-rev`)
  - **Clash Nyanpasu** (`~/.config/clash-nyanpasu`)
  - **Mihomo Party** (`~/.config/mihomo-party`)
  - **Flclash** (`~/.config/flclash`)
  - **NekoBox / Nekoray / Matsuri** (`~/.config/nekoray`, `~/.config/Matsuri`)
  - Preserves all subscriptions, routing rules, proxies, and profile caches for immediate out-of-the-box connectivity.
- **Terminal & Global Proxy Utilities**:
  - Automatically migrates **Proxychains-ng** (`~/.proxychains`, `/etc/proxychains.conf`) and shell environment proxy wrappers.

### 3. Email Clients & Automated Workflow Migration
- **Desktop & CLI Mail Clients**:
  - **Desktop Clients (e.g. Thunderbird)**: Full backup and restoration of `~/.thunderbird/` profiles, account setups, offline mail stores, and local keyrings—launch Thunderbird on the new machine and start reading emails immediately without re-entering IMAP/SMTP passwords.
  - **Terminal / CLI Clients**: Full support for `Himalaya`, `Aerc`, and `Neomutt` configuration trees.
- **Secure Password & GPG Credential Store**:
  - Packages the critical **GPG keys** (`~/.gnupg`) and **Unix password store** (`~/.password-store`), ensuring credentials retrieved via `pass show` work immediately.
- **Automation Scripts & Background Timers**:
  - Preserves custom mail management, triage, or automated notification scripts under `~/.local/bin/` and their associated `systemd --user` timers.

### 4. Zero-Login AI State & System Keyring Persistence
- **Linux Secret Service & Keyring Sync**:
  - Automatically migrates **Linux System Keyrings** (`~/.local/share/keyrings/`), preserving encrypted credentials and OAuth tokens stored by **Antigravity CLI (`agy`)**, **VS Code**, **GitHub CLI**, and Chromium.
- **Active AI Developer Tool Sessions**:
  - **Antigravity CLI (`agy`)** (`~/.gemini/antigravity-cli/` & Secret Service Keyring)
  - **OpenAI Codex** (`~/.codex/auth.json`, `~/.codex/config.toml`)
  - **Claude Code** (`~/.claude.json`, `~/.claude/`)
  - **xAI Grok** (`~/.grok/auth.json`)
  - **GitHub CLI (`gh`)** (`~/.config/gh/hosts.yml`)
- All CLI tools remain in an authenticated state on the new machine—no QR codes or browser re-logins required.

> [!TIP]
> **Best Practice Recommendation (Login Password)**:
> We strongly recommend setting the **same user login password** on your new computer as your old computer during OS setup.
> - **Why**: The Linux display manager's PAM authentication stack (e.g. SDDM, GDM) automatically uses your login password to unlock the desktop Keyring silently upon system login. When passwords match, tools like `agy`, VS Code, and GitHub CLI achieve a 100% zero-prompt, seamless transition.
> - **If you use a different password on the new machine**: When launching `agy` or VS Code for the first time, a desktop prompt will ask to unlock the keyring. Simply enter your **old computer's password** once to unlock, and you can subsequently synchronize the keyring password via `seahorse` or system settings.

### 5. Smart Username & Path Adaptation
- If your old username was `alice` and your new machine username is `bob`, OmaMigrate's restoration engine automatically sanitizes and rewrites hardcoded paths across configuration files (`.codex`, `.claude.json`, `antigravity-cli`, `git/config`).

### 6. Fully Idempotent & Fault-Tolerant Restoration
- **Anti-Root Guard**: Prevents running the restore script with `sudo` to protect file ownership.
- **Auto Database Unlock**: Automatically detects and cleans up leftover `/var/lib/pacman/db.lck` locks from network disconnects or aborts.
- **Write-Permission Unlocking**: Grants `u+w` before copying, eliminating Git packfile `Permission denied` errors.
- **Re-runnable Anytime**: If interrupted by a network drop, simply run `./restore.sh` again to resume without corrupting existing files.

---

## Comparison: OmaMigrate vs. Dotfiles Sync

| Dimension | Standard Dotfile Sync (e.g. Git Sync Plugins) | OmaMigrate |
| :--- | :--- | :--- |
| **Scope** | UI config files (`~/.config/hypr`) | **Whole-System Ecosystem** |
| **Application Packages** | ❌ None (must install manually) | ✅ **Full auto-install via yay/pacman** |
| **Hardware Compatibility** | ⚠️ Can break if device-bound | ✅ **Smart hardware driver filtering** |
| **sing-box & System Daemons** | ❌ No system-level file support | ✅ **Full /etc & systemd support** |
| **AI Workflows (Mail Triage)** | ❌ Missing GPG/Pass credentials | ✅ **Complete workflow & timers restored** |
| **AI CLI Login Sessions** | ❌ Requires re-login everywhere | ✅ **Zero-login instant readiness** |
| **Different Usernames** | ❌ Breaks on hardcoded `/home/user` | ✅ **Automatic path translation** |

---

## Installation & Desktop Integration

### 1. Install Plugin

Install and enable OmaMigrate directly using Omarchy's official plugin manager:

```bash
omarchy plugin add https://github.com/luneth90/omamigrate.git --enable
```

### 2. Bind Shortcut & Restart Shell

Run this command in your terminal to append the shortcut to `~/.config/hypr/bindings.lua` and restart the shell to take effect immediately (recommended: `SUPER + CTRL + M`, non-conflicting with Omarchy system defaults):

```bash
echo 'o.bind("SUPER + CTRL + M", "OmaMigrate", "omarchy-shell shell toggle luneth90.omamigrate")' >> ~/.config/hypr/bindings.lua
omarchy restart shell
```

---

## Migration Workflow (Desktop-First)

### Scenario A: One-Click GUI Workflow (Recommended)

Press `SUPER + CTRL + M` anywhere on your Omarchy desktop to summon the OmaMigrate HUD:

1. **📦 Step 1: Export & Package System**
   - Click the first button to filter hardware drivers, capture packages, dotfiles, services, and credentials into `~/omarchy-migration.tar.gz`.
   - **Smart Lightweight Mode & Toggle**: By default, OmaMigrate creates a streamlined archive (~25MB) preserving all apps, configs, and zero-login credentials. Check **"Include full AI chat histories & plugins"** if you wish to transfer hundreds of megabytes of past LLM conversation logs and plugins (~650MB+).
2. **📡 Step 2: Beam via LocalSend**
   - Click the second button to launch LocalSend and wireless beam the package directly to `~/Downloads` on your new computer.
3. **⚡ Step 3: One-Click Restore on New Machine**
   - On the new computer, open OmaMigrate and click the third button to automatically install packages, restore credentials, adapt paths, and reload Hyprland!

### Scenario B: Bare-Metal Restoration (No Plugin Required)

If your new computer has a fresh Omarchy installation without the OmaMigrate plugin installed yet, you can restore directly using the standalone engine embedded inside the archive:

```bash
mkdir -p ~/omarchy-restore && tar -xzf ~/Downloads/omarchy-migration.tar.gz -C ~/omarchy-restore
cd ~/omarchy-restore && ./restore.sh
```
*The restore engine will install all applications, configure services, restore keyrings, and automatically restore the OmaMigrate plugin itself!*

### Scenario C: Terminal CLI Usage

OmaMigrate also ships with a fully featured CLI for headless or script-driven environments:

```bash
# Lightweight export (configs & credentials only, ~25MB, recommended)
omamigrate export [custom-output.tar.gz]

# Full export including complete AI chat histories & plugins (~650MB+)
omamigrate export --with-history [custom-output.tar.gz]

# Beam archive via LocalSend
omamigrate send [archive-path.tar.gz]

# Restore ecosystem from archive
omamigrate restore <archive-path.tar.gz>
```

> **💡 Note**: If you want to use the `omamigrate` command directly in your shell, symlink it to your PATH: `ln -s ~/.config/omarchy/plugins/luneth90.omamigrate/bin/omamigrate ~/.local/bin/omamigrate`.

---

## Upgrade & Maintenance

Lifecycle and update commands:

```bash
# Update to latest version & reload shell
omarchy plugin update luneth90.omamigrate
omarchy restart shell

# Uninstall plugin
omarchy plugin remove luneth90.omamigrate
```

---

## Testing & Validation

A built-in test suite validates script syntax and executable integrity:

```bash
./tests/test_syntax.sh
```

---

## License

MIT License © 2026 OmaMigrate Project
