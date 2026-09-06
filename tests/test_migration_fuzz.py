"""Unit tests and regression verification for fuzzing routines and input parsers."""

from __future__ import annotations

import unittest
from pathlib import Path
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
        self.assertEqual(sanitize_username_path(result, "olduser", "newuser"), result)

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

    def test_symlink_adaptation(self):
        old_home = "/home/olduser"
        new_home = "/home/newuser"
        target = "/home/olduser/.config/systemd/user/icloud-mail-triage.timer"
        if target.startswith(old_home):
            new_target = new_home + target[len(old_home):]
        else:
            new_target = target
        self.assertEqual(new_target, "/home/newuser/.config/systemd/user/icloud-mail-triage.timer")

    def test_temp_backup_file_filtering(self):
        import re
        pattern = re.compile(r"^.*(\.bak.*|~|\.tmp)$")
        self.assertTrue(pattern.match("config.json.bak"))
        self.assertTrue(pattern.match("config.json.bak.20260831-110110"))
        self.assertTrue(pattern.match("config.json.bak-old"))
        self.assertTrue(pattern.match("config.json~"))
        self.assertTrue(pattern.match("config.json.tmp"))
        self.assertFalse(pattern.match("config.json"))
        self.assertFalse(pattern.match("sing-box.service"))

    def test_singbox_config_validity(self):
        valid = '{"inbounds": [{"type": "tun"}], "outbounds": [{"tag": "proxy"}]}'
        self.assertTrue(validate_singbox_config(valid))
        invalid = '{"inbounds": "not-a-list"}'
        self.assertFalse(validate_singbox_config(invalid))


class TestRestoreContract(unittest.TestCase):
    """Regression checks for critical restore convergence guarantees."""

    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        cls.restore = (root / "lib" / "restore.sh").read_text()
        cls.export = (root / "lib" / "export.sh").read_text()
        cls.core = (root / "lib" / "core.sh").read_text()
        cls.ai_state = (root / "lib" / "ai-state.sh").read_text()
        cls.qml = (root / "OmaMigrate.qml").read_text()

    def test_tun_is_loaded_and_persisted_before_service_activation(self):
        module_file = "/etc/modules-load.d/99-omamigrate-sing-box-tun.conf"
        self.assertIn("modprobe tun", self.restore)
        self.assertIn(module_file, self.restore)
        self.assertIn("[ ! -c /dev/net/tun ]", self.restore)
        self.assertLess(self.restore.index("modprobe tun"), self.restore.index("pacman -Syu"))
        self.assertLess(self.restore.index("modprobe tun"), self.restore.index("for srv in sing-box"))

    def test_singbox_permissions_and_health_are_verified(self):
        self.assertIn("$ELEVATOR find /etc/sing-box", self.restore)
        self.assertIn('systemctl is-active --quiet "${srv}.service"', self.restore)
        self.assertIn('record_restore_error "Could not restart ${srv}.service."', self.restore)

    def test_timer_is_stopped_before_system_config_deployment(self):
        stop = "systemctl stop sing-box-node-rotate.timer"
        deploy = 'msg_step "Deploying /etc system configs..."'
        self.assertLess(self.restore.index(stop), self.restore.index(deploy))

    def test_package_restore_never_performs_partial_upgrade_sync(self):
        self.assertNotIn("pacman -Sy --noconfirm", self.restore)
        self.assertIn('NATIVE_PKGS+=("$pkg")', self.restore)
        self.assertIn('AUR_PKGS+=("$pkg")', self.restore)

    def test_restore_archive_is_not_modified_and_shell_profiles_are_exported(self):
        self.assertNotIn('rm -rf "${RESTORE_DATA_DIR}/user_home', self.restore)
        self.assertIn(".zshrc .zprofile", self.export)

    def test_mihoro_config_and_user_mihomo_service_are_restored(self):
        self.assertIn('"mihoro.toml"', self.core)
        self.assertIn('USER_MIHOMO_REQUESTED=true', self.restore)
        self.assertIn('systemctl --user restart mihomo.service', self.restore)
        self.assertIn('$ELEVATOR systemctl disable --now mihomo.service', self.restore)

    def test_complete_ai_backup_has_transactional_snapshots_and_manifest(self):
        self.assertIn("src.backup(dst)", self.ai_state)
        self.assertIn("PRAGMA quick_check", self.ai_state)
        self.assertIn("ai_manifest.sha256", self.export)
        self.assertIn("ai_verify_manifest", self.restore)

    def test_mainstream_agent_history_roots_are_covered(self):
        for path in (
            '.claude',
            '.codex',
            '.gemini',
            '.pi',
            '.grok',
            '.omp',
            '.config/opencode',
            '.local/share/opencode',
        ):
            self.assertIn(f'"{path}"', self.ai_state)

    def test_standard_mode_uses_allowlist_not_history_denylist(self):
        self.assertIn("AI_STANDARD_ITEMS", self.export)
        self.assertNotIn('AI_EXCLUDES=(', self.export)
        self.assertIn("Standard (credentials & configs only; no histories or plugins)", self.export)

    def test_omp_profiles_and_opencode_database_overrides_are_registered(self):
        self.assertIn("PI_CONFIG_DIR", self.export)
        self.assertIn("PI_CODING_AGENT_DIR", self.export)
        self.assertIn('"${omp_root}/profiles"', self.export)
        self.assertIn("OPENCODE_DB", self.export)

    def test_gui_does_not_offer_incomplete_system_backup(self):
        self.assertNotIn("Skip Protected Files", self.qml)
        self.assertNotIn("Skip System Files", self.qml)
        self.assertNotIn("OMAMIGRATE_SKIP_PROTECTED_SYSTEM", self.qml)
        self.assertIn("refusing to create an incomplete migration backup", self.export)

    def test_shell_json_is_excluded_from_bulk_restore_and_atomically_injected(self):
        self.assertIn("--exclude='.config/omarchy/shell.json'", self.restore)
        self.assertIn("TARGET_SHELL_JSON", self.restore)
        self.assertIn("TMP_SHELL_JSON", self.restore)
        self.assertIn("luneth90.omamigrate", self.restore)


if __name__ == "__main__":
    unittest.main()
