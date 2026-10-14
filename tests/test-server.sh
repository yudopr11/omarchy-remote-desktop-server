#!/usr/bin/env bash
# Contract tests for the unit's ExecStart wrapper (T7).

# The wrapper refuses to run outside a graphical session; everything below runs
# inside one, except the case that checks that refusal.
export WAYLAND_DISPLAY="wayland-test"

conf_dir() { printf '%s' "$XDG_CONFIG_HOME/hypr-rdp"; }
run_dir() { printf '%s' "$XDG_RUNTIME_DIR/hypr-rdp"; }

# argv — the argument list the stub hypr-rdp was exec'd with.
argv() { grep '^hypr-rdp ' "$STUB_LOG" | tail -1; }

configure_all() {
  mkdir -p "$(conf_dir)" "$(run_dir)"
  printf 'cert\n' > "$(conf_dir)/tls.crt"
  printf 'key\n' > "$(conf_dir)/tls.key"
  printf 'secret-password\n' > "$(run_dir)/password"
  chmod 600 "$(run_dir)/password"
}

t_server_argv_exact() {
  setup_env
  configure_all
  write_options 'BIND="0.0.0.0:3389"' 'USERNAME="admin"' 'OPTIONS=(' '  --fps 30' \
    '  --bitrate 8000000' '  --h264-backend auto' '  --max-frames-in-flight 4' ')'
  "$SCRIPTS/omarchy-rdp-server" || fail "server exited non-zero"
  assert_eq "hypr-rdp --bind 0.0.0.0:3389 --cert $(conf_dir)/tls.crt --key $(conf_dir)/tls.key --username admin --password-file $(run_dir)/password --fps 30 --bitrate 8000000 --h264-backend auto --max-frames-in-flight 4" \
    "$(argv)"
}

t_server_username_fallback() {
  setup_env
  configure_all
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' ')'
  "$SCRIPTS/omarchy-rdp-server" || fail "server exited non-zero"
  assert_contains "$(argv)" "--username $(id -un)"
}

t_server_prefers_runtime_password() {
  setup_env
  configure_all
  printf 'stored-password\n' > "$(conf_dir)/password"
  write_options 'BIND="127.0.0.1:3389"'
  "$SCRIPTS/omarchy-rdp-server" || fail "server exited non-zero"
  assert_contains "$(argv)" "--password-file $(run_dir)/password"
}

t_server_falls_back_to_stored_password() {
  setup_env
  configure_all
  rm -f "$(run_dir)/password"
  printf 'stored-password\n' > "$(conf_dir)/password"
  write_options 'BIND="127.0.0.1:3389"'
  "$SCRIPTS/omarchy-rdp-server" || fail "server exited non-zero"
  assert_contains "$(argv)" "--password-file $(conf_dir)/password"
}

t_server_requires_tls() {
  setup_env
  configure_all
  rm -f "$(conf_dir)/tls.key"
  local out
  out="$("$SCRIPTS/omarchy-rdp-server" 2>&1)"
  assert_eq "2" "$?"
  assert_contains "$out" "tls.key"
  assert_not_contains "$(cat "$STUB_LOG")" "hypr-rdp --bind"
}

t_server_requires_password() {
  setup_env
  configure_all
  rm -f "$(run_dir)/password"
  local out
  out="$("$SCRIPTS/omarchy-rdp-server" 2>&1)"
  assert_eq "2" "$?"
  assert_contains "$out" "password"
  assert_not_contains "$(cat "$STUB_LOG")" "hypr-rdp --bind"
}

t_server_password_stays_out_of_argv() {
  setup_env
  configure_all
  write_options 'BIND="127.0.0.1:3389"'
  "$SCRIPTS/omarchy-rdp-server" || fail "server exited non-zero"
  assert_not_contains "$(argv)" "secret-password"
  assert_not_contains "$(cat "$STUB_LOG")" "secret-password"
}

t_server_needs_wayland() {
  setup_env
  configure_all
  write_options 'BIND="127.0.0.1:3389"'
  local out
  out="$(env -u WAYLAND_DISPLAY "$SCRIPTS/omarchy-rdp-server" 2>&1)"
  assert_eq "2" "$?"
  assert_contains "$out" "WAYLAND_DISPLAY"
  assert_not_contains "$(cat "$STUB_LOG")" "hypr-rdp --bind"
}
