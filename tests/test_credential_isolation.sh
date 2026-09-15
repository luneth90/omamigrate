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

# Simulate sudo -S (read password from stdin, handle -v or tar)
if [[ "${1:-}" == "-S" ]]; then
  read -r input_pass
  if [[ "$input_pass" != "$CANARY" ]]; then
    echo "STDIN_CANARY_MISMATCH" >> "$LOG_FILE"
    exit 1
  fi
  echo "STDIN_CANARY_VERIFIED_SAFELY" >> "$LOG_FILE"
  touch "${TEST_DIR:-/tmp}/sudo_timestamp"

  shift # remove -S
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-p" ]]; then
      shift 2
      continue
    elif [[ "$1" == "--" ]]; then
      shift
      continue
    fi
    break
  done

  if [[ "${1:-}" == "-v" ]]; then
    exit 0
  fi

  if [[ "${1:-}" == *"/tar" || "${1:-}" == "tar" ]]; then
    shift
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "-cf" ]]; then
        shift
        target_arg="${1:-}"
        if [[ "$target_arg" == "-" ]]; then
          shift
          if [[ "${1:-}" == "--" ]]; then
            shift
            # Verify that none of the operands are unallowlisted or options
            for op in "$@"; do
              if [[ "$op" == *"/shadow"* || "$op" == "--"* ]]; then
                echo "EXPLOIT_BYPASS_OPERAND_DETECTED: $op" >> "$LOG_FILE"
                exit 6
              fi
            done
            echo "TAR_STREAM_STDOUT_VERIFIED" >> "$LOG_FILE"
            tar -cf - --files-from=/dev/null
            exit 0
          fi
        fi
        echo "EXPLOIT_TAR_REOPENED_PATH: $target_arg" >> "$LOG_FILE"
        exit 5
      fi
      shift
    done
    exit 0
  fi
  exit 0
fi

# Simulate sudo -k (kill/revoke cached timestamp)
if [[ "${1:-}" == "-k" ]]; then
  echo "TIMESTAMP_REVOKED" >> "$LOG_FILE"
  rm -f "${TEST_DIR:-/tmp}/sudo_timestamp"
  exit 0
fi

# Simulate sudo -n true / sudo -n -v / sudo -n id / privileged commands
if [[ "${1:-}" == "-n" ]]; then
  if [[ -f "${TEST_DIR:-/tmp}/sudo_timestamp" ]]; then
    echo "TIMESTAMP_CACHE_VALID" >> "$LOG_FILE"
    shift
    [[ "${1:-}" == "--" ]] && shift
    echo "SUDO_PRIVILEGED_CMD: $*" >> "$LOG_FILE"
    if [[ "${1:-}" == "id" ]]; then
      echo "uid=0(root) gid=0(root) groups=0(root)"
      exit 0
    fi
    if [[ "${1:-}" == *"/tar" || "${1:-}" == "tar" ]]; then
      tar_input="$(mktemp)"
      cat > "$tar_input"
      echo "--- TAR ARCHIVE STREAM ENTRIES ---" >> "$LOG_FILE"
      tar -tf "$tar_input" >> "$LOG_FILE" 2>/dev/null || true
      echo "--- END TAR ARCHIVE STREAM ---" >> "$LOG_FILE"
      rm -f "$tar_input"
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
code = m.group(1)
# Adapt sudo_path to MOCK_BIN/sudo exclusively for mock environment
code = code.replace('sudo_path = \"/usr/bin/sudo\"', 'sudo_path = \"${MOCK_BIN}/sudo\"')
code = code.replace('st.st_uid != 0 or st.st_gid != 0 or not (st.st_mode & stat.S_ISUID) or (st.st_mode & 0o022)', 'not os.access(sudo_path, os.X_OK)')
with open('${RUNNER_SCRIPT}', 'w') as out:
    out.write(code)
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
if "${MOCK_BIN}/sudo" -n id 2>/dev/null | grep -q "uid=0"; then
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
printf '%s\n' "${CANARY_SECRET}" | python3 "${RUNNER_SCRIPT}" "backup" "${TEST_DIR}/mock_worker.sh" "0"

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
printf '%s\n' "${CANARY_SECRET}" | python3 "${RUNNER_SCRIPT}" "restore" "${TEST_DIR}/mock_worker.sh" "${TEST_DIR}/dummy.tar.gz"

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
  printf 'test\n' | python3 "${RUNNER_SCRIPT}" "backup" "${TEST_DIR}/mock_worker.sh" "0" >/dev/null 2>&1 || true
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
python3 -c "
import re
with open('${ROOT_DIR}/OmaMigrate.qml') as f:
    c = f.read()
