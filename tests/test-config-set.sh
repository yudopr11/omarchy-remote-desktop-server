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
