# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
