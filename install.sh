#!/usr/bin/env bash
# install.sh — install the Remote Desktop runtime the panel drives.
#
# Copies the helpers, the unit and (on a fresh machine) the default options into
# their live locations, mints a TLS identity when there is none, enables the unit
# and finally asks for the RDP password. Every file it owns is recorded in a
# ledger; a modified or foreign file refuses the whole run (exit 3) instead of
# being overwritten, and that check happens before anything is touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ownership.sh
source "$SCRIPT_DIR/lib/ownership.sh"

HELPERS=(omarchy-rdp-server omarchy-rdp-password omarchy-rdp-status omarchy-rdp-stop omarchy-rdp-config)
UNIT_NAME="hypr-rdp.service"
DEFAULT_PORT=3389

BIN_DIR="$HOME/.local/bin"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
UNIT_DIR="$CONFIG_HOME/systemd/user"
CONF_DIR="$CONFIG_HOME/hypr-rdp"

bind_mode=""
skip_password=false

usage() {
  cat >&2 <<'USAGE'
usage: install.sh [--bind lan|localhost] [--skip-password]
  --bind lan|localhost  rewrite BIND= in an existing options file (port is kept)
  --skip-password       do not ask for the RDP password (runtime update)
USAGE
}

usage_error() {
  printf 'install.sh: %s\n' "$1" >&2
  usage
  exit 1
}

refuse() {
  printf 'install.sh: refusing to touch %s\n' "$1" >&2
  exit 3
}

json_array() {
  local item out=""
  for item in "$@"; do
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    if [[ -z $out ]]; then out="\"$item\""; else out="$out,\"$item\""; fi
  done
  printf '[%s]' "$out"
}

while (( $# )); do
  case "$1" in
    --bind)
      [[ $# -ge 2 ]] || usage_error "--bind needs lan or localhost"
      bind_mode="$2"
      shift 2
      ;;
    --bind=*) bind_mode="${1#--bind=}"; shift ;;
    --skip-password) skip_password=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error "unknown option: $1" ;;
  esac
done
if [[ -n $bind_mode && $bind_mode != lan && $bind_mode != localhost ]]; then
  usage_error "--bind must be lan or localhost"
fi

# The ledger's owner marker names the plugin these files belong to. A different
# marker means another install (or another plugin) put files here; nothing is
# written and the run stops before the first copy.
if has_foreign_marker; then
  refuse "$(ownership_dir)/owner (foreign marker: $(ownership_marker))"
fi

# Pre-flight: decide about every destination before writing anything, so a
# refusal leaves the machine exactly as it was.
check_target() {
  local target="$1" source="$2"
  if [[ ! -e $target && ! -L $target ]]; then
    return 0
  fi
  if [[ -L $target ]]; then
    refuse "$target (symlink)"
  fi
  if [[ ! -f $target ]]; then
    refuse "$target (not a regular file)"
  fi
  if ! no_symlink_in_path "$target"; then
    refuse "$target (symlinked path)"
  fi
  if ! is_managed_target "$target" "$source"; then
    refuse "$target (modified since it was installed)"
  fi
}

for helper in "${HELPERS[@]}"; do
  check_target "$BIN_DIR/$helper" "$SCRIPT_DIR/scripts/$helper"
done
check_target "$UNIT_DIR/$UNIT_NAME" "$SCRIPT_DIR/systemd/$UNIT_NAME"

# The engine itself comes from the AUR. Install it before anything is written, so
# a package step that fails leaves the machine as it was. The probe is the same
# run probe `omarchy-rdp-status` uses, so a test stub can stand in for absence.
if ! hypr-rdp --version >/dev/null 2>&1; then
  if ! omarchy-pkg-add hypr-rdp; then
    printf 'install.sh: hypr-rdp is missing and omarchy-pkg-add failed\n' >&2
    exit 1
  fi
fi

# --bind rewrites the host of an existing options file and keeps its port; the
# panel's `set bind` is the precise tool, this flag is the first-run shortcut.
update_bind() {
  local file="$1" mode="$2" host port current candidate
  case "$mode" in
    lan) host="0.0.0.0" ;;
    localhost) host="127.0.0.1" ;;
  esac
  port="$DEFAULT_PORT"
  current="$(sed -n 's/^BIND="\(.*\)"$/\1/p' "$file" | head -1)"
  if [[ $current == *:* ]]; then
    candidate="${current##*:}"
    if [[ $candidate =~ ^[0-9]+$ ]] && (( candidate >= 1 && candidate <= 65535 )); then
      port="$candidate"
    fi
  fi
  if grep -q '^BIND=' "$file"; then
    sed -i "s|^BIND=.*|BIND=\"$host:$port\"|" "$file"
  else
    printf 'BIND="%s:%s"\n' "$host" "$port" >> "$file"
  fi
}

