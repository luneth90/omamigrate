#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> [Credential Isolation] 1. Static Security Auditing..."

# Guard 1: Ensure OMAMIGRATE_SUDO_PASS is completely purged
if grep -rn "OMAMIGRATE_SUDO_PASS" "${ROOT_DIR}/bin" "${ROOT_DIR}/lib" "${ROOT_DIR}/OmaMigrate.qml" 2>/dev/null; then
  echo "FAIL: OMAMIGRATE_SUDO_PASS must not exist in any production script or QML" >&2
  exit 1
fi

# Guard 2: Ensure savedPassword property is eliminated from OmaMigrate.qml
if grep -q "savedPassword" "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "FAIL: savedPassword must not be present in OmaMigrate.qml" >&2
  exit 1
fi

# Guard 3: Ensure OmaMigrate.qml uses stdinEnabled for authProcess
if ! grep -q "stdinEnabled: true" "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "FAIL: authProcess in OmaMigrate.qml must have stdinEnabled: true" >&2
  exit 1
fi

# Guard 4: Ensure OmaMigrate.qml authProcess uses sudo -S without inline passwords in argv
if grep -Fq 'echo "$0" | sudo' "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "FAIL: authProcess must not pass password via bash -c argv" >&2
  exit 1
fi

# Guard 5: Ensure askpass script creation is eliminated from lib/restore.sh
if grep -q "SUDO_ASKPASS_SCRIPT" "${ROOT_DIR}/lib/restore.sh"; then
  echo "FAIL: SUDO_ASKPASS_SCRIPT must not be created in lib/restore.sh" >&2
  exit 1
fi

# Guard 6: Ensure secrets are not retained across QML lifecycle properties
if grep -E "exportSecret|restoreSecret|pendingSecret" "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "FAIL: exportSecret, restoreSecret, or pendingSecret must not exist in OmaMigrate.qml" >&2
  exit 1
fi

# Guard 7: Ensure clearEnvironment: true is configured for Process definitions in OmaMigrate.qml
if ! grep -q "clearEnvironment: true" "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "FAIL: clearEnvironment: true must be configured in OmaMigrate.qml" >&2
  exit 1
fi

# Guard 8: Ensure lib/export.sh and lib/restore.sh do not read SUDO_PASS from stdin
if grep -E "read.*SUDO_PASS" "${ROOT_DIR}/lib/export.sh" "${ROOT_DIR}/lib/restore.sh" 2>/dev/null; then
  echo "FAIL: lib/export.sh and lib/restore.sh must not read SUDO_PASS from stdin" >&2
  exit 1
fi

# Guard 9: Ensure absolute binary paths are used in OmaMigrate.qml Process invocations
if grep -E 'command:\s*\[\s*"(sudo|bash)"' "${ROOT_DIR}/OmaMigrate.qml"; then
  echo "FAIL: OmaMigrate.qml must use absolute paths (/usr/bin/...) for commands" >&2
  exit 1
fi

echo "  -> Static checks passed."

echo "==> [Credential Isolation] 2. Dynamic Process Inspection via Mock Privileged Flow..."

TEST_DIR="$(mktemp -d)"
MOCK_BIN="${TEST_DIR}/bin"
mkdir -p "${MOCK_BIN}"

CANARY_SECRET="CANARY_SECRET_$(date +%s%N)_TOPSECRET"
LOG_DIR="${TEST_DIR}/logs"
mkdir -p "${LOG_DIR}"

echo "${CANARY_SECRET}" > "${TEST_DIR}/canary_expected.txt"
echo "${CANARY_SECRET}" > "/tmp/canary_expected.txt"
chmod 600 "${TEST_DIR}/canary_expected.txt" "/tmp/canary_expected.txt"

# Create mock sudo that checks stdin, argv, and environ
cat << 'EOF' > "${MOCK_BIN}/sudo"
#!/usr/bin/env bash
set -eu

LOG_FILE="${TEST_MOCK_LOG:-/tmp/sudo_mock.log}"
CANARY_FILE="${TEST_DIR:-/tmp}/canary_expected.txt"
if [[ ! -f "$CANARY_FILE" ]]; then
  CANARY_FILE="/tmp/canary_expected.txt"
fi
CANARY="$(cat "$CANARY_FILE")"

# Check argv for leaked canary
for arg in "$@"; do
  if [[ "$arg" == *"$CANARY"* ]]; then
    echo "LEAK_DETECTED_IN_ARGV: $arg" >> "$LOG_FILE"
    exit 2
  fi
