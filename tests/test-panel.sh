#!/usr/bin/env bash
# UI contract tests for the panel's power actions.

t_power_actions_follow_server_state() {
  setup_env
  local start_block stop_block forget_block
  start_block="$(grep -B 4 -A 2 -F 'text: root.armed ? "Start"' "$ROOT_DIR/Panel.qml" || true)"
  stop_block="$(grep -B 4 -A 2 -F 'text: "Stop & disarm"' "$ROOT_DIR/Panel.qml" || true)"
  forget_block="$(grep -B 3 -A 2 -F 'text: "Stop & forget password"' "$ROOT_DIR/Panel.qml" || true)"

  assert_contains "$start_block" 'visible: !root.active'
  assert_contains "$stop_block" 'visible: root.active'
  assert_contains "$forget_block" 'visible: root.storedPassword'
}
