#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# shellcheck source=../lib/ai-state.sh
source "${ROOT_DIR}/lib/ai-state.sh"

printf '%s\n' "${AI_STATE_PATHS[@]}" | grep -qx '.omp'
printf '%s\n' "${AI_STATE_PATHS[@]}" | grep -qx '.config/opencode'
printf '%s\n' "${AI_STATE_PATHS[@]}" | grep -qx '.local/share/opencode'
if printf '%s\n' "${AI_STANDARD_ITEMS[@]}" | grep -Eq '(^|/)(sessions|projects|conversations|history\.jsonl)($|/)'; then
  echo "Standard AI allow-list contains session history." >&2
  exit 1
fi
if printf '%s\n' "${AI_STANDARD_ITEMS[@]}" | grep -Eq '(^|/)(skills|themes|hooks|extensions)($|/)'; then
  echo "Standard AI allow-list contains plugins or customization bundles." >&2
  exit 1
fi
if printf '%s\n' "${AI_COMPLETE_RSYNC_EXCLUDES[@]}" | grep -qx -- '--exclude=bin'; then
  echo "Complete AI backup excludes plugin binaries globally." >&2
  exit 1
fi
printf '%s\n' "${AI_COMPLETE_RSYNC_EXCLUDES[@]}" | \
  grep -qx -- '--exclude=/antigravity-cli/bin/'
printf '%s\n' "${AI_COMPLETE_EXTRA_ITEMS[@]}" | \
  grep -qx '.gemini/antigravity-cli/cache/conversation_metadata.json'
printf '%s\n' "${AI_COMPLETE_EXTRA_ITEMS[@]}" | \
  grep -qx '.gemini/antigravity-cli/cache/last_conversations.json'

mkdir -p \
  "$TEST_ROOT/source/.codex" \
  "$TEST_ROOT/source/.gemini/antigravity-cli/bin" \
  "$TEST_ROOT/source/.gemini/plugins/example/bin" \
  "$TEST_ROOT/target/.codex" \
  "$TEST_ROOT/target/.claude/projects/-home-source-user-Projects-demo" \
  "$TEST_ROOT/target/.grok/sessions/%2Fhome%2Fsource-user%2FProjects%2Fdemo"

python3 - "$TEST_ROOT/source/.codex/state_5.sqlite" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute("CREATE TABLE threads (id TEXT, cwd TEXT, title TEXT)")
connection.execute(
    "INSERT INTO threads VALUES (?, ?, ?)",
    ("thread-1", "/home/source-user/Projects/demo", "Discuss /home/source-user literally"),
)
connection.commit()
connection.close()
PY

touch "$TEST_ROOT/source/.gemini/antigravity-cli/bin/agentapi"
touch "$TEST_ROOT/source/.gemini/plugins/example/bin/plugin-helper"
mkdir -p "$TEST_ROOT/filtered/.gemini"
rsync -a "${AI_COMPLETE_RSYNC_EXCLUDES[@]}" \
  "$TEST_ROOT/source/.gemini/" "$TEST_ROOT/filtered/.gemini/"
test ! -e "$TEST_ROOT/filtered/.gemini/antigravity-cli/bin/agentapi"
test -e "$TEST_ROOT/filtered/.gemini/plugins/example/bin/plugin-helper"

ai_snapshot_sqlite_file \
  "$TEST_ROOT/source/.codex/state_5.sqlite" \
  "$TEST_ROOT/target/.codex/state_5.sqlite"

cat > "$TEST_ROOT/target/.codex/session.jsonl" <<'EOF'
{"type":"session_meta","payload":{"cwd":"/home/source-user/Projects/demo","message":"Keep /home/source-user in conversation text","recent":{"/home/source-user/Projects/demo":"thread-1"}}}
EOF

ai_adapt_sqlite_paths "$TEST_ROOT/target/.codex" /home/source-user /home/target-user
ai_adapt_json_paths "$TEST_ROOT/target/.codex" /home/source-user /home/target-user

python3 - "$TEST_ROOT/target/.codex/state_5.sqlite" "$TEST_ROOT/target/.codex/session.jsonl" <<'PY'
import json
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
cwd, title = connection.execute("SELECT cwd, title FROM threads").fetchone()
connection.close()
assert cwd == "/home/target-user/Projects/demo"
assert title == "Discuss /home/source-user literally"

event = json.loads(open(sys.argv[2], encoding="utf-8").read())
assert event["payload"]["cwd"] == "/home/target-user/Projects/demo"
assert event["payload"]["message"] == "Keep /home/source-user in conversation text"
assert event["payload"]["recent"] == {"/home/target-user/Projects/demo": "thread-1"}
PY

ai_rename_encoded_directories "$TEST_ROOT/target/.claude" /home/source-user /home/target-user
ai_rename_encoded_directories "$TEST_ROOT/target/.grok" /home/source-user /home/target-user
test -d "$TEST_ROOT/target/.claude/projects/-home-target-user-Projects-demo"
test -d "$TEST_ROOT/target/.grok/sessions/%2Fhome%2Ftarget-user%2FProjects%2Fdemo"

touch "$TEST_ROOT/target/.codex/state_5.sqlite-wal"
touch "$TEST_ROOT/target/.codex/session.lock"
ai_cleanup_target_runtime_state "$TEST_ROOT/target/.codex"
test ! -e "$TEST_ROOT/target/.codex/state_5.sqlite-wal"
test ! -e "$TEST_ROOT/target/.codex/session.lock"
test -e "$TEST_ROOT/target/.codex/state_5.sqlite"

touch "$TEST_ROOT/target/custom-opencode.db" "$TEST_ROOT/target/custom-opencode.db-wal"
ai_cleanup_target_runtime_state "$TEST_ROOT/target/custom-opencode.db"
test ! -e "$TEST_ROOT/target/custom-opencode.db-wal"

ai_write_manifest "$TEST_ROOT/target" "$TEST_ROOT/manifest.sha256" .codex .claude .grok
ai_verify_manifest "$TEST_ROOT/target" "$TEST_ROOT/manifest.sha256"
printf '%s\n' '{"changed":true}' >> "$TEST_ROOT/target/.codex/session.jsonl"
if ai_verify_manifest "$TEST_ROOT/target" "$TEST_ROOT/manifest.sha256" >/dev/null 2>&1; then
  echo "AI manifest verification accepted modified history." >&2
  exit 1
fi

echo "AI state snapshot and adaptation tests passed."
