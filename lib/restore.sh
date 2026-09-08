#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Automated Restoration Engine (Idempotent, Safe & Fault-tolerant)
# ==============================================================================
set -uo pipefail

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
AI_STATE_HELPER="${SCRIPT_DIR}/ai-state.sh"
AI_STATE_HELPER_READY=false
if [ -f "$AI_STATE_HELPER" ]; then
  # shellcheck source=ai-state.sh
  source "$AI_STATE_HELPER"
  AI_STATE_HELPER_READY=true
fi
RESTORE_ERRORS=()
SING_BOX_READY=true
SING_BOX_REQUESTED=false
SING_BOX_TUN_REQUIRED=false
TUN_MODULE_IS_MODULAR=false
ROTATE_TIMER_REQUESTED=false
USER_TIMER_REQUESTED=false
USER_MIHOMO_REQUESTED=false
PRESERVE_OMAMIGRATE=false
AI_BACKUP_MODE="$(cat "${RESTORE_DATA_DIR}/pkg_meta/ai_backup_mode.txt" 2>/dev/null || true)"
AI_HISTORY_REQUESTED=false
AI_RESTORE_PATHS=()

if [ "$AI_BACKUP_MODE" = complete ]; then
  AI_HISTORY_REQUESTED=true
elif [ -d "${RESTORE_DATA_DIR}/user_home/.codex/sessions" ] || \
     [ -d "${RESTORE_DATA_DIR}/user_home/.claude/projects" ] || \
     [ -d "${RESTORE_DATA_DIR}/user_home/.gemini/antigravity-cli/conversations" ] || \
     [ -d "${RESTORE_DATA_DIR}/user_home/.grok/sessions" ] || \
     [ -d "${RESTORE_DATA_DIR}/user_home/.omp/agent/sessions" ] || \
     [ -f "${RESTORE_DATA_DIR}/user_home/.local/share/opencode/opencode.db" ]; then
  # Backward compatibility for Complete archives made before mode metadata.
  AI_HISTORY_REQUESTED=true
  AI_BACKUP_MODE=complete
fi

if [ "$AI_STATE_HELPER_READY" = true ]; then
  if [ -f "${RESTORE_DATA_DIR}/pkg_meta/ai_state_paths.txt" ]; then
    while IFS= read -r ai_relative; do
      [ -n "$ai_relative" ] || continue
      if ! ai_valid_relative_path "$ai_relative"; then
        msg_error "Invalid AI state path in archive: ${ai_relative}"
        exit 1
      fi
      if [ ! -e "${RESTORE_DATA_DIR}/user_home/${ai_relative}" ] && \
         [ ! -L "${RESTORE_DATA_DIR}/user_home/${ai_relative}" ]; then
        msg_error "AI state metadata references a missing archive path: ${ai_relative}"
        exit 1
      fi
      AI_RESTORE_PATHS+=("$ai_relative")
    done < "${RESTORE_DATA_DIR}/pkg_meta/ai_state_paths.txt"
  else
    for ai_relative in "${AI_STATE_PATHS[@]}"; do
      if [ -e "${RESTORE_DATA_DIR}/user_home/${ai_relative}" ] || \
         [ -L "${RESTORE_DATA_DIR}/user_home/${ai_relative}" ]; then
        AI_RESTORE_PATHS+=("$ai_relative")
      fi
    done
  fi
fi

if [ -d "${RESTORE_DATA_DIR}/system_root/etc/sing-box" ] || \
   [ -f "${RESTORE_DATA_DIR}/system_root/etc/systemd/system/sing-box.service" ]; then
  SING_BOX_REQUESTED=true
fi
if grep -RqsE '"type"[[:space:]]*:[[:space:]]*"tun"' \
    --include='*.json' "${RESTORE_DATA_DIR}/system_root/etc/sing-box" 2>/dev/null; then
  SING_BOX_TUN_REQUIRED=true
fi
if [ -f "${RESTORE_DATA_DIR}/system_root/etc/systemd/system/sing-box-node-rotate.timer" ]; then
  ROTATE_TIMER_REQUESTED=true
  SING_BOX_REQUESTED=true
fi
if [ -f "${RESTORE_DATA_DIR}/user_home/.config/systemd/user/icloud-mail-triage.timer" ]; then
  USER_TIMER_REQUESTED=true
fi
if [ -f "${RESTORE_DATA_DIR}/user_home/.config/systemd/user/mihomo.service" ] || \
   [ -L "${RESTORE_DATA_DIR}/user_home/.config/systemd/user/mihomo.service" ]; then
  USER_MIHOMO_REQUESTED=true
fi

record_restore_error() {
  RESTORE_ERRORS+=("$*")
  msg_error "$*"
}

# Verify the immutable archive payload before changing the target home. The
# restored copies may later differ because source-home paths are translated.
if [ -s "${RESTORE_DATA_DIR}/pkg_meta/ai_manifest.sha256" ]; then
  if [ "$AI_STATE_HELPER_READY" != true ]; then
    msg_error "This archive contains verified AI state, but ai-state.sh is unavailable."
    exit 1
  fi
  msg_step "Verifying AI session archive integrity..."
  if ! ai_verify_manifest "${RESTORE_DATA_DIR}/user_home" \
      "${RESTORE_DATA_DIR}/pkg_meta/ai_manifest.sha256"; then
    msg_error "AI session archive verification failed; no restore changes were made."
    exit 1
  fi
fi

