#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Automated Packaging & Export Engine
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/ai-state.sh"

if ! command -v rsync >/dev/null 2>&1; then
  msg_error "rsync is required to create a migration backup. Install it and retry."
  exit 1
fi

if [ -n "${1:-}" ]; then
  OUTPUT_FILE="$1"
else
  HOST_SLUG="$(hostname -s 2>/dev/null || echo "omarchy")"
  HOST_SLUG="$(echo "${HOST_SLUG}" | tr -cd '[:alnum:]_-')"
  [ -z "${HOST_SLUG}" ] && HOST_SLUG="omarchy"
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  OUTPUT_FILE="$HOME/omamigrate-${HOST_SLUG}-${TIMESTAMP}.tar.gz"
fi

STAGING_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/omamigrate"
mkdir -p "$STAGING_BASE"
chmod 700 "$STAGING_BASE"
rm -rf "${STAGING_BASE}/export-"* 2>/dev/null || true

BACKUP_DIR="$(mktemp -d "${STAGING_BASE}/export-XXXXXX")"
trap 'rm -rf "${BACKUP_DIR:-}"' EXIT INT TERM

# Privilege Elevation Initialization: Authenticate once via stdin stream if non-interactive
if ! sudo -n true 2>/dev/null; then
  if [ ! -t 0 ]; then
    if IFS= read -r -t 1 -s SUDO_PASS; then
      printf '%s\n' "$SUDO_PASS" | sudo -S -p "" -v 2>/dev/null || true
      unset SUDO_PASS
    fi
  fi
fi

msg_info "Creating OmaMigrate migration backup..."
msg_step "Creating staging directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}/user_home"
mkdir -p "${BACKUP_DIR}/system_root"
mkdir -p "${BACKUP_DIR}/pkg_meta"

# 1. Export Package Lists (with hardware driver blacklist filter)
msg_info "Scanning and filtering installed software packages..."
pacman -Qqe | grep -vE "${HW_EXCLUDE_REGEX}" > "${BACKUP_DIR}/pkg_meta/packages_explicit.txt" || true
pacman -Qqem > "${BACKUP_DIR}/pkg_meta/packages_aur.txt" 2>/dev/null || true
echo "$HOME" > "${BACKUP_DIR}/pkg_meta/source_home.txt"
echo "$(id -un)" > "${BACKUP_DIR}/pkg_meta/source_user.txt"
msg_ok "Recorded $(wc -l < "${BACKUP_DIR}/pkg_meta/packages_explicit.txt") explicit packages (hardware drivers excluded)"

# 2. Export User Dotfiles & Credentials
msg_info "Archiving user dotfiles and authentication credentials..."

for f in .bashrc .bash_profile .profile .zshrc .zprofile .claude.json; do
  [ -f "$HOME/$f" ] && cp -p "$HOME/$f" "${BACKUP_DIR}/user_home/"
done

for dir in .ssh .gnupg .password-store .proxychains; do
  if [ -d "$HOME/$dir" ]; then
    msg_step "Including credential / proxy store: ~/${dir}"
    cp -rp "$HOME/$dir" "${BACKUP_DIR}/user_home/"
  fi
done

