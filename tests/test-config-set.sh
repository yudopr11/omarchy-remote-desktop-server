#!/usr/bin/env bash
# Contract tests for `omarchy-rdp-config set` (T5: bind, username, output).

options_path() { printf '%s' "$XDG_CONFIG_HOME/hypr-rdp/options"; }

options_sha() { sha256sum < "$(options_path)" | cut -d' ' -f1; }

# monitor_fixture — one monitor in the real hyprctl shape (nested workspace).
monitor_fixture() {
  mkdir -p "$STUB_STATE"
  cat > "$STUB_STATE/hyprctl.monitors" <<'JSON'
[{
    "id": 0,
    "name": "eDP-1",
    "description": "Samsung Display Corp. 0x4181",
    "width": 2880,
    "height": 1800,
    "activeWorkspace": {
        "id": 1,
        "name": "1"
    },
    "focused": true
}]
JSON
}

count_lines() { grep -c -e "$1" "$(options_path)" || true; }

case_bind_mode() {
  local mode="$1" expected="$2" extra=()
  shift 2
  setup_env
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set bind --mode "$mode" "$@")" || fail "set exited non-zero"
  assert_contains "$out" "\"bind\":\"$expected\""
  assert_contains "$(cat "$(options_path)")" "BIND=\"$expected\""
}

t_bind_localhost() {
  case_bind_mode localhost "127.0.0.1:3389"
}

t_bind_lan_default_port() {
  case_bind_mode lan "0.0.0.0:3389"
}

t_bind_custom_address() {
  setup_env
  printf '2: enp1s0    inet 10.0.0.5/24 brd 10.0.0.255 scope global enp1s0\n' > "$STUB_STATE/ip.addr"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set bind --mode custom --host 10.0.0.5 --port 3390)" \
    || fail "set exited non-zero"
  assert_contains "$out" '"bind":"10.0.0.5:3390"'
}

t_bind_keeps_current_port() {
  setup_env
  write_options 'BIND="0.0.0.0:13389"'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set bind --mode localhost)" || fail "set exited non-zero"
  assert_contains "$out" '"bind":"127.0.0.1:13389"'
}

t_bind_rejects_unknown_host() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  local before after out
  before="$(options_sha)"
  out="$("$SCRIPTS/omarchy-rdp-config" set bind --mode custom --host 8.8.8.8 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"error"'
  after="$(options_sha)"
  assert_eq "$before" "$after"
}

t_bind_rejects_bad_port() {
  setup_env
  local port before after out
  for port in 0 65536 abc; do
    write_options 'BIND="127.0.0.1:3389"'
    before="$(options_sha)"
    out="$("$SCRIPTS/omarchy-rdp-config" set bind --mode lan --port "$port" 2>&1)"
    assert_eq "1" "$?"
    assert_contains "$out" '"error"'
    after="$(options_sha)"
    assert_eq "$before" "$after"
  done
}

t_username_roundtrip() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set username --value admin)" || fail "set exited non-zero"
  assert_contains "$out" '"username":"admin"'
  assert_eq "1" "$(count_lines '^USERNAME=')"
  assert_contains "$(cat "$(options_path)")" 'USERNAME="admin"'
}

t_username_rejects_injection() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'USERNAME="yudopr"'
  local before after value out
  for value in '$(reboot)' '`id`' 'a"b' 'a\b' 'a b' '' \
               'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; do
    before="$(options_sha)"
    out="$("$SCRIPTS/omarchy-rdp-config" set username --value "$value" 2>&1)"
    assert_eq "1" "$?" 
    assert_contains "$out" '"error"'
    after="$(options_sha)"
    assert_eq "$before" "$after"
  done
}

t_output_named() {
  setup_env
  monitor_fixture
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set output --value eDP-1)" || fail "set exited non-zero"
  assert_contains "$out" '"output":"eDP-1"'
  assert_contains "$out" '"virtual":false'
  assert_contains "$(cat "$(options_path)")" '--output eDP-1'
  assert_eq "1" "$(count_lines '^  --output eDP-1$')"
}

t_output_virtual() {
  setup_env
  monitor_fixture
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' '  --output eDP-1' ')'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set output --value virtual)" || fail "set exited non-zero"
  assert_contains "$out" '"output":""'
  assert_contains "$out" '"virtual":true'
  assert_not_contains "$(cat "$(options_path)")" '--output'
}

t_output_rejects_unknown() {
  setup_env
  monitor_fixture
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  local before after out
  before="$(options_sha)"
  out="$("$SCRIPTS/omarchy-rdp-config" set output --value HDMI-A-9 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"error"'
  after="$(options_sha)"
  assert_eq "$before" "$after"
}

