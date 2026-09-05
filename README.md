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
- Re-configuring system-level services like **sing-box** proxies and auto-rotation timers;
- Re-authenticating all your **AI developer tools** (Claude Code, OpenAI Codex, Antigravity `agy`, Grok);
- Repairing broken automated services or email clients due to missing GPG keys or `pass` password stores;
- Manually fixing broken absolute paths when your username on the new machine differs from the old machine.

**OmaMigrate** solves this by providing a unified, cross-architecture **whole-system state migration engine**:

```
[ Old Omarchy Machine ]                                   [ New Omarchy Machine ]
  ├── Explicit Packages (Filtered)                          ├── Auto-install Packages (yay/pacman)
  ├── sing-box & Systemd Timers      === LocalSend / ===>   ├── Restore Services & Auto-enable Timers
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

### 2. System-Level Network & Daemons (`sing-box`)
- Safely packages `/etc/sing-box/config.json` with appropriate group permissions (`640 root:sing-box`).
- Preserves `/usr/local/bin/sing-box-node-rotate` and systemd timers (`sing-box-node-rotate.timer`).
- Automatically enables and starts services upon restoration.

### 3. Email Clients & Automated Workflow Migration
- **Desktop & CLI Mail Clients**:
  - **Desktop Clients (e.g. Thunderbird)**: Full backup and restoration of `~/.thunderbird/` profiles, account setups, offline mail stores, and local keyrings—launch Thunderbird on the new machine and start reading emails immediately without re-entering IMAP/SMTP passwords.
  - **Terminal / CLI Clients**: Full support for `Himalaya`, `Aerc`, and `Neomutt` configuration trees.
- **Secure Password & GPG Credential Store**:
  - Packages the critical **GPG keys** (`~/.gnupg`) and **Unix password store** (`~/.password-store`), ensuring credentials retrieved via `pass show` work immediately.
- **Automation Scripts & Background Timers**:
  - Preserves custom mail management, triage, or automated notification scripts under `~/.local/bin/` and their associated `systemd --user` timers.

### 4. Zero-Login AI State Persistence
- Migrates active sessions and OAuth tokens for:
  - **Claude Code** (`~/.claude.json`, `~/.claude/`)
  - **OpenAI Codex** (`~/.codex/auth.json`, `~/.codex/config.toml`)
  - **Antigravity CLI (`agy`)** (`~/.gemini/antigravity-cli/`)
  - **xAI Grok** (`~/.grok/auth.json`)
  - **GitHub CLI (`gh`)** (`~/.config/gh/hosts.yml`)
- All CLI tools remain in an authenticated state on the new machine—no QR codes, no browser log-ins.

### 5. Smart Username & Path Adaptation
- If your old username was `xiaowei` and your new machine username is `luneth90`, OmaMigrate's restoration engine automatically sanitizes and rewrites hardcoded paths across configuration files (`.codex`, `.claude.json`, `antigravity-cli`, `git/config`).

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

## Quick Start Guide

### Step 1: Export on Old Machine

Run via the CLI tool:

```bash
# Export system ecosystem into ~/omarchy-migration.tar.gz
omamigrate export
```

*(You will be prompted once for your `sudo` password to securely read `/etc/sing-box/config.json`)*.

---

### Step 2: Transfer to New Machine

**Option A: LocalSend (Fastest & Wireless)**
```bash
omamigrate send
```
Or open LocalSend on both machines and beam `~/omarchy-migration.tar.gz` to the new machine's `~/Downloads`.

**Option B: Network SCP**
```bash
scp ~/omarchy-migration.tar.gz <new-user>@<new-ip>:~/Downloads/
```

---

### Step 3: Restore on New Machine

On the new machine, open a terminal and run:

```bash
omamigrate restore ~/Downloads/omarchy-migration.tar.gz
```

*Or run standalone without installing OmaMigrate beforehand:*

```bash
mkdir -p ~/omarchy-restore && tar -xzf ~/Downloads/omarchy-migration.tar.gz -C ~/omarchy-restore
cd ~/omarchy-restore && ./restore.sh
```

The restore engine will automatically install missing packages, restore configs, remap paths, start services, and reload your Hyprland desktop.

---

## Omarchy Plugin Integration

To integrate OmaMigrate directly into your Omarchy desktop:

1. Clone or symlink the project to your plugins directory:
   ```bash
   ln -s ~/Projects/omamigrate ~/.config/omarchy/plugins/luneth90.omamigrate
   omarchy-shell shell rescanPlugins
   ```
2. Symlink the CLI to your path:
   ```bash
   ln -s ~/Projects/omamigrate/bin/omamigrate ~/.local/bin/omamigrate
   ```
3. (Optional) Bind a shortcut in `~/.config/hypr/bindings.lua`:
   ```lua
   o.bind("SUPER + SHIFT + M", "OmaMigrate", "omarchy-shell shell summon luneth90.omamigrate '{}'")
   ```

---

## Testing & Validation

A built-in test suite validates script syntax and executable integrity:

```bash
./tests/test_syntax.sh
```

---

## License

MIT License © 2026 [luneth90](https://github.com/luneth90)