m = re.search(r'readonly property string runnerPythonCode:\s*\x60([^\x60]+)\x60', c)
code = m.group(1).replace('sudo_path = \"/usr/bin/sudo\"', 'sudo_path = \"${POISON_DIR}/sudo\"')
exec(code)
" "backup" "/bin/true" "0" >/dev/null 2>&1 || STATUS_CODE=$?

if [ "${STATUS_CODE}" -ne 2 ]; then
  echo "FAIL: Runner did not reject invalid sudo binary (expected exit code 2, got ${STATUS_CODE})" >&2
  exit 1
fi
echo "  -> Verified: non-setuid or rogue sudo binaries are strictly rejected."

# Regression Test 4: Symlink Traversal, Descriptor Collision & Stream Defense
echo "==> [Credential Isolation] 5. Regression Test: Symlink Traversal & Race Defense..."
echo "  Testing staging archive creation against symlink attack & pathname reopening..."

CANARY_ROOT_TARGET="${TEST_DIR}/sensitive_root_target"
echo "CONFIDENTIAL_ROOT_CANARY_DO_NOT_TRUNCATE_12345" > "${CANARY_ROOT_TARGET}"

STAGING_BASE="${TEST_DIR}/.cache/omamigrate"
mkdir -p "${STAGING_BASE}"
chmod 700 "${STAGING_BASE}"

# Pre-create malicious symlinks targeting the sensitive root file
ln -snf "${CANARY_ROOT_TARGET}" "${STAGING_BASE}/staging-sys-predictable.tar"
ln -snf "${CANARY_ROOT_TARGET}" "${STAGING_BASE}/staging-sys-$$.tar"

# Test 4a: Privileged tar invocation MUST NEVER accept a destination file path argument
# and privileged operands MUST be derived strictly from ALLOWLIST with -- terminator
> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
rm -f "${TEST_DIR}/sudo_timestamp"

# Create a test runner simulating detected unreadable allowlist items and attempting unallowlisted injection
RUNNER_STAGING_TEST="${TEST_DIR}/runner_staging_test.py"
python3 -c "
with open('${RUNNER_SCRIPT}') as f:
    c = f.read()
# Inject 'etc/sing-box' (allowlisted) and attempt to inject 'etc/shadow' and '--checkpoint=1' (bypass attempts)
c = c.replace('unreadable = []', 'unreadable = [\"etc/sing-box\", \"etc/shadow\", \"--checkpoint=1\"]')
with open('${RUNNER_STAGING_TEST}', 'w') as out:
    out.write(c)
"

printf '%s\n' "${CANARY_SECRET}" | \
  HOME="${TEST_DIR}" \
  python3 "${RUNNER_STAGING_TEST}" "backup" "${TEST_DIR}/mock_worker.sh" "0"

# Check if canary target remained intact
if [[ "$(cat "${CANARY_ROOT_TARGET}")" != "CONFIDENTIAL_ROOT_CANARY_DO_NOT_TRUNCATE_12345" ]]; then
  echo "FAIL: Sensitive target file was modified or truncated!" >&2
  exit 1
fi

# Check mock sudo log: verify tar was NEVER invoked with an archive file path or unallowlisted bypass operands
if grep -q "EXPLOIT_TAR_REOPENED_PATH" "${TEST_MOCK_LOG}" 2>/dev/null || grep -q "EXPLOIT_TAR_REOPENED_PATH" /tmp/sudo_mock.log 2>/dev/null; then
  echo "FAIL: Privileged process attempted to reopen user-controlled pathname or missed -- separator!" >&2
  cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log >&2
  exit 1
fi

if grep -q "EXPLOIT_BYPASS_OPERAND_DETECTED" "${TEST_MOCK_LOG}" 2>/dev/null || grep -q "EXPLOIT_BYPASS_OPERAND_DETECTED" /tmp/sudo_mock.log 2>/dev/null; then
  echo "FAIL: Allowlist bypass operand was passed to privileged tar!" >&2
  cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log >&2
  exit 1
fi

if ! grep -q "TAR_STREAM_STDOUT_VERIFIED" "${TEST_MOCK_LOG}" 2>/dev/null && ! grep -q "TAR_STREAM_STDOUT_VERIFIED" /tmp/sudo_mock.log 2>/dev/null; then
  echo "FAIL: Sudo tar was not invoked with stdout stream and -- terminator!" >&2
  cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log >&2
  exit 1
fi
echo "  -> Verified: root tar never opened user pathname; operands derived strictly from allowlist with -- terminator."

