#!/usr/bin/env bash
# Contract tests for `omarchy-rdp-config get`.

t_get_defaults() {
  setup_env
  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"bind":"127.0.0.1:3389"'
  assert_contains "$out" '"host":"127.0.0.1"'
  assert_contains "$out" '"port":3389'
  assert_contains "$out" "\"username\":\"$(id -un)\""
  assert_contains "$out" '"output":""'
  assert_contains "$out" '"virtual":true'
  assert_contains "$out" '"autostart":false'
  assert_contains "$out" '"storedPassword":false'
  assert_contains "$out" '"fps":30'
  assert_contains "$out" '"bitrate":8000000'
  assert_contains "$out" '"h264Backend":"auto"'
  assert_contains "$out" '"captureMode":"wlr"'
  assert_contains "$out" '"unknownFlags":[]'
  assert_contains "$out" '"monitors":[]'
  assert_contains "$out" '"addresses":[]'
}

t_get_reads_options() {
  setup_env
  write_options 'BIND="0.0.0.0:13389"' 'USERNAME="admin"' 'OPTIONS=(' \
    '  --fps 45' '  --bitrate 12000000' '  --h264-backend vaapi' \
    '  --capture-mode ext' '  --output DP-3' ')'

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"bind":"0.0.0.0:13389"'
  assert_contains "$out" '"host":"0.0.0.0"'
  assert_contains "$out" '"port":13389'
  assert_contains "$out" '"username":"admin"'
  assert_contains "$out" '"output":"DP-3"'
  assert_contains "$out" '"virtual":false'
  assert_contains "$out" '"fps":45'
  assert_contains "$out" '"bitrate":12000000'
  assert_contains "$out" '"h264Backend":"vaapi"'
  assert_contains "$out" '"captureMode":"ext"'
}

t_get_reads_single_line_options() {
  setup_env
  write_options 'BIND="0.0.0.0:3389"' \
    'OPTIONS=(--fps 60 --bitrate 4000000 --output eDP-1)'

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"fps":60'
  assert_contains "$out" '"bitrate":4000000'
  assert_contains "$out" '"output":"eDP-1"'
  assert_contains "$out" '"virtual":false'
}

t_get_preserves_unknown() {
  setup_env
  write_options 'BIND="127.0.0.1:3389"' 'OPTIONS=(' '  --fps 30' \
    '  --file-transfer-mode both' '  --output eDP-1' ')'

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"unknownFlags":["--file-transfer-mode","both"]'
  assert_contains "$out" '"virtual":false'
}

t_get_monitors_and_addresses() {
  setup_env
  # Real `hyprctl monitors -j` shape: pretty-printed, with nested objects whose
  # own "name" keys must not be mistaken for the monitor's.
  cat > "$STUB_STATE/hyprctl.monitors" <<'JSON'
[{
    "id": 0,
    "name": "eDP-1",
    "description": "Samsung Display Corp. 0x4181",
    "make": "Samsung Display Corp.",
    "model": "0x4181",
    "width": 2880,
    "height": 1800,
    "activeWorkspace": {
        "id": 1,
        "name": "1"
    },
    "specialWorkspace": {
        "id": 0,
        "name": ""
    },
    "reserved": [0, 26, 0, 0],
    "scale": 1.25,
    "focused": true,
    "availableModes": ["2880x1800@90.00Hz","2880x1800@60.00Hz"]
},
{
    "id": 1,
    "name": "DP-3",
    "description": "Dell Inc. DELL U2720Q",
    "make": "Dell Inc.",
    "model": "DELL U2720Q",
    "width": 3840,
    "height": 2160,
    "activeWorkspace": {
        "id": 2,
        "name": "2"
    },
    "focused": false,
    "availableModes": ["3840x2160@60.00Hz"]
}]
JSON
  cat > "$STUB_STATE/ip.addr" <<'IPADDR'
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
2: enp1s0    inet 192.168.1.20/24 brd 192.168.1.255 scope global dynamic enp1s0\       valid_lft 86381sec preferred_lft 86381sec
IPADDR

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"monitors":[{"name":"eDP-1","description":"Samsung Display Corp. 0x4181","width":2880,"height":1800,"focused":true},{"name":"DP-3","description":"Dell Inc. DELL U2720Q","width":3840,"height":2160,"focused":false}]'
  assert_contains "$out" '"addresses":["192.168.1.20"]'
}

t_get_missing_hyprctl() {
  setup_env
  mask_stub hyprctl

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"monitors":[]'
}

t_get_clamps_broken_numbers() {
  setup_env
  write_options 'BIND="not a bind"' 'OPTIONS=(' '  --fps seven' '  --bitrate -5' ')'

  local out
  out="$("$SCRIPTS/omarchy-rdp-config" get)" || fail "get exited non-zero"
  assert_contains "$out" '"fps":30'
  assert_contains "$out" '"bitrate":8000000'
  assert_contains "$out" '"host":"not a bind"'
  assert_contains "$out" '"port":0'
}
