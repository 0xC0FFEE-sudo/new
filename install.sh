#!/bin/sh
# install.sh - install `new` on macOS. No sudo, idempotent.
set -eu

APP_DIR="$HOME/.local/share/newvm"
BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/newvm"
SRC_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)

say()  { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '  x %s\n' "$*" >&2; exit 1; }

printf '\nnew - installing\n\n'

# ---------------------------------------------------------------- checks ---
[ "$(uname -s)" = "Darwin" ] || die "macOS only (this is a macOS tool)"

if [ "$(uname -m)" != "arm64" ]; then
  warn "this Mac is not Apple Silicon; the toolchain images are arm64-only"
fi

OS_MAJOR=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1 || echo 0)
if [ "$OS_MAJOR" -lt 14 ] 2>/dev/null; then
  die "macOS 14 (Sonoma) or newer is required (found ${OS_MAJOR:-unknown})"
fi

for f in new config.env lib/provision.sh lib/apply.sh lib/session.sh \
         lib/with.sh lib/manifest.sh lib/bashrc tools/apt-core.txt; do
  [ -f "$SRC_DIR/$f" ] || die "missing $f in $SRC_DIR"
done

# shuru is only needed to boot a VM. A warning keeps `new --help` usable without it.
if command -v shuru >/dev/null 2>&1; then
  say "shuru:  $(shuru --version 2>/dev/null || echo 'installed')"
else
  warn "shuru is not installed. Install it with:"
  warn "    brew tap superhq-ai/tap && brew install shuru"
fi

# name collision
if command -v new >/dev/null 2>&1; then
  _p=$(command -v new)
  case "$_p" in
    "$BIN_DIR"/*) : ;;
    *) warn "something else named 'new' is already on PATH at $_p" ;;
  esac
fi

# ---------------------------------------------------------------- install --
say "installing to $APP_DIR"
mkdir -p "$APP_DIR/lib" "$APP_DIR/tools" "$BIN_DIR" "$CFG_DIR" \
         "$APP_DIR/state/logs" "$APP_DIR/state/ckpt" "$APP_DIR/state/payload"

cp "$SRC_DIR/new"            "$APP_DIR/new"
cp "$SRC_DIR/config.env"     "$APP_DIR/config.env"
cp "$SRC_DIR/lib/"*.sh       "$APP_DIR/lib/"
[ -d "$SRC_DIR/tools" ] && cp "$SRC_DIR/tools/"*.txt "$APP_DIR/tools/" 2>/dev/null || true
chmod 755 "$APP_DIR/new" "$APP_DIR/lib/"*.sh
chmod 644 "$APP_DIR/config.env" "$APP_DIR/tools/"*.txt
chmod 700 "$APP_DIR/state" "$APP_DIR/state/payload" 2>/dev/null || true

# user config is only seeded once, never overwritten
for f in config.env secrets.conf; do
  if [ -f "$CFG_DIR/$f" ]; then
    say "$CFG_DIR/$f exists, left alone"
  else
    cp "$SRC_DIR/config.env" "$CFG_DIR/config.env"
    [ "$f" = "secrets.conf" ] || printf '%s\n' "$(cat <<'TPL'
# ~/.config/newvm/secrets.conf
#
# Each line:  NAME_IN_VM=HOST_ENV_VAR@host1,host2
#
# The sandbox gets a placeholder. The proxy substitutes the real value from the
# host environment, and only on requests to the listed hosts. The real key never
# enters the VM and is never written to disk there.
#
# Run `new secrets` to see which of these are set on your host.

# VENDOR_API_KEY=VENDOR_API_KEY@api.vendor.com
TPL
)" > "$CFG_DIR/$f"
    say "seeded $CFG_DIR/$f"
  fi
done
[ -f "$CFG_DIR/secrets.conf" ] || say "seeded $CFG_DIR/config.env"

ln -sf "$APP_DIR/new" "$BIN_DIR/new"

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on your PATH - add this to your ~/.zshrc:"
     warn "    export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

printf '\n  installed.\n\n'
say "try:   new --help"
say "       cd ~/some/project && new"
say "the first run builds a toolchain image (10-30 min, resumable)."
printf '\n'