# User scripts
mkdir -p "${BACKUP_DIR}/user_home/.local/bin"
if [ -d "$HOME/.local/bin" ]; then
  msg_step "Including user scripts: ~/.local/bin"
  cp -rp "$HOME/.local/bin"/* "${BACKUP_DIR}/user_home/.local/bin/" 2>/dev/null || true
  # Exclude OmaMigrate binary/symlinks from backup
  rm -f "${BACKUP_DIR}/user_home/.local/bin/"*omamigrate* 2>/dev/null || true
fi

# Linux desktop Secret Service / Keyrings (agy, VS Code, Git, Chrome credentials)
if [ -d "$HOME/.local/share/keyrings" ]; then
  msg_step "Including desktop keyrings: ~/.local/share/keyrings"
  mkdir -p "${BACKUP_DIR}/user_home/.local/share"
  cp -rp "$HOME/.local/share/keyrings" "${BACKUP_DIR}/user_home/.local/share/"
fi

# User application configs
mkdir -p "${BACKUP_DIR}/user_home/.config"
for item in "${CONFIG_TARGETS[@]}"; do
  if [ -e "$HOME/.config/$item" ]; then
    msg_step "Including config: ~/.config/${item}"
    if [ -d "$HOME/.config/$item" ]; then
      rsync -a --exclude='Cache' --exclude='GPUCache' --exclude='*.asar' --exclude='*.sock' \
        --exclude='plugins/*omamigrate*' --exclude='*omamigrate*' \
        "$HOME/.config/$item" "${BACKUP_DIR}/user_home/.config/" 2>/dev/null || true
    else
      cp -p "$HOME/.config/$item" "${BACKUP_DIR}/user_home/.config/"
    fi
  fi
done

# Strictly exclude OmaMigrate plugin files, directories, and registrations
rm -rf "${BACKUP_DIR}/user_home/.config/omarchy/plugins/"*omamigrate* 2>/dev/null || true
rm -rf "${BACKUP_DIR}/user_home/.config/"*omamigrate* 2>/dev/null || true

# Strip omamigrate plugin registration from exported shell.json
if [ -f "${BACKUP_DIR}/user_home/.config/omarchy/shell.json" ] && command -v jq >/dev/null 2>&1; then
  jq '.plugins = [.plugins[]? | select((.id // "") | test("omamigrate") | not)]' \
    "${BACKUP_DIR}/user_home/.config/omarchy/shell.json" > "${BACKUP_DIR}/user_home/.config/omarchy/shell.json.tmp" && \
    mv "${BACKUP_DIR}/user_home/.config/omarchy/shell.json.tmp" "${BACKUP_DIR}/user_home/.config/omarchy/shell.json"
fi

# Export portable GitHub CLI credentials (so gh works even without unlocked keyring on target)
if command -v gh >/dev/null 2>&1; then
  GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
  if [ -n "$GH_TOKEN" ] && [ -n "$GH_USER" ]; then
    msg_step "Including standalone GitHub CLI authentication for ${GH_USER}..."
    mkdir -p "${BACKUP_DIR}/user_home/.config/gh"
    cat << EOF > "${BACKUP_DIR}/user_home/.config/gh/hosts.yml"
github.com:
    git_protocol: https
    user: ${GH_USER}
    oauth_token: ${GH_TOKEN}
    users:
        ${GH_USER}:
            oauth_token: ${GH_TOKEN}
EOF
    chmod 600 "${BACKUP_DIR}/user_home/.config/gh/hosts.yml"
    [ -f "$HOME/.config/gh/config.yml" ] && cp -p "$HOME/.config/gh/config.yml" "${BACKUP_DIR}/user_home/.config/gh/"
  fi
fi

# AI CLI state & configs (Toggleable: Complete vs Standard)
OMAMIGRATE_FULL_AI="${OMAMIGRATE_FULL_AI:-0}"
AI_COPIED_ROOTS=()
AI_HOME_ROOT="$(realpath -ms -- "$HOME")"

register_ai_home_path() {
  local requested="${1%/}"
  local absolute relative existing
  [ -e "$requested" ] || [ -L "$requested" ] || return 0
  absolute="$(realpath -ms -- "$requested")"
  case "$absolute" in
    "${AI_HOME_ROOT}/"*) relative="${absolute#${AI_HOME_ROOT}/}" ;;
    *)
      msg_error "AI state outside the home directory is not portable: ${absolute}"
      return 1
      ;;
  esac
  for existing in "${AI_STATE_PATHS[@]}"; do
    if [ "$relative" = "$existing" ] || [[ "$relative" == "${existing}/"* ]]; then
      return 0
    fi
  done
  AI_STATE_PATHS+=("$relative")
}

register_ai_standard_item() {
  local relative="$1"
  local existing
  for existing in "${AI_STANDARD_ITEMS[@]}"; do
    [ "$relative" = "$existing" ] && return 0
  done
  AI_STANDARD_ITEMS+=("$relative")
}

# Honor XDG and agent-specific overrides when they point inside the portable
# home tree. Normalized paths outside $HOME are rejected instead of being copied
# into an archive path containing '..'.
opencode_config_root="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
opencode_data_root="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
omp_xdg_root="${XDG_DATA_HOME:-$HOME/.local/share}/omp"
omp_config_root="${HOME}/${PI_CONFIG_DIR:-.omp}"
register_ai_home_path "$opencode_config_root" || exit 1
register_ai_home_path "$opencode_data_root" || exit 1
register_ai_home_path "${XDG_STATE_HOME:-$HOME/.local/state}/opencode" || exit 1
register_ai_home_path "$omp_xdg_root" || exit 1
register_ai_home_path "$omp_config_root" || exit 1
if [[ "$opencode_config_root" == "${HOME}/"* ]]; then
  opencode_config_relative="${opencode_config_root#${HOME}/}"
  register_ai_standard_item "${opencode_config_relative}/opencode.json"
  register_ai_standard_item "${opencode_config_relative}/tui.jsonc"
fi
if [[ "$opencode_data_root" == "${HOME}/"* ]]; then
  opencode_data_relative="${opencode_data_root#${HOME}/}"
  register_ai_standard_item "${opencode_data_relative}/auth.json"
fi
if [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
  register_ai_home_path "$PI_CODING_AGENT_DIR" || exit 1
  if [[ "$PI_CODING_AGENT_DIR" == "${HOME}/"* ]]; then
    custom_omp_relative="${PI_CODING_AGENT_DIR#${HOME}/}"
    register_ai_standard_item "${custom_omp_relative}/config.yml"
    register_ai_standard_item "${custom_omp_relative}/settings.json"
    register_ai_standard_item "${custom_omp_relative}/agent.db"
  fi
fi

# OMP named profiles relocate the complete agent tree below
# <root>/profiles/<name>/agent. Standard mode keeps only each root/profile's
# config and auth database; Complete mode includes the whole registered root.
OMP_CONFIG_ROOTS=("${HOME}/.omp" "$omp_config_root" "$omp_xdg_root")
for omp_root in "${OMP_CONFIG_ROOTS[@]}"; do
  [ -d "$omp_root" ] || continue
  omp_root="$(realpath -ms -- "$omp_root")"
  if [[ "$omp_root" == "${AI_HOME_ROOT}/"* ]]; then
    omp_relative="${omp_root#${AI_HOME_ROOT}/}"
    for omp_item in config.yml config.yaml settings.json agent.db; do
      register_ai_standard_item "${omp_relative}/agent/${omp_item}"
    done
    if [ -d "${omp_root}/profiles" ]; then
      while IFS= read -r -d '' profile_item; do
        register_ai_standard_item "${profile_item#${AI_HOME_ROOT}/}"
      done < <(find "${omp_root}/profiles" -type f \
        \( -path '*/agent/config.yml' -o -path '*/agent/config.yaml' -o \
           -path '*/agent/settings.json' -o -path '*/agent/agent.db' \) -print0)
    fi
  fi