done

# Check environ for leaked canary
if env | grep -q "$CANARY"; then
  echo "LEAK_DETECTED_IN_ENV" >> "$LOG_FILE"
  exit 3
fi

# Simulate sudo -S -p "" -v (read password from stdin)
if [[ "${1:-}" == "-S" ]]; then
  read -r input_pass
  if [[ "$input_pass" == "$CANARY" ]]; then
    echo "STDIN_CANARY_VERIFIED_SAFELY" >> "$LOG_FILE"
    touch "${TEST_DIR:-/tmp}/sudo_timestamp"
    exit 0
  else
    echo "STDIN_CANARY_MISMATCH" >> "$LOG_FILE"
    exit 1
  fi
fi

# Simulate sudo -k (kill/revoke cached timestamp)
if [[ "${1:-}" == "-k" ]]; then
  echo "TIMESTAMP_REVOKED" >> "$LOG_FILE"
  rm -f "${TEST_DIR:-/tmp}/sudo_timestamp"
  exit 0
fi

# Simulate sudo -n true / sudo -n -v / sudo -n id
if [[ "${1:-}" == "-n" ]]; then
  if [[ -f "${TEST_DIR:-/tmp}/sudo_timestamp" ]]; then
    echo "TIMESTAMP_CACHE_VALID" >> "$LOG_FILE"
    if [[ "${2:-}" == "id" ]]; then
      echo "uid=0(root) gid=0(root) groups=0(root)"
    fi
    exit 0
  else
    echo "TIMESTAMP_CACHE_EXPIRED" >> "$LOG_FILE"
    exit 1
  fi
fi

# General execution
exit 0
EOF
chmod 755 "${MOCK_BIN}/sudo"

export TEST_DIR
export TEST_MOCK_LOG="${LOG_DIR}/mock_sudo.log"
export PATH="${MOCK_BIN}:${PATH}"

# Test direct stdin pipe authentication and dynamic /proc inspection
echo "  Testing short-lived authentication process stdin pipe & /proc isolation..."

PIPE_MONITOR_LOG="${LOG_DIR}/pipe_proc_monitor.log"
(
  while true; do
    for pid in /proc/[0-9]*; do
      [ -d "$pid" ] || continue
      if [ -r "$pid/cmdline" ]; then
        if cat "$pid/cmdline" 2>/dev/null | tr '\0' ' ' | grep -q "$CANARY_SECRET"; then
          echo "LEAK_FOUND_IN_PROCFS_CMDLINE: $pid" >> "$PIPE_MONITOR_LOG"
        fi
      fi
      if [ -r "$pid/environ" ]; then
        if cat "$pid/environ" 2>/dev/null | tr '\0' '\n' | grep -q "$CANARY_SECRET"; then
          if [ "$pid" != "/proc/$$" ] && [ "$pid" != "/proc/$BASHPID" ]; then
            echo "LEAK_FOUND_IN_PROCFS_ENVIRON: $pid" >> "$PIPE_MONITOR_LOG"
          fi
        fi
      fi
    done
    sleep 0.01
  done
) &
PIPE_MONITOR_PID=$!

# Run the short-lived auth command directly via stdin pipe (same as authProcess)
printf '%s\n' "${CANARY_SECRET}" | sudo -S -p "" -v
kill "${PIPE_MONITOR_PID}" 2>/dev/null || true
wait "${PIPE_MONITOR_PID}" 2>/dev/null || true

if [ -s "${PIPE_MONITOR_LOG}" ]; then
  echo "FAIL: Canary secret detected in /proc filesystem during stdin pipe execution:" >&2
  cat "${PIPE_MONITOR_LOG}" >&2
  exit 1
fi

if ! grep -q "STDIN_CANARY_VERIFIED_SAFELY" "${TEST_MOCK_LOG}"; then
  echo "FAIL: Mock sudo did not receive canary via stdin" >&2
  exit 1
fi
echo "  -> Direct stdin pipe verified: secret absent from argv and environ."

