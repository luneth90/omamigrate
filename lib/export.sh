#!/usr/bin/env bash
# ==============================================================================
# OmaMigrate: Automated Packaging & Export Engine
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"

OUTPUT_FILE="${1:-$HOME/omarchy-migration.tar.gz}"
BACKUP_DIR="$(mktemp -d -t omamigrate-XXXXXX)"

trap 'rm -rf "${BACKUP_DIR}"' EXIT

msg_info "Starting OmaMigrate Export..."
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
msg_ok "Exported $(wc -l < "${BACKUP_DIR}/pkg_meta/packages_explicit.txt") explicit packages (hardware drivers excluded)"

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
fi

# User application configs
mkdir -p "${BACKUP_DIR}/user_home/.config"
for item in "${CONFIG_TARGETS[@]}"; do
  if [ -e "$HOME/.config/$item" ]; then
    msg_step "Including config: ~/.config/${item}"
    cp -rp "$HOME/.config/$item" "${BACKUP_DIR}/user_home/.config/"
  fi
done

# AI CLI state & configs (excluding bulky sqlite caches and logs)
for agent_dir in "${AI_AGENT_DIRS[@]}"; do
  if [ -d "$HOME/$agent_dir" ]; then
    msg_step "Including AI state: ~/${agent_dir}"
    mkdir -p "${BACKUP_DIR}/user_home/$agent_dir"
    rsync -a --exclude='cache' --exclude='Cache' --exclude='logs' --exclude='log' --exclude='*.log' --exclude='*.sqlite*' \
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
msg_info "Collecting system-level proxy configurations & services (requires sudo access)..."

# Proxy directories in /etc
for pdir in "${PROXY_SYSTEM_DIRS[@]}"; do
  if [ -d "$pdir" ]; then
    msg_step "Backing up system proxy directory: ${pdir}"
    sudo mkdir -p "${BACKUP_DIR}/system_root${pdir}"
    sudo cp -rp "${pdir}/." "${BACKUP_DIR}/system_root${pdir}/" 2>/dev/null || true
  fi
done

# Proxy individual files (e.g. /etc/proxychains.conf, /usr/local/bin/sing-box-node-rotate)
for pfile in "${PROXY_SYSTEM_FILES[@]}"; do
  if [ -f "$pfile" ]; then
    msg_step "Backing up system proxy file: ${pfile}"
    sudo mkdir -p "${BACKUP_DIR}/system_root$(dirname "$pfile")"
    sudo cp -p "$pfile" "${BACKUP_DIR}/system_root${pfile}" 2>/dev/null || true
  fi
done

# Systemd units for proxies & services
sudo mkdir -p "${BACKUP_DIR}/system_root/etc/systemd/system"
for s in "${PROXY_SYSTEM_SERVICES[@]}"; do
  if [ -f "/etc/systemd/system/$s" ]; then
    msg_step "Backing up systemd unit: ${s}"
    sudo cp -p "/etc/systemd/system/$s" "${BACKUP_DIR}/system_root/etc/systemd/system/"
  fi
done

# Reclaim permissions on staging dir
sudo chown -R "$(id -un):$(id -gn)" "${BACKUP_DIR}"

# 4. Embed the automated restore script
msg_info "Embedding restore engine..."
cp -p "${SCRIPT_DIR}/restore.sh" "${BACKUP_DIR}/restore.sh"
chmod +x "${BACKUP_DIR}/restore.sh"

# 5. Build final compressed archive
msg_info "Creating final archive at ${OUTPUT_FILE}..."
tar -czf "${OUTPUT_FILE}" -C "${BACKUP_DIR}" .

msg_ok "Archive created successfully: ${OUTPUT_FILE} ($(du -h "${OUTPUT_FILE}" | cut -f1))"
