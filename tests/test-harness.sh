#!/usr/bin/env bash
# Tests for the harness itself: a mask must not leak into the source stub.

t_mask_stub_isolates_source() {
  setup_env
  local before after
  before="$(sha256sum "$STUB_DIR/hyprctl" | cut -d' ' -f1)"

  mask_stub hyprctl

  after="$(sha256sum "$STUB_DIR/hyprctl" | cut -d' ' -f1)"
  assert_eq "$before" "$after"
  local rc=0
  "$TEST_TMP/bin/hyprctl" monitors -j >/dev/null 2>&1 || rc=$?
  assert_eq "127" "$rc"
}

t_stub_log_records_calls() {
  setup_env
  hyprctl monitors -j >/dev/null 2>&1
  assert_contains "$(cat "$STUB_LOG")" "hyprctl monitors -j"
}
