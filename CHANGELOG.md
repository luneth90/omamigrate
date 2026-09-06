# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-09-06

### Added
- **Expanded AI Developer Tool Persistence**: Full credential, session, and configuration migration support for **Pi**, **Oh My Pi (OMP)** (named profiles, XDG & `PI_CODING_AGENT_DIR`), and **OpenCode** (`opencode.db` SQLite state, configuration, and workspace state) alongside Antigravity CLI (`agy`), OpenAI Codex, Claude Code, and xAI Grok.
- **Dual Migration Modes (Standard vs. Complete)**:
  - **Standard Mode**: Strict allowlist of credentials and configurations, excluding conversation histories and plugins to keep backups minimal and fast.
  - **Complete Mode**: Full migration including session histories, conversation memories, skills, and plugins with transactionally consistent SQLite live snapshots and integrity verification (`ai_manifest.sha256`).
- **Proxy Ecosystem Expansion**: Full configuration and service restoration support for Mihoro (`mihoro.toml`) and user-level `mihomo.service`.
- **Automatic Kernel TUN Module Persistence**: Automatically loads and configures `/etc/modules-load.d/99-omamigrate-sing-box-tun.conf` for VPN/proxy requirements before service start.

### Fixed
- **Atomic Shell Configuration Restoration**: Exclude `~/.config/omarchy/shell.json` from bulk archive extractions and inject `luneth90.omamigrate` into the JSON structure prior to writing to disk. This prevents Quickshell's inotify watcher from detecting a transient missing state and hot-unloading OmaMigrate during active restoration.
- **Active Agent Process Lock Guard**: Refuse restoration while supported AI CLI agents are actively executing, preventing race conditions and database/WAL corruption.
- **Package Manager Resilient Fallback**: Split native packages and AUR packages during restore, preventing pacman transaction aborts when `yay` is absent.
- **Structured Path Adaptation**: Ensure old username paths in session files and configs are accurately translated to the current `$HOME` without altering user prompt or response content.

## [1.0.0] - 2026-09-06

### Added
- Initial release of **OmaMigrate**.
- **Hardware-Agnostic Package Filtering**: Automatically exports explicitly installed packages via `pacman -Qqe` while filtering out device/kernel-specific drivers (e.g. Asahi, m1n1, uboot) for cross-architecture portability (x86_64 and ARM64).
- **Automated Service Migration**:
  - Full support for `sing-box` configurations, node rotation daemon, and systemd timers.
  - Full support for AI email triage (`icloud-mail-triage`) including user systemd timers, himalaya config, and prompt configurations.
- **Sensitive Credential Security**: Safe archiving and permission recovery for SSH (`~/.ssh`), GPG keys (`~/.gnupg`), and `pass` password store (`~/.password-store`).
- **Zero-Login AI Session Persistence**: Preserves session state and tokens for Claude Code, OpenAI Codex, Antigravity (`agy`), and Grok.
- **Dynamic Path Sanitization**: Automatically detects and replaces old username paths (e.g. `/home/olduser` -> `/home/newuser`) in all restored configurations.
- **Idempotent Restoration Engine**:
  - Guard against running under `sudo` to prevent file permission pollution.
  - Automatic stale `pacman/db.lck` cleanup on interrupted runs.
  - Incremental, fault-tolerant package and toolchain installations (`yay` and `mise install`).
- **LocalSend Integration**: One-click wireless local network beam transfer between Omarchy machines.
- **Desktop UI**: Native Quickshell overlay (`OmaMigrate.qml`) and versatile CLI (`omamigrate`).
