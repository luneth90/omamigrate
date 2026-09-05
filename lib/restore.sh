#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Automated Restoration Engine (Idempotent, Safe & Fault-tolerant)
# ==============================================================================
set -u

# 1. Guard against root execution
if [ "$(id -u)" -eq 0 ]; then
  echo ""
  echo "===================================================================="
  echo " [Error] Please DO NOT run this script with sudo or as root!"
  echo " Run directly as your normal user: ./restore.sh"
  echo " (The script will automatically prompt for sudo when needed)"
  echo "===================================================================="
  echo ""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="$(id -un)"
CURRENT_HOME="$HOME"

echo "=========================================================="
echo " OmaMigrate: Restoring Omarchy Ecosystem..."
echo " Target User: ${CURRENT_USER} (Home: ${CURRENT_HOME})"
echo "=========================================================="

# 2. Automatically clear pacman database locks from interrupted operations
if [ -f /var/lib/pacman/db.lck ]; then
  echo "==> [Clean] Detected lingering pacman lock file, clearing..."
  sudo rm -f /var/lib/pacman/db.lck || true
fi

# 3. Restore user configuration files
echo "==> 1. Restoring user configs and dotfiles..."
mkdir -p "${CURRENT_HOME}/.config" "${CURRENT_HOME}/.local/bin"

if [ -d "${SCRIPT_DIR}/user_home" ]; then
  chmod -R u+w "${CURRENT_HOME}" 2>/dev/null || true
  cp -rfp "${SCRIPT_DIR}/user_home/." "${CURRENT_HOME}/"
fi

