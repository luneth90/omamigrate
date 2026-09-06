#!/usr/bin/env bash
set -euo pipefail

# Resolve the configured XDG download directory without making assumptions about
# its translated name. Fall back to parsing the XDG config when the helper is
# unavailable, and only use ~/Downloads when neither source is configured.
resolve_download_dir() {
  local directory=""
  local config_file="${XDG_CONFIG_HOME:-${HOME}/.config}/user-dirs.dirs"
  local configured_value=""

  if command -v xdg-user-dir >/dev/null 2>&1; then
    directory="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
  fi

  if [ -z "${directory}" ] && [ -r "${config_file}" ]; then
    configured_value="$(sed -n '/^XDG_DOWNLOAD_DIR=/{s/^XDG_DOWNLOAD_DIR=//;p;q;}' "${config_file}")"
    configured_value="${configured_value#\"}"
    configured_value="${configured_value%\"}"
    case "${configured_value}" in
      "\$HOME") directory="${HOME}" ;;
      "\$HOME/"*) directory="${HOME}/${configured_value#\$HOME/}" ;;
      /*) directory="${configured_value}" ;;
    esac
  fi

  printf '%s' "${directory:-${HOME}/Downloads}"
}

download_dir="$(resolve_download_dir)"

json_escape() {
  local value="${1}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

archives=()
while IFS= read -r -d '' archive; do
  archives+=("${archive}")
done < <(
  if [ -d "${download_dir}" ]; then
    find "${download_dir}" -maxdepth 2 -type f \
      \( -iname '*migration*.tar.gz' -o -iname '*migration*.tgz' \
         -o -iname '*migrate*.tar.gz' -o -iname '*migrate*.tgz' \) \
      -print0 2>/dev/null
  fi | sort -zu
)

printf '['
for index in "${!archives[@]}"; do
  archive="${archives[$index]}"
  name="$(basename "${archive}")"
  size="$(du -h "${archive}" 2>/dev/null | cut -f1)"
  timestamp="$(stat -c '%Y' "${archive}" 2>/dev/null || printf '0')"
  date_text="$(date -d "@${timestamp}" '+%m/%d %H:%M' 2>/dev/null || printf 'unknown')"

  if [ "${index}" -gt 0 ]; then
    printf ','
  fi
  printf '{"name":"%s","path":"%s","size":"%s","date":"%s"}' \
    "$(json_escape "${name}")" \
    "$(json_escape "${archive}")" \
    "$(json_escape "${size}")" \
    "$(json_escape "${date_text}")"
done
printf ']\n'