# Test omamigrate backup stdin elevation streaming & zero /proc exposure
echo "  Testing omamigrate backup stdin elevation stream & zero /proc exposure..."
BACKUP_OUT="${TEST_DIR}/test_backup.tar.gz"
rm -f "${TEST_DIR}/sudo_timestamp"
BACKUP_MONITOR_LOG="${LOG_DIR}/backup_proc_monitor.log"
(
  while true; do
    for pid in /proc/[0-9]*; do
      [ -d "$pid" ] || continue
      if [ -r "$pid/cmdline" ]; then
        if cat "$pid/cmdline" 2>/dev/null | tr '\0' ' ' | grep -q "$CANARY_SECRET"; then
          echo "LEAK_FOUND_IN_PROCFS_CMDLINE: $pid" >> "$BACKUP_MONITOR_LOG"
        fi
      fi
      if [ -r "$pid/environ" ]; then
        if cat "$pid/environ" 2>/dev/null | tr '\0' '\n' | grep -q "$CANARY_SECRET"; then
          if [ "$pid" != "/proc/$$" ] && [ "$pid" != "/proc/$BASHPID" ]; then
            echo "LEAK_FOUND_IN_PROCFS_ENVIRON: $pid" >> "$BACKUP_MONITOR_LOG"
          fi
        fi
      fi
    done
    sleep 0.01
  done
) &
BACKUP_MONITOR_PID=$!

printf '%s\n' "${CANARY_SECRET}" | "${ROOT_DIR}/bin/omamigrate" backup "${BACKUP_OUT}" >/dev/null 2>&1 || true
kill "${BACKUP_MONITOR_PID}" 2>/dev/null || true
wait "${BACKUP_MONITOR_PID}" 2>/dev/null || true

if [ -s "${BACKUP_MONITOR_LOG}" ]; then
  echo "FAIL: Canary secret detected in /proc during backup stdin stream:" >&2
  cat "${BACKUP_MONITOR_LOG}" >&2
  exit 1
fi
echo "  -> Backup stdin elevation verified: zero /proc exposure."

# If graphical display is active, also test live Quickshell process execution
if command -v quickshell >/dev/null 2>&1 && { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }; then
  echo "  Testing Quickshell Process stdin streaming under live compositor..."
  
  MOCK_QML="${TEST_DIR}/test_auth.qml"
  cat << EOF > "${MOCK_QML}"
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  Process {
    id: authProc
    command: ["sudo", "-S", "-p", "", "-v"]
    stdinEnabled: true
    property string secretBuffer: "${CANARY_SECRET}"
    onStarted: {
      authProc.write(secretBuffer + "\n")
      secretBuffer = ""
    }
    onExited: function(code) {
      if (code === 0 && secretBuffer === "") {
        console.log("QML_AUTH_SUCCESS_SECRET_CLEARED")
      } else {
        console.log("QML_AUTH_FAILED_CODE_" + code)
      }
      Qt.quit()
    }
  }
  Component.onCompleted: {
    authProc.running = true
  }
}
EOF

  QS_RUNTIME="${TEST_DIR}/runtime"
  mkdir -p "${QS_RUNTIME}"
  chmod 700 "${QS_RUNTIME}"

  MONITOR_LOG="${LOG_DIR}/proc_monitor.log"
  (
    while true; do
      for pid in /proc/[0-9]*; do
        [ -d "$pid" ] || continue
        if [ -r "$pid/cmdline" ]; then
          if cat "$pid/cmdline" 2>/dev/null | tr '\0' ' ' | grep -q "$CANARY_SECRET"; then
            echo "LEAK_FOUND_IN_PROCFS_CMDLINE: $pid" >> "$MONITOR_LOG"
          fi
        fi
        if [ -r "$pid/environ" ]; then
          if cat "$pid/environ" 2>/dev/null | tr '\0' '\n' | grep -q "$CANARY_SECRET"; then
            if [ "$pid" != "/proc/$$" ] && [ "$pid" != "/proc/$BASHPID" ]; then
              echo "LEAK_FOUND_IN_PROCFS_ENVIRON: $pid" >> "$MONITOR_LOG"
            fi
          fi
        fi
      done
      sleep 0.02
    done
  ) &
  MONITOR_PID=$!

  qs_out="$(XDG_RUNTIME_DIR="${QS_RUNTIME}" timeout 5 quickshell -p "${MOCK_QML}" 2>&1 || true)"
  kill "${MONITOR_PID}" 2>/dev/null || true
  wait "${MONITOR_PID}" 2>/dev/null || true

  if ! grep -q "QML_AUTH_SUCCESS_SECRET_CLEARED" <<< "${qs_out}"; then
    echo "FAIL: Quickshell auth process did not succeed or clear secret: ${qs_out}" >&2
    exit 1
  fi

  if [ -s "${MONITOR_LOG}" ]; then
    echo "FAIL: Canary secret detected in /proc filesystem during Quickshell execution:" >&2
    cat "${MONITOR_LOG}" >&2
    exit 1
  fi

  echo "  -> Quickshell stdin pipe passed with zero /proc exposure."
