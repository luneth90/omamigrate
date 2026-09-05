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

echo "==> Testing CLI help..."
"${ROOT_DIR}/bin/omamigrate" --help >/dev/null

echo "==> All tests passed successfully!"
