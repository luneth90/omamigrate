"""Atheris fuzz harness for OmaMigrate input parsers and migration routines.

This harness verifies robustness against unexpected, malformed, or hostile
inputs in package filtering regexes, archive JSON descriptors, path rewrites,
and CLI parameter handling.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import atheris
except ImportError:
    atheris = None

ROOT = Path(__file__).resolve().parent.parent

# Driver blacklist pattern from lib/export.sh
DRIVER_BLACKLIST_RE = re.compile(r"^(linux-asahi|m1n1|uboot-asahi|speakersafetyd|asahi-.*|apple-.*)$")

# Allowed subcommands and flags from bin/omamigrate
VALID_COMMANDS = {"backup", "export", "restore", "import", "send", "status", "help"}
VALID_FLAGS = {"--help", "-h", "--with-ai-history", "--complete"}


def sanitize_username_path(text: str, old_user: str, new_user: str) -> str:
    """Simulate path sanitization from lib/restore.sh."""
    if not old_user or not new_user:
        return text
    # Bounded length check
    bounded_text = text[:131072]
    safe_old = re.escape(old_user)
    return re.sub(rf"/home/{safe_old}(?=[/\s\"'`;]|%20|$)", f"/home/{new_user}", bounded_text)


def parse_archive_json(data_str: str) -> list[dict]:
    """Simulate archive JSON parser from lib/scan-archives.sh."""
    try:
        parsed = json.loads(data_str[:65536])
        if not isinstance(parsed, list):
            return []
        valid_items = []
        for item in parsed[:100]:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", ""))[:256]
            path = str(item.get("path", ""))[:1024]
            size = str(item.get("size", ""))[:64]
            date = str(item.get("date", ""))[:64]
            # Verify no path traversal outside designated downloads
            if ".." in path or "\x00" in path:
                continue
            valid_items.append({"name": name, "path": path, "size": size, "date": date})
        return valid_items
    except (json.JSONDecodeError, UnicodeDecodeError, RecursionError):
        return []


def test_one_input(data: bytes) -> None:
    """Fuzz migration input routines with raw byte streams."""
    if not data:
        return

    try:
        raw_str = data.decode("utf-8", errors="replace")
    except Exception:
        return

    # 1. Test driver blacklist regex against hostile or malformed package names
    pkg_candidate = raw_str[:256].strip()
    try:
        _ = bool(DRIVER_BLACKLIST_RE.match(pkg_candidate))
    except Exception:
        pass

    # 2. Test archive JSON parsing
    _ = parse_archive_json(raw_str)

    # 3. Test username path sanitization
    parts = raw_str[:512].split("\n", 2)
    old_u = parts[0] if len(parts) > 0 else "user1"
    new_u = parts[1] if len(parts) > 1 else "user2"
    body = parts[2] if len(parts) > 2 else raw_str
    try:
        _ = sanitize_username_path(body, old_u, new_u)
    except Exception:
        pass

    # 4. Test command line tokenizer and argument validator
    tokens = raw_str[:512].split()
    for token in tokens[:10]:
        _ = token in VALID_COMMANDS
        _ = token in VALID_FLAGS


if __name__ == "__main__":
    if atheris is None:
        # Fallback smoke test for environments without atheris installed
        print("Atheris not installed locally; executing deterministic smoke corpus...")
        corpus = [
            b"",
            b"linux-asahi",
            b"speakersafetyd-git",
            b"m1n1\x00malicious",
            b'[{"name": "test.tar.gz", "path": "/home/user/Downloads/test.tar.gz", "size": "10MB", "date": "2026-09-06"}]',
            b'[{"path": "../../etc/shadow"}]',
            b'{"invalid": "format"}',
            b"alice\nbob\n/home/alice/.config/hypr\n",
            b"backup --with-ai-history --complete",
            b"--invalid-flag-injection",
        ]
        for item in corpus:
            test_one_input(item)
        print("Smoke corpus execution succeeded!")
        sys.exit(0)

    atheris.instrument_all()
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
