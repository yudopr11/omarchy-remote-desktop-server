#!/usr/bin/env bash
# Contract tests for `install.sh` (T9).

PLUGIN_ID="io.github.yudopr11.omarchy-remote-desktop-server"
PASSWORD="installsecret12"

# BIN_DIR and friends are only meaningful after setup_env repointed HOME; a
# top-level assignment would hold the developer's real dotfiles path.
case_setup() {
  setup_env
  BIN_DIR="$HOME/.local/bin"
  UNIT_FILE="$XDG_CONFIG_HOME/systemd/user/hypr-rdp.service"
  CONF_DIR="$XDG_CONFIG_HOME/hypr-rdp"
  LEDGER="$XDG_STATE_HOME/omarchy-rdp/installed-files"
  assert_contains "$HOME" "$TEST_TMP"
}

# install.sh runs the password helper by name (PATH first, then the just-installed
# copy), so cases replace it here instead of typing into a terminal.
stub_password_helper() {
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/omarchy-rdp-password" <<EOF
#!/usr/bin/env bash
printf 'omarchy-rdp-password %s\n' "\$*" >> "\$STUB_LOG"
mkdir -p "\$XDG_RUNTIME_DIR/hypr-rdp"
printf '%s\n' "$PASSWORD" > "\$XDG_RUNTIME_DIR/hypr-rdp/password"
exit 0
EOF
  chmod 755 "$TEST_TMP/bin/omarchy-rdp-password"
}

install_run() {
  "$ROOT_DIR/install.sh" "$@"
}

t_install_clean_tree() {
  case_setup
  stub_password_helper
  local out
  out="$(install_run)" || fail "install.sh exited non-zero"
  local h
  for h in omarchy-rdp-server omarchy-rdp-password omarchy-rdp-status omarchy-rdp-stop omarchy-rdp-config; do
    [[ -f $BIN_DIR/$h ]] || fail "missing helper: $h"
    assert_eq "755" "$(stat -c '%a' "$BIN_DIR/$h")"
  done
  [[ -f $UNIT_FILE ]] || fail "missing unit file"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user set-environment XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user daemon-reload"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user enable --now hypr-rdp.service"
  assert_eq "$PLUGIN_ID" "$(cat "$LEDGER/owner")"
  assert_eq "600" "$(stat -c '%a' "$CONF_DIR/options")"
  diff -q "$CONF_DIR/options" "$ROOT_DIR/config/options" >/dev/null || fail "fresh options must equal the shipped defaults"
  assert_contains "$(cat "$STUB_LOG")" "omarchy-rdp-password --store"
  assert_contains "$out" '"password":true'
}

t_install_preserves_options() {
  case_setup
  stub_password_helper
  mkdir -p "$CONF_DIR"
  printf 'BIND="0.0.0.0:13389"\n\nOPTIONS=(\n  --fps 45\n)\n' > "$CONF_DIR/options"
  local before after
  before="$(sha256sum "$CONF_DIR/options" | cut -d' ' -f1)"
  install_run >/dev/null || fail "install.sh exited non-zero"
  after="$(sha256sum "$CONF_DIR/options" | cut -d' ' -f1)"
  assert_eq "$before" "$after"
  assert_contains "$(cat "$CONF_DIR/options")" "--fps 45"
}

t_install_bind_flag_touches_bind_only() {
  case_setup
  stub_password_helper
  mkdir -p "$CONF_DIR"
  printf 'BIND="0.0.0.0:13389"\n\nOPTIONS=(\n  --fps 45\n)\n' > "$CONF_DIR/options"
  install_run --bind lan >/dev/null || fail "install.sh exited non-zero"
  assert_contains "$(cat "$CONF_DIR/options")" 'BIND="0.0.0.0:13389"'
  assert_contains "$(cat "$CONF_DIR/options")" "--fps 45"
  install_run --bind localhost >/dev/null || fail "install.sh --bind localhost exited non-zero"
  assert_contains "$(cat "$CONF_DIR/options")" 'BIND="127.0.0.1:13389"'
}

t_install_creates_tls_once() {
  case_setup
  stub_password_helper
  install_run >/dev/null || fail "install.sh exited non-zero"
  [[ -f $CONF_DIR/tls.crt && -f $CONF_DIR/tls.key ]] || fail "tls identity not created"
  assert_eq "600" "$(stat -c '%a' "$CONF_DIR/tls.crt")"
  assert_eq "600" "$(stat -c '%a' "$CONF_DIR/tls.key")"
  local before after
  before="$(sha256sum "$CONF_DIR/tls.crt" "$CONF_DIR/tls.key" | sha256sum)"
  install_run >/dev/null || fail "second install.sh exited non-zero"
  after="$(sha256sum "$CONF_DIR/tls.crt" "$CONF_DIR/tls.key" | sha256sum)"
  assert_eq "$before" "$after"
}

t_install_works_without_xdg_runtime_dir() {
  case_setup
  local out
  out="$(env -u XDG_RUNTIME_DIR "$ROOT_DIR/install.sh" --skip-password)" \
    || fail "install.sh should work without XDG_RUNTIME_DIR"
  assert_contains "$out" '"installed":'
  assert_file_absent "$XDG_RUNTIME_DIR/hypr-rdp/password"
}

t_install_skip_password() {
  case_setup
  local out
  out="$(install_run --skip-password)" || fail "install.sh exited non-zero"
  assert_not_contains "$(cat "$STUB_LOG")" "omarchy-rdp-password"
  assert_contains "$out" '"password":false'
}

