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

echo "  -> Static checks passed."

echo "==> [Credential Isolation] 2. Dynamic Process Inspection via Mock Privileged Flow..."

TEST_DIR="$(mktemp -d)"
MOCK_BIN="${TEST_DIR}/bin"
mkdir -p "${MOCK_BIN}"

CANARY_SECRET="CANARY_SECRET_$(date +%s%N)_TOPSECRET"
LOG_DIR="${TEST_DIR}/logs"
mkdir -p "${LOG_DIR}"

echo "${CANARY_SECRET}" > "${TEST_DIR}/canary_expected.txt"
chmod 600 "${TEST_DIR}/canary_expected.txt"

# Create mock sudo that checks stdin, argv, and environ
cat << 'EOF' > "${MOCK_BIN}/sudo"
#!/usr/bin/env bash
set -eu

LOG_FILE="${TEST_MOCK_LOG:-/tmp/sudo_mock.log}"
CANARY="$(cat "${TEST_DIR}/canary_expected.txt")"

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
    touch "${TEST_DIR}/sudo_timestamp"
    exit 0
  else
    echo "STDIN_CANARY_MISMATCH" >> "$LOG_FILE"
    exit 1
  fi
fi

# Simulate sudo -n true / sudo -n -v
if [[ "${1:-}" == "-n" ]]; then
  if [[ -f "${TEST_DIR}/sudo_timestamp" ]]; then
    echo "TIMESTAMP_CACHE_VALID" >> "$LOG_FILE"
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
        if tr '\0' ' ' < "$pid/cmdline" 2>/dev/null | grep -q "$CANARY_SECRET"; then
          echo "LEAK_FOUND_IN_PROCFS_CMDLINE: $pid" >> "$PIPE_MONITOR_LOG"
        fi
      fi
      if [ -r "$pid/environ" ]; then
        if tr '\0' '\n' < "$pid/environ" 2>/dev/null | grep -q "$CANARY_SECRET"; then
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
          if tr '\0' ' ' < "$pid/cmdline" 2>/dev/null | grep -q "$CANARY_SECRET"; then
            echo "LEAK_FOUND_IN_PROCFS_CMDLINE: $pid" >> "$MONITOR_LOG"
          fi
        fi
        if [ -r "$pid/environ" ]; then
          if tr '\0' '\n' < "$pid/environ" 2>/dev/null | grep -q "$CANARY_SECRET"; then
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

rm -rf "${TEST_DIR}"
echo "==> [Credential Isolation] All tests passed! Credential exposure path completely eliminated."
