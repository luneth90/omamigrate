#!/usr/bin/env bash
# Shared AI agent state definitions and portable snapshot/adaptation helpers.

# Paths are relative to $HOME so an archive can be restored under a different
# username without retaining the source machine's absolute home directory.
AI_STATE_PATHS=(
  ".claude"
  ".codex"
  ".gemini"
  ".pi"
  ".grok"
  ".omp"
  ".local/share/omp"
  ".config/opencode"
  ".local/share/opencode"
  ".local/state/opencode"
)

# Standard backups use an allow-list. This prevents history files added by a
# future agent release from silently leaking into the no-history backup mode.
AI_STANDARD_ITEMS=(
  ".claude/settings.json"
  ".claude/.credentials.json"
  ".codex/config.toml"
  ".codex/auth.json"
  ".codex/computer-use/config.json"
  ".gemini/config"
  ".gemini/antigravity-cli/settings.json"
  ".pi/agent/settings.json"
  ".grok/config.toml"
  ".grok/auth.json"
  ".grok/trusted_folders.toml"
  ".omp/agent/config.yml"
  ".omp/agent/settings.json"
  ".omp/agent/agent.db"
  ".config/opencode/opencode.json"
  ".config/opencode/tui.jsonc"
  ".local/share/opencode/auth.json"
)

# Small, rebuildable indexes that materially improve first-launch continuity
# after a Complete Agy restore. The surrounding cache directory remains
# excluded so transient or large cached data is not migrated.
AI_COMPLETE_EXTRA_ITEMS=(
  ".gemini/antigravity-cli/cache/conversation_metadata.json"
  ".gemini/antigravity-cli/cache/last_conversations.json"
  ".gemini/antigravity-cli/cache/default_project_id.txt"
  ".gemini/antigravity-cli/cache/onboarding.json"
)

# Complete backups retain histories, memories, plugins and session artifacts,
# while excluding process-local state and data that the applications rebuild.
AI_COMPLETE_RSYNC_EXCLUDES=(
  "--exclude=cache"
  "--exclude=Cache"
  "--exclude=GPUCache"
  "--exclude=logs"
  "--exclude=log"
  "--exclude=tmp"
  "--exclude=.tmp"
  "--exclude=/antigravity-cli/crashes/"
  "--exclude=/antigravity-cli/presence/"
  "--exclude=/antigravity-cli/updater/"
  "--exclude=/antigravity-cli/bin/"
  "--exclude=ipc"
  "--exclude=daemon"
  "--exclude=thread-writer-locks"
  "--exclude=Singleton*"
  "--exclude=/antigravity-cli/active_sessions.json"
  "--exclude=*.log"
  "--exclude=*.sock"
  "--exclude=*.lock"
  "--exclude=*.pid"
  "--exclude=*-wal"
  "--exclude=*-shm"
  "--exclude=*-journal"
  "--exclude=*.sqlite"
  "--exclude=*.sqlite3"
  "--exclude=*.db"
  "--exclude=queue_*.sqlite*"
  "--exclude=logs_*.sqlite*"
)

