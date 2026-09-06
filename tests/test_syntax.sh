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
  touch "${TEST_HOME}/${download_name}/omamigrate \"quoted\".tar.gz"
  touch "${TEST_HOME}/${download_name}/unrelated-source.tar.gz"
  scan_output="$(HOME="${TEST_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${ROOT_DIR}/lib/scan-archives.sh")"
  jq -e '
    length == 2 and
    any(.[]; .name == "omarchy-migration with spaces.tar.gz") and
    any(.[]; .name == "omamigrate \"quoted\".tar.gz") and
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
"${ROOT_DIR}/bin/omamigrate" --help >/dev/null

echo "==> All tests passed successfully!"
