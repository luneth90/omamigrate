#!/usr/bin/env bash
set -euo pipefail

# Resolve localized XDG download folders (for example ~/下载), then also check
# the home directory because OmaMigrate exports there by default.
download_dir="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
if [ -z "${download_dir}" ]; then
  download_dir="${HOME}/Downloads"
fi

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
  {
    if [ -d "${download_dir}" ]; then
      find "${download_dir}" -maxdepth 2 -type f \( -iname '*.tar.gz' -o -iname '*.tgz' \) -print0
    fi
    find "${HOME}" -maxdepth 1 -type f \( -iname '*.tar.gz' -o -iname '*.tgz' \) -print0
  } 2>/dev/null | sort -zu
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
