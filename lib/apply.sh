#!/usr/bin/env bash
# apply.sh - runs inside the shuru microVM with the host payload on disk.
#
#   apply.sh <checkpoint-name> apply [stage]
#     apply  : install the session runner, the on-demand tool scripts, the
#              host credentials and the marker files. Idempotent, ~1s.
#     build  : also run the staged toolchain builder (stage 1..3).
#
# Everything it writes lives inside the checkpoint, so it is inherited by every
# project sandbox booted from that checkpoint.
set -uo pipefail

# shuru's guest init leaves HOME empty; every tool that installs itself into
# ~ would otherwise scatter files across /.
export HOME=/root USER=root LOGNAME=root
mkdir -p "$HOME"
[ -f "$HOME/.profile" ] || printf 'export HOME=/root\n' > "$HOME/.profile"

BUILD_DIR=/newvm-build
LIB=/usr/local/lib/newvm
BIN=/usr/local/bin
STATE=/var/lib/newvm
LOGDIR=/var/log/newvm

C_D=$'\033[2m'; C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
[ -t 1 ] || { C_D=""; C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""; }

ts() { date -u +%H:%M:%S; }
say()  { printf '%s[%s] %s%s\n' "$C_D" "$(ts)" "$1" "$C_0"; }
good() { printf '%s[%s] + %s%s\n' "$C_G" "$(ts)" "$1" "$C_0"; }
bad()  { printf '%s[%s] ! %s%s\n' "$C_R" "$(ts)" "$1" "$C_0"; }

[ -d "$BUILD_DIR" ] || { bad "payload missing at $BUILD_DIR"; exit 1; }
if [ ! -f "$BUILD_DIR/build.conf" ]; then
  bad "payload is incomplete ($BUILD_DIR/build.conf missing)"
  exit 1
fi
. "$BUILD_DIR/build.conf"
mkdir -p "$STATE"; cp "$BUILD_DIR/build.conf" "$STATE/build.conf" 2>/dev/null

MARKER="${1:-unknown}"
ACTION="${2:-apply}"
STAGE="${3:-}"

mkdir -p "$LIB/with.d" "$LIB/tools" "$STATE/steps" "$LOGDIR" /workspace /root

# ------------------------------------------------------------- runner files --
install_file() { # src dst mode
  [ -f "$1" ] || return 1
  if [ -f "$2" ] && cmp -s "$1" "$2"; then return 0; fi
  mkdir -p "$(dirname "$2")" && cp "$1" "$2" && chmod "${3:-644}" "$2" && return 0
}

# Overwrite the runner scripts only when the host recipe changed, so a tweak
# made inside the sandbox is not silently reverted on the next boot.
_want=$(sed -n 's/^NEWVM_RECIPE=//p' "$BUILD_DIR/build.conf" 2>/dev/null)
_have=$(cat "$STATE/recipe" 2>/dev/null)
changed=0
if [ "$_want" != "$_have" ] || [ ! -f "$STATE/hostcopy" ]; then
  changed=1
  mkdir -p "$STATE/hostcopy.d"
  for _f in session.sh bashrc manifest.sh provision.sh apply.sh with.sh; do
    [ -f "$LIB/$_f" ] && cp "$LIB/$_f" "$STATE/hostcopy.d/$_f" 2>/dev/null
  done
  printf '%s' "$_want" > "$STATE/recipe"
  touch "$STATE/hostcopy"
