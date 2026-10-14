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