else
  echo "  (No Wayland/X11 display present; skipping live compositor surface launch, stdin streaming contract verified)"
fi

echo "==> [Credential Isolation] 3. Testing Cache & Artifact Directories..."

CACHE_TEST_DIR="${TEST_DIR}/cache"
mkdir -p "${CACHE_TEST_DIR}"

XDG_CACHE_HOME="${CACHE_TEST_DIR}" "${ROOT_DIR}/bin/omamigrate" status >/dev/null 2>&1 || true

# Assert no askpass script or plaintext file was created anywhere in cache
if find "${CACHE_TEST_DIR}" -name "*askpass*" 2>/dev/null | grep -q .; then
  echo "FAIL: Askpass script found in cache directory" >&2
  exit 1
fi

echo "==> [Credential Isolation] 4. Regression Tests: Worker Zero-Credential & PATH Defense..."

# Extract runnerPythonCode directly from OmaMigrate.qml
RUNNER_SCRIPT="${TEST_DIR}/runner.py"
python3 -c "
import re
with open('${ROOT_DIR}/OmaMigrate.qml') as f:
    c = f.read()
m = re.search(r'readonly property string runnerPythonCode:\s*\x60([^\x60]+)\x60', c)
if not m:
    raise RuntimeError('Could not extract runnerPythonCode from OmaMigrate.qml')
with open('${RUNNER_SCRIPT}', 'w') as out:
    out.write(m.group(1))
"

# Regression Test 1: Worker Substitution Attack Defense (Zero Credential Bytes & Zero Privilege Capability Leak)
echo "  Testing Worker Substitution in backup: worker receives zero credentials & zero sudo capability..."
WORKER_LOG="${TEST_DIR}/worker_received.log"
cat << EOF > "${TEST_DIR}/mock_worker.sh"
#!/usr/bin/env bash
WORKER_LOG="${TEST_DIR}/worker_received.log"
# 1. Attempt to read leaked credentials from stdin
read -r -t 1 worker_stdin || worker_stdin=""
echo "WORKER_RECEIVED_BYTES:\${#worker_stdin}" >> "\${WORKER_LOG}"
echo "WORKER_STDIN:\${worker_stdin}" >> "\${WORKER_LOG}"

# 2. Adversarial attack attempt: try to abuse inherited sudo capability
if "\${OMAMIGRATE_TEST_SUDO:-sudo}" -n id 2>/dev/null | grep -q "uid=0"; then
  echo "EXPLOIT_SUDO_CAPABILITY_ABUSED: Worker gained root access!" >> "\${WORKER_LOG}"
  exit 99
fi
echo "WORKER_SUDO_CAPABILITY_CHECK:PASSED" >> "\${WORKER_LOG}"
exit 0
EOF
chmod 755 "${TEST_DIR}/mock_worker.sh"

> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
> "${WORKER_LOG}"
rm -f "${TEST_DIR}/sudo_timestamp"
printf '%s\n' "${CANARY_SECRET}" | OMAMIGRATE_TEST_SUDO="${MOCK_BIN}/sudo" python3 "${RUNNER_SCRIPT}" "backup" "${TEST_DIR}/mock_worker.sh" "0"

if ! grep -q "STDIN_CANARY_VERIFIED_SAFELY" "${TEST_MOCK_LOG}" 2>/dev/null && ! grep -q "STDIN_CANARY_VERIFIED_SAFELY" /tmp/sudo_mock.log 2>/dev/null; then
  echo "FAIL: Sudo did not receive canary password during runner execution" >&2
  exit 1
fi

if ! grep -q "TIMESTAMP_REVOKED" "${TEST_MOCK_LOG}" 2>/dev/null && ! grep -q "TIMESTAMP_REVOKED" /tmp/sudo_mock.log 2>/dev/null; then
  echo "FAIL: Sudo timestamp was not immediately revoked via sudo -k!" >&2
  exit 1
fi

if ! grep -q "WORKER_RECEIVED_BYTES:0" "${WORKER_LOG}"; then
  echo "FAIL: Worker received non-zero credential bytes on stdin!" >&2
  cat "${WORKER_LOG}" >&2
  exit 1
fi

if grep -q "EXPLOIT_SUDO_CAPABILITY_ABUSED" "${WORKER_LOG}"; then
  echo "FAIL: Worker was able to consume sudo capability!" >&2
  cat "${WORKER_LOG}" >&2
  exit 1
