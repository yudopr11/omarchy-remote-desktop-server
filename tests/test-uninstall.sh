#!/usr/bin/env bash
# Contract tests for `uninstall.sh` (T10).

HELPERS=(omarchy-rdp-server omarchy-rdp-password omarchy-rdp-status omarchy-rdp-stop omarchy-rdp-config)

# Paths are only meaningful after setup_env repointed HOME (see lib.sh).
case_setup() {
  setup_env
  BIN_DIR="$HOME/.local/bin"
  UNIT_FILE="$XDG_CONFIG_HOME/systemd/user/hypr-rdp.service"
  CONF_DIR="$XDG_CONFIG_HOME/hypr-rdp"
  LEDGER="$XDG_STATE_HOME/omarchy-rdp/installed-files"
  assert_contains "$HOME" "$TEST_TMP"
}

# install_tree — let install.sh place the tree, so uninstall.sh removes exactly
# what the installer recorded (no hand-built fixtures).
install_tree() {
  "$ROOT_DIR/install.sh" --skip-password >/dev/null || fail "install.sh exited non-zero"
}

uninstall_run() {
  "$ROOT_DIR/uninstall.sh" "$@"
}

t_uninstall_removes_managed() {
  case_setup
  install_tree
  local out rc h
  out="$(uninstall_run)"
  rc=$?
  assert_eq "0" "$rc"
  for h in "${HELPERS[@]}"; do assert_file_absent "$BIN_DIR/$h"; done
  assert_file_absent "$UNIT_FILE"
  assert_file_absent "$LEDGER/owner"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user stop hypr-rdp.service"
  assert_contains "$(cat "$STUB_LOG")" "systemctl --user disable hypr-rdp.service"
  assert_contains "$out" '"skipped":[]'
  assert_contains "$out" '"removed":["'
}

t_uninstall_skips_modified_file() {
  case_setup
  install_tree
  printf '# tampered\n' >> "$BIN_DIR/omarchy-rdp-stop"
  local out rc
  out="$(uninstall_run)"
  rc=$?
  assert_eq "3" "$rc"
  [[ -f $BIN_DIR/omarchy-rdp-stop ]] || fail "a modified helper must survive"
  assert_contains "$out" "omarchy-rdp-stop"
  assert_file_absent "$BIN_DIR/omarchy-rdp-server"
  assert_file_absent "$UNIT_FILE"
}

t_uninstall_skips_foreign_marker() {
  case_setup
  install_tree
  printf 'io.github.someone-else\n' > "$LEDGER/owner"
  local out rc
  out="$(uninstall_run)"
  rc=$?
  assert_eq "3" "$rc"
  [[ -f $BIN_DIR/omarchy-rdp-server ]] || fail "nothing may be removed under a foreign marker"
  [[ -f $UNIT_FILE ]] || fail "the unit must survive a foreign marker"
  assert_contains "$out" '"removed":[]'
}

t_uninstall_keep_config_by_default() {
  case_setup
  install_tree
  [[ -f $CONF_DIR/options ]] || fail "install_tree should have created options"
  local rc
  uninstall_run >/dev/null
  rc=$?
  assert_eq "0" "$rc"
  [[ -f $CONF_DIR/options ]] || fail "config must survive without --remove-config"
}

t_uninstall_remove_config() {
  case_setup
  install_tree
  printf 'a-long-enough-password\n' > "$CONF_DIR/password"
  chmod 600 "$CONF_DIR/password"
  local out rc f
  out="$(uninstall_run --remove-config)"
  rc=$?
  assert_eq "0" "$rc"
  for f in options password tls.crt tls.key; do assert_file_absent "$CONF_DIR/$f"; done
}

t_uninstall_remove_package() {
  case_setup
  install_tree
  local out rc
  out="$(uninstall_run --remove-package)"
  rc=$?
  assert_eq "0" "$rc"
  assert_contains "$(cat "$STUB_LOG")" "omarchy-pkg-remove hypr-rdp"
}

t_uninstall_remove_package_fallback() {
  case_setup
  install_tree
  mask_stub omarchy-pkg-remove
  uninstall_run --remove-package >/dev/null || fail "uninstall.sh exited non-zero"
  assert_contains "$(cat "$STUB_LOG")" "pacman -Rns --noconfirm hypr-rdp"
}

t_uninstall_idempotent() {
  case_setup
  install_tree
  uninstall_run >/dev/null || fail "first uninstall.sh exited non-zero"
  local out rc
  out="$(uninstall_run)"
  rc=$?
  assert_eq "0" "$rc"
  assert_contains "$out" '"removed":[]'
}