t_write_preserves_comments_and_unknown() {
  setup_env
  write_options '# my own note' 'BIND="127.0.0.1:3389"' 'OPTIONS=(' \
    '  --fps 45' '  --file-transfer-mode both' ')'
  "$SCRIPTS/omarchy-rdp-config" set bind --mode lan >/dev/null || fail "set exited non-zero"
  local content
  content="$(cat "$(options_path)")"
  assert_contains "$content" '# my own note'
  assert_contains "$content" '--file-transfer-mode both'
  assert_contains "$content" '--fps 45'
  assert_contains "$content" 'BIND="0.0.0.0:3389"'
  assert_eq "1" "$(count_lines '^BIND=')"
  assert_eq "1" "$(count_lines '^OPTIONS=(')"
}

t_write_is_atomic_under_race() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  local i
  for (( i = 0; i < 20; i++ )); do
    "$SCRIPTS/omarchy-rdp-config" set bind --mode localhost >/dev/null 2>&1 &
    "$SCRIPTS/omarchy-rdp-config" set username --value "admin$i" >/dev/null 2>&1 &
    wait
  done

  assert_eq "1" "$(count_lines '^BIND=')"
  assert_eq "1" "$(count_lines '^USERNAME=')"
  local sourced
  sourced="$(set +u; source "$(options_path)"; printf '%s' "${BIND:-}")"
  assert_eq "127.0.0.1:3389" "$sourced"

  local leftovers
  leftovers="$(find "$XDG_CONFIG_HOME/hypr-rdp" -maxdepth 1 \
      \( -name 'options.tmp*' -o -name '.options*' \) | wc -l)"
  assert_eq "0" "$leftovers"
  assert_eq "1" "$(find "$XDG_CONFIG_HOME/hypr-rdp" -maxdepth 1 -name 'options.bak' | wc -l)"
  assert_eq "600" "$(stat -c '%a' "$(options_path)")"
}

# --- T6: set opt, set autostart, restart -------------------------------------

t_opt_fps_and_bitrate_replaced_in_place() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' \
    '  --bitrate 8000000' '  --output eDP-1' ')'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set opt --fps 60 --bitrate 16000000)" \
    || fail "set exited non-zero"
  assert_contains "$out" '"fps":60'
  assert_contains "$out" '"bitrate":16000000'
  local content
  content="$(cat "$(options_path)")"
  assert_contains "$content" '--output eDP-1'
  assert_eq "1" "$(count_lines '^  --fps 60$')"
  assert_eq "1" "$(count_lines '^  --bitrate 16000000$')"
  assert_eq "0" "$(count_lines '--fps 30')"
}

t_opt_backend_enum_replaced() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' \
    '  --h264-backend auto' '  --h264-backend=auto' ')'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set opt --h264-backend vaapi)" \
    || fail "set exited non-zero"
  assert_contains "$out" '"h264Backend":"vaapi"'
  assert_eq "1" "$(count_lines '^  --h264-backend vaapi$')"
  assert_eq "0" "$(count_lines 'auto')"
}

t_opt_capture_mode_none() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set opt --capture-mode ext)" \
    || fail "set exited non-zero"
  assert_contains "$out" '"captureMode":"ext"'
  assert_eq "1" "$(count_lines '^  --capture-mode ext$')"

  out="$("$SCRIPTS/omarchy-rdp-config" set opt --capture-mode none)" \
    || fail "set exited non-zero"
  assert_contains "$out" '"captureMode":""'
  assert_eq "0" "$(count_lines 'capture-mode')"
  assert_contains "$(cat "$(options_path)")" '--fps 30'
}

t_opt_audio_mode_and_default() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  local mode out
  for mode in off redirect mirror; do
    out="$($SCRIPTS/omarchy-rdp-config set opt --audio-mode "$mode")" \
      || fail "setting audio mode $mode failed"
    assert_contains "$out" "\"audioMode\":\"$mode\""
    assert_eq "1" "$(count_lines "^  --audio-mode $mode$")"
  done

  out="$($SCRIPTS/omarchy-rdp-config set opt --audio-mode default)" \
    || fail "resetting audio mode failed"
  assert_contains "$out" '"audioMode":""'
  assert_eq "0" "$(count_lines 'audio-mode')"
  assert_contains "$(cat "$(options_path)")" '--fps 30'
}

t_opt_rejects_out_of_range() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  local before after args out
  for args in "--fps 0" "--fps 121" "--fps abc" "--bitrate 99999" \
              "--bitrate 100000001" "--h264-backend nvenc" "--capture-mode portal" \
              "--audio-mode disabled"; do
    before="$(options_sha)"
    # shellcheck disable=SC2086
    out="$("$SCRIPTS/omarchy-rdp-config" set opt $args 2>&1)"
    assert_eq "1" "$?" "set opt $args"
    assert_contains "$out" '"error"'
    after="$(options_sha)"
    assert_eq "$before" "$after" "set opt $args must not write"
  done
}