# Overwriting live SQLite/WAL and JSONL state can corrupt both source and target
# histories. Complete restores therefore require all supported agents closed.
if [ "$AI_HISTORY_REQUESTED" = true ]; then
  ACTIVE_AI_PROCESSES=()
  for ai_process in claude codex gemini agy antigravity agentapi grok omp opencode pi; do
    if pgrep -u "$(id -u)" -x "$ai_process" >/dev/null 2>&1; then
      ACTIVE_AI_PROCESSES+=("$ai_process")
    fi
  done
  if [ ${#ACTIVE_AI_PROCESSES[@]} -gt 0 ]; then
    msg_error "Close active AI agents before restoring Complete history: ${ACTIVE_AI_PROCESSES[*]}"
    exit 1
  fi
fi

# Sudo Privilege Initialization: Authenticate ONCE and keep alive
SUDO_PID=""

cleanup_privileges() {
  [ -n "${SUDO_PID:-}" ] && kill "${SUDO_PID}" 2>/dev/null || true
}
trap cleanup_privileges EXIT INT TERM

# If not authenticated yet, prompt in terminal or read from stdin pipe in GUI/non-interactive mode
if ! sudo -n true 2>/dev/null; then
  if [ -t 0 ]; then
    msg_info "Administrator privileges required to restore system configurations & packages."
    sudo -v || { msg_error "Administrator authentication failed."; exit 1; }
  else
    if IFS= read -r -t 1 -s SUDO_PASS; then
      printf '%s\n' "$SUDO_PASS" | sudo -S -p "" -v 2>/dev/null || true
      unset SUDO_PASS
    fi
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

# System restoration cannot converge without working privilege escalation.  Fail
# before making partial changes instead of printing a false success later.
if ! $ELEVATOR true 2>/dev/null; then
  msg_error "Administrator privileges are unavailable; restoration cannot continue safely."
  exit 1
fi

# Load TUN before package restoration. A full Arch upgrade can replace the
# running kernel's module directory; a module loaded beforehand remains usable
# until reboot, while the modules-load entry handles the newly installed kernel.
if [ "$SING_BOX_TUN_REQUIRED" = true ]; then
  modinfo tun >/dev/null 2>&1 && TUN_MODULE_IS_MODULAR=true
  if [ ! -c /dev/net/tun ] && ! $ELEVATOR modprobe tun; then
    record_restore_error "The TUN kernel module could not be loaded before package restoration."
    SING_BOX_READY=false
  fi
fi

msg_info "Starting OmaMigrate Ecosystem Restoration..."
msg_step "Target User: ${CURRENT_USER} (${CURRENT_HOME})"

# 2. Clear only a stale pacman database lock. Never race a live package manager.
if [ -f /var/lib/pacman/db.lck ]; then
  if pgrep -x pacman >/dev/null 2>&1 || pgrep -x yay >/dev/null 2>&1 || pgrep -x paru >/dev/null 2>&1; then
    msg_error "A package manager is currently running; wait for it to finish and retry restoration."
    exit 1
  fi
  msg_step "Clearing stale pacman lock file..."
  $ELEVATOR rm -f /var/lib/pacman/db.lck || {
    msg_error "Could not clear the stale pacman lock."
    exit 1
  }
fi

# 3. Restore user configuration files
msg_info "Restoring user configs and dotfiles..."
mkdir -p "${CURRENT_HOME}/.config" "${CURRENT_HOME}/.local/bin"

if [ -d "${RESTORE_DATA_DIR}/user_home" ]; then
  # Preserve the active plugin registration without ever modifying the unpacked
  # backup. Reusing an archive must produce the same input on every run.
  if grep -q "omamigrate" "${CURRENT_HOME}/.config/omarchy/shell.json" 2>/dev/null || \
     [ -n "${OMAMIGRATE_GUI:-}" ] || \
     [ -d "${CURRENT_HOME}/.config/omarchy/plugins/luneth90.omamigrate" ] || \
     [ -n "$(find "${CURRENT_HOME}/.config/omarchy/plugins" -maxdepth 1 -name "*omamigrate*" 2>/dev/null)" ]; then
    PRESERVE_OMAMIGRATE=true
  fi

  if [ "$USER_TIMER_REQUESTED" = true ]; then
    if systemctl --user is-active --quiet icloud-mail-triage.timer 2>/dev/null && \
       ! systemctl --user stop icloud-mail-triage.timer; then
      record_restore_error "Could not stop the active email triage timer before deployment."
    fi
    if systemctl --user is-active --quiet icloud-mail-triage.service 2>/dev/null && \
       ! systemctl --user stop icloud-mail-triage.service; then
      record_restore_error "Could not stop the active email triage service before deployment."
    fi
  fi
  if [ "$USER_MIHOMO_REQUESTED" = true ] && \
     systemctl --user is-active --quiet mihomo.service 2>/dev/null && \
     ! systemctl --user stop mihomo.service; then
    record_restore_error "Could not stop the active Mihoro-managed mihomo service before deployment."
  fi

  if [ "$AI_HISTORY_REQUESTED" = true ] && [ "$AI_STATE_HELPER_READY" = true ]; then
    msg_step "Removing stale AI database journals and runtime locks..."
    for ai_relative in "${AI_RESTORE_PATHS[@]}"; do
      if ! ai_cleanup_target_runtime_state "${CURRENT_HOME}/${ai_relative}"; then
        record_restore_error "Could not clean runtime state for ~/${ai_relative}."
      fi
    done
  fi

  if [ -d "${RESTORE_DATA_DIR}/user_home/.config" ]; then
    for cfg in "${RESTORE_DATA_DIR}/user_home/.config"/*; do
      [ -e "$cfg" ] && msg_step "Restoring config: ~/.config/$(basename "$cfg")"
    done
  fi
  for cred in .ssh .gnupg .password-store .claude .codex .gemini .pi .grok .omp .thunderbird .proxychains; do
    [ -d "${RESTORE_DATA_DIR}/user_home/$cred" ] && msg_step "Restoring credential store: ~/$cred"
  done

  # CRITICAL: Exclude ~/.config/omarchy/shell.json from the bulk extraction!
  # If shell.json is restored without luneth90.omamigrate, Quickshell's file watcher
  # detects the removal and instantly unloads OmaMigrate, which destroys the QML window
  # and kills the running restore process mid-flight.
  if command -v rsync >/dev/null 2>&1; then
    if ! rsync -a \
      --exclude='.config/omarchy/shell.json' \
      --exclude='.config/omarchy/plugins/*omamigrate*' \
      --exclude='.config/*omamigrate*' \
      --exclude='.local/bin/*omamigrate*' \
      --exclude='*omamigrate*' \
      "${RESTORE_DATA_DIR}/user_home/" "${CURRENT_HOME}/"; then
      record_restore_error "User configurations could not be restored completely."
    fi
  else
    if ! tar -C "${RESTORE_DATA_DIR}/user_home" \
      --exclude='./.config/omarchy/shell.json' \
      --exclude='.config/omarchy/shell.json' \
      --exclude='./.config/omarchy/plugins/*omamigrate*' \
      --exclude='.config/*omamigrate*' \
      --exclude='./.local/bin/*omamigrate*' \
      --exclude='*omamigrate*' \
      -cf - . | tar -C "${CURRENT_HOME}" -xpf -; then
      record_restore_error "User configurations could not be restored completely."
    fi
  fi

  # Restore ~/.config/omarchy/shell.json atomically:
  # If OmaMigrate is active or present, ensure "luneth90.omamigrate" is preserved
  # IN ADVANCE before writing to ~/.config/omarchy/shell.json.
  if [ -f "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json" ]; then
    mkdir -p "${CURRENT_HOME}/.config/omarchy"
    TARGET_SHELL_JSON="${CURRENT_HOME}/.config/omarchy/shell.json"
    TMP_SHELL_JSON="$(mktemp "${TARGET_SHELL_JSON}.XXXXXX" 2>/dev/null || mktemp)"
    if [ "$PRESERVE_OMAMIGRATE" = true ] && command -v jq >/dev/null 2>&1; then
      jq '.plugins = (.plugins // []) + (if any(.plugins[]?; (.id // "") == "luneth90.omamigrate") then [] else [{"id": "luneth90.omamigrate"}] end)' \
        "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json" > "$TMP_SHELL_JSON"
    elif [ "$PRESERVE_OMAMIGRATE" = true ] && command -v python3 >/dev/null 2>&1; then
      python3 -c '
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r") as f:
    d = json.load(f)
plugins = d.get("plugins", [])
if not any(x.get("id") == "luneth90.omamigrate" for x in plugins if isinstance(x, dict)):
    plugins.append({"id": "luneth90.omamigrate"})
d["plugins"] = plugins
with open(dst, "w") as f:
    json.dump(d, f, indent=2)
' "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json" "$TMP_SHELL_JSON"
    else
      cp -p "${RESTORE_DATA_DIR}/user_home/.config/omarchy/shell.json" "$TMP_SHELL_JSON"
    fi
    if [ -f "$TARGET_SHELL_JSON" ]; then
      chmod --reference="$TARGET_SHELL_JSON" "$TMP_SHELL_JSON" 2>/dev/null || true
    fi
    if mv "$TMP_SHELL_JSON" "$TARGET_SHELL_JSON"; then
      [ "$PRESERVE_OMAMIGRATE" = true ] && msg_step "Preserved OmaMigrate plugin registration in shell.json."
    else
      rm -f "$TMP_SHELL_JSON"
      record_restore_error "Could not safely restore shell.json configuration."
    fi
  fi
  if [ ${#RESTORE_ERRORS[@]} -eq 0 ]; then
    msg_ok "User configs and dotfiles extracted."
  fi
fi

# 4. Smart Path Adaptation (replaces old machine username with current username)
OLD_HOME="$(cat "${RESTORE_DATA_DIR}/pkg_meta/source_home.txt" 2>/dev/null || true)"
if [ -n "${OLD_HOME}" ] && [ "${CURRENT_HOME}" != "${OLD_HOME}" ]; then
  OLD_HOME_PATTERN="$(printf '%s' "$OLD_HOME" | sed 's/[][\\.^$*|]/\\&/g')"
  CURRENT_HOME_REPLACEMENT="$(printf '%s' "$CURRENT_HOME" | sed 's/[\\&|]/\\&/g')"

  replace_old_home() {
    local path="$1"
    [ -f "$path" ] && sed -i "s|${OLD_HOME_PATTERN}|${CURRENT_HOME_REPLACEMENT}|g" "$path"
  }

  msg_info "Adapting username paths (${OLD_HOME} -> ${CURRENT_HOME})..."
  msg_step "Translating AI, shell profiles and CLI agent configs..."
  replace_old_home "${CURRENT_HOME}/.codex/config.toml"
  replace_old_home "${CURRENT_HOME}/.claude.json"
  replace_old_home "${CURRENT_HOME}/.gemini/antigravity-cli/settings.json"
  replace_old_home "${CURRENT_HOME}/.gemini/config/config.json"
  replace_old_home "${CURRENT_HOME}/.gemini/config/mcp_config.json"
  replace_old_home "${CURRENT_HOME}/.claude/settings.json"
  replace_old_home "${CURRENT_HOME}/.pi/agent/settings.json"
  replace_old_home "${CURRENT_HOME}/.grok/config.toml"
  replace_old_home "${CURRENT_HOME}/.grok/trusted_folders.toml"
  replace_old_home "${CURRENT_HOME}/.omp/agent/config.yml"
  replace_old_home "${CURRENT_HOME}/.omp/agent/settings.json"
  replace_old_home "${CURRENT_HOME}/.config/opencode/opencode.json"
  replace_old_home "${CURRENT_HOME}/.config/opencode/tui.jsonc"
  for ai_relative in "${AI_RESTORE_PATHS[@]}"; do
    if [ -d "${CURRENT_HOME}/${ai_relative}" ]; then
      find "${CURRENT_HOME}/${ai_relative}" -type f \
        \( -name 'config.yml' -o -name 'config.yaml' \) \
        -exec sed -i "s|${OLD_HOME_PATTERN}|${CURRENT_HOME_REPLACEMENT}|g" {} + \
        2>/dev/null || true
    fi
  done
  [ -f "${CURRENT_HOME}/.config/git/config" ] && sed -i "s|!${OLD_HOME_PATTERN}.*gh auth git-credential|!gh auth git-credential|g" "${CURRENT_HOME}/.config/git/config"
  replace_old_home "${CURRENT_HOME}/.ssh/config"
  replace_old_home "${CURRENT_HOME}/.bashrc"
  replace_old_home "${CURRENT_HOME}/.bash_profile"
  replace_old_home "${CURRENT_HOME}/.profile"
  replace_old_home "${CURRENT_HOME}/.zshrc"
  replace_old_home "${CURRENT_HOME}/.zprofile"
  replace_old_home "${CURRENT_HOME}/.config/mihoro.toml"
  [ -d "${CURRENT_HOME}/.thunderbird" ] && find "${CURRENT_HOME}/.thunderbird" -type f -name "*.ini" -exec sed -i "s|${OLD_HOME_PATTERN}|${CURRENT_HOME_REPLACEMENT}|g" {} + 2>/dev/null || true

  msg_step "Translating proxy client paths..."
  for pdir in clash clash-verge clash-verge-rev clash-nyanpasu mihomo mihomo-party nekoray Matsuri flclash v2raya; do
    if [ -d "${CURRENT_HOME}/.config/${pdir}" ]; then
      find "${CURRENT_HOME}/.config/${pdir}" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \) \
        -exec sed -i "s|${OLD_HOME_PATTERN}|${CURRENT_HOME_REPLACEMENT}|g" {} + 2>/dev/null || true
    fi
  done

  if [ "$AI_STATE_HELPER_READY" = true ]; then
    msg_step "Renaming AI project indexes encoded with the source home path..."
    for ai_relative in "${AI_RESTORE_PATHS[@]}"; do
      if ! ai_rename_encoded_directories "${CURRENT_HOME}/${ai_relative}" "$OLD_HOME" "$CURRENT_HOME"; then
        record_restore_error "Could not translate encoded project paths in ~/${ai_relative}."
      fi
    done
  fi

  if [ -d "${CURRENT_HOME}/.config/systemd/user" ]; then
    find "${CURRENT_HOME}/.config/systemd/user" -type f \
      \( -name "*.service" -o -name "*.timer" -o -name "*.socket" -o -name "*.path" \) \
      -exec sed -i "s|${OLD_HOME_PATTERN}|${CURRENT_HOME_REPLACEMENT}|g" {} + 2>/dev/null || true
  fi

  msg_step "Adapting user symlinks pointing to old home..."
  SYMLINK_ROOTS=()
  for relative_root in .config .local .ssh .gnupg .password-store .claude .codex .gemini .pi .grok .omp .thunderbird .proxychains; do
    [ -e "${CURRENT_HOME}/${relative_root}" ] && SYMLINK_ROOTS+=("${CURRENT_HOME}/${relative_root}")
  done
  find "${SYMLINK_ROOTS[@]}" -type l 2>/dev/null | while IFS= read -r symlink; do
    target="$(readlink "$symlink" 2>/dev/null || true)"
    if [ "$target" = "$OLD_HOME" ] || [[ "$target" == "${OLD_HOME}/"* ]]; then
      new_target="${CURRENT_HOME}${target#${OLD_HOME}}"
      ln -snf "$new_target" "$symlink" 2>/dev/null || true
    fi
  done

  msg_ok "Username paths adapted successfully."
fi

# 5. Fix permissions for security and credentials
msg_info "Configuring secure permissions for credentials..."
msg_step "Securing ~/.ssh, ~/.gnupg, ~/.password-store..."
PERMISSION_ERROR_COUNT=${#RESTORE_ERRORS[@]}
for user_path in .config .local .ssh .gnupg .password-store .claude .codex .gemini .pi .grok .omp .thunderbird .proxychains; do
  if [ -e "${CURRENT_HOME}/${user_path}" ] && ! chmod -R u+rwX "${CURRENT_HOME}/${user_path}"; then
    record_restore_error "Could not restore user-write permissions on ~/${user_path}."
  fi
done
for ai_relative in "${AI_RESTORE_PATHS[@]}"; do
  if [ -e "${CURRENT_HOME}/${ai_relative}" ] && \
     ! chmod -R u+rwX "${CURRENT_HOME}/${ai_relative}"; then
    record_restore_error "Could not restore user-write permissions on ~/${ai_relative}."
  fi
done

if [ -d "${CURRENT_HOME}/.ssh" ]; then
  chmod 700 "${CURRENT_HOME}/.ssh" && \
    find "${CURRENT_HOME}/.ssh" -type f -exec chmod 600 {} + && \
    find "${CURRENT_HOME}/.ssh" -type f -name "*.pub" -exec chmod 644 {} + || \
    record_restore_error "Could not enforce SSH credential permissions."
  if [ -f "${CURRENT_HOME}/.ssh/known_hosts" ] && ! chmod 644 "${CURRENT_HOME}/.ssh/known_hosts"; then
    record_restore_error "Could not enforce known_hosts permissions."
  fi
fi
if [ -d "${CURRENT_HOME}/.gnupg" ] && \
   ! { chmod 700 "${CURRENT_HOME}/.gnupg" && find "${CURRENT_HOME}/.gnupg" -type f -exec chmod 600 {} +; }; then
  record_restore_error "Could not enforce GnuPG credential permissions."
fi
if [ -d "${CURRENT_HOME}/.password-store" ] && ! chmod 700 "${CURRENT_HOME}/.password-store"; then
  record_restore_error "Could not enforce password-store permissions."
fi
if [ -d "${CURRENT_HOME}/.local/bin" ] && \
   ! find "${CURRENT_HOME}/.local/bin" -maxdepth 1 -type f -exec chmod u+x {} +; then
  record_restore_error "Could not restore executable permissions in ~/.local/bin."
fi
if [ -d "${CURRENT_HOME}/.local/share/keyrings" ] && \
   ! { chmod 700 "${CURRENT_HOME}/.local/share/keyrings" && find "${CURRENT_HOME}/.local/share/keyrings" -maxdepth 1 -type f -exec chmod 600 {} +; }; then
  record_restore_error "Could not enforce desktop keyring permissions."
fi
if [ -d "${CURRENT_HOME}/.config/gh" ] && \
   ! { chmod 700 "${CURRENT_HOME}/.config/gh" && find "${CURRENT_HOME}/.config/gh" -maxdepth 1 -type f -exec chmod 600 {} +; }; then
  record_restore_error "Could not enforce GitHub CLI credential permissions."
fi
if [ -f "${CURRENT_HOME}/.config/mihoro.toml" ] && \
   ! chmod 600 "${CURRENT_HOME}/.config/mihoro.toml"; then
  record_restore_error "Could not secure the Mihoro configuration."
fi

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
if [ ${#RESTORE_ERRORS[@]} -eq "$PERMISSION_ERROR_COUNT" ]; then
  msg_ok "Credentials and keyrings secured."
fi

# 6. Restore system-level configs (sing-box, mihomo, v2raya, xray, v2ray, daed, proxychains)
if [ -d "${RESTORE_DATA_DIR}/system_root" ]; then
  msg_info "Restoring system-level proxy configurations..."

  # An already-active Persistent timer can fire while files are being copied.
  # Stop it before deployment; it is stamped and started again in Step 9.
  if [ "$ROTATE_TIMER_REQUESTED" = true ]; then
    if $ELEVATOR systemctl is-active --quiet sing-box-node-rotate.timer 2>/dev/null && \
       ! $ELEVATOR systemctl stop sing-box-node-rotate.timer; then
      record_restore_error "Could not stop the active sing-box rotation timer before deployment."
    fi
    if $ELEVATOR systemctl is-active --quiet sing-box-node-rotate.service 2>/dev/null && \
       ! $ELEVATOR systemctl stop sing-box-node-rotate.service; then
      record_restore_error "Could not stop the active sing-box rotation service before deployment."
    fi
  fi

  msg_step "Deploying /etc system configs..."
  # Do not copy the staging directory's own metadata onto `/`, and do not
  # preserve the staging user's ownership for privileged files.
  SYSTEM_ROOT_ITEMS=()
  shopt -s nullglob dotglob
  for system_root_item in "${RESTORE_DATA_DIR}/system_root"/*; do
    SYSTEM_ROOT_ITEMS+=("$(basename -- "$system_root_item")")
  done
  shopt -u nullglob dotglob
  if [ ${#SYSTEM_ROOT_ITEMS[@]} -gt 0 ] && \
     ! tar -C "${RESTORE_DATA_DIR}/system_root" -cf - -- "${SYSTEM_ROOT_ITEMS[@]}" | \
       $ELEVATOR tar -C / --no-same-owner --no-overwrite-dir -xpf -; then
      record_restore_error "System-level configurations could not be deployed."
  fi
  for system_config_name in sing-box mihomo v2raya xray v2ray daed; do
    if [ -d "${RESTORE_DATA_DIR}/system_root/etc/${system_config_name}" ] && \
       [ -d "/etc/${system_config_name}" ]; then
      $ELEVATOR find "/etc/${system_config_name}" -type f \
        \( -name '*.bak*' -o -name '*~' -o -name '*.tmp' \) -delete 2>/dev/null || \
        record_restore_error "Could not remove stale files from /etc/${system_config_name}."
    fi
  done

  for unit_name in sing-box.service sing-box-node-rotate.service sing-box-node-rotate.timer \
                   mihomo.service v2raya.service xray.service v2ray.service daed.service daed-next.service; do
    unit_source="${RESTORE_DATA_DIR}/system_root/etc/systemd/system/${unit_name}"
    unit_target="/etc/systemd/system/${unit_name}"
    if [ -e "$unit_source" ] || [ -L "$unit_source" ]; then
      if ! $ELEVATOR chown -h root:root "$unit_target"; then
        record_restore_error "Could not secure restored unit ${unit_name}."
      elif [ ! -L "$unit_target" ] && ! $ELEVATOR chmod 644 "$unit_target"; then
        record_restore_error "Could not set permissions on restored unit ${unit_name}."
      fi
    fi
  done
  if [ -f "${RESTORE_DATA_DIR}/system_root/usr/local/bin/sing-box-node-rotate" ] && \
     [ -f "/usr/local/bin/sing-box-node-rotate" ] && \
     ! { $ELEVATOR chown root:root /usr/local/bin/sing-box-node-rotate && \
         $ELEVATOR chmod 755 /usr/local/bin/sing-box-node-rotate; }; then
    record_restore_error "Could not secure the sing-box node rotation script."
  fi
  if [ -f "/etc/proxychains.conf" ] && \
     ! { $ELEVATOR chown root:root /etc/proxychains.conf && $ELEVATOR chmod 644 /etc/proxychains.conf; }; then
    record_restore_error "Could not secure /etc/proxychains.conf."
  fi
  if [ ${#RESTORE_ERRORS[@]} -eq 0 ]; then
    msg_ok "System-level configurations restored."
  fi
fi

# 7. Incremental package installation (arch-native & yay/AUR)
msg_info "Detecting and installing missing software packages..."
PKG_FILE="${RESTORE_DATA_DIR}/pkg_meta/packages_explicit.txt"

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
    NATIVE_PKGS=()
    AUR_PKGS=()
    for pkg in "${MISSING_PKGS[@]}"; do
      if pacman -Si "$pkg" >/dev/null 2>&1; then
        NATIVE_PKGS+=("$pkg")
      else
        AUR_PKGS+=("$pkg")
      fi
    done

    # Never pass a mixed repo/AUR list to pacman: one unknown target aborts the
    # complete transaction. Also avoid `pacman -Sy`, which creates a partial-
    # upgrade risk on Arch when it is not paired with a full upgrade.
    if [ ${#NATIVE_PKGS[@]} -gt 0 ]; then
      msg_step "Installing ${#NATIVE_PKGS[@]} native packages with pacman..."
      if ! $ELEVATOR pacman -Syu --needed --noconfirm "${NATIVE_PKGS[@]}"; then
        msg_warn "Some native packages could not be installed; critical dependencies will be checked separately."
      fi
    fi

    if [ ${#AUR_PKGS[@]} -gt 0 ]; then
      if command -v yay >/dev/null 2>&1; then
        msg_step "Installing ${#AUR_PKGS[@]} AUR packages with yay..."
        yay -S --needed --noconfirm --sudoflags "-n" --answerclean None --answerdiff None --answeredit None "${AUR_PKGS[@]}" < /dev/null || \
          msg_warn "Some AUR packages could not be installed: ${AUR_PKGS[*]}"
      else
        msg_warn "AUR packages require yay and were not installed: ${AUR_PKGS[*]}"
      fi
    fi
  else
    msg_ok "All required packages are already installed."
  fi
fi

# Ensure core dependencies
CORE_DEPS=(pass fcitx5 fcitx5-chinese-addons fcitx5-configtool jq curl github-cli rsync)
if [ "$SING_BOX_REQUESTED" = true ]; then
  CORE_DEPS+=("sing-box")
fi
if [ ${#AI_RESTORE_PATHS[@]} -gt 0 ]; then
  CORE_DEPS+=("python")
fi
CORE_MISSING=()
for cpkg in "${CORE_DEPS[@]}"; do
  if ! pacman -Qi "$cpkg" >/dev/null 2>&1; then
    CORE_MISSING+=("$cpkg")
  fi
done
if [ ${#CORE_MISSING[@]} -gt 0 ]; then
  msg_step "Installing missing core dependencies: ${CORE_MISSING[*]}"
  if ! $ELEVATOR pacman -Syu --needed --noconfirm "${CORE_MISSING[@]}"; then
    record_restore_error "One or more core dependencies could not be installed."
  fi
fi

CORE_STILL_MISSING=()
for cpkg in "${CORE_DEPS[@]}"; do
  pacman -Qi "$cpkg" >/dev/null 2>&1 || CORE_STILL_MISSING+=("$cpkg")
done
if [ ${#CORE_STILL_MISSING[@]} -gt 0 ]; then
  record_restore_error "Required packages are still missing: ${CORE_STILL_MISSING[*]}"
  if [[ " ${CORE_STILL_MISSING[*]} " == *" sing-box "* ]]; then
    SING_BOX_READY=false
  fi
else
  msg_ok "Package dependencies verified."
fi

# Update only structured path fields inside session JSON/JSONL and SQLite. User
# prompts and assistant text are intentionally left byte-for-byte unchanged.
if [ -n "$OLD_HOME" ] && [ "$CURRENT_HOME" != "$OLD_HOME" ] && \
   [ ${#AI_RESTORE_PATHS[@]} -gt 0 ]; then
  if [ "$AI_STATE_HELPER_READY" != true ]; then
    record_restore_error "AI path adaptation support is unavailable."
  elif ! command -v python3 >/dev/null 2>&1; then
    record_restore_error "python3 is required to translate AI session paths."
  else
    msg_step "Translating structured paths in AI histories and databases..."
    for ai_relative in "${AI_RESTORE_PATHS[@]}"; do
      if ! ai_adapt_json_paths "${CURRENT_HOME}/${ai_relative}" "$OLD_HOME" "$CURRENT_HOME"; then
        record_restore_error "Could not translate AI JSON history paths in ~/${ai_relative}."
      fi
      if ! ai_adapt_sqlite_paths "${CURRENT_HOME}/${ai_relative}" "$OLD_HOME" "$CURRENT_HOME"; then
        record_restore_error "Could not translate AI database paths in ~/${ai_relative}."
      fi
    done
  fi
fi

if [ "$PRESERVE_OMAMIGRATE" = true ] && [ -f "${CURRENT_HOME}/.config/omarchy/shell.json" ]; then
  SHELL_JSON="${CURRENT_HOME}/.config/omarchy/shell.json"
  SHELL_JSON_TMP="$(mktemp "${SHELL_JSON}.XXXXXX")"
  if jq '.plugins = (.plugins // []) + (if any(.plugins[]?; (.id // "") == "luneth90.omamigrate") then [] else [{"id": "luneth90.omamigrate"}] end)' \
      "$SHELL_JSON" > "$SHELL_JSON_TMP" && \
     chmod --reference="$SHELL_JSON" "$SHELL_JSON_TMP" && \
     mv "$SHELL_JSON_TMP" "$SHELL_JSON"; then
    msg_step "Preserved the active OmaMigrate plugin registration."
  else
    rm -f "$SHELL_JSON_TMP"
    record_restore_error "Could not preserve the active OmaMigrate plugin registration."
  fi
fi

# Post-install sing-box prerequisites and permissions. These are enforced after
# package installation so the service account/group exist on a fresh machine.
if [ "$SING_BOX_REQUESTED" = true ]; then
  msg_step "Enforcing sing-box configuration permissions and boot prerequisites..."

  if [ ! -d /etc/sing-box ]; then
    record_restore_error "The restored sing-box configuration directory is missing."
    SING_BOX_READY=false
  elif ! getent group sing-box >/dev/null 2>&1 || ! id -u sing-box >/dev/null 2>&1; then
    record_restore_error "The sing-box service account/group was not created by the package installation."
    SING_BOX_READY=false
  else
    if ! $ELEVATOR chown -R root:sing-box /etc/sing-box || \
       ! $ELEVATOR find /etc/sing-box -type d -exec chmod 750 {} + || \
       ! $ELEVATOR find /etc/sing-box -type f -exec chmod 640 {} + || \
       ! $ELEVATOR usermod -aG sing-box "$CURRENT_USER"; then
      record_restore_error "Could not enforce sing-box ownership and permissions."
      SING_BOX_READY=false
    fi
  fi

  if $ELEVATOR grep -RqsE '"type"[[:space:]]*:[[:space:]]*"tun"' \
      --include='*.json' /etc/sing-box; then
    SING_BOX_TUN_REQUIRED=true
  fi

  if [ "$SING_BOX_TUN_REQUIRED" = true ]; then
    if [ ! -c /dev/net/tun ]; then
      msg_step "Loading the TUN kernel module..."
      if ! $ELEVATOR modprobe tun; then
        record_restore_error "The TUN kernel module could not be loaded."
        SING_BOX_READY=false
      fi
    fi
    if [ ! -c /dev/net/tun ]; then
      record_restore_error "/dev/net/tun is unavailable after loading the TUN module."
      SING_BOX_READY=false
    fi

    # /dev is recreated at boot, so loading a module once is insufficient. If
    # TUN is modular, persist it through systemd-modules-load. A built-in driver
    # already survives reboot and must not get a bogus modules-load entry.
    if [ "$TUN_MODULE_IS_MODULAR" = true ] || modinfo tun >/dev/null 2>&1; then
      TUN_MODULE_FILE=/etc/modules-load.d/99-omamigrate-sing-box-tun.conf
      if ! $ELEVATOR install -d -m 755 /etc/modules-load.d; then
        record_restore_error "Could not persist the TUN kernel module requirement."
        SING_BOX_READY=false
      elif ! printf '%s\n' tun | $ELEVATOR cmp -s - "$TUN_MODULE_FILE"; then
        if ! printf '%s\n' tun | $ELEVATOR tee "$TUN_MODULE_FILE" >/dev/null; then
          record_restore_error "Could not persist the TUN kernel module requirement."
          SING_BOX_READY=false
        fi
      fi
      if ! $ELEVATOR chown root:root "$TUN_MODULE_FILE" || \
         ! $ELEVATOR chmod 644 "$TUN_MODULE_FILE"; then
        record_restore_error "Could not secure the TUN modules-load configuration."
        SING_BOX_READY=false
      fi
    else
      $ELEVATOR rm -f /etc/modules-load.d/99-omamigrate-sing-box-tun.conf 2>/dev/null || true
    fi
  else
    # Converge away from an OmaMigrate-owned directive when the restored
    # sing-box configuration no longer contains a TUN inbound.
    $ELEVATOR rm -f /etc/modules-load.d/99-omamigrate-sing-box-tun.conf 2>/dev/null || true
  fi

  if [ "$SING_BOX_READY" = true ]; then
    $ELEVATOR install -d -o sing-box -g sing-box -m 750 /var/lib/sing-box || {
      record_restore_error "Could not prepare the sing-box state directory."
      SING_BOX_READY=false
    }
  fi

  if [ "$SING_BOX_READY" = true ] && \
     ! $ELEVATOR -u sing-box sing-box -D /var/lib/sing-box -C /etc/sing-box check; then
    record_restore_error "The restored sing-box configuration failed validation."
    SING_BOX_READY=false
  fi
fi

cleanup_sing_box_runtime() {
  local interface_name
  local -a tun_interfaces=()

  $ELEVATOR test -d /etc/sing-box || return 0
  command -v jq >/dev/null 2>&1 || return 0

  mapfile -t tun_interfaces < <(
    $ELEVATOR find /etc/sing-box -type f -name '*.json' \
      -exec jq -r '.inbounds[]? | select(.type == "tun") | (.interface_name // "tun0")' {} + 2>/dev/null | sort -u
  )
  [ ${#tun_interfaces[@]} -gt 0 ] || return 0

  msg_step "Removing stale sing-box TUN interfaces and routing state..."
  for interface_name in "${tun_interfaces[@]}"; do
    if [[ "$interface_name" =~ ^[[:alnum:]_.:-]{1,15}$ ]] && \
       $ELEVATOR ip link show dev "$interface_name" >/dev/null 2>&1; then
      $ELEVATOR ip link delete dev "$interface_name" 2>/dev/null || true
    fi
  done

  # 2022 is sing-box's auto-route table. Remove only after confirming that the
  # restored configuration contains a TUN inbound.
  $ELEVATOR ip -4 route flush table 2022 2>/dev/null || true
  $ELEVATOR ip -6 route flush table 2022 2>/dev/null || true
  while $ELEVATOR ip -4 rule del table 2022 2>/dev/null; do :; done
  while $ELEVATOR ip -6 rule del table 2022 2>/dev/null; do :; done
}

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
if ! $ELEVATOR systemctl daemon-reload; then
  record_restore_error "systemd could not reload restored unit files."
fi

# Mihoro owns a per-user mihomo.service. Do not run the package-provided system
# service at the same time: both instances may contend for proxy ports, TUN and
# routing state. This also cleans up a system service started by an older restore.
if [ "$USER_MIHOMO_REQUESTED" = true ] && \
   $ELEVATOR systemctl cat mihomo.service >/dev/null 2>&1; then
  msg_step "Disabling the conflicting system-level mihomo service..."
  if ! $ELEVATOR systemctl disable --now mihomo.service; then
    record_restore_error "Could not disable the system-level mihomo service for Mihoro mode."
  fi
fi

for srv in sing-box mihomo v2raya xray v2ray daed daed-next; do
  if [ "$srv" = mihomo ] && [ "$USER_MIHOMO_REQUESTED" = true ]; then
    continue
  fi
  SERVICE_REQUESTED=false
  if [ -f "${RESTORE_DATA_DIR}/system_root/etc/systemd/system/${srv}.service" ] || \
     { [ "$srv" != daed-next ] && [ -d "${RESTORE_DATA_DIR}/system_root/etc/$srv" ]; }; then
    SERVICE_REQUESTED=true
  fi
  if [ "$SERVICE_REQUESTED" = true ]; then
    if ! $ELEVATOR systemctl cat "${srv}.service" >/dev/null 2>&1; then
      record_restore_error "The restored ${srv}.service unit is unavailable."
      continue
    fi
    if [ "$srv" = sing-box ] && [ "$SING_BOX_READY" != true ]; then
      msg_warn "sing-box prerequisites failed; leaving the service stopped."
      $ELEVATOR systemctl stop sing-box.service 2>/dev/null || true
      continue
    fi

    msg_step "Enabling and restarting $srv service..."
    if ! $ELEVATOR systemctl stop "${srv}.service"; then
      record_restore_error "Could not stop ${srv}.service before applying restored state."
      [ "$srv" = sing-box ] && SING_BOX_READY=false
      continue
    fi
    if [ "$srv" = sing-box ]; then
      cleanup_sing_box_runtime
    fi
    $ELEVATOR systemctl reset-failed "${srv}.service" 2>/dev/null || true

    if ! $ELEVATOR systemctl enable "${srv}.service"; then
      record_restore_error "Could not enable ${srv}.service."
      continue
    fi
    if ! $ELEVATOR systemctl restart "${srv}.service"; then
      record_restore_error "Could not restart ${srv}.service."
      [ "$srv" = sing-box ] && SING_BOX_READY=false
      continue
    fi
    if ! $ELEVATOR systemctl is-active --quiet "${srv}.service"; then
      record_restore_error "${srv}.service did not reach the active state."
      [ "$srv" = sing-box ] && SING_BOX_READY=false
    else
      msg_ok "${srv}.service is active."
    fi
  fi
done

if [ "$ROTATE_TIMER_REQUESTED" = true ]; then
  msg_step "Enabling sing-box-node-rotate timer..."
  # Prevent systemd Persistent=true from immediately triggering node rotation during restore
  if [ "$SING_BOX_READY" != true ]; then
    msg_warn "Leaving sing-box-node-rotate.timer stopped because sing-box is not healthy."
  elif ! $ELEVATOR install -d -m 755 /var/lib/systemd/timers || \
       ! $ELEVATOR touch /var/lib/systemd/timers/stamp-sing-box-node-rotate.timer; then
    record_restore_error "Could not update the sing-box rotation timer timestamp."
  else
    $ELEVATOR systemctl reset-failed sing-box-node-rotate.timer 2>/dev/null || true
    if ! $ELEVATOR systemctl enable --now sing-box-node-rotate.timer || \
       ! $ELEVATOR systemctl is-active --quiet sing-box-node-rotate.timer; then
      record_restore_error "sing-box-node-rotate.timer could not be activated."
    fi
  fi
fi

# User-level services and timers restored from the archive.
if [ "$USER_MIHOMO_REQUESTED" = true ] || [ "$USER_TIMER_REQUESTED" = true ]; then
  if ! systemctl --user daemon-reload; then
    record_restore_error "The user systemd manager could not reload unit files."
  fi
fi

if [ "$USER_MIHOMO_REQUESTED" = true ]; then
  msg_step "Enabling and restarting the Mihoro-managed mihomo service..."
  if ! systemctl --user cat mihomo.service >/dev/null 2>&1; then
    record_restore_error "The restored user mihomo.service unit is unavailable."
  else
    systemctl --user reset-failed mihomo.service 2>/dev/null || true
    if ! systemctl --user enable mihomo.service; then
      record_restore_error "Could not enable the Mihoro-managed mihomo.service."
    elif ! systemctl --user restart mihomo.service; then
      record_restore_error "Could not restart the Mihoro-managed mihomo.service."
    elif ! systemctl --user is-active --quiet mihomo.service; then
      record_restore_error "The Mihoro-managed mihomo.service did not reach the active state."
    else
      msg_ok "Mihoro-managed mihomo.service is active."
    fi
  fi
fi

if [ "$USER_TIMER_REQUESTED" = true ]; then
  msg_step "Enabling daily email triage timer..."
  systemctl --user reset-failed icloud-mail-triage.timer 2>/dev/null || true
  if ! systemctl --user enable --now icloud-mail-triage.timer || \
     ! systemctl --user is-active --quiet icloud-mail-triage.timer; then
    record_restore_error "icloud-mail-triage.timer could not be activated."
  fi
fi
if [ ${#RESTORE_ERRORS[@]} -eq 0 ]; then
  msg_ok "Background services and timers activated."
fi

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

if [ ${#RESTORE_ERRORS[@]} -gt 0 ]; then
  msg_error "Restoration completed with ${#RESTORE_ERRORS[@]} critical error(s):"
  for restore_error in "${RESTORE_ERRORS[@]}"; do
    echo "    - ${restore_error}" >&2
  done
  exit 1
fi

msg_ok "Restoration completed successfully and all critical services are healthy!"