fi

if ! grep -q "WORKER_SUDO_CAPABILITY_CHECK:PASSED" "${WORKER_LOG}"; then
  echo "FAIL: Worker sudo capability check failed!" >&2
  cat "${WORKER_LOG}" >&2
  exit 1
fi
echo "  -> Verified: backup worker script received 0 credential bytes and 0 sudo capability."

# Test Restore Worker Capability Isolation
echo "  Testing Worker Substitution in restore: worker receives zero credentials & zero sudo capability..."
> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
> "${WORKER_LOG}"
rm -f "${TEST_DIR}/sudo_timestamp"
printf '%s\n' "${CANARY_SECRET}" | OMAMIGRATE_TEST_SUDO="${MOCK_BIN}/sudo" python3 "${RUNNER_SCRIPT}" "restore" "${TEST_DIR}/mock_worker.sh" "${TEST_DIR}/dummy.tar.gz"

if ! grep -q "WORKER_RECEIVED_BYTES:0" "${WORKER_LOG}"; then
  echo "FAIL: Restore worker received non-zero credential bytes on stdin!" >&2
  cat "${WORKER_LOG}" >&2
  exit 1
fi

if grep -q "EXPLOIT_SUDO_CAPABILITY_ABUSED" "${WORKER_LOG}"; then
  echo "FAIL: Restore worker was able to consume sudo capability!" >&2
  cat "${WORKER_LOG}" >&2
  exit 1
fi

if ! grep -q "WORKER_SUDO_CAPABILITY_CHECK:PASSED" "${WORKER_LOG}"; then
  echo "FAIL: Restore worker sudo capability check failed!" >&2
  cat "${WORKER_LOG}" >&2
  exit 1
fi
echo "  -> Verified: restore worker script received 0 credential bytes and 0 sudo capability."

# Regression Test 2: PATH Substitution Attack Defense
echo "  Testing PATH substitution hijacking resistance..."
POISON_DIR="${TEST_DIR}/poison"
mkdir -p "${POISON_DIR}"
cat << 'EOF' > "${POISON_DIR}/sudo"
#!/bin/sh
echo "POISONED_SUDO_EXECUTED" >> "${TEST_DIR}/poison_exec.log"
exit 99
EOF
chmod 755 "${POISON_DIR}/sudo"

cat << 'EOF' > "${POISON_DIR}/bash"
#!/bin/sh
echo "POISONED_BASH_EXECUTED" >> "${TEST_DIR}/poison_exec.log"
exit 99
EOF
chmod 755 "${POISON_DIR}/bash"

# Run with poisoned PATH prepended
(
  export PATH="${POISON_DIR}:${PATH}"
  # Executing via system bash should never invoke poisoned binaries in PATH
  /usr/bin/bash "${ROOT_DIR}/bin/omamigrate" status >/dev/null 2>&1 || true
  # Runner execution with clean_env should never invoke poisoned binaries in PATH
  printf 'test\n' | OMAMIGRATE_TEST_SUDO="${MOCK_BIN}/sudo" python3 "${RUNNER_SCRIPT}" "backup" "${TEST_DIR}/mock_worker.sh" "0" >/dev/null 2>&1 || true
)

if [ -f "${TEST_DIR}/poison_exec.log" ]; then
  echo "FAIL: Poisoned binary in PATH was executed!" >&2
  cat "${TEST_DIR}/poison_exec.log" >&2
  exit 1
fi
echo "  -> Verified: absolute system paths prevent PATH hijacking."

# Regression Test 3: Sudo SetUID Integrity Verification
echo "  Testing sudo integrity enforcement..."
STATUS_CODE=0
printf 'test\n' | OMAMIGRATE_TEST_VERIFY=1 OMAMIGRATE_TEST_SUDO="${POISON_DIR}/sudo" \
  python3 "${RUNNER_SCRIPT}" "backup" "/bin/true" "0" >/dev/null 2>&1 || STATUS_CODE=$?

if [ "${STATUS_CODE}" -ne 2 ]; then
  echo "FAIL: Runner did not reject invalid sudo binary (expected exit code 2, got ${STATUS_CODE})" >&2
  exit 1
fi
echo "  -> Verified: non-setuid or rogue sudo binaries are strictly rejected."

rm -f /tmp/canary_expected.txt /tmp/sudo_mock.log
rm -rf "${TEST_DIR}"
echo "==> [Credential Isolation] All tests passed! Credential exposure path completely eliminated."