done

# OpenCode supports relocating its SQLite history with OPENCODE_DB. Preserve
# custom locations only when they remain inside the portable home tree.
if [ -n "${OPENCODE_DB:-}" ]; then
  register_ai_home_path "$OPENCODE_DB" || exit 1
fi

copy_ai_standard_item() {
  local relative="$1"
  local source="${HOME}/${relative}"
  local destination="${BACKUP_DIR}/user_home/${relative}"

  [ -e "$source" ] || [ -L "$source" ] || return 0
  mkdir -p "$(dirname "$destination")"
  if [ -d "$source" ]; then
    mkdir -p "$destination"
    rsync -a \
      --exclude='cache' --exclude='Cache' --exclude='GPUCache' \
      --exclude='logs' --exclude='log' --exclude='*.log' \
      --exclude='*.sock' --exclude='*.lock' --exclude='*.pid' \
      "${source%/}/" "${destination}/"
  elif [ "$(head -c 15 "$source" 2>/dev/null || true)" = "SQLite format 3" ]; then
    ai_snapshot_sqlite_file "$source" "$destination"
  else
    cp -pL "$source" "$destination"
  fi
}

if [ "$OMAMIGRATE_FULL_AI" = "1" ]; then
  msg_info "AI Backup Mode: Complete (histories, sessions, memories & plugins)"
  for relative in "${AI_STATE_PATHS[@]}"; do
    source_path="${HOME}/${relative}"
    destination_path="${BACKUP_DIR}/user_home/${relative}"
    [ -e "$source_path" ] || [ -L "$source_path" ] || continue

    msg_step "Snapshotting AI state: ~/${relative}"
    mkdir -p "$(dirname "$destination_path")"
    if [ -d "$source_path" ]; then
      database_source_path="$source_path"
      if [ -L "$source_path" ]; then
        database_source_path="$(realpath -e -- "$source_path")"
      fi
      mkdir -p "$destination_path"
      # Databases are copied separately with SQLite's online backup API. This
      # produces one consistent database even if WAL mode is in use.
      if ! rsync -a "${AI_COMPLETE_RSYNC_EXCLUDES[@]}" \
          "${source_path%/}/" "${destination_path}/"; then
        msg_error "Could not snapshot AI state: ~/${relative}"
        exit 1
      fi
      if ! ai_snapshot_databases_in_tree "$database_source_path" "$destination_path"; then
        msg_error "Could not create a consistent AI database snapshot for ~/${relative}."
        exit 1
      fi
      # A second non-database pass catches JSONL/session-index appends that
      # occurred while the transactional database snapshots were being made.
      if ! rsync -a --checksum "${AI_COMPLETE_RSYNC_EXCLUDES[@]}" \
          "${source_path%/}/" "${destination_path}/"; then
        msg_error "AI state changed too quickly to snapshot reliably: ~/${relative}"
        exit 1
      fi
    elif ! copy_ai_standard_item "$relative"; then
      msg_error "Could not snapshot AI state file: ~/${relative}"
      exit 1
    fi
  done
  for relative in "${AI_COMPLETE_EXTRA_ITEMS[@]}"; do
    if ! copy_ai_standard_item "$relative"; then
      msg_error "Could not preserve the Agy session index: ~/${relative}"
      exit 1
    fi
  done
  printf '%s\n' complete > "${BACKUP_DIR}/pkg_meta/ai_backup_mode.txt"
