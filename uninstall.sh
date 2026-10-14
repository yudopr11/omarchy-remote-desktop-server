#!/usr/bin/env bash
# uninstall.sh — remove the runtime this plugin installed.
#
# Only files the ledger names as ours are removed: anything missing from the
# ledger, edited since install time, or sitting behind a foreign owner marker is
# reported under "skipped" and left alone. Exit 3 when something was skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ownership.sh
source "$SCRIPT_DIR/lib/ownership.sh"

HELPERS=(omarchy-rdp-server omarchy-rdp-password omarchy-rdp-status omarchy-rdp-stop omarchy-rdp-config)
UNIT_NAME="hypr-rdp.service"
CONFIG_FILES=(options password tls.crt tls.key)

BIN_DIR="$HOME/.local/bin"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
UNIT_DIR="$CONFIG_HOME/systemd/user"
CONF_DIR="$CONFIG_HOME/hypr-rdp"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-rdp"

remove_config=false
remove_package=false

usage() {
  cat >&2 <<'USAGE'
usage: uninstall.sh [--remove-config] [--remove-package]
  --remove-config   also delete ~/.config/hypr-rdp (options, password, TLS)
  --remove-package  also uninstall the hypr-rdp package
USAGE
}

while (( $# )); do
  case "$1" in
    --remove-config) remove_config=true; shift ;;
    --remove-package) remove_package=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'uninstall.sh: unknown option: %s\n' "$1" >&2; usage; exit 1 ;;
  esac
done

json_array() {
  local item out=""
  for item in "$@"; do
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    if [[ -z $out ]]; then out="\"$item\""; else out="$out,\"$item\""; fi
  done
  printf '[%s]' "$out"
}

removed=()
skipped=()

foreign=false
if has_foreign_marker; then
  foreign=true
fi

# remove_target <path> — delete the file when the ledger says it is ours, and
# report it either way. A foreign marker disqualifies every target at once.
remove_target() {
  local target="$1"
  if [[ ! -e $target && ! -L $target ]]; then
    return 0
  fi
  if [[ $foreign == true ]] || ! is_managed_target "$target"; then
    skipped+=("$target")
    return 0
  fi
  rm -f -- "$target"
  forget_managed "$target"
  removed+=("$target")
}

print_result() {
  printf '{"removed":%s,"skipped":%s}\n' \
    "$(json_array "${removed[@]}")" "$(json_array "${skipped[@]}")"
}

# Never leave an unmanaged unit pointing at helpers we just removed. If the
# unit is foreign or modified, keep its whole runtime intact and report it.
unit_present=false
if [[ -e $UNIT_DIR/$UNIT_NAME || -L $UNIT_DIR/$UNIT_NAME ]]; then
  unit_present=true
fi
if [[ $unit_present == true ]] && ! is_managed_target "$UNIT_DIR/$UNIT_NAME"; then
  skipped+=("$UNIT_DIR/$UNIT_NAME")
  for helper in "${HELPERS[@]}"; do
    target="$BIN_DIR/$helper"
    if [[ -e $target || -L $target ]]; then skipped+=("$target"); fi
  done
  if [[ $remove_config == true ]]; then
    for file in "${CONFIG_FILES[@]}"; do
      target="$CONF_DIR/$file"
      if [[ -e $target || -L $target ]]; then skipped+=("$target"); fi
    done
  fi
  printf 'uninstall.sh: keeping runtime because %s is not managed by this plugin\n' "$UNIT_NAME" >&2
  print_result
  exit 3
fi

# Stop and disable before removing the unit. If either fails, nothing is removed.
unit_to_remove=false
if [[ $unit_present == true ]]; then
  if ! systemctl --user stop "$UNIT_NAME"; then
    printf 'uninstall.sh: could not stop %s; nothing was removed\n' "$UNIT_NAME" >&2
    exit 1
  fi
  if ! systemctl --user disable "$UNIT_NAME"; then
    printf 'uninstall.sh: could not disable %s; nothing was removed\n' "$UNIT_NAME" >&2
    exit 1
  fi
  unit_to_remove=true
fi

remove_target "$UNIT_DIR/$UNIT_NAME"
if [[ $unit_to_remove == true ]]; then
  if [[ -e $UNIT_DIR/$UNIT_NAME || -L $UNIT_DIR/$UNIT_NAME ]]; then
    # It changed after the preflight. Retain helpers rather than orphaning it.
    for helper in "${HELPERS[@]}"; do
      target="$BIN_DIR/$helper"
      if [[ -e $target || -L $target ]]; then skipped+=("$target"); fi
    done
    print_result
    exit 3
  fi
  if ! systemctl --user daemon-reload; then
    printf 'uninstall.sh: could not reload the user systemd manager after removing %s; helpers were kept\n' "$UNIT_NAME" >&2
    exit 1
  fi
fi

for helper in "${HELPERS[@]}"; do
  remove_target "$BIN_DIR/$helper"
done

if [[ $foreign == false && -f $(ownership_dir)/owner ]]; then
  rm -f "$(ownership_dir)/owner"
fi

if [[ $remove_config == true ]]; then
  for file in "${CONFIG_FILES[@]}"; do
    if [[ -f $CONF_DIR/$file ]]; then
      rm -f -- "$CONF_DIR/$file"
      removed+=("$CONF_DIR/$file")
    fi
  done
fi

# Only prune directories that are now empty: a skipped file keeps its parent.
rmdir "$CONF_DIR" 2>/dev/null || true
rmdir "$(ownership_dir)" 2>/dev/null || true
rmdir "$STATE_DIR" 2>/dev/null || true

# remove_package_now — prefer Omarchy's remover, fall back to pacman. Exit 127
# from the wrapper (and from the test stubs) means "not really installed here";
# any other non-zero status is the remover's own answer and we stop there.
remove_package_now() {
  if command -v omarchy-pkg-remove >/dev/null 2>&1; then
    local status=0
    omarchy-pkg-remove hypr-rdp || status=$?
    if (( status == 0 )); then
      return 0
    fi
    (( status == 127 )) || exit "$status"
  fi
  pacman -Rns --noconfirm hypr-rdp
}

if [[ $remove_package == true ]]; then
  remove_package_now
fi

print_result

if (( ${#skipped[@]} > 0 )); then
  exit 3
fi
