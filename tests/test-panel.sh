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

t_power_actions_share_a_row() {
  setup_env
  local power_row
  power_row="$(awk '
    /PanelSectionHeader \{ text: "POWER"/ { in_power = 1 }
    in_power && /Row \{/ { in_row = 1; depth = 1; print; next }
    in_row {
      print
      line = $0
      depth += gsub(/\{/, "", line) - gsub(/\}/, "", line)
      if (depth == 0) exit
    }
  ' "$ROOT_DIR/Panel.qml")"

  assert_contains "$power_row" 'text: root.armed ? "Start"'
  assert_contains "$power_row" 'text: "Stop & disarm"'
  assert_contains "$power_row" 'text: "Stop & forget password"'
}

t_bar_icon_is_smaller_and_centered() {
  setup_env
  local mark_size horizontal_offset
  mark_size="$(grep -F 'readonly property real markSize:' "$ROOT_DIR/BarWidget.qml" || true)"
  horizontal_offset="$(grep -F 'anchors.horizontalCenterOffset:' "$ROOT_DIR/BarWidget.qml" || true)"

  assert_contains "$mark_size" '* 0.56'
  [[ -z "$horizontal_offset" ]] || return 1
  assert_contains "$(grep -F 'readonly property real openPanelIndicatorWidth:' "$ROOT_DIR/BarWidget.qml")" 'markSize'
  assert_contains "$(grep -F 'hasVisualContent:' "$ROOT_DIR/BarWidget.qml" || true)" 'true'
}

t_bar_icon_highlights_active_server() {
  setup_env
  local server_active mark_color active_opacity active_probe
  server_active="$(grep -F 'property bool serverActive:' "$ROOT_DIR/BarWidget.qml" || true)"
  mark_color="$(grep -F 'readonly property color markColor:' "$ROOT_DIR/BarWidget.qml" || true)"
  active_opacity="$(grep -F 'opacity: root.serverActive ? 1.0 : 0.45' "$ROOT_DIR/BarWidget.qml" || true)"
  active_probe="$(grep -F 'command: ["systemctl", "--user", "is-active", "hypr-rdp.service"]' "$ROOT_DIR/BarWidget.qml" || true)"

  assert_contains "$server_active" 'serverActive'
  assert_contains "$mark_color" 'root.bar ? root.bar.barForeground : Color.foreground'
  assert_contains "$active_opacity" 'serverActive ? 1.0 : 0.45'
  assert_contains "$active_probe" 'hypr-rdp.service'
}
