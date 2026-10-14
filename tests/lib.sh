#!/usr/bin/env bash
# Shared harness for the bash test suite.
#
# Each test file defines `t_<name>` case functions; every case calls setup_env
# first. System commands are replaced by the stubs in tests/stubs: setup_env
# links each stub into a per-case bin dir and puts that dir first on PATH, so a
# case can express "command not installed" with `mask_stub <name>`. Stub
# behaviour is driven by files under $STUB_STATE; every stub call is appended to
# $STUB_LOG.
#
# Assertions record a failure and return non-zero instead of aborting, so one
# run reports every broken assertion in a case.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TESTS_DIR")"
SCRIPTS="$ROOT_DIR/scripts"
STUB_DIR="$TESTS_DIR/stubs"
: "${ORIGINAL_PATH:=$PATH}"

FAILURES=0
CASE=""

fail() {
  printf '  FAIL %s: %s\n' "${CASE:-<no case>}" "$*" >&2
  FAILURES=$((FAILURES + 1))
  return 1
}

# setup_env — fresh HOME/XDG tree, per-case stub bin dir, empty stub log.
setup_env() {
  if [[ -n ${TEST_TMP:-} && -d ${TEST_TMP:-} ]]; then rm -rf "$TEST_TMP"; fi
  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-rdp-test.XXXXXX")"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_RUNTIME_DIR="$TEST_TMP/run"
  export STUB_STATE="$TEST_TMP/stub-state"
  export STUB_LOG="$TEST_TMP/stub.log"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" \
           "$STUB_STATE" "$TEST_TMP/bin"
  : > "$STUB_LOG"
  local stub
  for stub in "$STUB_DIR"/*; do
    [[ -f $stub ]] || continue
    ln -sf "$stub" "$TEST_TMP/bin/$(basename "$stub")"
  done
  export PATH="$TEST_TMP/bin:$ORIGINAL_PATH"
}

# mask_stub <name> — make <name> behave as if it were not installed. A PATH
# entry alone cannot hide a command that is also installed system-wide (the
# real /usr/bin/hypr-rdp still answers), so the mask is an executable that
# prints nothing and exits 127, which every caller must treat as "missing".
mask_stub() {
  cat > "$TEST_TMP/bin/$1" <<'MASK'
#!/usr/bin/env bash
printf '%s\n' "([masked])" >> "$STUB_LOG"
exit 127
MASK
  chmod +x "$TEST_TMP/bin/$1"
}

run_case() {
  local name="$1" fn="$2"
  CASE="$name"
  local before=$FAILURES
  "$fn"
  local rc=$?
  if (( FAILURES > before )); then
    printf 'FAIL %s\n' "$name"
    return 1
  fi
  if (( rc != 0 )); then
    printf 'FAIL %s (case exited %d)\n' "$name" "$rc"
    FAILURES=$((FAILURES + 1))
    return 1
  fi
  printf 'PASS %s\n' "$name"
}

assert_eq() {
  if [[ $1 != "$2" ]]; then fail "expected [$1], got [$2]"; return 1; fi
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected to contain [$2], got [$1]"; return 1 ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "expected NOT to contain [$2], got [$1]"; return 1 ;;
    *) ;;
  esac
}

assert_file_absent() {
  if [[ -e $1 ]]; then fail "expected to be absent: $1"; return 1; fi
}
