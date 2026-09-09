# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.5] - 2026-09-09

### Security & Hardening
- **Two-Phase Privilege Separation Architecture**: Decoupled mutable user-space worker scripts from all privileged system operations. User-space workers (`export.sh` and `restore.sh`) execute in completely unprivileged environments with standard input bound to `/dev/null` and zero ambient sudo credentials.
- **Strict In-Memory Privileged Helper**: Implemented an in-memory, integrity- and ownership-bound runner in `OmaMigrate.qml` with a narrow operation and argument allowlist. Privileged operations are strictly restricted to allowlisted targets (`/etc/sing-box`, `/etc/mihomo`, `/etc/v2raya`, `/etc/xray`, `/etc/v2ray`, `/etc/daed`, `/etc/proxychains.conf`, `/usr/local/bin/sing-box-node-rotate`, and systemd service units).
- **Package Name Sanitization**: Enforce strict character allowlists (`^[a-zA-Z0-9_@.+-]+$`) on all package restoration operations, preventing option injection or argument smuggling into `/usr/bin/pacman`.
- **Immediate Credential Revocation (`sudo -k`)**: Guaranteed immediate sudo ticket revocation via `sudo -k` after every privileged operation in both backup and restore flows. Sudo tickets are never left active across process boundaries, completely preventing rogue worker processes or same-UID processes from consuming reusable sudo timestamps.
- **Adversarial Privilege Capability Regression Tests**: Added adversarial tests in `tests/test_credential_isolation.sh` demonstrating that substituting a worker script with a malicious payload attempting `sudo -n id` strictly fails with zero capability leakage.

## [1.1.4] - 2026-09-09

### Security & Hardening
- **Executable Identity & Absolute System Paths**: Enforce fixed absolute paths (`/usr/bin/python3`, `/usr/bin/sudo`, `/usr/bin/bash`) across all UI Process invocations and worker scripts. Eliminate PATH resolution vulnerability preventing user-session PATH spoofing and binary injection.
- **Environment Sanitization**: Applied `clearEnvironment: true` and restricted `PATH="/usr/bin:/bin"` to all privileged and shell execution processes in `OmaMigrate.qml`, eliminating `LD_PRELOAD`, `SUDO_ASKPASS`, and environment variable injection vectors.
- **Privilege Boundary Integrity Verification**: Implemented strict pre-execution integrity checks on `/usr/bin/sudo`, verifying root:root ownership (UID 0, GID 0), SetUID mode (`04755`), and preventing group/world-writable permissions before routing any credentials.
- **Zero Credential Bytes to Mutable Plugin Workers**: Completely eliminated `exportSecret`, `restoreSecret`, and `pendingSecret` properties from UI processes. Stream credentials exclusively to the isolated `/usr/bin/sudo` privilege boundary in a dedicated session, redirecting standard input to `/dev/null` prior to launching user-space worker scripts. Mutable plugin scripts never receive credential bytes, preventing TOCTOU worker substitution attacks.
- **PTY Session Privilege Isolation**: Utilized an authentic in-memory PTY session bridge for GUI execution. This allows Linux Sudoers under default `timestamp_type = tty` policies to establish valid terminal credentials and share them with non-interactive child workers (`pacman`, `yay`, `modprobe`) without piping raw secrets to user-side code.
- **Regression Test Suite**: Added automated tests verifying PATH replacement immunity and worker substitution defense (proving neither fake PATH binaries nor replaced worker scripts can intercept credentials).

## [1.1.3] - 2026-09-08

### Fixed
- **Restore Engine Hang & Yay Infinite Loop**: Removed `--sudoloop` from the `yay` AUR package installation routine in `lib/restore.sh`. Yay's upstream `--sudoloop` enters an unthrottled infinite retry loop when `sudo -v` fails in non-terminal environments (`sudo: a terminal is required to read the password`). Restore routines already maintain their own background keepalive loop, rendering yay's `--sudoloop` redundant.
- **Fail-Fast AUR Package Installation**: Added `--sudoflags "-n"` and standard input redirection (`< /dev/null`) to `yay`, ensuring package manager elevation operates strictly non-interactively and fails fast without blocking or looping when terminal input is unavailable.
- **Archive Extraction Input Guard**: Redirected standard input to `/dev/null` during `tar` archive extraction in `bin/omamigrate` to guarantee stdin credentials stream cleanly to the restore engine without premature consumption.

### Added
- **Top-Right Force Close Button**: Added an independent `✕` close button in the top-right corner of the OmaMigrate modal card (`z: 1000`), positioned above the processing shield. Users can now forcibly terminate active background processes (backup, restore, authorization, or scanning) and immediately close the window with a mouse click at any time.

## [1.1.2] - 2026-09-08

### Fixed
- **GUI Process Privilege Elevation**: Fix non-TTY sudo privilege elevation where `sudo` child processes inside subshells could not access Quickshell's parent process credentials under standard `timestamp_type = tty` / `ppid` policies.
- **Pipeline Stdin Credential Delivery**: Directly forward validated credentials via standard input pipe into `export.sh` and `restore.sh`, authenticating within the execution process tree with immediate zeroing of secrets from memory, maintaining full compliance with process isolation rules (no `argv`, no `environ`, no disk artifacts).
- **Interactive Terminal Sudo Prompt**: Explicitly prompt with `sudo -v` in interactive terminal sessions before running protected archive pipelines to ensure seamless execution.

## [1.1.1] - 2026-09-08

### Security & Hardening
- **Process Credential Isolation**: Eliminate password exposure in process command-line metadata (`argv`) and environment variables (`OMAMIGRATE_SUDO_PASS`).
- **Direct Stdin Authentication Streaming**: Stream authentication password directly to `sudo -S -p "" -v` via standard input pipe using Quickshell `stdinEnabled` without invoking intermediate shell arguments, immediately purging memory buffers upon transmission.
- **Sudo Credential Cache Re-use**: Execute backup and restore routines strictly against the active sudo credential cache (`sudo -n`), with background keepalive loops and automatic lifecycle cleanup on process exit.
- **Zero Disk Artifacts**: Remove transient `askpass` script generation in restore routines, guaranteeing no sensitive credentials ever touch the filesystem.
- **Automated Process-Level Inspection Test**: Added `tests/test_credential_isolation.sh` to dynamically inspect spawned processes, verifying that canary secrets are strictly absent from `/proc/*/cmdline` and `/proc/*/environ`.

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