installed=()

mkdir -p "$BIN_DIR" "$UNIT_DIR" "$(ownership_dir)"

for helper in "${HELPERS[@]}"; do
  install -m 0755 "$SCRIPT_DIR/scripts/$helper" "$BIN_DIR/$helper"
  record_managed "$BIN_DIR/$helper"
  installed+=("$BIN_DIR/$helper")
done

install -m 0644 "$SCRIPT_DIR/systemd/$UNIT_NAME" "$UNIT_DIR/$UNIT_NAME"
record_managed "$UNIT_DIR/$UNIT_NAME"
installed+=("$UNIT_DIR/$UNIT_NAME")

options_created=false
if [[ ! -f $CONF_DIR/options ]]; then
  mkdir -p "$CONF_DIR"
  install -m 0600 "$SCRIPT_DIR/config/options" "$CONF_DIR/options"
  options_created=true
elif [[ -n $bind_mode ]]; then
  update_bind "$CONF_DIR/options" "$bind_mode"
fi

# TLS identity: created once, never replaced (clients remember the fingerprint).
tls_created=false
if [[ ! -f $CONF_DIR/tls.crt || ! -f $CONF_DIR/tls.key ]]; then
  mkdir -p "$CONF_DIR"
  tls_host="$(hostname -f 2>/dev/null || true)"
  [[ -n $tls_host ]] || tls_host="$(uname -n)"
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
    -subj "/CN=$tls_host" \
    -keyout "$CONF_DIR/tls.key" -out "$CONF_DIR/tls.crt" >/dev/null 2>&1
  chmod 600 "$CONF_DIR/tls.key" "$CONF_DIR/tls.crt"
  tls_created=true
fi

systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"

# The helper is looked up on PATH first, so the same script that was just
# installed normally handles this (and a test or an alternative install can
# substitute it); only then fall back to the copy we placed. A machine that is
# already armed is not asked again — the panel's Install action is then purely
# "add what is missing".
password_ok=false
armed=false
if [[ -s $XDG_RUNTIME_DIR/hypr-rdp/password || -s $CONF_DIR/password ]]; then
  armed=true
fi
if [[ $skip_password == false && $armed == false ]]; then
  password_helper=""
  if command -v omarchy-rdp-password >/dev/null 2>&1; then
    password_helper="$(command -v omarchy-rdp-password)"
  elif [[ -x $BIN_DIR/omarchy-rdp-password ]]; then
    password_helper="$BIN_DIR/omarchy-rdp-password"
  fi
  if [[ -n $password_helper ]]; then
    if "$password_helper" --store; then
      password_ok=true
    else
      printf 'install.sh: password not set; run omarchy-rdp-password --store\n' >&2
    fi
  fi
fi

printf '{"installed":%s,"optionsCreated":%s,"tlsCreated":%s,"password":%s}\n' \
  "$(json_array "${installed[@]}")" "$options_created" "$tls_created" "$password_ok"
