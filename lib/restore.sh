#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Automated Restoration Engine (Idempotent, Safe & Fault-tolerant)
# ==============================================================================
set -u

# Logging helpers (compatible with CLI & GUI stream parser)
msg_info()  { echo -e "\033[0;36m==>\033[0m \033[1m$*\033[0m"; }
msg_step()  { echo -e "  \033[0;34m->\033[0m $*"; }
msg_ok()    { echo -e "  \033[0;32m✓\033[0m $*"; }
msg_warn()  { echo -e "  \033[0;33m!\033[0m \033[0;33m$*\033[0m"; }
msg_error() { echo -e "  \033[0;31m✗\033[0m \033[0;31m$*\033[0m" >&2; }

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
RESTORE_DATA_DIR="${1:-$SCRIPT_DIR}"
CURRENT_USER="$(id -un)"
CURRENT_HOME="$HOME"

# Sudo Privilege Initialization: Authenticate ONCE and keep alive
SUDO_ASKPASS_SCRIPT=""
SUDO_PID=""

cleanup_privileges() {
  [ -n "${SUDO_PID:-}" ] && kill "${SUDO_PID}" 2>/dev/null || true
  [ -n "${SUDO_ASKPASS_SCRIPT:-}" ] && rm -f "${SUDO_ASKPASS_SCRIPT}" 2>/dev/null || true
}
trap cleanup_privileges EXIT INT TERM

# If password provided by OmaMigrate GUI, configure credentials and transient askpass helper
if [ -n "${OMAMIGRATE_SUDO_PASS:-}" ]; then
  echo "$OMAMIGRATE_SUDO_PASS" | sudo -S -p "" -v 2>/dev/null || true
  
  ASKPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omamigrate"
  mkdir -p "$ASKPASS_DIR" && chmod 700 "$ASKPASS_DIR"
  SUDO_ASKPASS_SCRIPT="$(mktemp "${ASKPASS_DIR}/askpass-XXXXXX.sh")"
  cat << EOF > "$SUDO_ASKPASS_SCRIPT"
#!/usr/bin/env bash
echo "$OMAMIGRATE_SUDO_PASS"
EOF
  chmod 700 "$SUDO_ASKPASS_SCRIPT"
  export SUDO_ASKPASS="$SUDO_ASKPASS_SCRIPT"
  unset OMAMIGRATE_SUDO_PASS
fi

# If in an interactive terminal and not authenticated yet, prompt ONCE
if ! sudo -n true 2>/dev/null; then
  if [ -t 0 ]; then
    msg_info "Administrator privileges required to restore system configurations & packages."
    sudo -v || { msg_error "Administrator authentication failed."; exit 1; }
  fi
fi