# Test 4b: Direct symlink collision rejection with O_NOFOLLOW|O_EXCL
echo "  Testing O_NOFOLLOW|O_EXCL descriptor collision rejection..."
COLLISION_PATH="${STAGING_BASE}/staging-sys-collision.tar"
ln -snf "${CANARY_ROOT_TARGET}" "${COLLISION_PATH}"

python3 -c "
import os, sys
flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
try:
    fd = os.open('${COLLISION_PATH}', flags, 0o600)
    print('FAIL: Symlink was opened despite O_NOFOLLOW|O_EXCL!', file=sys.stderr)
    os.close(fd)
    sys.exit(1)
except (FileExistsError, OSError) as e:
    sys.exit(0)
"

if [[ "$(cat "${CANARY_ROOT_TARGET}")" != "CONFIDENTIAL_ROOT_CANARY_DO_NOT_TRUNCATE_12345" ]]; then
  echo "FAIL: Sensitive target file was truncated during collision test!" >&2
  exit 1
fi
echo "  -> Verified: O_NOFOLLOW|O_EXCL descriptor strictly rejects pre-created symlinks."

# Regression Test 6: Adversarial Worker & Staging-Swap Defense (Descriptor-based Staging & Zero Arbitrary Root Execution)
echo "==> [Credential Isolation] 6. Regression Test: Adversarial Worker & Staging-Swap Defense..."
echo "  Testing malicious worker substitution, arbitrary executable script injection, and staging swap..."

ADVERSARIAL_DIR="${TEST_DIR}/adversarial_stage"
mkdir -p "${ADVERSARIAL_DIR}/system_root/usr/local/bin"
mkdir -p "${ADVERSARIAL_DIR}/system_root/etc/systemd/system"
mkdir -p "${ADVERSARIAL_DIR}/system_root/etc/sing-box"

# 1. Malicious executable payload attempting to hijack usr/local/bin/sing-box-node-rotate
MALICIOUS_SCRIPT="${ADVERSARIAL_DIR}/system_root/usr/local/bin/sing-box-node-rotate"
echo "#!/bin/sh" > "${MALICIOUS_SCRIPT}"
echo "EXPLOIT_EXECUTABLE_PAYLOAD_RAN_CANARY" >> "${MALICIOUS_SCRIPT}"
chmod 777 "${MALICIOUS_SCRIPT}"

# 2. Malicious systemd unit attempting arbitrary ExecStart execution
MALICIOUS_UNIT="${ADVERSARIAL_DIR}/system_root/etc/systemd/system/sing-box.service"
echo "[Service]" > "${MALICIOUS_UNIT}"
echo "ExecStart=/usr/bin/touch /tmp/malicious_exploit_canary" >> "${MALICIOUS_UNIT}"
chmod 644 "${MALICIOUS_UNIT}"

# 3. Malicious symlink attempting to traverse to sensitive target
ln -snf "${CANARY_ROOT_TARGET}" "${ADVERSARIAL_DIR}/system_root/etc/sing-box/malicious_symlink.json"

# 4. Executable file disguised as config (must be rejected by 0111 permission check)
EXEC_CONFIG="${ADVERSARIAL_DIR}/system_root/etc/sing-box/executable_config.json"
echo '{"log": {"level": "warn"}}' > "${EXEC_CONFIG}"
chmod 755 "${EXEC_CONFIG}"

# 5. Legitimate passive JSON configuration
SAFE_CONFIG="${ADVERSARIAL_DIR}/system_root/etc/sing-box/safe_config.json"
echo '{"log": {"level": "info"}}' > "${SAFE_CONFIG}"
chmod 644 "${SAFE_CONFIG}"

# 6. File targeted by background swap attack to replace with sensitive symlink
SWAP_TARGET="${ADVERSARIAL_DIR}/system_root/etc/sing-box/swap_target.json"
echo '{"log": {"level": "swap"}}' > "${SWAP_TARGET}"
chmod 644 "${SWAP_TARGET}"

# Create adversarial worker script that outputs stage_ready and launches a background process attempting to swap files
ADVERSARIAL_WORKER="${TEST_DIR}/adversarial_worker.sh"
cat << EOF > "${ADVERSARIAL_WORKER}"
#!/usr/bin/env bash
echo "OMAMIGRATE_STAGE_READY: ${ADVERSARIAL_DIR}"
(
  for i in {1..20}; do
    ln -snf "${CANARY_ROOT_TARGET}" "${SWAP_TARGET}" 2>/dev/null || true
    sleep 0.01
  done
) &
exit 0
EOF
chmod 755 "${ADVERSARIAL_WORKER}"

> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
rm -f "${TEST_DIR}/sudo_timestamp"

