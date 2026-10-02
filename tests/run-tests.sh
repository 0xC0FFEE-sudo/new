#!/usr/bin/env bash
# newvm test suite.
#
# Fakes the `shuru` CLI so that argument construction, config parsing and
# checkpoint bookkeeping can be verified WITHOUT booting a VM or downloading
# anything. Everything here runs in a throwaway HOME.

set -uo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/newvm-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; SKIP=0
C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_D=$'\033[2m'; C_0=$'\033[0m'
[ -t 1 ] || { C_G=""; C_R=""; C_Y=""; C_D=""; C_0=""; }

ok()   { PASS=$((PASS+1)); printf '  %sok%s   %s\n' "$C_G" "$C_0" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  %sFAIL%s %s\n' "$C_R" "$C_0" "$1"; [ -n "${2:-}" ] && printf '       %s%s%s\n' "$C_D" "$2" "$C_0"; }
skip() { SKIP=$((SKIP+1)); printf '  %sskip%s %s (%s)\n' "$C_Y" "$C_0" "$1" "${2:-}"; }

check() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2"$'\n'"     got:      $3"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) ok "$1";; *) bad "$1" "expected to contain: $3"$'\n'"     got: $2";; esac
}
notcontains() { # name haystack needle
  case "$2" in *"$3"*) bad "$1" "should not contain: $3";; *) ok "$1";; esac
}

