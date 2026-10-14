#!/usr/bin/env bash
# Verify the unit's password conditions using systemd's own condition evaluator.

t_unit_starts_with_either_nonempty_password() {
  if ! command -v systemd-analyze >/dev/null 2>&1; then
    fail "systemd-analyze is required to verify unit conditions"
    return 1
  fi

  systemd-analyze verify "$ROOT_DIR/systemd/hypr-rdp.service" >/dev/null 2>&1 \
    || fail "systemd-analyze rejected the unit file"

  setup_env
  local -a conditions=()
  local line
  while IFS= read -r line; do
    line="${line//%t/$XDG_RUNTIME_DIR}"
    line="${line//%E/$XDG_CONFIG_HOME}"
    line="${line//%h/$HOME}"
    conditions+=("$line")
  done < <(grep -E '^Condition(PathExists|FileNotEmpty)=' "$ROOT_DIR/systemd/hypr-rdp.service")
  assert_eq "2" "${#conditions[@]}"
  assert_contains "${conditions[*]}" "$XDG_CONFIG_HOME/hypr-rdp/password"

  mkdir -p "$XDG_RUNTIME_DIR/hypr-rdp" "$XDG_CONFIG_HOME/hypr-rdp"
  printf 'runtime-secret\n' > "$XDG_RUNTIME_DIR/hypr-rdp/password"
  systemd-analyze condition "${conditions[@]}" >/dev/null 2>&1 \
    || fail "a nonempty runtime password must satisfy the unit conditions"

  rm -f "$XDG_RUNTIME_DIR/hypr-rdp/password"
  printf 'stored-secret\n' > "$XDG_CONFIG_HOME/hypr-rdp/password"
  systemd-analyze condition "${conditions[@]}" >/dev/null 2>&1 \
    || fail "a nonempty stored password must satisfy the unit conditions"

  : > "$XDG_CONFIG_HOME/hypr-rdp/password"
  if systemd-analyze condition "${conditions[@]}" >/dev/null 2>&1; then
    fail "an empty password file must not satisfy the unit conditions"
  fi
}