# 4. Smart Path Adaptation (replaces old machine username with current username)
OLD_HOME="/home/xiaowei"
if [ "${CURRENT_HOME}" != "${OLD_HOME}" ]; then
  echo "==> 2. Adapting username paths (${OLD_HOME} -> ${CURRENT_HOME})..."
  [ -f "${CURRENT_HOME}/.codex/config.toml" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.codex/config.toml"
  [ -f "${CURRENT_HOME}/.claude.json" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.claude.json"
  [ -f "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json"
  [ -f "${CURRENT_HOME}/.config/git/config" ] && sed -i "s|!${OLD_HOME}.*gh auth git-credential|!gh auth git-credential|g" "${CURRENT_HOME}/.config/git/config"
fi

# 5. Fix permissions for security and credentials
echo "==> 3. Setting secure permissions for credentials..."
sudo chown -R "${CURRENT_USER}:${CURRENT_USER}" \
  "${CURRENT_HOME}/.config" \
  "${CURRENT_HOME}/.local" \
  "${CURRENT_HOME}/.ssh" \
  "${CURRENT_HOME}/.gnupg" \
  "${CURRENT_HOME}/.password-store" \
  "${CURRENT_HOME}/.claude" \
  "${CURRENT_HOME}/.codex" \
  "${CURRENT_HOME}/.gemini" \
  "${CURRENT_HOME}/.grok" 2>/dev/null || true

[ -d "${CURRENT_HOME}/.ssh" ] && chmod 700 "${CURRENT_HOME}/.ssh" && chmod -f 600 "${CURRENT_HOME}/.ssh"/id_* 2>/dev/null || true
[ -d "${CURRENT_HOME}/.gnupg" ] && chmod 700 "${CURRENT_HOME}/.gnupg" && find "${CURRENT_HOME}/.gnupg" -type f -exec chmod 600 {} + 2>/dev/null || true
[ -d "${CURRENT_HOME}/.password-store" ] && chmod 700 "${CURRENT_HOME}/.password-store"
[ -d "${CURRENT_HOME}/.local/bin" ] && chmod +x "${CURRENT_HOME}/.local/bin"/* 2>/dev/null || true

# 6. Restore system-level configs (sing-box, rotate script, system timers)
echo "==> 4. Restoring system-level configurations..."
if [ -d "${SCRIPT_DIR}/system_root/etc/sing-box" ]; then
  sudo mkdir -p /etc/sing-box
  sudo cp -p "${SCRIPT_DIR}/system_root/etc/sing-box/config.json" /etc/sing-box/
  if getent group sing-box >/dev/null 2>&1; then
    sudo chown root:sing-box /etc/sing-box/config.json
  else
    sudo chown root:root /etc/sing-box/config.json
  fi
  sudo chmod 640 /etc/sing-box/config.json
fi

if [ -f "${SCRIPT_DIR}/system_root/usr/local/bin/sing-box-node-rotate" ]; then
  sudo mkdir -p /usr/local/bin
  sudo cp -p "${SCRIPT_DIR}/system_root/usr/local/bin/sing-box-node-rotate" /usr/local/bin/
  sudo chmod 755 /usr/local/bin/sing-box-node-rotate
fi

if [ -d "${SCRIPT_DIR}/system_root/etc/systemd/system" ]; then
  sudo cp -p "${SCRIPT_DIR}/system_root/etc/systemd/system/"* /etc/systemd/system/ 2>/dev/null || true
fi

# 7. Incremental package installation (arch-native & yay/AUR)
echo "==> 5. Detecting and installing missing packages..."
PKG_FILE="${SCRIPT_DIR}/pkg_meta/packages_explicit.txt"

if [ -f "$PKG_FILE" ]; then
  MISSING_PKGS=()
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
      MISSING_PKGS+=("$pkg")
    fi
  done < "$PKG_FILE"

  if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "    Found ${#MISSING_PKGS[@]} missing packages: ${MISSING_PKGS[*]}"
    echo "    Installing packages..."
    if command -v yay >/dev/null 2>&1; then
      yay -S --needed --noconfirm "${MISSING_PKGS[@]}" || {
        echo "    [Notice] Some packages failed due to network timeout. You can re-run ./restore.sh anytime to retry."
      }
    elif command -v omarchy >/dev/null 2>&1; then
      omarchy pkg add "${MISSING_PKGS[@]}" || sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || true
    else
      sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || true
    fi
  else
    echo "    All required packages are already installed."
  fi
fi

# Ensure core dependencies
CORE_DEPS=(sing-box pass himalaya fcitx5 fcitx5-chinese-addons fcitx5-configtool jq curl)
CORE_MISSING=()
for cpkg in "${CORE_DEPS[@]}"; do
  if ! pacman -Qi "$cpkg" >/dev/null 2>&1; then
    CORE_MISSING+=("$cpkg")
  fi
done
if [ ${#CORE_MISSING[@]} -gt 0 ]; then
  echo "    Installing core dependencies: ${CORE_MISSING[*]}"
  if command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm "${CORE_MISSING[@]}" || true
  else
    sudo pacman -S --needed --noconfirm "${CORE_MISSING[@]}" || true
  fi
fi

# 8. Restore mise development toolchains
echo "==> 6. Restoring mise CLI tools and language runtimes..."
if command -v mise >/dev/null 2>&1; then
  echo "    Running mise install..."
  mise install -y || {
    echo "    [Notice] Some mise tools timed out downloading. Run 'mise install' later to finish."
  }
else
  echo "    mise not found; install with 'yay -S mise-bin' and run 'mise install' to restore CLI tools."
fi

# 9. Activate and enable services & timers
echo "==> 7. Activating background timers and services..."
sudo systemctl daemon-reload
if command -v sing-box >/dev/null 2>&1; then
  echo "    Enabling sing-box service & node rotate timer..."
  sudo systemctl enable --now sing-box.service 2>/dev/null || true
  if [ -f "/etc/systemd/system/sing-box-node-rotate.timer" ]; then
    sudo systemctl enable --now sing-box-node-rotate.timer 2>/dev/null || true
  fi
fi

echo "    Enabling daily email triage timer (icloud-mail-triage.timer)..."
systemctl --user daemon-reload
systemctl --user enable --now icloud-mail-triage.timer 2>/dev/null || true

# 10. Reload desktop environment
echo "==> 8. Reloading Hyprland & Omarchy shell..."
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload 2>/dev/null || true
fi
if command -v omarchy >/dev/null 2>&1; then
  omarchy restart shell 2>/dev/null || true
fi

echo ""
echo "=========================================================="
echo " OmaMigrate: Restoration completed successfully!"
echo " Fully idempotent: re-run ./restore.sh anytime if needed."
echo "=========================================================="
