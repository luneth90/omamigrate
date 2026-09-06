# OmaMigrate

**English** | [简体中文](README.zh-CN.md)

> OmaMigrate creates portable backups of installed package lists, selected user configurations, AI credentials and optional session history, proxy and system service configurations, and automated workflows—then restores them on another Omarchy machine.

> [!IMPORTANT]
> **No telemetry. No cloud service. No automatic backup uploads.** OmaMigrate creates migration archives locally and never sends their contents to a developer-controlled server. The optional **Open LocalSend** action hands the archive to LocalSend for a direct transfer to a nearby device over your local network—not a cloud upload. Package managers and authenticated tools may still make their normal network requests.

> [!WARNING]
> Migration backups may contain SSH and GPG keys, AI login credentials, password stores, and desktop keyrings. Treat every archive as sensitive: transfer it only through trusted channels, restrict access, and delete unneeded copies securely.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Omarchy%20%7C%20Arch%20Linux-blue?logo=archlinux)](https://omarchy.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](CHANGELOG.md)
[![Architecture](https://img.shields.io/badge/Arch-x86__64%20%7C%20aarch64-orange)](#hardware-agnostic-portability)

<p align="center">
  <img src="preview.png" alt="OmaMigrate backup interface" width="720">
</p>

---

## Overview

Traditional dotfiles sync tools (such as Git-based UI sync widgets) only copy basic configuration files (`~/.config/hypr`). When setting up a new computer, you are still left with hours of manual work:
- Re-installing dozens of GUI applications and CLI packages;
- Re-configuring network proxy services (**sing-box**, **Mihomo / Clash Verge**, **v2rayA**, **daed**, etc.) and system timers;
- Re-authenticating all your **AI developer tools** (Claude Code, OpenAI Codex, Antigravity `agy`, Grok);
- Repairing broken automated services or email clients due to missing GPG keys or `pass` password stores;
- Manually fixing broken absolute paths when your username on the new machine differs from the old machine.

**OmaMigrate** addresses these tasks with a unified, cross-architecture migration workflow for selected system and user state:

```
[ Old Omarchy Machine ]                                   [ New Omarchy Machine ]
  ├── Explicit Packages (Filtered)                          ├── Auto-install Packages (yay/pacman)
  ├── Proxy Ecosystem (sing-box/Mihomo/Clash/v2rayA/daed) === LocalSend (local network) ===> ├── Restore Services & Auto-enable Timers
  ├── Mail Profiles & Pass/GPG Keys     Archive (tar)       ├── Restore GPG Keys & Password Store
  ├── AI Sessions (Claude/Codex/Agy)                        ├── Restore AI Credentials & Sessions
  └── Desktop & Hyprland Configs                            └── Auto-adapt Username Paths & Reload
```

---

## Core Capabilities

### 1. Hardware-Agnostic Package Portability
- Extracts your complete list of explicitly installed applications (`pacman -Qqe`).
- **Smart Driver Blacklisting**: Automatically excludes Apple Silicon (Asahi Linux) and vendor-specific kernel drivers (`linux-asahi`, `m1n1`, `uboot`, `speakersafetyd`).
- **Result**: Known device-specific packages are filtered when moving between an **Apple Silicon Mac (aarch64)** and an **Intel/AMD PC (x86_64)**. On the target machine, `yay` and `pacman` download binaries built for that architecture, reducing hardware-specific package conflicts.

### 2. Universal Mainstream Proxy Ecosystem Support (Multi-Proxy Ready)
Whether you prefer background daemons or modern GUI desktop clients, OmaMigrate backs up supported configurations and attempts to reactivate their services after restoration:
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
  - Preserves supported subscriptions, routing rules, proxies, and profile caches so clients can resume with their previous configuration when credentials and formats remain valid.
- **Terminal & Global Proxy Utilities**:
  - Automatically migrates **Proxychains-ng** (`~/.proxychains`, `/etc/proxychains.conf`) and shell environment proxy wrappers.

### 3. Email Clients & Automated Workflow Migration
- **Desktop & CLI Mail Clients**:
  - **Desktop Clients (e.g. Thunderbird)**: Backs up and restores `~/.thunderbird/` profiles, account settings, offline mail stores, and local keyrings. Compatible profiles can be reused on the new machine, though the client may still request re-authentication.
  - **Terminal / CLI Clients**: Backs up configuration trees for `Himalaya`, `Aerc`, and `Neomutt`.
- **Secure Password & GPG Credential Store**:
  - Packages **GPG keys** (`~/.gnupg`) and the **Unix password store** (`~/.password-store`) so `pass`-based credential workflows can be restored.
- **Automation Scripts & Background Timers**:
  - Preserves custom mail management, triage, or automated notification scripts under `~/.local/bin/` and their associated `systemd --user` timers.

### 4. AI Credentials, Sessions & System Keyring Persistence
- **Linux Secret Service & Keyring Sync**:
  - Automatically migrates **Linux System Keyrings** (`~/.local/share/keyrings/`), preserving encrypted credentials and OAuth tokens stored by **Antigravity CLI (`agy`)**, **VS Code**, **GitHub CLI**, and Chromium.
- **Active AI Developer Tool Sessions**:
  - **Antigravity CLI (`agy`)** (`~/.gemini/antigravity-cli/` & Secret Service Keyring)
  - **OpenAI Codex** (`~/.codex/auth.json`, `~/.codex/config.toml`)
  - **Claude Code** (`~/.claude.json`, `~/.claude/`)
  - **xAI Grok** (`~/.grok/auth.json`)
  - **GitHub CLI (`gh`)** (`~/.config/gh/hosts.yml`)
- When saved tokens remain valid and the restored keyring can be unlocked, supported tools may retain their authenticated state. Some providers or applications may still require re-authentication.

> [!TIP]
> **Best Practice Recommendation (Login Password)**:
> We strongly recommend setting the **same user login password** on your new computer as your old computer during OS setup.
> - **Why**: The Linux display manager's PAM authentication stack (e.g. SDDM, GDM) can use your login password to unlock the desktop Keyring during sign-in. Matching passwords improves the chance that tools such as `agy`, VS Code, and GitHub CLI can reuse restored credentials without an extra unlock prompt.
> - **If you use a different password on the new machine**: When launching `agy` or VS Code for the first time, a desktop prompt will ask to unlock the keyring. Simply enter your **old computer's password** once to unlock, and you can subsequently synchronize the keyring password via `seahorse` or system settings.

### 5. Smart Username & Path Adaptation
- If your old username was `alice` and your new machine username is `bob`, OmaMigrate's restoration engine automatically sanitizes and rewrites hardcoded paths across configuration files (`.codex`, `.claude.json`, `antigravity-cli`, `git/config`).

### 6. Re-runnable & Fault-Tolerant Restoration
- **Anti-Root Guard**: Prevents running the restore script with `sudo` to protect file ownership.
- **Auto Database Unlock**: Automatically detects and cleans up leftover `/var/lib/pacman/db.lck` locks from network disconnects or aborts.
- **Write-Permission Unlocking**: Grants `u+w` before copying, reducing Git packfile `Permission denied` errors.
- **Re-runnable Workflow**: If interrupted by a network drop, the restore script is designed to be run again without requiring a fresh archive extraction.

---

## Comparison: OmaMigrate vs. Dotfiles Sync

| Dimension | Standard Dotfile Sync (e.g. Git Sync Plugins) | OmaMigrate |
| :--- | :--- | :--- |
| **Scope** | UI config files (`~/.config/hypr`) | **Selected system and user state** |
| **Application Packages** | ❌ None (must install manually) | ✅ **Restore missing packages via yay/pacman** |
| **Hardware Compatibility** | ⚠️ Can break if device-bound | ✅ **Smart hardware driver filtering** |
| **sing-box & System Daemons** | ❌ No system-level file support | ✅ **Supported /etc and systemd files** |
| **AI Workflows (Mail Triage)** | ❌ Missing GPG/Pass credentials | ✅ **Selected workflows and timers restored** |
| **AI CLI Login Sessions** | ❌ Requires re-login everywhere | ✅ **Restores saved credentials and sessions when still valid** |
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

### Scenario A: GUI Workflow (Recommended)

Press `SUPER + CTRL + M` anywhere on your Omarchy desktop to summon the OmaMigrate HUD:

1. **📦 Step 1: Create a Migration Backup**
   - Click the first button to filter hardware drivers and capture packages, AI tools and credentials, proxy services, dotfiles, and system configurations into `~/omamigrate-backup.tar.gz`.
   - Choose **Standard** (recommended) for apps, AI credentials, proxy services, and configurations. Choose **Complete** to also include AI chat histories, sessions, and plugins; the backup may be large depending on your local data.
2. **📡 Step 2: Direct Local Transfer**
   - Open the backup in LocalSend, then select a nearby target device for a direct local-network transfer without cloud storage. The receiving device normally saves it to `~/Downloads`.
3. **⚡ Step 3: Restore on New Machine**
   - On the new computer, open OmaMigrate and click the third button to automatically install packages, restore credentials, adapt paths, and reload Hyprland!

### Scenario B: Bare-Metal Restoration (No Plugin Required)

If your new computer has a fresh Omarchy installation without the OmaMigrate plugin installed yet, you can restore directly using the standalone engine embedded inside the archive:

```bash
mkdir -p ~/omarchy-restore && tar -xzf ~/Downloads/omamigrate-backup.tar.gz -C ~/omarchy-restore
cd ~/omarchy-restore && ./restore.sh
```
*The restore engine installs missing packages where available, restores supported services and keyrings, and adapts known configuration paths.*

### Scenario C: Terminal CLI Usage

OmaMigrate also ships with a fully featured CLI for headless or script-driven environments:

```bash
# Standard migration backup (recommended)
omamigrate backup [custom-output.tar.gz]

# Complete migration backup with AI histories and plugins; size depends on local data
omamigrate backup --with-ai-history [custom-output.tar.gz]

# Open a migration backup in LocalSend for direct local-network transfer
omamigrate send [backup-file.tar.gz]

# Restore from a migration backup
omamigrate restore <backup-file.tar.gz>
```

Run `omamigrate --help` for the complete command list, or `omamigrate <command> --help` for command-specific options. The legacy `export` command remains available as an alias for `backup`.

To make the `omamigrate` command available directly in your shell, create a symlink in your PATH:

```bash
mkdir -p ~/.local/bin && ln -s ~/.config/omarchy/plugins/luneth90.omamigrate/bin/omamigrate ~/.local/bin/omamigrate
```

---

## Upgrade & Maintenance

### Update

```bash
omarchy plugin update luneth90.omamigrate --yes
```

Restart the shell if the interface does not refresh automatically:

```bash
omarchy restart shell
```

### Remove

```bash
omarchy plugin remove luneth90.omamigrate
```

If you created the optional CLI symlink above, remove that symlink separately:

```bash
test ! -L ~/.local/bin/omamigrate || unlink ~/.local/bin/omamigrate
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
