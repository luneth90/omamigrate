#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Automated Packaging & Export Engine
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"

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

# Initialize sudo credential cache if password provided by OmaMigrate GUI
if [ -n "${OMAMIGRATE_SUDO_PASS:-}" ]; then
  echo "$OMAMIGRATE_SUDO_PASS" | sudo -S -p "" -v 2>/dev/null || true
  unset OMAMIGRATE_SUDO_PASS
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

for f in .bashrc .bash_profile .profile .claude.json; do
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

# AI CLI state & configs (Toggleable: Full vs Lightweight)
OMAMIGRATE_FULL_AI="${OMAMIGRATE_FULL_AI:-0}"
if [ "$OMAMIGRATE_FULL_AI" = "1" ]; then
  msg_info "AI Backup Mode: Full (including complete chat histories, sessions & plugins)"
  AI_EXCLUDES=(
    "--exclude=cache"
    "--exclude=Cache"
    "--exclude=GPUCache"
    "--exclude=logs"
    "--exclude=log"
    "--exclude=*.log"
    "--exclude=*.sock"
  )
else
  msg_info "AI Backup Mode: Lightweight (credentials & configs only, skipping large sessions/binaries)"
  AI_EXCLUDES=(
    "--exclude=sessions"
    "--exclude=projects"
    "--exclude=plugins"
    "--exclude=bin"
    "--exclude=conversations"
    "--exclude=brain"
    "--exclude=bundled"
    "--exclude=marketplace-cache"
    "--exclude=vendor"
    "--exclude=.tmp"
    "--exclude=cache"
    "--exclude=Cache"
    "--exclude=GPUCache"
    "--exclude=logs"
    "--exclude=log"
    "--exclude=*.log"
    "--exclude=*.sqlite*"
    "--exclude=*.sock"
  )
fi

for agent_dir in "${AI_AGENT_DIRS[@]}"; do
  if [ -d "$HOME/$agent_dir" ]; then
    msg_step "Including AI state: ~/${agent_dir}"
    mkdir -p "${BACKUP_DIR}/user_home/$agent_dir"
    rsync -a "${AI_EXCLUDES[@]}" \
      "$HOME/$agent_dir/" "${BACKUP_DIR}/user_home/$agent_dir/" 2>/dev/null || true
  fi
done

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
    msg_warn "Could not archive protected configs (authentication cancelled or failed)."
  fi
fi

# 4. Embed the automated restore script
msg_info "Embedding restore engine..."
cp -p "${SCRIPT_DIR}/restore.sh" "${BACKUP_DIR}/restore.sh"
chmod +x "${BACKUP_DIR}/restore.sh"

# 5. Build final compressed archive
msg_info "Creating final archive at ${OUTPUT_FILE}..."
tar -czf "${OUTPUT_FILE}" -C "${BACKUP_DIR}" .

msg_ok "Migration backup created successfully: ${OUTPUT_FILE} ($(du -h "${OUTPUT_FILE}" | cut -f1))"