fi
_install_file() {
  if [ "$changed" = "1" ]; then install_file "$1" "$2" "$3"; else
    [ -f "$2" ] || install_file "$1" "$2" "$3"
  fi
  return 0
}
install_file "$BUILD_DIR/session.sh"   "$LIB/session.sh"   755 || true
install_file "$BUILD_DIR/bashrc"       "$LIB/bashrc"       644 || true
install_file "$BUILD_DIR/manifest.sh"  "$LIB/manifest.sh"  755 || true
install_file "$BUILD_DIR/provision.sh" "$LIB/provision.sh" 755 || true
install_file "$BUILD_DIR/apply.sh"     "$LIB/apply.sh"     755 || true
install_file "$BUILD_DIR/with.sh"      "$LIB/with.sh"      755 || true
for f in "$BUILD_DIR"/with.d/*.sh; do
  [ -f "$f" ] || continue
  install_file "$f" "$LIB/with.d/$(basename "$f")" 755 || true
done
for f in "$BUILD_DIR"/tools/*.txt; do
  [ -f "$f" ] || continue
  install_file "$f" "$LIB/tools/$(basename "$f")" 644 || true
done

# convenience entry points
link_bin() { # target source [args]
  [ -f "$2" ] || return 0
  printf '#!/bin/sh\nexec %s %s "$@"\n' "$2" "$3" > "$1"
  chmod 755 "$1"
}
link_bin "$BIN/newvm-session"   "$LIB/session.sh"   ""
link_bin "$BIN/newvm-manifest"  "$LIB/manifest.sh"  ""
link_bin "$BIN/newvm-provision" "$LIB/provision.sh" "--all"
link_bin "$BIN/newvm-rebuild"   "$LIB/provision.sh" "--all --force"
link_bin "$BIN/newvm-with"      "$LIB/with.sh"      ""

cat > "$BIN/newvm-doctor" <<'DOCTOR'
#!/usr/bin/env bash
# newvm-doctor - verify the toolchain inside this sandbox
export DEBIAN_FRONTEND=noninteractive
printf '\n  system      %s\n' "$(uname -srm)"
printf '  cpus        %s\n' "$(nproc)"
printf '  memory      %s\n' "$(free -m | awk '/^Mem:/{print $2" MB total, "$7" MB available"}')"
printf '  disk        %s\n' "$(df -h / | awk 'NR==2{print $2" total, "$4" free"}')"
printf '  workspace   %s (%s)\n' "$(cd /workspace 2>/dev/null && pwd || echo missing)" "$(mountpoint -q /workspace && echo mounted || echo 'not mounted')"
printf '\n  tools\n'
check() { printf '    %-14s %s\n' "$1" "$($2 --version 2>/dev/null | head -1 || echo '-')"; }
check bash      bash
check git       git
check node      node
check npm       npm
check bun       bun
check python3   python3
check uv        uv
check go        go
check cargo     cargo
check rustc     rustc
check java      java
check codex     codex
check claude    claude
check gemini    gemini
check copilot   copilot
check opencode  opencode
check gh        gh
check docker    docker
check rg        rg
check fzf       fzf
check tmux      tmux
check nvim      nvim
printf '\n  keys wired  %s\n' "$(env | grep -oE '^(OPENAI|ANTHROPIC|GEMINI|GOOGLE|XAI|GROQ|OPENROUTER|MISTRAL|DEEPSEEK|TOGETHER|PERPLEXITY|COHERE|FIREWORKS|GITHUB|GH|NPM|DOCKERHUB)_[A-Z_]*' | tr '\n' ' ' || echo none)"
printf '\n'
DOCTOR
chmod 755 "$BIN/newvm-doctor"

# agent CLIs that sandbox themselves do not need to inside a throwaway VM
if [ -f /root/.codex/config.toml ] && ! grep -q sandbox_mode /root/.codex/config.toml 2>/dev/null; then
  cat >> /root/.codex/config.toml <<'CFG'

# added by newvm: this machine is already an isolated microVM
approval_policy = "never"
sandbox_mode = "danger-full-access"
CFG
  changed=1
fi
cat > "$BIN/ncodex" <<'NCODEX'
#!/usr/bin/env bash
# ncodex - codex with its own sandbox disabled: this machine is already one
if codex --help 2>&1 | grep -q -- '--dangerously-bypass-approvals-and-sandbox'; then
  exec codex --dangerously-bypass-approvals-and-sandbox "$@"
fi
exec codex "$@"
NCODEX
chmod 755 "$BIN/ncodex"

# apt-get install without a prior update, and a friendlier package manager
cat > "$BIN/newvm-apt" <<'APT'
#!/usr/bin/env bash
# newvm-apt - install packages in the sandbox (runs apt-get update first)
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
case "${1:-}" in
  update|upgrade) exec apt-get "${@:2}" ;;
  "") shift ;;
  install|remove|purge) mode="$1"; shift; apt-get update -qq; exec apt-get "$mode" "$@" ;;
  *) apt-get update -qq; exec apt-get "$@" ;;
esac
APT
chmod 755 "$BIN/newvm-apt"
ln -sf "$BIN/newvm-apt" "$BIN/aptinstall" 2>/dev/null

# shell wiring
if [ -f "$LIB/bashrc" ]; then
  install_file "$LIB/bashrc" /etc/newvm/bashrc 644 || true
  if ! grep -q 'newvm/bashrc' /root/.bashrc 2>/dev/null; then
    cat >> /root/.bashrc <<'BRC'

# newvm sandbox environment
[ -f /etc/newvm/bashrc ] && . /etc/newvm/bashrc
BRC
    changed=1
  fi
fi
# One owner for the login-shell PATH. Written every boot (cheap, idempotent) so
# it can never drift from the tools that are actually installed.
cat > /etc/profile.d/newvm.sh <<'PROF'
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.deno/bin:/usr/local/go/bin:$HOME/go/bin:$PATH" ;;
esac
PROF
chmod 644 /etc/profile.d/newvm.sh
chmod 700 /root; chmod 755 /workspace 2>/dev/null

# --------------------------------------------------------- host credentials --
auth_applied() {
  # skip the copy when the recorded hash already matches and files are present
  _want="${NEWVM_AUTH:-none}"
  [ -f "$STATE/auth" ] || return 1
  [ "$(cat "$STATE/auth" 2>/dev/null)" = "$_want" ] || return 1
  [ -f /root/.codex/auth.json ] || [ ! -f "$BUILD_DIR/payload/root/.codex/auth.json" ] || return 1
  return 0
}

# P0.1: the golden toolchain image must never contain credentials. They are
# applied per sandbox only.
if [ "$ACTION" = "build" ] || [ -d "$BUILD_DIR/payload/root" ]; then
  if auth_applied || [ "$ACTION" = "build" ]; then
    say "credentials already current (${NEWVM_AUTH:-none})"
  else
    # F7: a credential deleted on the host must disappear here too
    for _p in .codex/auth.json .codex/config.toml .claude/.credentials.json \
              .claude/settings.json .gemini/oauth_creds.json .gemini/settings.json \
              .config/gh/hosts.yml .local/share/opencode/auth.json; do
      [ -f "$BUILD_DIR/payload/root/$_p" ] || rm -f "/root/$_p"
    done
    cp -a "$BUILD_DIR/payload/root/." /root/ 2>/dev/null
    printf '%s' "${NEWVM_AUTH:-none}" > "$STATE/auth"
    # F12: credentials are private, everywhere
    chmod 700 /root 2>/dev/null
    find /root/.codex /root/.claude /root/.gemini /root/.config/gh \
         /root/.local/share/opencode -type f -exec chmod 600 {} + 2>/dev/null
    chmod 600 /root/.gitconfig 2>/dev/null
    [ -d /root/.ssh ] && { chmod 700 /root/.ssh; find /root/.ssh -type f -exec chmod 600 {} + 2>/dev/null; }
    _n=$(find "$BUILD_DIR/payload/root" -type f | wc -l | tr -d ' ')
    [ "$_n" -gt 0 ] && good "host credentials applied ($_n files)"
  fi
fi

# do not leave a second copy of the credentials lying around in the guest
rm -rf "$BUILD_DIR/payload/root" 2>/dev/null

printf '%s' "${NEWVM_AUTH:-none}" > "$STATE/auth.received"
printf '%s\n' "$MARKER" > "$STATE/last-marker"

# ------------------------------------------------------------------- build --
if [ "$ACTION" = "build" ] && [ -n "$STAGE" ]; then
  say "building toolchain stage $STAGE (marker $MARKER)"
  bash "$LIB/provision.sh" "$STAGE" || exit $?
fi

exit 0