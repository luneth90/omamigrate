#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Core definitions, constants & logging
# ==============================================================================
set -u

# Text styles & colors
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

msg_info()  { echo -e "${CYAN}==>${NC} ${BOLD}$*${NC}"; }
msg_step()  { echo -e "  ${BLUE}->${NC} $*"; }
msg_ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
msg_warn()  { echo -e "  ${YELLOW}!${NC} ${YELLOW}$*${NC}"; }
msg_error() { echo -e "  ${RED}✗${NC} ${RED}$*${NC}" >&2; }

# Hardware & Architecture filtering regex
# Excludes hardware-bound kernels, bootloaders, and device-specific audio drivers
HW_EXCLUDE_REGEX="^(archlinuxarm|asahi|m1n1|uboot|linux-|kernel-|grub|speakersafetyd)"

# Default configs to backup from ~/.config/
CONFIG_TARGETS=(
  "hypr"
  "omarchy"
  "alacritty"
  "foot"
  "kitty"
  "ghostty"
  "nvim"
  "fcitx5"
  "btop"
  "git"
  "lazygit"
  "starship.toml"
  "systemd"
  "mise"
  "icloud-mail-triage"
  "himalaya"
  "aerc"
  "neomutt"
  "herdr"
  "tensaku"
  "tmux"
  "1Password"
  "obsidian"
  # Mainstream Proxy Clients & GUIs
  "clash"
  "clash-verge"
  "clash-verge-rev"
  "clash-nyanpasu"
  "mihomo"
  "mihomo-party"
  "flclash"
  "nekoray"
  "Matsuri"
  "v2raya"
  "sing-box"
)

# AI Agents directories to backup from ~/
AI_AGENT_DIRS=(
  ".claude"
  ".codex"
  ".gemini"
  ".pi"
  ".grok"
)

# System-level proxy directories in /etc to backup if present
PROXY_SYSTEM_DIRS=(
  "/etc/sing-box"
  "/etc/mihomo"
  "/etc/v2raya"
  "/etc/xray"
  "/etc/v2ray"
  "/etc/daed"
)

# System-level proxy individual files to backup if present
PROXY_SYSTEM_FILES=(
  "/etc/proxychains.conf"
  "/usr/local/bin/sing-box-node-rotate"
)

# System-level proxy systemd service & timer units
PROXY_SYSTEM_SERVICES=(
  "sing-box.service"
  "sing-box-node-rotate.service"
  "sing-box-node-rotate.timer"
  "mihomo.service"
  "v2raya.service"
  "xray.service"
  "v2ray.service"
  "daed.service"
  "daed-next.service"
)

# Fundamental system utilities guaranteed during restore
CORE_DEPENDENCIES=(
  "pass"
  "fcitx5"
  "fcitx5-chinese-addons"
  "fcitx5-configtool"
  "jq"
  "curl"
)