t_autostart_on_copies_password_and_enables() {
  setup_env
  mkdir -p "$XDG_RUNTIME_DIR/hypr-rdp"
  printf 'a-very-secret-password\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set autostart --value on)" || fail "set exited non-zero"
  assert_contains "$out" '"autostart":true'
  assert_contains "$out" '"storedPassword":true'
  assert_eq "a-very-secret-password" "$(cat "$XDG_CONFIG_HOME/hypr-rdp/password")"
  assert_eq "600" "$(stat -c '%a' "$XDG_CONFIG_HOME/hypr-rdp/password")"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user enable hypr-rdp.service"
}

t_autostart_on_does_not_store_password_when_enable_fails() {
  setup_env
  mkdir -p "$XDG_RUNTIME_DIR/hypr-rdp"
  printf 'new-secret\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  printf '1' > "$STUB_STATE/systemctl.enable.exit"

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set autostart --value on 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"error"'
  assert_file_absent "$XDG_CONFIG_HOME/hypr-rdp/password"
}

t_autostart_on_refuses_without_runtime_password() {
  setup_env
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set autostart --value on 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" 'terminal'
  assert_contains "$out" '"error"'
  assert_not_contains "$(cat "$STUB_LOG")" "enable"
  assert_file_absent "$XDG_CONFIG_HOME/hypr-rdp/password"
}

t_autostart_off_removes_copy_and_disables() {
  setup_env
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp"
  printf 'old-secret\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  printf 'enabled' > "$STUB_STATE/systemctl.is-enabled"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set autostart --value off)" || fail "set exited non-zero"
  assert_contains "$out" '"autostart":false'
  assert_contains "$out" '"storedPassword":false'
  assert_file_absent "$XDG_CONFIG_HOME/hypr-rdp/password"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user disable hypr-rdp.service"
}

t_autostart_off_preserves_password_when_disable_fails() {
  setup_env
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp"
  printf 'old-secret\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  printf 'enabled' > "$STUB_STATE/systemctl.is-enabled"
  printf '1' > "$STUB_STATE/systemctl.disable.exit"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" set autostart --value off 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"error"'
  assert_eq "old-secret" "$(cat "$XDG_CONFIG_HOME/hypr-rdp/password")"
}

t_restart_waits_for_our_listener() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '0' > "$STUB_STATE/systemctl.is-active"
  printf 'LISTEN 0 4096 127.0.0.1:3389 0.0.0.0:* users:(("hypr-rdp",pid=1234,fd=7))\n' \
    > "$STUB_STATE/ss.listen"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" restart)" || fail "restart exited non-zero"
  assert_contains "$out" '"ready":true'
  assert_contains "$out" '"restarted":true'
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user restart hypr-rdp.service"
}

t_restart_reports_failure_when_not_listening() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '0' > "$STUB_STATE/systemctl.is-active"
  printf 'hypr-rdp: bind failed\n' > "$STUB_STATE/journalctl.out"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" restart 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"ready":false'
  assert_contains "$out" 'bind failed'
  assert_contains "$(cat "$STUB_LOG")" "ss -ltnpH"
  assert_contains "$(cat "$STUB_LOG")" "journalctl"
}

t_restart_foreign_listener_is_not_ready() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '0' > "$STUB_STATE/systemctl.is-active"
  printf 'LISTEN 0 4096 127.0.0.1:3389 0.0.0.0:* users:(("unrelated",pid=99,fd=3))\n' \
    > "$STUB_STATE/ss.listen"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" restart 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"ready":false'
}

t_restart_inactive_is_a_noop() {
  setup_env
  printf '1' > "$STUB_STATE/systemctl.is-active"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" restart)" || fail "restart exited non-zero"
  assert_contains "$out" '"restarted":false'
  assert_contains "$out" '"ready":true'
  assert_not_contains "$(cat "$STUB_LOG")" "restart"
}

# `start` is the panel's power switch: `restart` intentionally skips an inactive
# unit, so bringing a stopped server up needs its own command.
t_start_brings_inactive_unit_up() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '1' > "$STUB_STATE/systemctl.is-active"
  printf 'LISTEN 0 4096 127.0.0.1:3389 0.0.0.0:* users:(("hypr-rdp",pid=1234,fd=7))\n' \
    > "$STUB_STATE/ss.listen"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" start)" || fail "start exited non-zero"
  assert_contains "$out" '"started":true'
  assert_contains "$out" '"ready":true'
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user set-environment XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user start hypr-rdp.service"
  assert_not_contains "$(cat "$STUB_LOG")" "restart hypr-rdp.service"
}

t_start_reports_failure_when_not_listening() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '1' > "$STUB_STATE/systemctl.is-active"
  printf 'hypr-rdp: port busy\n' > "$STUB_STATE/journalctl.out"
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" start 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"ready":false'
  assert_contains "$out" 'port busy'
  assert_contains "$(cat "$STUB_LOG")" "journalctl --user -u hypr-rdp.service -n 20 --no-pager"
}
