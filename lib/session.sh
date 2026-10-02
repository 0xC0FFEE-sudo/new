#!/usr/bin/env bash
# newvm-session - guest entry point for every `new` session.
#
# Reads the parameters the host passes as argv, prepares the workspace, applies
# any --with tools, prints a short banner and hands over to the shell.

# shuru's guest init leaves HOME empty; without this every tool would treat /
# as the home directory and codex/claude/git would write to the wrong place.
export HOME=/root USER=root LOGNAME=root
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.deno/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
mkdir -p "$HOME"

PROJECT="sandbox"
CHECKPOINT="checkpoint"
PARENT="base"
SAVE="never"
WITH=""
SYNC_AUTH=0
MOUNTMODE="rw"
HOSTDIR=""
WORKSPACE="/workspace"
SHELL_BIN="bash"
CPUS=""
MEM=""
DISK=""
SECRETS=""
VERSION_TAG=""
CMD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)    PROJECT="$2"; shift 2 ;;
    --checkpoint) CHECKPOINT="$2"; shift 2 ;;
    --parent)     PARENT="$2"; shift 2 ;;
    --save)       SAVE="$2"; shift 2 ;;
    --with)       WITH="$2"; shift 2 ;;
    --sync-auth)  SYNC_AUTH="$2"; shift 2 ;;
    --mountmode)  MOUNTMODE="$2"; shift 2 ;;
    --hostdir)    HOSTDIR="$2"; shift 2 ;;
    --workspace)  WORKSPACE="$2"; shift 2 ;;
    --shell)      SHELL_BIN="$2"; shift 2 ;;
    --cpus)       CPUS="$2"; shift 2 ;;
    --memory)     MEM="$2"; shift 2 ;;
    --disk)       DISK="$2"; shift 2 ;;
    --secrets)    SECRETS="$2"; shift 2 ;;
    --version-tag) VERSION_TAG="$2"; shift 2 ;;
    --cmd)        shift; CMD="$*"; break ;;
    *)            shift ;;
  esac
done

export NEWVM_PROJECT="$PROJECT" NEWVM_CHECKPOINT="$CHECKPOINT" NEWVM_SAVE="$SAVE"
export NEWVM_PARENT="$PARENT" NEWVM_CPUS="$CPUS" NEWVM_MEM="$MEM" NEWVM_DISK="$DISK"
export NEWVM_MOUNT="$MOUNTMODE" NEWVM_HOSTDIR="$HOSTDIR" NEWVM_VERSION="$VERSION_TAG"

bold=$'\033[1m'; dim=$'\033[2m'; cyan=$'\033[36m'; green=$'\033[32m'; yellow=$'\033[33m'; off=$'\033[0m'
[ -t 1 ] || { bold=""; dim=""; cyan=""; green=""; yellow=""; off=""; }

# --------------------------------------------------------------- workspace --
if mountpoint -q "$WORKSPACE" 2>/dev/null; then
  :
elif [ -d "$WORKSPACE" ]; then
  :
else
  mkdir -p "$WORKSPACE" 2>/dev/null
fi
[ -d "$WORKSPACE" ] || WORKSPACE=""

# ------------------------------------------------------------ -- with tools --
apply_with() {
  [ -n "$WITH" ] || return 0
  local installer=/usr/local/lib/newvm/with.sh t
  [ -f "$installer" ] || { printf '%s  tool installer missing in this image%s\n' "$yellow" "$off"; return 0; }
  local IFS=','
  for t in $WITH; do
    unset IFS
    t=$(printf '%s' "$t" | tr -d ' ')
    [ -n "$t" ] || { IFS=','; continue; }
    bash "$installer" "$t"
    IFS=','
  done
  unset IFS
  return 0
}

banner() {
  local free total used rw_note="" save_note=""
  [ "$MOUNTMODE" = "ro" ] && rw_note="${dim} · writes are RAM-only, discarded on exit (use --rw to write to the host folder)${off}"
  if [ "$SAVE" = "never" ]; then
    save_note="nothing is kept - this session disappears when you leave"
  else
    save_note="saves itself as '$CHECKPOINT' when you leave"
  fi
  total=$(df -h / 2>/dev/null | awk 'NR==2{print $2}')
  free=$(df -h / 2>/dev/null | awk 'NR==2{print $4}')
  used=$(free -m 2>/dev/null | awk '/^Mem:/{print $3" MB of "$2" MB"}')
  cat <<BANNER

${bold}${cyan}  $PROJECT${off} ${dim}· ephemeral microVM sandbox${off}
  ${dim}------------------------------------------------------------${off}
  checkpoint   ${bold}$CHECKPOINT${off} ${dim}· from $PARENT${off}
  resources    ${CPUS:-?} cpus · ${used:-?} · $total disk ${dim}(${free:-?} free)${off}
  workspace    $WORKSPACE ${dim}($MOUNTMODE${HOSTDIR:+ ← $HOSTDIR}${off})${rw_note}
  keys         ${SECRETS:-none}${off}${dim} · placeholders, real values stay on the host${off}
  toolchain    codex · claude · opencode · gemini · copilot · node · python · go · rust · bun · docker · gh
  ${dim}------------------------------------------------------------${off}
  ${dim}on exit:${off} $save_note
  ${dim}help:   ${off}newvm-doctor · newvm-manifest · newvm-with <tool> · newvm-provision · ncodex · vmexit

BANNER
}

apply_with
if [ -n "$CMD" ]; then
  [ -n "$WORKSPACE" ] && { cd "$WORKSPACE" 2>/dev/null || true; }
  exec bash -lc "$CMD"
fi

[ -n "$WORKSPACE" ] && { cd "$WORKSPACE" 2>/dev/null || true; }
banner

SHELL_BIN=${SHELL_BIN:-bash}
command -v "$SHELL_BIN" >/dev/null 2>&1 || SHELL_BIN=bash
[ -n "$SHELL_BIN" ] || SHELL_BIN="sh"

if [ -t 0 ] && [ -t 1 ]; then
  exec "$SHELL_BIN" -i
else
  exec "$SHELL_BIN"
fi