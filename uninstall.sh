#!/bin/sh
# uninstall.sh - remove everything `new` created. Asks before deleting.
set -eu

APP_DIR="$HOME/.local/share/newvm"
BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/newvm"
CKPT_DIR="$HOME/.local/share/shuru/checkpoints"
YES="${1:-}"

have() { command -v "$1" >/dev/null 2>&1; }

printf '\nuninstalling new\n\n'

printf '  these will be removed:\n'
printf '    %s   (the program, ~130 KB)\n' "$APP_DIR"
printf '    %s   (the launcher symlink)\n' "$BIN_DIR/new"
printf '    %s  (your config)\n' "$CFG_DIR"
printf '\n'
printf '  these are the sandbox images and will be KEPT unless you ask:\n'
for f in "$CKPT_DIR"/newvm-* "$CKPT_DIR"/snap-*; do
  [ -f "$f" ] || continue
  printf '    %s  (%s)\n' "$(basename "$f")" "$(du -h "$f" 2>/dev/null | cut -f1)"
done
printf '\n'

if [ "$YES" != "--yes" ] && [ "$YES" != "-y" ]; then
  printf 'remove the program and config? [y/N] '
  read -r _a
  case "$_a" in
    y|Y|yes|YES) : ;;
    *) printf '  nothing was removed.\n\n'; exit 0 ;;
  esac
fi

rm -f "$BIN_DIR/new"
rm -rf "$APP_DIR"
rm -rf "$CFG_DIR"

if have shuru; then
  if [ "$YES" = "--images" ] || [ "$YES" = "-y" ]; then
    shuru prune >/dev/null 2>&1 || true
    for f in "$CKPT_DIR"/newvm-* "$CKPT_DIR"/snap-*; do
      [ -f "$f" ] || continue
      n=$(basename "$f"); n=${n%.*}
      shuru checkpoint delete "$n" >/dev/null 2>&1 || true
    done
    printf '  sandbox images removed.\n'
  else
    printf '  sandbox images kept. Remove them later with:\n'
    printf '    ./uninstall.sh --images      # deletes newvm*/snap* checkpoints\n'
    printf '    shuru checkpoint list         # to see what is left\n'
  fi
fi

printf '\n  done. shuru itself was not touched.\n\n'