printf '%s\n' "${CANARY_SECRET}" | \
  python3 "${RUNNER_SCRIPT}" "restore" "${ADVERSARIAL_WORKER}" "${TEST_DIR}/dummy.tar.gz"

# Formal assertions:
COMBINED_SUDO_LOG="${TEST_DIR}/combined_sudo.log"
cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log 2>/dev/null > "${COMBINED_SUDO_LOG}" || true

# A. Sudo was NEVER invoked with chmod 755 or chown on usr/local/bin
if grep -q "chmod.*755.*sing-box-node-rotate" "${COMBINED_SUDO_LOG}" 2>/dev/null || \
   grep -q "chown.*sing-box-node-rotate" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Privileged runner attempted to chmod/chown unallowlisted script!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

# B. Sudo tar stream NEVER contained the executable script or malicious unit or symlink
if grep -q "sing-box-node-rotate" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Privileged tar archive stream contained executable script sing-box-node-rotate!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

if grep -q "etc/systemd/system/sing-box.service" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Privileged tar archive stream contained archive-supplied unit file!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

if grep -q "malicious_symlink.json" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Privileged tar archive stream contained symlink!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

if grep -q "executable_config.json" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Privileged tar archive stream contained file with execute permissions!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

# C. Valid passive config was safely handled via descriptor in memory
if ! grep -q "etc/sing-box/safe_config.json" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Valid passive configuration was not deployed!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

echo "  -> Verified: adversarial worker, executable script, unit injection, symlink traversal, and staging swap were strictly defeated."

# Regression Test 7: Bounded Staging Limits & Oversized Package Metadata Defense
echo "==> [Credential Isolation] 7. Regression Test: Bounded Staging & Package Metadata Defense..."
echo "  Testing config file count limits (>50), total byte limits (>5MB), and package metadata bounds..."

BOUNDS_DIR="${TEST_DIR}/bounds_stage"
mkdir -p "${BOUNDS_DIR}/system_root/etc/sing-box"
mkdir -p "${BOUNDS_DIR}/pkg_meta"

# 1. Populate > 50 valid json config files to test MAX_CONFIG_FILES cap (50)
for i in $(seq 1 70); do
  echo "{\"rule_id\": $i}" > "${BOUNDS_DIR}/system_root/etc/sing-box/rule_${i}.json"
  chmod 644 "${BOUNDS_DIR}/system_root/etc/sing-box/rule_${i}.json"
done

# 2. Package metadata adversarial cases:
# Test 7.1: Oversized missing_native_pkgs.txt (>64KB) - should be skipped/rejected
OVERSIZED_PKG_META="${BOUNDS_DIR}/pkg_meta/missing_native_pkgs.txt"
python3 -c "
with open('${OVERSIZED_PKG_META}', 'w') as f:
    for i in range(10000):
        f.write('malicious-pkg-' + str(i) + '\n')
"
chmod 644 "${OVERSIZED_PKG_META}"

BOUNDS_WORKER="${TEST_DIR}/bounds_worker.sh"
cat << EOF > "${BOUNDS_WORKER}"
#!/usr/bin/env bash
echo "OMAMIGRATE_STAGE_READY: ${BOUNDS_DIR}"
exit 0
EOF
chmod 755 "${BOUNDS_WORKER}"

> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
rm -f "${TEST_DIR}/sudo_timestamp"

# Create a valid test archive with known allowed packages
BOUNDS_ARCHIVE="${TEST_DIR}/bounds_test_archive.tar.gz"
python3 -c "
import tarfile, io
with tarfile.open('${BOUNDS_ARCHIVE}', 'w:gz') as tf:
    ti = tarfile.TarInfo('pkg_meta/packages_explicit.txt')
    data = b'sing-box\nmihomo\n'
    ti.size = len(data)
    tf.addfile(ti, io.BytesIO(data))
"

printf '%s\n' "${CANARY_SECRET}" | \
  python3 "${RUNNER_SCRIPT}" "restore" "${BOUNDS_WORKER}" "${BOUNDS_ARCHIVE}"

COMBINED_SUDO_LOG="${TEST_DIR}/combined_sudo.log"
cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log 2>/dev/null > "${COMBINED_SUDO_LOG}" || true

# Assertions for Test 7.1:
# A. Oversized missing_native_pkgs.txt (>64KB) was NOT passed to pacman
if grep -q "malicious-pkg" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Oversized package metadata was passed to pacman!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

# B. File count in tar stream was capped at MAX_CONFIG_FILES (50)
STREAMED_RULES=$(grep "etc/sing-box/rule_" "${COMBINED_SUDO_LOG}" 2>/dev/null | wc -l)
if [ "$STREAMED_RULES" -gt 50 ]; then
  echo "FAIL: Traversal streamed $STREAMED_RULES config files, exceeding MAX_CONFIG_FILES cap (50)!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi
if [ "$STREAMED_RULES" -eq 0 ]; then
  echo "FAIL: No config files were streamed!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

# Test 7.2: Verify package binding & cap with valid sized package metadata
# Use fresh staging dir because runner cleans up stage_ready_dir upon completion
BOUNDS_DIR_2="${TEST_DIR}/bounds_stage_2"
mkdir -p "${BOUNDS_DIR_2}/pkg_meta"
cat << EOF > "${BOUNDS_DIR_2}/pkg_meta/missing_native_pkgs.txt"
mihomo
sing-box
untrusted-arbitrary-package
EOF
chmod 644 "${BOUNDS_DIR_2}/pkg_meta/missing_native_pkgs.txt"

BOUNDS_WORKER_2="${TEST_DIR}/bounds_worker_2.sh"
cat << EOF > "${BOUNDS_WORKER_2}"
#!/usr/bin/env bash
echo "OMAMIGRATE_STAGE_READY: ${BOUNDS_DIR_2}"
exit 0
EOF
chmod 755 "${BOUNDS_WORKER_2}"

> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
rm -f "${TEST_DIR}/sudo_timestamp"

printf '%s\n' "${CANARY_SECRET}" | \
  python3 "${RUNNER_SCRIPT}" "restore" "${BOUNDS_WORKER_2}" "${BOUNDS_ARCHIVE}"

cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log 2>/dev/null > "${COMBINED_SUDO_LOG}" || true

if grep -q "untrusted-arbitrary-package" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Untrusted package not bound to archive was passed to privileged pacman!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

if ! grep -q "pacman.*sing-box" "${COMBINED_SUDO_LOG}" 2>/dev/null && \
   ! grep -q "pacman.*mihomo" "${COMBINED_SUDO_LOG}" 2>/dev/null; then
  echo "FAIL: Legitimate bound packages were not passed to pacman!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

# Test 7.3: Total byte limit (> 5MB)
BYTE_FLOOD_DIR="${TEST_DIR}/byte_flood_stage"
mkdir -p "${BYTE_FLOOD_DIR}/system_root/etc/sing-box"
# 4 files of 1.5MB each = 6.0MB total, which exceeds 5MB limit
for i in 1 2 3 4; do
  python3 -c "
with open('${BYTE_FLOOD_DIR}/system_root/etc/sing-box/flood_${i}.json', 'w') as f:
    f.write('{\"data\": \"' + 'A' * (1500 * 1024) + '\"}')
"
  chmod 644 "${BYTE_FLOOD_DIR}/system_root/etc/sing-box/flood_${i}.json"
done

BYTE_FLOOD_WORKER="${TEST_DIR}/byte_flood_worker.sh"
cat << EOF > "${BYTE_FLOOD_WORKER}"
#!/usr/bin/env bash
echo "OMAMIGRATE_STAGE_READY: ${BYTE_FLOOD_DIR}"
exit 0
EOF
chmod 755 "${BYTE_FLOOD_WORKER}"

> "${TEST_MOCK_LOG}"
> /tmp/sudo_mock.log
rm -f "${TEST_DIR}/sudo_timestamp"

printf '%s\n' "${CANARY_SECRET}" | \
  python3 "${RUNNER_SCRIPT}" "restore" "${BYTE_FLOOD_WORKER}" "${BOUNDS_ARCHIVE}"

cat "${TEST_MOCK_LOG}" /tmp/sudo_mock.log 2>/dev/null > "${COMBINED_SUDO_LOG}" || true

# 3 files * 1.5MB = 4.5MB <= 5MB. 4th file would make it 6.0MB > 5MB, so at most 3 should be streamed
FLOOD_STREAMED=$(grep "etc/sing-box/flood_" "${COMBINED_SUDO_LOG}" 2>/dev/null | wc -l)
if [ "$FLOOD_STREAMED" -gt 3 ]; then
  echo "FAIL: Byte flood exceeded MAX_CONFIG_TOTAL_BYTES (streamed $FLOOD_STREAMED large files)!" >&2
  cat "${COMBINED_SUDO_LOG}" >&2
  exit 1
fi

echo "  -> Verified: excessive file count (>50), total bytes (>5MB), and oversized/unbound package metadata were strictly defended."

rm -f /tmp/canary_expected.txt /tmp/sudo_mock.log
rm -rf "${TEST_DIR}"
echo "==> [Credential Isolation] All tests passed! Credential exposure path completely eliminated."
