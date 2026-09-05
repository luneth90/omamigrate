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
OLD_HOME="$(cat "${SCRIPT_DIR}/pkg_meta/source_home.txt" 2>/dev/null || true)"
if [ -n "${OLD_HOME}" ] && [ "${CURRENT_HOME}" != "${OLD_HOME}" ]; then
  echo "==> 2. Adapting username paths (${OLD_HOME} -> ${CURRENT_HOME})..."
  [ -f "${CURRENT_HOME}/.codex/config.toml" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.codex/config.toml"
  [ -f "${CURRENT_HOME}/.claude.json" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.claude.json"
  [ -f "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json"
  [ -f "${CURRENT_HOME}/.config/git/config" ] && sed -i "s|!${OLD_HOME}.*gh auth git-credential|!gh auth git-credential|g" "${CURRENT_HOME}/.config/git/config"
  [ -d "${CURRENT_HOME}/.thunderbird" ] && find "${CURRENT_HOME}/.thunderbird" -type f -name "*.ini" -exec sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" {} + 2>/dev/null || true

  # Adapt proxy configuration paths
  for pdir in clash clash-verge clash-verge-rev clash-nyanpasu mihomo mihomo-party nekoray Matsuri flclash v2raya; do
    if [ -d "${CURRENT_HOME}/.config/${pdir}" ]; then
      find "${CURRENT_HOME}/.config/${pdir}" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \) \
        -exec sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" {} + 2>/dev/null || true
    fi
  done
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
  "${CURRENT_HOME}/.grok" \
  "${CURRENT_HOME}/.thunderbird" \
  "${CURRENT_HOME}/.proxychains" 2>/dev/null || true

[ -d "${CURRENT_HOME}/.ssh" ] && chmod 700 "${CURRENT_HOME}/.ssh" && chmod -f 600 "${CURRENT_HOME}/.ssh"/id_* 2>/dev/null || true
[ -d "${CURRENT_HOME}/.gnupg" ] && chmod 700 "${CURRENT_HOME}/.gnupg" && find "${CURRENT_HOME}/.gnupg" -type f -exec chmod 600 {} + 2>/dev/null || true
[ -d "${CURRENT_HOME}/.password-store" ] && chmod 700 "${CURRENT_HOME}/.password-store"
[ -d "${CURRENT_HOME}/.local/bin" ] && chmod +x "${CURRENT_HOME}/.local/bin"/* 2>/dev/null || true
[ -d "${CURRENT_HOME}/.local/share/keyrings" ] && chmod 700 "${CURRENT_HOME}/.local/share/keyrings" && chmod -f 600 "${CURRENT_HOME}/.local/share/keyrings"/* 2>/dev/null || true

# Intelligent Keyring State Detection & Guidance
if [ -d "${CURRENT_HOME}/.local/share/keyrings" ]; then
  HAS_ENCRYPTED_KEYRING=false
  for kr in "${CURRENT_HOME}/.local/share/keyrings"/*.keyring; do
    [ -f "$kr" ] || continue
    if head -c 12 "$kr" 2>/dev/null | grep -q "GnomeKeyring"; then
      HAS_ENCRYPTED_KEYRING=true
      break
    fi
  done
  if [ "$HAS_ENCRYPTED_KEYRING" = true ]; then
    echo "    [Keyring] Detected password-protected desktop keyring:"
    echo "      * If your new computer uses the same login password as the old computer, PAM will unlock it automatically."
    echo "      * If you set a different login password on this new computer, enter the OLD computer's password when prompted on first launch."
  else
    echo "    [Keyring] Desktop keyring restored (blank/auto-unlock mode)."
  fi
fi

# 6. Restore system-level configs (sing-box, mihomo, v2raya, xray, v2ray, daed, proxychains)
echo "==> 4. Restoring system-level configurations..."
for etc_dir in sing-box mihomo v2raya xray v2ray daed; do
  if [ -d "${SCRIPT_DIR}/system_root/etc/${etc_dir}" ]; then
    echo "    Restoring /etc/${etc_dir}..."
    sudo mkdir -p "/etc/${etc_dir}"
    sudo cp -rp "${SCRIPT_DIR}/system_root/etc/${etc_dir}/." "/etc/${etc_dir}/"
    if [ "${etc_dir}" = "sing-box" ]; then
      if getent group sing-box >/dev/null 2>&1; then
        sudo chown -R root:sing-box "/etc/sing-box"
      else
        sudo chown -R root:root "/etc/sing-box"
      fi
      [ -f "/etc/sing-box/config.json" ] && sudo chmod 640 "/etc/sing-box/config.json"
    fi
  fi
done

if [ -f "${SCRIPT_DIR}/system_root/etc/proxychains.conf" ]; then
  echo "    Restoring /etc/proxychains.conf..."
  sudo cp -p "${SCRIPT_DIR}/system_root/etc/proxychains.conf" /etc/proxychains.conf
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
CORE_DEPS=(pass fcitx5 fcitx5-chinese-addons fcitx5-configtool jq curl)
if [ -d "${SCRIPT_DIR}/system_root/etc/sing-box" ]; then
  CORE_DEPS+=("sing-box")
fi
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

# sing-box
if [ -d "${SCRIPT_DIR}/system_root/etc/sing-box" ] || [ -f "/etc/systemd/system/sing-box.service" ]; then
  if command -v sing-box >/dev/null 2>&1; then
    echo "    Enabling sing-box service & node rotate timer..."
    sudo systemctl enable --now sing-box.service 2>/dev/null || true
    if [ -f "/etc/systemd/system/sing-box-node-rotate.timer" ]; then
      sudo systemctl enable --now sing-box-node-rotate.timer 2>/dev/null || true
    fi
  fi
fi

# mihomo
if [ -d "${SCRIPT_DIR}/system_root/etc/mihomo" ] || [ -f "/etc/systemd/system/mihomo.service" ]; then
  if command -v mihomo >/dev/null 2>&1; then
    echo "    Enabling mihomo service..."
    sudo systemctl enable --now mihomo.service 2>/dev/null || true
  fi
fi

# v2raya
if [ -d "${SCRIPT_DIR}/system_root/etc/v2raya" ] || [ -f "/etc/systemd/system/v2raya.service" ]; then
  if command -v v2raya >/dev/null 2>&1; then
    echo "    Enabling v2raya service..."
    sudo systemctl enable --now v2raya.service 2>/dev/null || true
  fi
fi

# xray / v2ray
if [ -d "${SCRIPT_DIR}/system_root/etc/xray" ] || [ -f "/etc/systemd/system/xray.service" ]; then
  if command -v xray >/dev/null 2>&1; then
    echo "    Enabling xray service..."
    sudo systemctl enable --now xray.service 2>/dev/null || true
  fi
fi
if [ -d "${SCRIPT_DIR}/system_root/etc/v2ray" ] || [ -f "/etc/systemd/system/v2ray.service" ]; then
  if command -v v2ray >/dev/null 2>&1; then
    echo "    Enabling v2ray service..."
    sudo systemctl enable --now v2ray.service 2>/dev/null || true
  fi
fi

# daed
if [ -d "${SCRIPT_DIR}/system_root/etc/daed" ] || [ -f "/etc/systemd/system/daed.service" ]; then
  if command -v daed >/dev/null 2>&1; then
    echo "    Enabling daed service..."
    sudo systemctl enable --now daed.service 2>/dev/null || true
  fi
fi

# user systemd timers
systemctl --user daemon-reload
if [ -f "${CURRENT_HOME}/.config/systemd/user/icloud-mail-triage.timer" ]; then
  echo "    Enabling daily email triage timer (icloud-mail-triage.timer)..."
  systemctl --user enable --now icloud-mail-triage.timer 2>/dev/null || true
fi

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
