"""Unit tests and regression verification for fuzzing routines and input parsers."""

from __future__ import annotations

import unittest
from tests.fuzz_migration import (
    DRIVER_BLACKLIST_RE,
    parse_archive_json,
    sanitize_username_path,
    validate_ai_credentials_payload,
    validate_pass_store_entry,
    validate_singbox_config,
    test_one_input,
)


class TestMigrationParsers(unittest.TestCase):
    """Test parser correctness and resilience against malformed inputs."""

    def test_driver_blacklist_matches(self):
        blocked = ["linux-asahi", "m1n1", "uboot-asahi", "speakersafetyd", "asahi-scripts", "apple-bcm-firmware"]
        for pkg in blocked:
            self.assertTrue(bool(DRIVER_BLACKLIST_RE.match(pkg)), f"Expected {pkg} to be blacklisted")

        allowed = ["linux", "linux-zen", "git", "sing-box", "hyprland", "waybar"]
        for pkg in allowed:
            self.assertFalse(bool(DRIVER_BLACKLIST_RE.match(pkg)), f"Expected {pkg} to be allowed")

    def test_path_sanitization(self):
        content = 'exec = /home/olduser/.config/hypr/autostart.sh\nicon = "/home/olduser/pictures/avatar.png"'
        result = sanitize_username_path(content, "olduser", "newuser")
        self.assertIn("/home/newuser/.config/hypr/autostart.sh", result)
        self.assertIn("/home/newuser/pictures/avatar.png", result)
        self.assertNotIn("/home/olduser", result)

    def test_archive_json_validation(self):
        valid_json = '[{"name": "omarchy-migration.tar.gz", "path": "/home/u/Downloads/omarchy-migration.tar.gz", "size": "15MB", "date": "2026-09-06"}]'
        archives = parse_archive_json(valid_json)
        self.assertEqual(len(archives), 1)
        self.assertEqual(archives[0]["name"], "omarchy-migration.tar.gz")

        # Test path traversal rejection
        malicious_json = '[{"name": "root.tar.gz", "path": "../../../etc/shadow", "size": "1MB", "date": "2026-09-06"}]'
        rejected = parse_archive_json(malicious_json)
        self.assertEqual(len(rejected), 0)

    def test_prototype_pollution_defense(self):
        malicious = '{"__proto__": {"polluted": true}, "normal": "value"}'
        self.assertFalse(validate_ai_credentials_payload(malicious))

        safe = '{"token": "valid-oauth-session-token", "model": "claude-sonnet"}'
        self.assertTrue(validate_ai_credentials_payload(safe))

    def test_pass_store_entry_safety(self):
        self.assertTrue(validate_pass_store_entry("email/personal/icloud.gpg"))
        self.assertFalse(validate_pass_store_entry("../../../etc/shadow"))
        self.assertFalse(validate_pass_store_entry("email/account; rm -rf /"))
        self.assertFalse(validate_pass_store_entry("/absolute/path/forbidden"))

    def test_fuzz_input_resilience(self):
        corpus = [
            b"",
            b"A" * 10000,
            b"\x00\xff\xfe\xfd",
            b'{"incomplete": [',
            b"/home/user\n/home/dest\n" + b"A" * 5000,
        ]
        for data in corpus:
            try:
                test_one_input(data)
            except Exception as e:
                self.fail(f"test_one_input raised unexpected exception {e} on input {data[:20]!r}")

    def test_backup_filename_format(self):
        import re
        pattern = re.compile(r"^omamigrate-[a-zA-Z0-9_-]+-\d{8}-\d{6}\.tar\.gz$")
        self.assertTrue(bool(pattern.match("omamigrate-archlinux-20260906-124500.tar.gz")))
        self.assertTrue(bool(pattern.match("omamigrate-omarchy-20260906-000000.tar.gz")))
        self.assertFalse(bool(pattern.match("omamigrate-backup.tar.gz")))

    def test_localsend_duplicate_archive_matching(self):
        import re
        pattern = re.compile(r"(?i).*migrat.*(\.tar\.gz|\.tgz|\.tar\s*\(\d+\)\.gz|\s*\(\d+\)\.tar\.gz)")
        candidates = [
            "omamigrate-omarchy-20260906-123456.tar.gz",
            "omamigrate-backup.tar.gz",
            "omamigrate-backup (2).tar.gz",
            "omamigrate-backup.tar (2).gz",
            "omarchy-migration.tgz",
            "omarchy-migration (1).tar.gz",
        ]
        for c in candidates:
            self.assertTrue(bool(pattern.match(c)), f"Candidate {c} should match")



if __name__ == "__main__":
    unittest.main()