else
  msg_info "AI Backup Mode: Standard (credentials & configs only; no histories or plugins)"
  for relative in "${AI_STANDARD_ITEMS[@]}"; do
    if ! copy_ai_standard_item "$relative"; then
      msg_error "Could not back up AI configuration: ~/${relative}"
      exit 1
    fi
  done
  printf '%s\n' standard > "${BACKUP_DIR}/pkg_meta/ai_backup_mode.txt"
fi

# Record exactly which logical roots were included and checksum every AI file.
# Restore verifies this before replacing any live agent state.
for relative in "${AI_STATE_PATHS[@]}"; do
  if [ -e "${BACKUP_DIR}/user_home/${relative}" ] || \
     [ -L "${BACKUP_DIR}/user_home/${relative}" ]; then
    AI_COPIED_ROOTS+=("$relative")
  fi
done
printf '%s\n' "${AI_COPIED_ROOTS[@]}" > "${BACKUP_DIR}/pkg_meta/ai_state_paths.txt"
if ! ai_write_manifest "${BACKUP_DIR}/user_home" \
    "${BACKUP_DIR}/pkg_meta/ai_manifest.sha256" "${AI_COPIED_ROOTS[@]}"; then
  msg_error "Could not create the AI state integrity manifest."
  exit 1
fi
msg_ok "AI state manifest recorded ($(wc -l < "${BACKUP_DIR}/pkg_meta/ai_manifest.sha256") files)."

# Desktop Mail Clients (Thunderbird profiles & account settings)
if [ -d "$HOME/.thunderbird" ]; then
  msg_step "Including Thunderbird profiles: ~/.thunderbird"
  mkdir -p "${BACKUP_DIR}/user_home/.thunderbird"
  rsync -a --exclude='cache2' --exclude='startupCache' \
    "$HOME/.thunderbird/" "${BACKUP_DIR}/user_home/.thunderbird/" 2>/dev/null || true
fi

# 3. System-level Services & Proxy Configuration
msg_info "Collecting system-level proxy configurations & services..."

mkdir -p "${BACKUP_DIR}/system_root"

unreadable_paths=()
readable_paths=()