# Keep sudo credentials alive in background continuously (no repetitive prompts)
if sudo -n true 2>/dev/null; then
  ( while true; do sudo -n -v 2>/dev/null; sleep 15; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_PID=$!
  ELEVATOR="sudo -n"
elif [ -n "${SUDO_ASKPASS:-}" ]; then
  ELEVATOR="sudo -A"
elif [ -t 0 ]; then
  ELEVATOR="sudo"
else
  ELEVATOR="sudo -n"
fi

msg_info "Starting OmaMigrate Ecosystem Restoration..."
msg_step "Target User: ${CURRENT_USER} (${CURRENT_HOME})"

# 2. Automatically clear pacman database locks from interrupted operations
if [ -f /var/lib/pacman/db.lck ]; then
  msg_step "Clearing lingering pacman lock file..."
  $ELEVATOR rm -f /var/lib/pacman/db.lck || true
fi

# 3. Restore user configuration files
msg_info "Restoring user configs and dotfiles..."
mkdir -p "${CURRENT_HOME}/.config" "${CURRENT_HOME}/.local/bin"

if [ -d "${RESTORE_DATA_DIR}/user_home" ]; then
  chmod -R u+w "${CURRENT_HOME}" 2>/dev/null || true

  # CRITICAL: Strip out OmaMigrate plugin files and binaries from extraction!
  # Quickshell's file watcher hot-reloads the plugin if its files are modified,
  # which would abruptly destroy the QML window and abort restoration!
  rm -rf "${RESTORE_DATA_DIR}/user_home/.config/omarchy/plugins/"*omamigrate* \
         "${RESTORE_DATA_DIR}/user_home/.config/"*omamigrate* \
         "${RESTORE_DATA_DIR}/user_home/.local/bin/"*omamigrate* 2>/dev/null || true

  # If OmaMigrate is active on the target machine, preserve its registration in restored shell.json
  if [ -f "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json" ] && [ -f "${CURRENT_HOME}/.config/omarchy/shell.json" ]; then
    if grep -q "omamigrate" "${CURRENT_HOME}/.config/omarchy/shell.json" 2>/dev/null || [ -n "${OMAMIGRATE_GUI:-}" ]; then
      if command -v jq >/dev/null 2>&1; then
        jq '.plugins = (.plugins // []) + (if any(.plugins[]?; (.id // "") == "luneth90.omamigrate") then [] else [{"id": "luneth90.omamigrate"}] end)' \
          "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json" > "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json.tmp" && \
          mv "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json.tmp" "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json"
      fi
    fi
  fi

  if [ -d "${RESTORE_DATA_DIR}/user_home/.config" ]; then
    for cfg in "${RESTORE_DATA_DIR}/user_home/.config"/*; do
      [ -e "$cfg" ] && msg_step "Restoring config: ~/.config/$(basename "$cfg")"
    done
  fi
  for cred in .ssh .gnupg .password-store .claude .codex .gemini .grok .thunderbird .proxychains; do
    [ -d "${RESTORE_DATA_DIR}/user_home/$cred" ] && msg_step "Restoring credential store: ~/$cred"
  done

  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='.config/omarchy/plugins/*omamigrate*' \
      --exclude='.config/*omamigrate*' \
      --exclude='.local/bin/*omamigrate*' \
      --exclude='*omamigrate*' \
      "${RESTORE_DATA_DIR}/user_home/" "${CURRENT_HOME}/"
  else
    cp -rfp "${RESTORE_DATA_DIR}/user_home/." "${CURRENT_HOME}/"
  fi
  msg_ok "User configs and dotfiles extracted."
fi

# 4. Smart Path Adaptation (replaces old machine username with current username)
OLD_HOME="$(cat "${RESTORE_DATA_DIR}/pkg_meta/source_home.txt" 2>/dev/null || true)"
if [ -n "${OLD_HOME}" ] && [ "${CURRENT_HOME}" != "${OLD_HOME}" ]; then
  msg_info "Adapting username paths (${OLD_HOME} -> ${CURRENT_HOME})..."
  msg_step "Translating AI and CLI agent configs..."
  [ -f "${CURRENT_HOME}/.codex/config.toml" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.codex/config.toml"
  [ -f "${CURRENT_HOME}/.claude.json" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.claude.json"
  [ -f "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json"
  [ -f "${CURRENT_HOME}/.config/git/config" ] && sed -i "s|!${OLD_HOME}.*gh auth git-credential|!gh auth git-credential|g" "${CURRENT_HOME}/.config/git/config"
  [ -f "${CURRENT_HOME}/.ssh/config" ] && sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" "${CURRENT_HOME}/.ssh/config"
  [ -d "${CURRENT_HOME}/.thunderbird" ] && find "${CURRENT_HOME}/.thunderbird" -type f -name "*.ini" -exec sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" {} + 2>/dev/null || true

  msg_step "Translating proxy client paths..."
  for pdir in clash clash-verge clash-verge-rev clash-nyanpasu mihomo mihomo-party nekoray Matsuri flclash v2raya; do
    if [ -d "${CURRENT_HOME}/.config/${pdir}" ]; then
      find "${CURRENT_HOME}/.config/${pdir}" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \) \
        -exec sed -i "s|${OLD_HOME}|${CURRENT_HOME}|g" {} + 2>/dev/null || true
    fi
  done
  msg_ok "Username paths adapted successfully."
fi

# 5. Fix permissions for security and credentials
msg_info "Configuring secure permissions for credentials..."
msg_step "Securing ~/.ssh, ~/.gnupg, ~/.password-store..."
chmod -R u+rwX \
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

if [ -d "${CURRENT_HOME}/.ssh" ]; then
  chmod 700 "${CURRENT_HOME}/.ssh"
  find "${CURRENT_HOME}/.ssh" -type f -exec chmod 600 {} + 2>/dev/null || true
  find "${CURRENT_HOME}/.ssh" -type f -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true
  [ -f "${CURRENT_HOME}/.ssh/known_hosts" ] && chmod 644 "${CURRENT_HOME}/.ssh/known_hosts" 2>/dev/null || true
fi
[ -d "${CURRENT_HOME}/.gnupg" ] && chmod 700 "${CURRENT_HOME}/.gnupg" && find "${CURRENT_HOME}/.gnupg" -type f -exec chmod 600 {} + 2>/dev/null || true
[ -d "${CURRENT_HOME}/.password-store" ] && chmod 700 "${CURRENT_HOME}/.password-store"
[ -d "${CURRENT_HOME}/.local/bin" ] && chmod +x "${CURRENT_HOME}/.local/bin"/* 2>/dev/null || true
[ -d "${CURRENT_HOME}/.local/share/keyrings" ] && chmod 700 "${CURRENT_HOME}/.local/share/keyrings" && chmod -f 600 "${CURRENT_HOME}/.local/share/keyrings"/* 2>/dev/null || true
[ -d "${CURRENT_HOME}/.config/gh" ] && chmod 700 "${CURRENT_HOME}/.config/gh" && chmod -f 600 "${CURRENT_HOME}/.config/gh"/* 2>/dev/null || true

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
    msg_step "Password-protected desktop keyring restored."
  else
    msg_step "Desktop keyring restored (blank/auto-unlock mode)."
  fi
fi
msg_ok "Credentials and keyrings secured."

# 6. Restore system-level configs (sing-box, mihomo, v2raya, xray, v2ray, daed, proxychains)
if [ -d "${RESTORE_DATA_DIR}/system_root" ]; then
  msg_info "Restoring system-level proxy configurations..."
  msg_step "Deploying /etc system configs..."
  $ELEVATOR cp -rfp "${RESTORE_DATA_DIR}/system_root/." / 2>/dev/null || true
  if getent group sing-box >/dev/null 2>&1; then
    $ELEVATOR chown -R root:sing-box "/etc/sing-box" 2>/dev/null || true
    $ELEVATOR usermod -aG sing-box "$CURRENT_USER" 2>/dev/null || true
    [ -f "/etc/sing-box/config.json" ] && $ELEVATOR chmod 640 "/etc/sing-box/config.json" 2>/dev/null || true
  fi
  [ -f "/usr/local/bin/sing-box-node-rotate" ] && $ELEVATOR chmod 755 /usr/local/bin/sing-box-node-rotate 2>/dev/null || true
  msg_ok "System-level configurations restored."
fi

# 7. Incremental package installation (arch-native & yay/AUR)
msg_info "Detecting and installing missing software packages..."
PKG_FILE="${RESTORE_DATA_DIR}/pkg_meta/packages_explicit.txt"

# Sync package databases first so package lookups and installs do not fail on fresh installations
if sudo -n true 2>/dev/null; then
  msg_step "Syncing package databases..."
  $ELEVATOR pacman -Sy --noconfirm 2>/dev/null || true
fi

if [ -f "$PKG_FILE" ]; then
  MISSING_PKGS=()
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
      MISSING_PKGS+=("$pkg")
    fi
  done < "$PKG_FILE"

  if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    msg_step "Found ${#MISSING_PKGS[@]} missing packages to install..."
    if command -v yay >/dev/null 2>&1; then
      msg_step "Installing missing packages with yay..."
      yay -S --needed --noconfirm --sudoloop --answerclean None --answerdiff None --answeredit None "${MISSING_PKGS[@]}" || {
        msg_warn "Some packages timed out. You can retry later."
      }
    elif command -v omarchy >/dev/null 2>&1; then
      msg_step "Installing missing packages with omarchy pkg..."
      omarchy pkg add "${MISSING_PKGS[@]}" || $ELEVATOR pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || true
    else
      msg_step "Installing missing packages with pacman..."
      $ELEVATOR pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || true
    fi
  else
    msg_ok "All required packages are already installed."
  fi
fi

# Ensure core dependencies
CORE_DEPS=(pass fcitx5 fcitx5-chinese-addons fcitx5-configtool jq curl github-cli)
if [ -d "${RESTORE_DATA_DIR}/system_root/etc/sing-box" ]; then
  CORE_DEPS+=("sing-box")
fi
CORE_MISSING=()
for cpkg in "${CORE_DEPS[@]}"; do
  if ! pacman -Qi "$cpkg" >/dev/null 2>&1; then
    CORE_MISSING+=("$cpkg")
  fi
done
if [ ${#CORE_MISSING[@]} -gt 0 ]; then
  msg_step "Installing missing core dependencies: ${CORE_MISSING[*]}"
  if command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm --sudoloop --answerclean None --answerdiff None --answeredit None "${CORE_MISSING[@]}" || true
  else
    $ELEVATOR pacman -S --needed --noconfirm "${CORE_MISSING[@]}" || true
  fi
fi
msg_ok "Package dependencies verified."

# 8. Restore mise development toolchains
if command -v mise >/dev/null 2>&1; then
  msg_info "Restoring mise development toolchains..."
  msg_step "Trusting and installing mise toolchains..."
  [ -f "${CURRENT_HOME}/.config/mise/config.toml" ] && mise trust "${CURRENT_HOME}/.config/mise/config.toml" 2>/dev/null || true
  mise install -y || msg_warn "Some mise tools timed out."
  mise reshim 2>/dev/null || true
  msg_ok "Development toolchains restored."
fi

# 9. Activate and enable services & timers
msg_info "Activating system background services and timers..."
$ELEVATOR systemctl daemon-reload

for srv in sing-box mihomo v2raya xray v2ray daed; do
  if [ -d "${RESTORE_DATA_DIR}/system_root/etc/$srv" ] || [ -f "/etc/systemd/system/${srv}.service" ]; then
    if command -v "$srv" >/dev/null 2>&1; then
      msg_step "Enabling $srv service..."
      $ELEVATOR systemctl enable --now "${srv}.service" 2>/dev/null || true
    fi
  fi
done

if [ -f "/etc/systemd/system/sing-box-node-rotate.timer" ]; then
  msg_step "Enabling sing-box-node-rotate timer..."
  $ELEVATOR systemctl enable --now sing-box-node-rotate.timer 2>/dev/null || true
fi

# user systemd timers
systemctl --user daemon-reload
if [ -f "${CURRENT_HOME}/.config/systemd/user/icloud-mail-triage.timer" ]; then
  msg_step "Enabling daily email triage timer..."
  systemctl --user enable --now icloud-mail-triage.timer 2>/dev/null || true
fi
msg_ok "Background services and timers activated."

# 10. Reload desktop environment
# Only reload Hyprland & restart shell automatically when executed from standalone CLI, NOT from OmaMigrate GUI
if [ -z "${OMAMIGRATE_GUI:-}" ]; then
  msg_info "Reloading desktop environment..."
  if command -v hyprctl >/dev/null 2>&1; then
    msg_step "Reloading Hyprland configuration..."
    hyprctl reload 2>/dev/null || true
  fi
  if command -v omarchy >/dev/null 2>&1; then
    msg_step "Restarting Omarchy shell..."
    omarchy restart shell 2>/dev/null || true
  fi
fi

msg_ok "Restoration completed successfully!"
