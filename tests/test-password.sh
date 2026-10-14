#!/usr/bin/env bash
# Contract tests for `omarchy-rdp-password` (T8).

PASSWORD="hunter2hunter2"

t_password_stdin_writes_file() {
  setup_env
  local out
  out="$(printf '%s\n' "$PASSWORD" | "$SCRIPTS/omarchy-rdp-password" --password-stdin)" || fail "password helper exited non-zero"
  assert_contains "$out" '"saved":true'
  assert_eq "$PASSWORD" "$(cat "$XDG_RUNTIME_DIR/hypr-rdp/password")"
  assert_eq "600" "$(stat -c '%a' "$XDG_RUNTIME_DIR/hypr-rdp/password")"
  assert_contains "$out" '"restarted":false'
}

t_password_never_in_argv() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '0' > "$STUB_STATE/systemctl.is-active"
  printf 'LISTEN 0 4096 127.0.0.1:3389 0.0.0.0:* users:(("hypr-rdp",pid=1234,fd=7))\n' > "$STUB_STATE/ss.listen"
  local out
  out="$(printf '%s\n' "$PASSWORD" | "$SCRIPTS/omarchy-rdp-password" --password-stdin)" || fail "password helper exited non-zero"
  assert_not_contains "$out" "$PASSWORD"
  assert_not_contains "$(cat "$STUB_LOG")" "$PASSWORD"
  assert_contains "$out" '"restarted":true'
}

t_password_too_short() {
  setup_env
  local out rc
  out="$(printf 'short\n' | "$SCRIPTS/omarchy-rdp-password" --password-stdin 2>&1)"
  rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" '"error"'
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
  assert_not_contains "$(cat "$STUB_LOG")" "restart"
}

t_password_store_flag() {
  setup_env
  local out
  out="$(printf '%s\n' "$PASSWORD" | "$SCRIPTS/omarchy-rdp-password" --password-stdin --store)" || fail "password helper exited non-zero"
  assert_contains "$out" '"stored":true'
  assert_eq "$PASSWORD" "$(cat "$XDG_CONFIG_HOME/hypr-rdp/password")"
  assert_eq "600" "$(stat -c '%a' "$XDG_CONFIG_HOME/hypr-rdp/password")"
}

t_password_store_follows_existing() {
  setup_env
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp"
  printf 'oldpassword1\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  local out
  out="$(printf '%s\n' "$PASSWORD" | "$SCRIPTS/omarchy-rdp-password" --password-stdin)" || fail "password helper exited non-zero"
  assert_contains "$out" '"stored":true'
  assert_eq "$PASSWORD" "$(cat "$XDG_CONFIG_HOME/hypr-rdp/password")"
}

t_password_restart_when_active() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf '0' > "$STUB_STATE/systemctl.is-active"
  printf 'LISTEN 0 4096 127.0.0.1:3389 0.0.0.0:* users:(("hypr-rdp",pid=1234,fd=7))\n' > "$STUB_STATE/ss.listen"
  local out
  out="$(printf '%s\n' "$PASSWORD" | "$SCRIPTS/omarchy-rdp-password" --password-stdin)" || fail "password helper exited non-zero"
  assert_contains "$out" '"restarted":true'
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user restart hypr-rdp.service"
}

t_password_disarms_on_failure() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp"
  printf 'oldpassword1\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  printf '0' > "$STUB_STATE/systemctl.is-active"
  # no listener -> the restart can never become ready
  local out rc
  out="$(printf '%s\n' "$PASSWORD" | "$SCRIPTS/omarchy-rdp-password" --password-stdin 2>&1)"
  rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" '"ready":false'
  assert_contains "$out" '"journal"'
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
  assert_file_absent "$XDG_CONFIG_HOME/hypr-rdp/password"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user stop hypr-rdp.service"
}

t_password_requires_stdin_flag() {
  setup_env
  local out rc
  out="$("$SCRIPTS/omarchy-rdp-password" </dev/null 2>&1)"
  rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "--password-stdin"
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
}