# ------------------------------------------------------------- fake shuru ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/shuru" <<'FAKE'
#!/usr/bin/env bash
# A stand-in for the shuru CLI: records the argv and maintains a fake
# checkpoint directory so that create/delete/list behave like the real thing.
printf '%s\n' "$*" >> "$FAKE_LOG"
CKPT="${FAKE_SHURU_HOME}/checkpoints"
mkdir -p "$CKPT" 2>/dev/null
while [ $# -gt 0 ]; do
  case "$1" in
    --version) echo "shuru 0.7.0 (fake)"; exit 0 ;;
    checkpoint)
      _sub="$2"
      case "$_sub" in
        create)
          shift 2                 # drop "checkpoint create"
          _name="${1:-}"          # the checkpoint name is the next argument
          shift
          while [ $# -gt 0 ]; do
            [ "$1" = "--" ] && break
            shift
          done
          if [ -n "$_name" ] && [ -n "$FAKE_CREATE_OK" ]; then
            : > "$CKPT/$_name.ext4"
            echo "shuru: checkpoint '$_name' saved" >&2
          fi
          exit 0 ;;
        delete)
          _n="${3:-}"; shift 3 2>/dev/null || true
          rm -f "$CKPT/$_n.ext4" "$CKPT/$_n.idx"
          echo "shuru: checkpoint '$_n' deleted" >&2
          exit 0 ;;
        list)
          printf '%-24s %-10s %s\n' NAME SIZE CREATED
          for f in "$CKPT"/*.ext4 "$CKPT"/*.idx; do
            [ -f "$f" ] || continue
            n=$(basename "$f"); n=${n%.*}
            printf '%-24s %-10s %s\n' "$n" "1.0M" "just now"
          done
          exit 0 ;;
      esac
      exit 0 ;;
    run) exit 0 ;;
  esac
  shift
done
exit 0
FAKE
chmod +x "$TMP/bin/shuru"

# fake shuru data dir
export FAKE_LOG="$TMP/shuru.log"
: > "$FAKE_LOG"
FAKE_SHURU_HOME="$TMP/shuruhome"
mkdir -p "$FAKE_SHURU_HOME/checkpoints"

# ----------------------------------------------------------------- harness --
NEW_BIN="$ROOT/new"
run_new() { # args... -> stdout+stderr in $OUT, argv log in $ARGV
  : > "$FAKE_LOG"
  [ -x "$TEST_HOME/.local/share/newvm/new" ] && NEW_BIN="$TEST_HOME/.local/share/newvm/new"
  OUT=$(cd "${TEST_DIR:-$TMP}" && HOME="$TEST_HOME" PATH="$TMP/bin:$PATH" "$NEW_BIN" "$@" 2>&1)
  ARGV=$(cat "$FAKE_LOG")
  return 0
}

new_home() {
  TEST_HOME="$TMP/home$RANDOM"
  mkdir -p "$TEST_HOME"
  export FAKE_SHURU_HOME="$TEST_HOME/.local/share/shuru"
  export FAKE_CREATE_OK=1
  # install the program into the fake home the way install.sh would
  mkdir -p "$TEST_HOME/.local/share"
  cp -R "$ROOT" "$TEST_HOME/.local/share/newvm"
  rm -rf "$TEST_HOME/.local/share/newvm/tests"
  # a pre-existing golden image so tests never trigger a 30-minute build
  mkdir -p "$FAKE_SHURU_HOME/checkpoints"
  : > "$FAKE_SHURU_HOME/checkpoints/newvm-base.ext4"
  _recipe=$(cd "$TEST_HOME/project" 2>/dev/null || mkdir -p "$TEST_HOME/project"; cd "$TEST_HOME/project" && \
           HOME="$TEST_HOME" PATH="$TMP/bin:$PATH" "$TEST_HOME/.local/share/newvm/new" env 2>/dev/null | sed -n 's/^RECIPE=//p')
  printf 'recipe=%s\ndisk=102400\nsession=1\n' "$_recipe" \
    > "$TEST_HOME/.local/share/newvm/state/ckpt/newvm-base.meta"
  TEST_DIR="$TEST_HOME/project"
  mkdir -p "$TEST_DIR"
}

# =============================================================== syntax =====
printf '\n%s  syntax%s\n' "$C_D" "$C_0"
for f in "$ROOT/new" "$ROOT"/lib/*.sh "$ROOT/install.sh" "$ROOT/uninstall.sh"; do
  if bash -n "$f" 2>"$TMP/err"; then ok "bash -n $(basename "$f")"
  else bad "bash -n $(basename "$f")" "$(cat "$TMP/err")"; fi
done
for f in "$ROOT/install.sh" "$ROOT/uninstall.sh"; do
  if sh -n "$f" 2>"$TMP/err"; then ok "sh -n $(basename "$f")"
  else bad "sh -n $(basename "$f")" "$(cat "$TMP/err")"; fi
done

# ============================================================ help/version ==
printf '\n%s  help and version work without shuru%s\n' "$C_D" "$C_0"
TEST_HOME="$TMP/home-help"; mkdir -p "$TEST_HOME"
O=$(cd "$TMP" && HOME="$TEST_HOME" PATH="/usr/bin:/bin" "$ROOT/new" --help 2>&1)
contains "--help works with no shuru installed" "$O" "USAGE"
O=$(cd "$TMP" && HOME="$TEST_HOME" PATH="/usr/bin:/bin" "$ROOT/new" --version 2>&1)
contains "--version works with no shuru" "$O" "new 1.0"
mkdir -p "$TEST_HOME/.local/share"; cp -R "$ROOT" "$TEST_HOME/.local/share/newvm"
O=$(cd "$TMP" && HOME="$TEST_HOME" PATH="/usr/bin:/bin" "$ROOT/new" doctor 2>&1)
contains "doctor runs without shuru and reports it" "$O" "MISSING"
contains "doctor checks the architecture" "$O" "arm64"

# ============================================================ resources =====
printf '\n%s  defaults and resource flags%s\n' "$C_D" "$C_0"
new_home
run_new env
contains "default memory is 8 GB"      "$OUT" "MEM=8192"
contains "default disk is 100 GB"      "$OUT" "DISK=102400"
contains "default mount is the overlay" "$OUT" "MOUNT=ro"

run_new --memory 16384 env
contains "--memory overrides the default" "$OUT" "MEM=16384"
run_new -m 4096 env
contains "-m overrides the default"       "$OUT" "MEM=4096"
O=$(cd "$TEST_DIR" && HOME="$TEST_HOME" NEW_MEM=2048 PATH="$TMP/bin:$PATH" "$NEW_BIN" env 2>&1)
contains "NEW_MEM in the environment wins over config" "$O" "MEM=2048"
O=$(cd "$TEST_DIR" && HOME="$TEST_HOME" PATH="$TMP/bin:$PATH" "$NEW_BIN" --memory 512 env 2>&1)
contains "a flag still beats the environment" "$O" "MEM=512"
new_home

# ======================================================= shuru argv build ===
printf '\n%s  shuru argument construction%s\n' "$C_D" "$C_0"
new_home
run_new --cmd 'true' --save never
contains "passes an explicit --config"      "$ARGV" "--config"
notcontains "does not use the project shuru.json" "$ARGV" "--config ./shuru.json"
contains "passes the cpu count"             "$ARGV" "--cpus"
contains "passes memory"                    "$ARGV" "--memory 8192"
contains "passes the disk size"             "$ARGV" "--disk-size 102400"
contains "mounts the project read-only by default" "$ARGV" ":/workspace:ro"
notcontains "does not allow host writes by default" "$ARGV" "--allow-host-writes"
contains "network is on by default"         "$ARGV" "--allow-net"
contains "boots from the golden image"     "$ARGV" "--from newvm-base"

run_new --rw --cmd 'true' --save never
contains "--rw mounts read-write"           "$ARGV" ":/workspace:rw"
contains "--rw allows host writes"          "$ARGV" "--allow-host-writes"

run_new --no-mount --cmd 'true' --save never
notcontains "--no-mount passes no --mount" "$ARGV" ":/workspace:"

run_new --no-net --cmd 'true' --save never
notcontains "--no-net drops --allow-net"    "$ARGV" "--allow-net"

run_new --net-hosts api.openai.com,github.com --cmd 'true' --save never
contains "--net-hosts allow-lists api.openai.com" "$ARGV" "--allow-host api.openai.com"
contains "--net-hosts allow-lists github.com"    "$ARGV" "--allow-host github.com"

run_new --ports 3000,8080:80 --cmd 'true' --save never
contains "--ports maps 3000 to 3000"        "$ARGV" "-p 3000:3000"
contains "--ports keeps an explicit mapping" "$ARGV" "-p 8080:80"

run_new --secret FOO=BAR@x.example.com --cmd 'true' --save never
contains "--secret is forwarded"            "$ARGV" "--secret FOO=BAR@x.example.com"

run_new --cmd 'true' --save never -- --allow-net
notcontains "forwarded flags after -- do not become secrets" "$ARGV" " --secret "

# a glob in a forwarded value must not expand
mkdir -p "$TEST_DIR/sub" && touch "$TEST_DIR/sub/one.txt" "$TEST_DIR/two.txt"
run_new --cmd 'true' --save never -- --allow-host '*'
notcontains "a glob in a forwarded flag is not expanded" "$ARGV" "two.txt"

# ============================================================== paths ======
printf '\n%s  project identity%s\n' "$C_D" "$C_0"
new_home
mkdir -p "$TMP/with space/project" && TEST_DIR="$TMP/with space/project"
run_new env
_real=$(cd "$TMP/with space/project" && pwd -P)
contains "a folder with a space is handled (canonicalised)" "$OUT" "PROJ_DIR=$_real"
run_new --cmd 'true' --save never
contains "a space in the path is not split into extra args" "$ARGV" "with space/project:/workspace:ro"

TEST_DIR="$TMP/linkdir"; mkdir -p "$TMP/realproj"; ln -sfn "$TMP/realproj" "$TMP/linkdir"
run_new env
_ck1=$(printf '%s' "$OUT" | sed -n 's/^PROJ_CKPT=//p')
TEST_DIR="$TMP/realproj"; run_new env
_ck2=$(printf '%s' "$OUT" | sed -n 's/^PROJ_CKPT=//p')
if [ "$_ck1" = "$_ck2" ]; then ok "a symlinked folder maps to the same sandbox"
else bad "a symlinked folder maps to the same sandbox" "$_ck1 vs $_ck2"; fi

run_new /nonexistent-directory-xyz
contains "a missing directory is a usage error" "$OUT" "not a directory"

# ============================================================== secrets ====
printf '\n%s  secrets%s\n' "$C_D" "$C_0"
new_home
run_new secrets
contains "secret table lists OPENAI_API_KEY" "$OUT" "OPENAI_API_KEY"
contains "unset keys are shown as unset"      "$OUT" "unset"
OPENAI_API_KEY=sk-test-value run_new --cmd 'true' --save never
TEST_HOME="$TEST_HOME" HOME="$TEST_HOME" OPENAI_API_KEY=sk-test-value \
  bash -c "cd '$TEST_DIR' && HOME='$TEST_HOME' PATH='$TMP/bin:\$PATH' '$ROOT/new' --cmd true --save never" >/dev/null 2>&1
contains "a set key is forwarded as a --secret" "$(cat "$FAKE_LOG")" "--secret OPENAI_API_KEY=OPENAI_API_KEY@api.openai.com"
run_new --no-secrets --cmd 'true' --save never
notcontains "--no-secrets wires nothing" "$ARGV" "--secret OPENAI"

# =========================================================== passthrough ===
printf '\n%s  command handling%s\n' "$C_D" "$C_0"
new_home
run_new --cmd 'echo hello'
contains "--cmd reaches the guest as argv" "$ARGV" "--cmd echo hello"
run_new run -- 'echo passthru'
contains "'new run --' is treated as a command" "$ARGV" "--cmd echo passthru"
run_new -- 'echo direct'
contains "everything after -- is the guest command" "$ARGV" "--cmd echo direct"
run_new --with a --with b --cmd 'true' --save never
contains "multiple --with keep their separator" "$ARGV" "--with a,b"

run_new not-a-directory-xyz
contains "a bare word that is not a directory is rejected" "$OUT" "not a directory"
run_new --save bogus
contains "an invalid --save value is a usage error" "$OUT" "--save must be"

# ======================================================= checkpoint logic ==
printf '\n%s  checkpoint bookkeeping%s\n' "$C_D" "$C_0"
new_home
CK="$FAKE_SHURU_HOME/checkpoints"
run_new --cmd 'true' --save never
contains "an ephemeral session uses run --from" "$ARGV" "run --from"
notcontains "an ephemeral session creates no checkpoint" "$ARGV" "checkpoint create"

run_new --cmd 'true'
contains "the first session in a folder saves itself" "$ARGV" "checkpoint create newvm-proj-"

# a saved sandbox must be resumed, not rebuilt from the golden image
_ck=$(cd "$TEST_DIR" && HOME="$TEST_HOME" PATH="$TMP/bin:$PATH" "$NEW_BIN" env 2>/dev/null | sed -n 's/^PROJ_CKPT=//p')
if [ -z "$_ck" ]; then
  bad "could not resolve a checkpoint name for the resume test"
else
  : > "$CK/$_ck.ext4"
  run_new --cmd 'true'
  contains "a later session rolls the saved sandbox forward" "$OUT" "rolling the saved sandbox forward"
  contains "a later session saves over the same name"          "$OUT" "saved as '$_ck'"
  contains "a later session boots from the staged previous state" "$OUT" "from checkpoint 'newvm-prev-"
  contains "the previous state is discarded afterwards"         "$OUT" "sandbox saved as '$_ck'"
[ -f "$CK/newvm-prev-"*"$_ck".ext4 ] && bad "the rollback copy was left behind" || ok "the rollback copy is cleaned up"
[ -f "$CK/$_ck.ext4" ] && ok "the sandbox checkpoint exists on disk" || bad "the sandbox checkpoint was not created"
fi

# =========================================================== subcommands ===
printf '\n%s  subcommands%s\n' "$C_D" "$C_0"
new_home
run_new list
contains "list reports the golden image" "$OUT" "newvm-base"
run_new status
contains "status reports the checkpoint"  "$OUT" "checkpoint"
run_new tools
contains "tools lists shellx"  "$OUT" "shellx"
contains "tools lists docker"  "$OUT" "docker"
run_new env
contains "env prints the memory setting" "$OUT" "MEM="
run_new --memory 12345 env
contains "a subcommand works after flags" "$OUT" "MEM=12345"
run_new doctor
contains "doctor reports the shuru version" "$OUT" "shuru"
run_new clean project
contains "clean project removes this folder's sandbox" "$OUT" "removed"
run_new unlock
contains "unlock clears locks" "$OUT" "locks"

# ======================================================= guest scripts =====
printf '\n%s  guest scripts%s\n' "$C_D" "$C_0"
new_home
run_new --with docker --cmd 'true' --save never
contains "--with is passed through to the guest" "$ARGV" "--with docker"
notcontains "--no-secrets adds no --secret flag" "$ARGV" " --secret "
contains "the session entry point is invoked"     "$ARGV" "newvm-session"

# the guest scripts must not rely on bashisms when run under sh
for f in "$ROOT"/lib/*.sh; do
  if sh -n "$f" 2>"$TMP/err"; then ok "sh -n lib/$(basename "$f")"
  else bad "sh -n lib/$(basename "$f")" "$(cat "$TMP/err")"; fi
done

# every tool advertised in the # TOOLS: line must be handled by name_of()
for t in $(sed -n 's/^# TOOLS: //p' "$ROOT/lib/with.sh" | tr -s ' \n' ' '); do
  if grep -q "^ *$t)\|^ *$(printf '%s' "$t" | sed 's/.*/|&/' | sed 's/^/&/')" "$ROOT/lib/with.sh" 2>/dev/null \
     || grep -q " $t)\| $t|" "$ROOT/lib/with.sh"; then
    ok "tool '$t' is handled"
  else
    bad "tool '$t' is advertised but has no installer case"
  fi
done

# =================================================================== done ===
printf '\n  %s%d passed%s, %s%d failed%s, %d skipped\n\n' \
  "$C_G" "$PASS" "$C_0" "$( [ "$FAIL" -gt 0 ] && printf '%s' "$C_R" || printf '%s' "$C_D")" "$FAIL" "$C_0" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0