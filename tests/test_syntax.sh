#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Validating OmaMigrate shell syntax..."

for script in "${ROOT_DIR}/bin/omamigrate" "${ROOT_DIR}/lib/"*.sh; do
  echo -n "Checking ${script}... "
  bash -n "$script"
  echo "OK"
done

echo "==> Validating Python syntax & unit tests..."
if command -v python3 >/dev/null 2>&1; then
  for pyscript in "${ROOT_DIR}/tests/"*.py; do
    if [[ -f "$pyscript" ]]; then
      echo -n "Checking ${pyscript}... "
      python3 -m py_compile "$pyscript"
      echo "OK"
    fi
  done
  python3 -m unittest discover -s "${ROOT_DIR}/tests" -p "test_*.py" -v
fi

echo "==> Checking executables..."
test -x "${ROOT_DIR}/bin/omamigrate"
test -x "${ROOT_DIR}/lib/export.sh"
test -x "${ROOT_DIR}/lib/restore.sh"
test -x "${ROOT_DIR}/lib/scan-archives.sh"

echo "==> Testing archive discovery..."
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "${TEST_HOME}"' EXIT
mkdir -p "${TEST_HOME}/.config"
touch "${TEST_HOME}/not-in-downloads.tgz"
for download_name in "Downloads" "Téléchargements" "ダウンロード" "下载"; do
  mkdir -p "${TEST_HOME}/${download_name}/LocalSend"
  printf 'XDG_DOWNLOAD_DIR="$HOME/%s"\n' "${download_name}" > "${TEST_HOME}/.config/user-dirs.dirs"
  touch "${TEST_HOME}/${download_name}/LocalSend/omarchy-migration with spaces.tar.gz"
  touch "${TEST_HOME}/${download_name}/omamigrate-backup \"quoted\".tar.gz"
  touch "${TEST_HOME}/${download_name}/unrelated-source.tar.gz"
  scan_output="$(HOME="${TEST_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${ROOT_DIR}/lib/scan-archives.sh")"
  jq -e '
    length == 2 and
    any(.[]; .name == "omarchy-migration with spaces.tar.gz") and
    any(.[]; .name == "omamigrate-backup \"quoted\".tar.gz") and
    all(.[]; .name != "unrelated-source.tar.gz") and
    all(.[]; .name != "not-in-downloads.tgz")
  ' <<< "${scan_output}" >/dev/null
done

echo "==> Checking QML collector usage..."
if grep -q 'onStreamFinished: function' "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "StdioCollector.streamFinished does not pass output as a signal argument" >&2
  exit 1
fi

echo "==> Testing CLI help..."
cli_help="$("${ROOT_DIR}/bin/omamigrate" --help)"
[[ "${cli_help}" == *'Create a portable migration backup'* ]]
[[ "${cli_help}" == *'omamigrate-backup.tar.gz'* ]]
[[ "${cli_help}" == *'omamigrate backup --with-ai-history'* ]]

backup_help="$("${ROOT_DIR}/bin/omamigrate" backup --help)"
[[ "${backup_help}" == *'--with-ai-history'* ]]
[[ "${backup_help}" == *'--complete'* ]]
[[ "$("${ROOT_DIR}/bin/omamigrate" help backup)" == "${backup_help}" ]]
[[ "$("${ROOT_DIR}/bin/omamigrate" export --help)" == "${backup_help}" ]]

restore_help="$("${ROOT_DIR}/bin/omamigrate" restore --help)"
[[ "${restore_help}" == *'restore <backup_file>'* ]]
[[ "$("${ROOT_DIR}/bin/omamigrate" help restore)" == "${restore_help}" ]]

send_help="$("${ROOT_DIR}/bin/omamigrate" send --help)"
[[ "${send_help}" == *'send [backup_file]'* ]]
"${ROOT_DIR}/bin/omamigrate" status --help >/dev/null

if rg -q '[\p{Han}]' "${ROOT_DIR}/bin/omamigrate"; then
  echo "CLI help and messages must remain English-only" >&2
  exit 1
fi

if "${ROOT_DIR}/bin/omamigrate" backup --unknown-option >/dev/null 2>&1; then
  echo "Unknown backup options must fail" >&2
  exit 1
fi

if "${ROOT_DIR}/bin/omamigrate" restore >/dev/null 2>&1; then
  echo "Restore without a backup file must fail" >&2
  exit 1
fi

echo "==> All tests passed successfully!"
