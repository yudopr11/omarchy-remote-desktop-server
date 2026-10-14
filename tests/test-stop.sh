#!/usr/bin/env bash
# Contract tests for `omarchy-rdp-stop` (T7).

t_stop_active() {
  setup_env
  mkdir -p "$XDG_RUNTIME_DIR/hypr-rdp"
  printf 'pw\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  printf '0' > "$STUB_STATE/systemctl.is-active"
  local out
  out="$("$SCRIPTS/omarchy-rdp-stop")" || fail "stop exited non-zero"
  assert_contains "$out" '"stopped":true'
  assert_contains "$out" '"armed":false'
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user stop hypr-rdp.service"
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
}

t_stop_idempotent() {
  setup_env
  local out
  out="$("$SCRIPTS/omarchy-rdp-stop")" || fail "stop exited non-zero"
  assert_contains "$out" '"stopped":true'
  assert_contains "$out" '"armed":false'
}

t_stop_keeps_autostart_when_enabled() {
  setup_env
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp" "$XDG_RUNTIME_DIR/hypr-rdp"
  printf 'pw\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  printf 'pw\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  printf 'enabled' > "$STUB_STATE/systemctl.is-enabled"
  local out
  out="$("$SCRIPTS/omarchy-rdp-stop")" || fail "stop exited non-zero"
  assert_contains "$out" '"autostart":true'
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
  assert_eq "pw" "$(cat "$XDG_CONFIG_HOME/hypr-rdp/password")"
}

t_stop_forget() {
  setup_env
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp" "$XDG_RUNTIME_DIR/hypr-rdp"
  printf 'pw\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  printf 'pw\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  printf 'enabled' > "$STUB_STATE/systemctl.is-enabled"
  local out
  out="$("$SCRIPTS/omarchy-rdp-stop" --forget)" || fail "stop exited non-zero"
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
  assert_file_absent "$XDG_CONFIG_HOME/hypr-rdp/password"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user disable hypr-rdp.service"
  assert_contains "$out" '"autostart":false'
}

t_stop_rejects_unknown_option() {
  setup_env
  local out
  out="$("$SCRIPTS/omarchy-rdp-stop" --now 2>&1)"
  assert_eq "1" "$?"
  assert_contains "$out" '"error"'
  assert_not_contains "$(cat "$STUB_LOG")" "stop"
}