ai_valid_relative_path() {
  local path="${1:-}"
  [ -n "$path" ] && [[ "$path" != /* ]] && \
    [[ "/$path/" != *"/../"* ]] && [[ "$path" != "." ]]
}

ai_path_is_runtime_state() {
  local path="/${1#/}"
  local base="${path##*/}"
  case "$path/" in
    */cache/*|*/Cache/*|*/GPUCache/*|*/logs/*|*/log/*|*/tmp/*|*/.tmp/*|\
    /antigravity-cli/crashes/*|/antigravity-cli/presence/*|\
    /antigravity-cli/updater/*|/antigravity-cli/bin/*|*/ipc/*|*/daemon/*|\
    */thread-writer-locks/*)
      return 0
      ;;
  esac
  case "$base" in
    Singleton*|active_sessions.json|*.log|*.sock|*.lock|*.pid|*-wal|*-shm|*-journal|\
    queue_*.sqlite|queue_*.sqlite3|queue_*.db|logs_*.sqlite|logs_*.sqlite3|logs_*.db)
      return 0
      ;;
  esac
  return 1
}

ai_snapshot_sqlite_file() {
  local source_file="$1"
  local destination_file="$2"
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required to snapshot live AI session databases safely." >&2
    return 1
  }
  mkdir -p "$(dirname "$destination_file")"
  python3 - "$source_file" "$destination_file" <<'PY'
import os
import sqlite3
import sys
from pathlib import Path
from urllib.parse import quote

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
temporary = destination.with_name(destination.name + ".omamigrate-snapshot")
temporary.unlink(missing_ok=True)

uri = f"file:{quote(str(source))}?mode=ro"
src = sqlite3.connect(uri, uri=True, timeout=30)
dst = sqlite3.connect(temporary)
try:
    src.backup(dst)
    result = dst.execute("PRAGMA quick_check").fetchone()
    if not result or result[0] != "ok":
        raise RuntimeError(f"SQLite quick_check failed: {result!r}")
finally:
    dst.close()
    src.close()

os.replace(temporary, destination)
os.chmod(destination, source.stat().st_mode & 0o777)
PY
}

ai_snapshot_databases_in_tree() {
  local source_root="$1"
  local destination_root="$2"
  local database relative destination

  [ -d "$source_root" ] || return 0
  while IFS= read -r -d '' database; do
    relative="${database#${source_root}/}"
    ai_path_is_runtime_state "$relative" && continue
    destination="${destination_root}/${relative}"
    mkdir -p "$(dirname "$destination")"
    if [ "$(head -c 15 "$database" 2>/dev/null || true)" = "SQLite format 3" ]; then
      ai_snapshot_sqlite_file "$database" "$destination" || return 1
    else
      cp -p "$database" "$destination" || return 1
    fi
  done < <(find "$source_root" -type f \
    \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -print0)
}

ai_write_manifest() {
  local user_home_root="$1"
  local manifest="$2"
  shift 2
  local relative

  : > "$manifest"
  for relative in "$@"; do
    ai_valid_relative_path "$relative" || return 1
    [ -e "${user_home_root}/${relative}" ] || [ -L "${user_home_root}/${relative}" ] || continue
    (
      cd "$user_home_root"
      if [ -d "$relative" ]; then
        find "$relative" -type f -print0 | sort -z | xargs -0 -r sha256sum
      elif [ -f "$relative" ]; then
        sha256sum "$relative"
      fi
    ) >> "$manifest" || return 1
  done
}

ai_verify_manifest() {
  local user_home_root="$1"
  local manifest="$2"
  [ -s "$manifest" ] || return 0
  (cd "$user_home_root" && sha256sum --quiet -c "$manifest")
}

ai_cleanup_target_runtime_state() {
  local target_root="$1"
  if [ -f "$target_root" ]; then
    rm -f "${target_root}-wal" "${target_root}-shm" \
      "${target_root}-journal" 2>/dev/null || return 1
    return 0
  fi
  [ -d "$target_root" ] || return 0
  find "$target_root" -type f \
    \( -name '*-wal' -o -name '*-shm' -o -name '*-journal' -o \
       -name '*.lock' -o -name '*.pid' \) -delete 2>/dev/null || return 1
  find "$target_root" -type s -delete 2>/dev/null || return 1
}

ai_adapt_json_paths() {
  local root="$1"
  local old_home="$2"
  local new_home="$3"
  [ -d "$root" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$root" "$old_home" "$new_home" <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
old_home = sys.argv[2]
new_home = sys.argv[3]

def path_key(key):
    key = (key or "").lower().replace("-", "_")
    exact = {
        "cwd", "cwds", "directory", "directories", "workdir",
        "working_directory", "path", "paths", "root", "roots",
        "workspace", "workspaces", "workspace_uri", "workspace_uris",
        "repo", "repository", "project", "project_dir", "project_root",
    }
    return key in exact or key.endswith(("_path", "_paths", "_dir", "_dirs", "_root", "_roots"))

def adapt(value, parent_key=None):
    changed = False
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            updated, child_changed = adapt(child, key)
            updated_key = key
            if isinstance(key, str) and (key == old_home or key.startswith(old_home + "/")):
                updated_key = new_home + key[len(old_home):]
            result[updated_key] = updated
            changed = changed or child_changed or updated_key != key
        return result, changed
    if isinstance(value, list):
        result = []
        for child in value:
            updated, child_changed = adapt(child, parent_key)
            result.append(updated)
            changed = changed or child_changed
        return result, changed
    if isinstance(value, str) and path_key(parent_key) and old_home in value:
        return value.replace(old_home, new_home), True
    return value, False

def rewrite_json(path):
    try:
        original = path.read_text(encoding="utf-8")
        value = json.loads(original)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return
    updated, changed = adapt(value)
    if not changed:
        return
    temporary = path.with_name(path.name + ".omamigrate-paths")
    temporary.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, path.stat().st_mode & 0o777)
    os.replace(temporary, path)

def rewrite_jsonl(path):
    temporary = path.with_name(path.name + ".omamigrate-paths")
    changed = False
    try:
        with path.open("r", encoding="utf-8") as source, temporary.open("w", encoding="utf-8") as target:
            for line in source:
                newline = "\n" if line.endswith("\n") else ""
                payload = line[:-1] if newline else line
                try:
                    value = json.loads(payload)
                    updated, line_changed = adapt(value)
                except json.JSONDecodeError:
                    target.write(line)
                    continue
                if line_changed:
                    target.write(json.dumps(updated, ensure_ascii=False, separators=(",", ":")) + newline)
                    changed = True
                else:
                    target.write(line)
    except (OSError, UnicodeDecodeError):
        temporary.unlink(missing_ok=True)
        return
    if changed:
        os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    else:
        temporary.unlink(missing_ok=True)

for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    if path.suffix == ".jsonl":
        rewrite_jsonl(path)
    elif path.suffix == ".json":
        rewrite_json(path)
PY
}

ai_adapt_sqlite_paths() {
  local root="$1"
  local old_home="$2"
  local new_home="$3"
  [ -e "$root" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$root" "$old_home" "$new_home" <<'PY'
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1])
old_home = sys.argv[2]
new_home = sys.argv[3]

def path_column(name):
    name = name.lower().replace("-", "_")
    exact = {
        "cwd", "cwds", "directory", "directories", "workdir",
        "working_directory", "path", "paths", "root", "roots",
        "workspace", "workspaces", "workspace_uri", "workspace_uris",
        "worktree", "worktrees", "repo", "repository",
    }
    return name in exact or name.endswith(
        ("_path", "_paths", "_dir", "_dirs", "_root", "_roots", "_cwd", "_cwds", "_uri", "_uris")
    )

def quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'

databases = [root] if root.is_file() else root.rglob("*")
for database in databases:
    if not database.is_file() or database.is_symlink():
        continue
    if database.suffix not in {".sqlite", ".sqlite3", ".db"}:
        continue
    try:
        if database.read_bytes()[:16] != b"SQLite format 3\0":
            continue
        connection = sqlite3.connect(database, timeout=30)
        tables = connection.execute(
            "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        connection.execute("BEGIN IMMEDIATE")
        for table, create_sql in tables:
            if create_sql and "VIRTUAL TABLE" in create_sql.upper():
                continue
            quoted_table = quote_identifier(table)
            columns = connection.execute(f"PRAGMA table_info({quoted_table})").fetchall()
            for column in columns:
                name = column[1]
                if not path_column(name):
                    continue
                quoted_column = quote_identifier(name)
                connection.execute(
                    f"UPDATE {quoted_table} "
                    f"SET {quoted_column}=replace({quoted_column}, ?, ?) "
                    f"WHERE typeof({quoted_column})='text' AND instr({quoted_column}, ?) > 0",
                    (old_home, new_home, old_home),
                )
        connection.commit()
        result = connection.execute("PRAGMA quick_check").fetchone()
        if not result or result[0] != "ok":
            raise RuntimeError(f"quick_check failed for {database}: {result!r}")
        connection.close()
    except Exception as error:
        print(f"Failed to adapt AI database {database}: {error}", file=sys.stderr)
        raise
PY
}

ai_rename_encoded_directories() {
  local root="$1"
  local old_home="$2"
  local new_home="$3"
  local old_dash="${old_home//\//-}"
  local new_dash="${new_home//\//-}"
  local old_url="${old_home//\//%2F}"
  local new_url="${new_home//\//%2F}"
  local token replacement directory renamed

  [ -d "$root" ] || return 0
  for token in "$old_dash" "$old_url"; do
    if [ "$token" = "$old_dash" ]; then
      replacement="$new_dash"
    else
      replacement="$new_url"
    fi
    while IFS= read -r -d '' directory; do
      renamed="${directory//$token/$replacement}"
      [ "$renamed" != "$directory" ] || continue
      case "$directory" in
        "$root"/*) ;;
        *) return 1 ;;
      esac
      if [ -e "$renamed" ]; then
        mkdir -p "$renamed"
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --checksum "$directory/" "$renamed/" || return 1
        else
          cp -a "$directory/." "$renamed/" || return 1
        fi
        find "$directory" -depth -delete || return 1
      else
        mv "$directory" "$renamed" || return 1
      fi
    done < <(find "$root" -depth -type d -name "*${token}*" -print0)
  done
}
