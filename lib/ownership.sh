#!/usr/bin/env bash
# Ownership helpers shared by install.sh and uninstall.sh.
#
# A file counts as ours only when the ledger's owner marker names this plugin,
# its path has no symlink anywhere, and its content either equals the source we
# ship or matches the checksum recorded when we installed it. Anything else is
# treated as somebody else's file and is refused, never overwritten.

# shellcheck disable=SC2034  # read by install.sh / uninstall.sh
OWNERSHIP_PLUGIN_ID="io.github.yudopr11.omarchy-remote-desktop-server"

ownership_dir() {
  printf '%s/omarchy-rdp/installed-files\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

checksum() {
  sha256sum "$1" | cut -d' ' -f1
}

checksum_file() {
  printf '%s/%s.sha256\n' "$(ownership_dir)" "$(basename "$1")"
}

# recorded_checksum <path> — the checksum we wrote at install time, if any.
recorded_checksum() {
  local file
  file="$(checksum_file "$1")"
  [[ -f $file ]] || return 1
  tr -d '[:space:]' < "$file"
}

# ownership_marker — the ledger's owner string, empty when there is no ledger.
ownership_marker() {
  local file
  file="$(ownership_dir)/owner"
  [[ -f $file ]] || return 0
  tr -d '[:space:]' < "$file"
}

has_foreign_marker() {
  local marker
  marker="$(ownership_marker)"
  [[ -n $marker && $marker != "$OWNERSHIP_PLUGIN_ID" ]]
}

# no_symlink_in_path <path> — every existing component from the root down must be
# a real directory (or a real file). `install` follows symlinks without asking;
# we refuse instead, because a symlinked destination can point anywhere.
no_symlink_in_path() {
  local target="$1"
  local walk=""
  local part
  local IFS='/'
  local -a parts=()
  read -r -a parts <<< "${target#/}"
  for part in "${parts[@]}"; do
    [[ -n $part ]] || continue
    walk="$walk/$part"
    if [[ -L $walk ]]; then
      return 1
    fi
  done
  return 0
}

# is_managed_target <path> [source] — 0 when <path> is a file we may replace:
# not a symlink, no symlink in its path, ledger not foreign, and content equal to
# <source> or to the checksum we recorded.
is_managed_target() {
  local target="$1"
  local source="${2:-}"
  if [[ ! -e $target ]]; then
    return 1
  fi
  if [[ -L $target || ! -f $target ]]; then
    return 1
  fi
  no_symlink_in_path "$target" || return 1
  if has_foreign_marker; then
    return 1
  fi
  if [[ -n $source && -f $source ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  local recorded
  recorded="$(recorded_checksum "$target")" || return 1
  [[ -n $recorded && $recorded == "$(checksum "$target")" ]]
}

# record_managed <path> — write the owner marker and the checksum of <path>.
record_managed() {
  local target="$1"
  local dir
  dir="$(ownership_dir)"
  mkdir -p "$dir"
  printf '%s\n' "$OWNERSHIP_PLUGIN_ID" > "$dir/owner"
  chmod 644 "$dir/owner"
  checksum "$target" > "$(checksum_file "$target")"
  chmod 644 "$(checksum_file "$target")"
}

# forget_managed <path> — drop a single checksum record (the marker is handled by
# the caller, which knows when the whole ledger is gone).
forget_managed() {
  rm -f "$(checksum_file "$1")"
}