for pdir in "${PROXY_SYSTEM_DIRS[@]}"; do
  if [ -d "$pdir" ]; then
    if find "$pdir" ! -readable -print -quit 2>/dev/null | grep -q .; then
      unreadable_paths+=("$pdir")
    else
      readable_paths+=("$pdir")
    fi
  fi
done

for pfile in "${PROXY_SYSTEM_FILES[@]}"; do
  if [ -f "$pfile" ]; then
    if [ -r "$pfile" ]; then
      readable_paths+=("$pfile")
    else
      unreadable_paths+=("$pfile")
    fi
  fi
done

for s in "${PROXY_SYSTEM_SERVICES[@]}"; do
  sfile="/etc/systemd/system/$s"
  if [ -f "$sfile" ]; then
    if [ -r "$sfile" ]; then
      readable_paths+=("$sfile")
    else
      unreadable_paths+=("$sfile")
    fi
  fi
done

# Copy readable system files directly as user (NO ROOT, NO PASSWORD!)
for path in "${readable_paths[@]}"; do
  msg_step "Backing up system config: ${path}"
  if [ -d "$path" ]; then
    mkdir -p "${BACKUP_DIR}/system_root${path}"
    cp -rp "${path}/." "${BACKUP_DIR}/system_root${path}/" 2>/dev/null || true
  elif [ -f "$path" ]; then
    mkdir -p "${BACKUP_DIR}/system_root$(dirname "$path")"
    cp -p "$path" "${BACKUP_DIR}/system_root${path}" 2>/dev/null || true
  fi
done

# If any protected system paths require elevation, do it ONCE via Polkit (pkexec) or sudo
if [ "${#unreadable_paths[@]}" -gt 0 ]; then
  msg_info "Protected system paths detected: ${unreadable_paths[*]}"
  tar_args=()
  for p in "${unreadable_paths[@]}"; do
    tar_args+=("${p#/}")
  done

  if ! sudo -n true 2>/dev/null; then
    if [ -t 0 ]; then
      msg_step "Requesting administrator privileges..."
      sudo -v || { msg_error "Administrator authentication failed."; exit 1; }
    else
      if IFS= read -r -t 1 -s SUDO_PASS; then
        printf '%s\n' "$SUDO_PASS" | sudo -S -p "" -v 2>/dev/null || true
        unset SUDO_PASS
      fi
    fi
  fi

  if sudo -n true 2>/dev/null; then
    ELEVATOR="sudo -n"
  elif [ -t 0 ]; then
    ELEVATOR="sudo"
  else
    ELEVATOR="sudo -n"
  fi

  msg_step "Requesting elevation (${ELEVATOR}) to archive protected configs..."
  if $ELEVATOR tar -C / -cf - "${tar_args[@]}" 2>/dev/null | tar -C "${BACKUP_DIR}/system_root" -xf - 2>/dev/null; then
    msg_ok "Protected configs archived."
  else
    msg_error "Could not archive protected system configs; refusing to create an incomplete migration backup."
    exit 1
  fi
fi

# Clean up temporary, editor swap, and historical backup files from system_root
find "${BACKUP_DIR}/system_root" -type f \( -name "*.bak*" -o -name "*~" -o -name "*.tmp" \) -delete 2>/dev/null || true

# 4. Embed the automated restore script
msg_info "Embedding restore engine..."
cp -p "${SCRIPT_DIR}/restore.sh" "${BACKUP_DIR}/restore.sh"
cp -p "${SCRIPT_DIR}/ai-state.sh" "${BACKUP_DIR}/ai-state.sh"
chmod +x "${BACKUP_DIR}/restore.sh"

# 5. Build final compressed archive
msg_info "Creating final archive at ${OUTPUT_FILE}..."
tar -czf "${OUTPUT_FILE}" -C "${BACKUP_DIR}" .

# Record last backup location for automated tooling & GUI
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/omamigrate"
echo "${OUTPUT_FILE}" > "${XDG_CACHE_HOME:-$HOME/.cache}/omamigrate/last_backup" 2>/dev/null || true

msg_ok "Migration backup created successfully: ${OUTPUT_FILE} ($(du -h "${OUTPUT_FILE}" | cut -f1))"
