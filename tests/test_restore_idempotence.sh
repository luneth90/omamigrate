#!/usr/bin/env bash
set -euo pipefail

command -v bwrap >/dev/null 2>&1 || {
  echo "SKIP: bubblewrap is unavailable; restore integration test not run."
  exit 0
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p \
  "$TEST_ROOT/etc/sing-box" \
  "$TEST_ROOT/etc/modules-load.d" \
  "$TEST_ROOT/var-lib" \
  "$TEST_ROOT/home" \
  "$TEST_ROOT/restore/user_home" \
  "$TEST_ROOT/restore/user_home/.config/mihomo" \
  "$TEST_ROOT/restore/user_home/.config/systemd/user" \
  "$TEST_ROOT/restore/user_home/.local/bin" \
  "$TEST_ROOT/restore/system_root/etc/sing-box" \
  "$TEST_ROOT/restore/pkg_meta" \
  "$TEST_ROOT/bin"

printf '%s\n' '/home/source-user' > "$TEST_ROOT/restore/pkg_meta/source_home.txt"
: > "$TEST_ROOT/restore/pkg_meta/packages_explicit.txt"
printf '%s\n' 'export PROJECT=/home/source-user/project' > "$TEST_ROOT/restore/user_home/.bashrc"
printf '%s\n' 'mihomo_binary_path = "/home/source-user/.local/bin/mihomo"' \
  > "$TEST_ROOT/restore/user_home/.config/mihoro.toml"
printf '%s\n' 'mixed-port: 7890' > "$TEST_ROOT/restore/user_home/.config/mihomo/config.yaml"
cat > "$TEST_ROOT/restore/user_home/.config/systemd/user/mihomo.service" <<'EOF'
[Service]
ExecStart=/home/source-user/.local/bin/mihomo -d /home/source-user/.config/mihomo
EOF
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_ROOT/restore/user_home/.local/bin/mihomo"
chmod +x "$TEST_ROOT/restore/user_home/.local/bin/mihomo"
printf '%s\n' '{"inbounds":[{"type":"tun","interface_name":"oma-test"}],"outbounds":[{"type":"direct"}]}' \
  > "$TEST_ROOT/restore/system_root/etc/sing-box/config.json"

cat > "$TEST_ROOT/bin/id" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  -u) echo 1000 ;;
  -un) echo target-user ;;
  "-u sing-box") echo 959 ;;
  *) exec /usr/bin/id "$@" ;;
esac
EOF

cat > "$TEST_ROOT/bin/getent" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = group ] && [ "${2:-}" = sing-box ]; then
  echo 'sing-box:x:959:'
  exit 0
fi
exec /usr/bin/getent "$@"
EOF

cat > "$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|-A) shift ;;
    -v) exit 0 ;;
    -u) shift 2 ;;
    *) break ;;
  esac
done
case "${1:-}" in
  chown|usermod) exit 0 ;;
  install)
    shift
    args=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -o|-g) shift 2 ;;
        *) args+=("$1"); shift ;;
      esac
    done
    exec /usr/bin/install "${args[@]}"
    ;;
esac
exec "$@"
EOF

cat > "$TEST_ROOT/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -Qi|-Si) exit 0 ;;
esac
exit 0
EOF

cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> /tmp/systemctl.log
case "$*" in
  *is-active*) exit 0 ;;
  *) exit 0 ;;
esac
EOF

for command_name in sing-box mise hyprctl omarchy; do
  cat > "$TEST_ROOT/bin/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
done

cat > "$TEST_ROOT/bin/ip" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'rule del'*) exit 1 ;;
  *) exit 0 ;;
esac
EOF

chmod +x "$TEST_ROOT/bin/"*

run_restore() {
  bwrap \
    --unshare-user --uid 0 --gid 0 \
    --ro-bind / / \
    --dev /dev \
    --dir /dev/net \
    --dev-bind /dev/null /dev/net/tun \
    --bind "$TEST_ROOT/etc" /etc \
    --bind "$TEST_ROOT/var-lib" /var/lib \
    --bind "$TEST_ROOT" /tmp \
    --setenv HOME /tmp/home \
    --setenv PATH /tmp/bin:/usr/bin:/bin \
    --setenv OMAMIGRATE_GUI 1 \
    /usr/bin/bash "$ROOT_DIR/lib/restore.sh" /tmp/restore
}

snapshot_state() {
  {
    find "$TEST_ROOT/etc" "$TEST_ROOT/home" "$TEST_ROOT/var-lib" \
      -printf '%y %m %P\n' -type f -exec sha256sum {} +
    readlink "$TEST_ROOT/home/.config/systemd/user/icloud-mail-triage.timer" 2>/dev/null || true
  } | sha256sum | cut -d' ' -f1
}

archive_before="$(find "$TEST_ROOT/restore" -type f -exec sha256sum {} + | sha256sum | cut -d' ' -f1)"
run_restore >/dev/null
first_state="$(snapshot_state)"
run_restore >/dev/null
second_state="$(snapshot_state)"
archive_after="$(find "$TEST_ROOT/restore" -type f -exec sha256sum {} + | sha256sum | cut -d' ' -f1)"

test "$first_state" = "$second_state"
test "$archive_before" = "$archive_after"
test "$(cat "$TEST_ROOT/etc/modules-load.d/99-omamigrate-sing-box-tun.conf")" = tun
grep -qx 'export PROJECT=/tmp/home/project' "$TEST_ROOT/home/.bashrc"
grep -qx 'mihomo_binary_path = "/tmp/home/.local/bin/mihomo"' "$TEST_ROOT/home/.config/mihoro.toml"
grep -q 'ExecStart=/tmp/home/.local/bin/mihomo -d /tmp/home/.config/mihomo' \
  "$TEST_ROOT/home/.config/systemd/user/mihomo.service"
test "$(stat -c %a "$TEST_ROOT/home/.config/mihoro.toml")" = 600
grep -q 'restart sing-box.service' "$TEST_ROOT/systemctl.log"
grep -q -- '--user restart mihomo.service' "$TEST_ROOT/systemctl.log"
grep -q 'disable --now mihomo.service' "$TEST_ROOT/systemctl.log"

echo "Restore two-run convergence test passed."