t_install_refuses_symlinked_target() {
  case_setup
  mkdir -p "$BIN_DIR"
  ln -s /tmp/not-a-real-helper "$BIN_DIR/omarchy-rdp-stop"
  local out rc
  out="$(install_run 2>&1)"
  rc=$?
  assert_eq "3" "$rc"
  assert_contains "$out" "omarchy-rdp-stop"
  if [[ -f $UNIT_FILE ]]; then fail "nothing may be installed when the pre-flight refuses"; fi
  assert_not_contains "$(cat "$STUB_LOG")" "daemon-reload"
}

t_install_refuses_symlinked_parent_for_missing_target() {
  case_setup
  local outside="$TEST_TMP/outside-bin"
  mkdir -p "$HOME/.local" "$outside"
  ln -s "$outside" "$BIN_DIR"

  local out rc
  out="$(install_run --skip-password 2>&1)"
  rc=$?
  assert_eq "3" "$rc"
  assert_contains "$out" "symlinked path"
  assert_file_absent "$outside/omarchy-rdp-server"
  assert_not_contains "$(cat "$STUB_LOG")" "omarchy-pkg-add"
}

t_install_refuses_foreign_marker() {
  case_setup
  mkdir -p "$LEDGER"
  printf 'io.github.someone-else\n' > "$LEDGER/owner"
  local out rc
  out="$(install_run 2>&1)"
  rc=$?
  assert_eq "3" "$rc"
  assert_contains "$out" "io.github.someone-else"
  if [[ -f $UNIT_FILE ]]; then fail "nothing may be installed when the marker is foreign"; fi
}

t_install_refuses_modified_managed_file() {
  case_setup
  stub_password_helper
  install_run >/dev/null || fail "first install.sh exited non-zero"
  printf '# tampered\n' >> "$BIN_DIR/omarchy-rdp-status"
  local out rc
  out="$(install_run 2>&1)"
  rc=$?
  assert_eq "3" "$rc"
  assert_contains "$out" "omarchy-rdp-status"
}

t_install_refuses_partial_tls_identity() {
  case_setup
  mkdir -p "$CONF_DIR"
  printf 'existing-certificate\n' > "$CONF_DIR/tls.crt"

  local out rc
  out="$(install_run --skip-password 2>&1)"
  rc=$?
  assert_eq "3" "$rc"
  assert_contains "$out" "incomplete TLS identity"
  assert_eq "existing-certificate" "$(cat "$CONF_DIR/tls.crt")"
  assert_file_absent "$CONF_DIR/tls.key"
  assert_file_absent "$BIN_DIR/omarchy-rdp-server"
  assert_not_contains "$(cat "$STUB_LOG")" "omarchy-pkg-add"
}

t_install_idempotent() {
  case_setup
  stub_password_helper
  install_run >/dev/null || fail "first install.sh exited non-zero"
  local options_before ledger_before
  options_before="$(sha256sum "$CONF_DIR/options" | cut -d' ' -f1)"
  ledger_before="$(find "$LEDGER" -maxdepth 1 -printf '%f\n' | sort)"
  install_run >/dev/null || fail "second install.sh exited non-zero"
  assert_eq "$options_before" "$(sha256sum "$CONF_DIR/options" | cut -d' ' -f1)"
  assert_eq "$ledger_before" "$(find "$LEDGER" -maxdepth 1 -printf '%f\n' | sort)"
  assert_eq "2" "$(grep -c 'enable --now hypr-rdp.service' "$STUB_LOG")"
}

t_install_no_password_in_log() {
  case_setup
  stub_password_helper
  install_run >/dev/null || fail "install.sh exited non-zero"
  assert_eq "$PASSWORD" "$(cat "$XDG_RUNTIME_DIR/hypr-rdp/password")"
  assert_not_contains "$(cat "$STUB_LOG")" "$PASSWORD"
}

# The engine package is the one thing install.sh cannot copy into place: it comes
# from the AUR through omarchy-pkg-add. Absence is expressed the same way status
# does it, by the run probe failing.
t_install_installs_missing_package() {
  case_setup
  stub_password_helper
  install_run --skip-password >/dev/null || fail "install.sh exited non-zero"
  assert_contains "$(cat "$STUB_LOG")" "omarchy-pkg-add hypr-rdp"
}

t_install_skips_package_when_present() {
  case_setup
  stub_password_helper
  printf 'hypr-rdp 0.1.6\n' > "$STUB_STATE/hypr-rdp.version"
  install_run --skip-password >/dev/null || fail "install.sh exited non-zero"
  assert_not_contains "$(cat "$STUB_LOG")" "omarchy-pkg-add"
}

t_install_stops_when_package_install_fails() {
  case_setup
  stub_password_helper
  printf '1\n' > "$STUB_STATE/omarchy-pkg-add.exit"
  if install_run --skip-password >/dev/null 2>&1; then
    fail "install.sh should fail when the package cannot be installed"
  fi
  assert_file_absent "$BIN_DIR/omarchy-rdp-server"
  assert_file_absent "$UNIT_FILE"
}

# A machine that is already armed keeps its password: the panel's Install button
# is then only about the missing pieces, so no second prompt.
t_install_skips_password_when_armed() {
  case_setup
  mkdir -p "$TEST_TMP/bin" "$XDG_RUNTIME_DIR/hypr-rdp"
  cat > "$TEST_TMP/bin/omarchy-rdp-password" <<'EOF'
#!/usr/bin/env bash
printf 'omarchy-rdp-password %s\n' "$*" >> "$STUB_LOG"
exit 9
EOF
  chmod 755 "$TEST_TMP/bin/omarchy-rdp-password"
  printf 'existingpassword\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  install_run >/dev/null || fail "install.sh exited non-zero"
  assert_not_contains "$(cat "$STUB_LOG")" "omarchy-rdp-password"
  assert_eq "existingpassword" "$(cat "$XDG_RUNTIME_DIR/hypr-rdp/password")"
}
