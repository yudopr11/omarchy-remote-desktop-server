#!/usr/bin/env bash
# Suite runner:
#   bash tests/run.sh                                        every tests/test-*.sh
#   bash tests/run.sh test-status.sh                         one file
#   bash tests/run.sh test-status.sh t_status_unconfigured   one case
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib.sh
source "$TESTS_DIR/lib.sh"

trap 'if [[ -n ${TEST_TMP:-} && -d ${TEST_TMP:-} ]]; then rm -rf "$TEST_TMP"; fi' EXIT

file_filter="${1:-}"
case_filter="${2:-}"

files=()
if [[ -n $file_filter ]]; then
  files=("$TESTS_DIR/$file_filter")
else
  while IFS= read -r f; do files+=("$f"); done \
    < <(find "$TESTS_DIR" -maxdepth 1 -name 'test-*.sh' -print | sort)
fi

cases=0
for file in "${files[@]}"; do
  if [[ ! -f $file ]]; then printf 'run.sh: no such test file: %s\n' "$file" >&2; exit 2; fi
  printf '== %s\n' "${file##*/}"
  before="$(compgen -A function | grep '^t_' | sort || true)"
  # shellcheck source=/dev/null
  source "$file"
  after="$(compgen -A function | grep '^t_' | sort || true)"
  while IFS= read -r fn; do
    [[ -n $fn ]] || continue
    if [[ -n $case_filter && $fn != "$case_filter" ]]; then continue; fi
    cases=$((cases + 1))
    run_case "$fn" "$fn"
  done < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
done

printf '\n%d case(s), %d failure(s)\n' "$cases" "$FAILURES"
(( FAILURES == 0 ))
