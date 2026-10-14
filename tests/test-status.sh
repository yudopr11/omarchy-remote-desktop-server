#!/usr/bin/env bash
# Contract tests for scripts/omarchy-rdp-status.

t_status_unconfigured() {
  setup_env
  mask_stub hypr-rdp
  local out
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"installed":false'
  assert_contains "$out" '"configured":false'
  assert_contains "$out" '"armed":false'
  assert_contains "$out" '"active":false'
  assert_contains "$out" '"listening":false'
  assert_contains "$out" '"runtimeInstalled":false'
}

t_status_configured_lan() {
  setup_env
  write_options 'BIND="0.0.0.0:3389"' 'USERNAME="yudopr"' 'OPTIONS=(' '  --fps 30' '  --bitrate 8000000' ')'
  printf '1.1.1.1 via 192.168.1.1 dev wlan0 src 192.168.1.20\n' > "$STUB_STATE/ip.addr"
  printf 'LISTEN 0 4096 0.0.0.0:3389 0.0.0.0:*\n' > "$STUB_STATE/ss.listen"
  printf '0' > "$STUB_STATE/systemctl.is-active"
  printf 'enabled' > "$STUB_STATE/systemctl.is-enabled"
  printf 'unit\n' > "$STUB_STATE/systemctl.cat"

  local out
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"configured":true'
  assert_contains "$out" '"active":true'
  assert_contains "$out" '"serviceKnown":true'
  assert_contains "$out" '"listening":true'
  assert_contains "$out" '"bind":"0.0.0.0:3389"'
  assert_contains "$out" '"endpoint":"192.168.1.20:3389"'
  assert_contains "$out" '"host":"0.0.0.0"'
  assert_contains "$out" '"port":3389'
  assert_contains "$out" '"username":"yudopr"'
  assert_contains "$out" '"virtual":true'
  assert_contains "$out" '"autostart":true'
}

t_status_loopback_endpoint() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'

  local out
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"endpoint":"127.0.0.1:3389"'
  assert_contains "$out" '"host":"127.0.0.1"'
  assert_contains "$out" '"port":3389'
}

t_status_foreign_listener() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  printf 'LISTEN 0 4096 127.0.0.1:3389 0.0.0.0:*\n' > "$STUB_STATE/ss.listen"
  printf '1' > "$STUB_STATE/systemctl.is-active"
  printf 'unit\n' > "$STUB_STATE/systemctl.cat"

  local out
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"listening":true'
  assert_contains "$out" '"active":false'
  assert_contains "$out" '"serviceKnown":true'
}

t_status_unknown_service() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"'
  # No $STUB_STATE/systemctl.cat: `systemctl --user cat` fails like a machine
  # where the unit was never installed.
  local out
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"serviceKnown":false'
  assert_contains "$out" '"active":false'
}

t_status_runtime_stale() {
  setup_env
  local bundle="$TEST_TMP/bundle"
  local unit_dir="$XDG_CONFIG_HOME/systemd/user"
  mkdir -p "$bundle/scripts" "$bundle/systemd" "$HOME/.local/bin" "$unit_dir"

  local helper
  for helper in omarchy-rdp-server omarchy-rdp-password omarchy-rdp-status \
                omarchy-rdp-stop omarchy-rdp-config; do
    printf '#!/usr/bin/env bash\ntrue\n' > "$bundle/scripts/$helper"
    cp "$bundle/scripts/$helper" "$HOME/.local/bin/$helper"
  done
  printf 'unit\n' > "$bundle/systemd/hypr-rdp.service"
  cp "$bundle/systemd/hypr-rdp.service" "$unit_dir/hypr-rdp.service"

  local out
  out="$(OMARCHY_RDP_PLUGIN_DIR="$bundle" "$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"runtimeInstalled":true'
  assert_contains "$out" '"runtimeStale":false'

  printf '# drifted\n' >> "$HOME/.local/bin/omarchy-rdp-server"
  out="$(OMARCHY_RDP_PLUGIN_DIR="$bundle" "$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"runtimeInstalled":true'
  assert_contains "$out" '"runtimeStale":true'
}

t_status_password_presence() {
  setup_env
  mkdir -p "$XDG_RUNTIME_DIR/hypr-rdp" "$XDG_CONFIG_HOME/hypr-rdp"
  printf 'secret\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"

  local out
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"armed":true'
  assert_contains "$out" '"storedPassword":false'

  printf 'secret\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  out="$("$SCRIPTS/omarchy-rdp-status")" || fail "status exited non-zero"
  assert_contains "$out" '"storedPassword":true'
}
