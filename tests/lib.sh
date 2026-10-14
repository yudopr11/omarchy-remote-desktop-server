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
# The developer's real HOME, captured before setup_env repoints it. Paths that
# depend on HOME/XDG_* MUST be computed inside a case (after setup_env): a
# variable assigned at file scope keeps the real dotfiles path, and a test that
# writes through it clobbers the machine running the suite (this happened).
: "${ORIGINAL_HOME:=$HOME}"
export ORIGINAL_HOME

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
  warn_real_home_paths
}

# warn_real_home_paths — loud note when a *_DIR / *_FILE / *_HOME / LEDGER
# variable still points into the real home while a case runs. Those are the names
# the install tests use for live destinations (BIN_DIR, CONF_DIR, UNIT_FILE,
# LEDGER); a path captured before setup_env is a write waiting to happen.
# Warning, not failure: an unrelated name could legitimately match.
warn_real_home_paths() {
  local name value
  while IFS= read -r name; do
    case "$name" in
      ROOT_DIR|TESTS_DIR|STUB_DIR|XDG_*|PI_*|TMPDIR) continue ;;
    esac
    case "$name" in
      *_DIR|*_FILE|*_HOME|LEDGER) ;;
      *) continue ;;
    esac
    value="${!name-}"
    case "$value" in
      "$ORIGINAL_HOME"/*) printf 'harness: %s=%s still points into the real home\n' "$name" "$value" >&2 ;;
    esac
  done < <(compgen -v 2>/dev/null || true)
}

# write_options <line>... — write a hypr-rdp options file into the case HOME.
write_options() {
  mkdir -p "$XDG_CONFIG_HOME/hypr-rdp"
  printf '%s\n' "$@" > "$XDG_CONFIG_HOME/hypr-rdp/options"
}

# mask_stub <name> — make <name> behave as if it were not installed. A PATH
# entry alone cannot hide a command that is also installed system-wide (the
# real /usr/bin/hypr-rdp still answers), so the mask is an executable that
# prints nothing and exits 127, which every caller must treat as "missing".
mask_stub() {
  # Drop the stub symlink first: writing through it would rewrite the source
  # stub in tests/stubs and leak the mask into every later case.
  rm -f "$TEST_TMP/bin/$1"
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
