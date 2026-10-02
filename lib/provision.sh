#!/usr/bin/env bash
# provision.sh - staged toolchain builder, runs inside the shuru microVM.
#
#   provision.sh 1|2|3            install that stage (idempotent, resumable)
#   provision.sh --all            run all three stages in order
#   provision.sh --all --force    ignore sentinels and redo everything
#
# Every step is guarded by a sentinel under /var/lib/newvm/steps, so a stage can
# be re-entered after a failure without redoing what already worked. Package
# lists live in /usr/local/lib/newvm/tools/*.txt - edit them on the host
# ($HOME/.local/share/newvm/tools) and run 'new rebuild' to apply the changes.
set -uo pipefail

export DEBIAN_FRONTEND=noninteractive
export GIT_TERMINAL_PROMPT=0
export NEEDRESTART_MODE=a
export HOME=/root USER=root LOGNAME=root
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.deno/bin:/usr/local/go/bin:$PATH"

LIB=/usr/local/lib/newvm
STEPS=/var/lib/newvm/steps
LOGDIR=/var/log/newvm

ARG1="${1:-}"
ARG2="${2:-}"
FORCE=0
[ "$ARG2" = "--force" ] && FORCE=1
ALL=0
[ "$ARG1" = "--all" ] && ALL=1
[ "$ARG1" = "--force" ] && { ALL=1; FORCE=1; }

# /newvm-build only exists during a build boot; fall back to the copy apply.sh kept
if [ -f /newvm-build/build.conf ]; then . /newvm-build/build.conf 2>/dev/null
elif [ -f /var/lib/newvm/build.conf ]; then . /var/lib/newvm/build.conf 2>/dev/null
fi
: "${NEWVM_PROFILE:=full}"
: "${NEWVM_EXTRAS:=}"
export NEWVM_EXTRAS NEWVM_PROFILE

mkdir -p "$STEPS" "$LOGDIR" /workspace /root
LOG="$LOGDIR/provision-${ARG1:-all}.log"
touch "$LOG"

C_D=$(printf '\033[2m'); C_B=$(printf '\033[1m'); C_G=$(printf '\033[32m')
C_Y=$(printf '\033[33m'); C_R=$(printf '\033[31m'); C_0=$(printf '\033[0m')
[ -t 1 ] || { C_D=""; C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""; }
ts() { date -u +%H:%M:%S; }

FAILS=0
SKIPPED=0            # set by steps that are gated off, so no sentinel is written
has()  { command -v "$1" >/dev/null 2>&1; }
extra() { case ",$NEWVM_EXTRAS," in *",$1,"*) return 0;; *) return 1;; esac; }
# Marks the current step as "not enabled" and returns non-zero so the calling
# function's remaining lines do not run. `step` treats that as skipped.
skip()  { SKIPPED=1; return 1; }
list_from() { [ -f "$1" ] || return 0; grep -vE '^[[:space:]]*(#|$)' "$1" | tr '\n' ' '; }
note() { printf '    %s\n' "$1" >> "$LOG"; }

step() { # id description command...
  _id="$1"; _desc="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  if [ "$FORCE" = "0" ] && [ -f "$STEPS/$_id" ]; then
    printf '%s[%s] = %s%s\n' "$C_D" "$(ts)" "$_desc (cached)" "$C_0"
    return 0
  fi
  printf '%s[%s] > %s%s\n' "$C_B" "$(ts)" "$_desc" "$C_0"
  printf '### %s %s :: %s\n' "$(date -u +%FT%TZ)" "$_id" "$_desc" >> "$LOG"
  SKIPPED=0
  if "$@" >> "$LOG" 2>&1; then
    if [ "$SKIPPED" = "1" ]; then
      printf '%s[%s] - %s (not enabled)%s\n' "$C_D" "$(ts)" "$_desc" "$C_0"
      return 0
    fi
    touch "$STEPS/$_id"
    printf '%s[%s] + %s%s\n' "$C_G" "$(ts)" "$_desc" "$C_0"
    return 0
  fi
  # a step that was gated off returns non-zero via skip(): that is not a failure
  if [ "$SKIPPED" = "1" ]; then
    printf '%s[%s] - %s (not enabled)%s\n' "$C_D" "$(ts)" "$_desc" "$C_0"
    return 0
  fi
  FAILS=$((FAILS+1))
  printf '%s[%s] ! %s FAILED%s\n' "$C_R" "$(ts)" "$_desc" "$C_0"
  tail -4 "$LOG" | sed 's/^/        /'
  return 1
}

# Install a list of apt packages; if the batch fails, retry one by one so a
# single unavailable name cannot take the whole toolchain down.
apt_install() {
  _list="$1"
  apt-get update -qq >> "$LOG" 2>&1 || { note "apt: index update failed"; return 1; }
  if apt-get install -y -qq --no-install-recommends $_list >> "$LOG" 2>&1; then
    return 0
  fi
  _fails=0
  for p in $_list; do
    if apt-get install -y -qq --no-install-recommends "$p" >> "$LOG" 2>&1; then
      note "recovered: $p"
    else
      note "unavailable: $p"
      _fails=$((_fails+1))
    fi
  done
  [ "$_fails" -eq 0 ]
}

fetch() { # url dest
  curl -fsSL --retry 3 --retry-delay 2 --max-time 900 --speed-limit 5000 --speed-time 30 \
    "$1" -o "$2" >> "$LOG" 2>&1
}

# ================================================================ stage 1 ====
APT_CORE_DEFAULT="build-essential pkg-config cmake ninja-build git git-lfs curl wget unzip zip
xz-utils bzip2 ca-certificates gnupg jq less file rsync bc procps psmisc lsof strace
ripgrep fd-find fzf bat tmux neovim htop tree iproute2 iputils-ping netcat-openbsd socat
dnsutils bash-completion zsh locales tzdata sudo acl attr libssl-dev libffi-dev libyaml-dev
zlib1g-dev libreadline-dev libsqlite3-dev libbz2-dev liblzma-dev libzstd-dev libxml2-dev
libxslt1-dev libgmp-dev libncurses-dev python3 python3-pip python3-venv python3-dev
shellcheck openjdk-21-jdk-headless gh openssl libatomic1 libgomp1"

# The base image strips /usr/share/{doc,man,info}; some postinst scripts
# (openjdk via update-alternatives) expect those directories to exist.
do_prepare_dirs() {
  mkdir -p /usr/share/man/man1 /usr/share/info /usr/share/doc /var/lib/dpkg/info \
           /usr/local/lib/node_modules /usr/local/bin /workspace
  mkdir -p "$HOME/.local/bin" "$HOME/.cache" "$HOME/.config"
  # an earlier run with HOME=/ scattered these into the filesystem root
  # Only directories a tool would have created are moved; /root's own files
  # (.bashrc, .profile) are ours and must never be overwritten.
  for d in .local .bun .cargo .rustup .cache .npm .deno .config; do
    [ -d "/$d" ] || continue
    if [ -d "$HOME/$d" ]; then
      cp -an "/$d/." "$HOME/$d/" 2>/dev/null; rm -rf "/${d:?}"
    else
      mv "/$d" "$HOME/$d" 2>/dev/null
    fi
  done
  if [ -f /.npmrc ]; then
    [ -f "$HOME/.npmrc" ] || cp -a /.npmrc "$HOME/.npmrc" 2>/dev/null
    rm -f /.npmrc
  fi
  # npm refuses a prefix that came from a stray project config
  if [ -f "$HOME/.npmrc" ] && grep -q '^prefix=' "$HOME/.npmrc" 2>/dev/null; then
    grep -v '^prefix=' "$HOME/.npmrc" > "$HOME/.npmrc.tmp" 2>/dev/null
    printf 'prefix=/usr/local\nfund=false\naudit=false\n' >> "$HOME/.npmrc.tmp"
    mv "$HOME/.npmrc.tmp" "$HOME/.npmrc"
    rm -f "$STEPS/lang.npm" "$STEPS/ai.npm"   # let npm config be re-applied
  fi
}

do_apt_core() {
  _list=$(list_from "$LIB/tools/apt-core.txt")
  [ -z "$_list" ] && _list="$APT_CORE_DEFAULT"
  do_prepare_dirs
  apt_install "$_list"
  dpkg --configure -a >> "$LOG" 2>&1
  return 0
}

do_locale() {
  sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
  locale-gen >/dev/null 2>&1
  update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  ln -snf /usr/share/zoneinfo/UTC /etc/localtime
  echo UTC > /etc/timezone
}

do_symlinks() {
  mkdir -p /usr/local/bin
  [ -x /usr/bin/fdfind ] && ln -sf /usr/bin/fdfind /usr/local/bin/fd
  [ -x /usr/bin/batcat ] && ln -sf /usr/bin/batcat /usr/local/bin/bat
  [ -x /usr/bin/nvim ]    && ln -sf /usr/bin/nvim    /usr/local/bin/nvim
  return 0
}

do_git_defaults() {
  git config --system init.defaultBranch main
  git config --system advice.detachedHead false
  git config --system core.longpaths true
  git config --system fetch.prune true
}

do_golang() {
  extra go || skip; return 0
  _ver=$(curl -fsSL --connect-timeout 20 --max-time 30 'https://go.dev/VERSION?m=text' 2>/dev/null | head -1)
  [ -n "$_ver" ] || { note "go: could not read the latest version"; return 0; }
  fetch "https://go.dev/dl/${_ver}.linux-arm64.tar.gz" /tmp/go.tgz || return 0
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
  printf 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"\n' > /etc/profile.d/newvm-go.sh
  chmod 644 /etc/profile.d/newvm-go.sh
}

do_extra_pkgs() {
  if ! extra java && ! extra ruby && ! extra php && ! extra elixir && ! extra db; then
    skip; return 0
  fi
  extra java   && apt_install "openjdk-21-jdk-headless"
  extra ruby   && apt_install "ruby-full"
  extra php    && apt_install "php-cli php-xml php-mbstring php-curl composer"
  extra elixir && apt_install "elixir"
  extra db     && apt_install "postgresql-client default-mysql-client redis-tools sqlite3"
  return 0
}

stage_core() {
  printf '\n%s  stage 1/3  core toolchain%s\n' "$C_B" "$C_0"
  step core.dirs     doc-man-info-dirs          -- do_prepare_dirs
  step core.apt      core-packages-and-libs      -- do_apt_core
  step core.locale   locale-and-timezone         -- do_locale
  step core.links    fd-bat-nvim-aliases         -- do_symlinks
  step core.git      git-defaults                -- do_git_defaults
  step core.extras   extra-language-packages     -- do_extra_pkgs
  step core.golang   go-toolchain                -- do_golang
}

# ================================================================ stage 2 ====
do_node() {
  _have=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
  [ -n "$_have" ] && [ "$_have" -ge 22 ] 2>/dev/null && return 0
  if curl -fsSL --max-time 90 https://deb.nodesource.com/setup_22.x -o /tmp/ns.sh; then
    sh /tmp/ns.sh -y >> "$LOG" 2>&1 && apt-get install -y -qq nodejs >> "$LOG" 2>&1
  else
    note "nodesource unreachable, trying the distro nodejs"
    apt-get install -y -qq nodejs npm >> "$LOG" 2>&1
  fi
  rm -f /tmp/ns.sh
  _v=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
  [ -n "$_v" ] || { note "node: not installed"; return 1; }
  [ "${_v:-0}" -ge 22 ] 2>/dev/null || { note "node $_v is older than the required 22"; return 1; }
  node -v >> "$LOG" 2>&1
}

do_npm_setup() {
  mkdir -p /usr/local/lib/node_modules
  npm config set prefix /usr/local
  npm config set fund false
  npm config set audit false
  npm config set update-notifier false
  npm --version >> "$LOG" 2>&1
}

do_python() {
  # Debian 13 marks the system python as externally managed (PEP 668)
  python3 -m pip install --break-system-packages -q --upgrade pip setuptools wheel >> "$LOG" 2>&1
  python3 -c 'import venv, sqlite3, ssl' >> "$LOG" 2>&1 || return 1
  return 0
}

do_uv() {
  has uv && return 0
  [ -x "$HOME/.local/bin/uv" ] && ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv && return 0
  curl -LsSf --max-time 180 https://astral.sh/uv/install.sh -o /tmp/uv.sh || return 1
  bash /tmp/uv.sh >> "$LOG" 2>&1
  rm -f /tmp/uv.sh
  [ -x "$HOME/.local/bin/uv" ] && ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
  has uv || return 1
  uv --version >> "$LOG" 2>&1
}

do_rust() {
  [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  has rustc && return 0
  curl -fsSL --connect-timeout 20 --max-time 300 https://sh.rustup.rs -o /tmp/rustup.sh || return 1
  sh /tmp/rustup.sh -y --profile minimal --no-modify-path >> "$LOG" 2>&1
  rm -f /tmp/rustup.sh
  [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  has rustc || return 1
  rustc --version >> "$LOG" 2>&1
}

do_bun() {
  has bun && return 0
  [ -x "$HOME/.bun/bin/bun" ] && ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun && return 0
  curl -fsSL --connect-timeout 20 --max-time 300 https://bun.sh/install -o /tmp/bun.sh || return 1
  bash /tmp/bun.sh >> "$LOG" 2>&1
  rm -f /tmp/bun.sh
  [ -x "$HOME/.bun/bin/bun" ] && ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
  has bun || return 1
  bun --version >> "$LOG" 2>&1
}

do_deno() {
  extra deno || skip; return 0
  has deno && return 0
  curl -fsSL --connect-timeout 20 --max-time 300 https://deno.land/install.sh -o /tmp/deno.sh || return 1
  sh /tmp/deno.sh -f -n >> "$LOG" 2>&1
  rm -f /tmp/deno.sh
  [ -x "$HOME/.deno/bin/deno" ] && ln -sf "$HOME/.deno/bin/deno" /usr/local/bin/deno
  has deno || return 1
  deno --version >> "$LOG" 2>&1
}

do_dotnet() {
  extra dotnet || skip; return 0
  has dotnet && return 0
  curl -fsSL --connect-timeout 20 --max-time 600 https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet.sh || return 1
  bash /tmp/dotnet.sh --channel 9.0 --install-dir /usr/share/dotnet >> "$LOG" 2>&1
  ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
  has dotnet || return 1
  dotnet --version >> "$LOG" 2>&1
}

stage_langs() {
  printf '\n%s  stage 2/3  language runtimes%s\n' "$C_B" "$C_0"
  step lang.home   home-and-dirs   -- do_prepare_dirs
  step lang.node   node-22-lts     -- do_node
  step lang.npm    npm-global-prep -- do_npm_setup
  step lang.python python-pip      -- do_python
  step lang.uv     uv              -- do_uv
  step lang.rust   rustup          -- do_rust
  step lang.bun    bun             -- do_bun
  step lang.deno   deno            -- do_deno
  step lang.dotnet dotnet-sdk      -- do_dotnet
}

# ================================================================ stage 3 ====
NPM_AI_DEFAULT="@openai/codex @anthropic-ai/claude-code @google/gemini-cli @github/copilot opencode-ai"

do_npm_ai() {
  _list=$(list_from "$LIB/tools/npm-ai.txt")
  [ -z "$_list" ] && _list="$NPM_AI_DEFAULT"
  _bad=0
  for p in $_list; do
    if npm install -g --silent "$p" >> "$LOG" 2>&1; then
      note "npm ok: $p"
    else
      note "npm FAILED: $p"
      _bad=$((_bad+1))
    fi
  done
  note "npm globals: $(($_bad)) failure(s)"
  return 0
}

do_uv_tools() {
  has uv || return 0
  _list=$(list_from "$LIB/tools/uv-tools.txt")
  [ -z "$_list" ] && _list="ruff llm"
  for t in $_list; do
    uv tool install --quiet "$t" >> "$LOG" 2>&1 || note "uv skipped: $t"
  done
  for t in $_list; do
    [ -e "$HOME/.local/bin/$t" ] && ln -sf "$HOME/.local/bin/$t" "/usr/local/bin/$t"
  done
  return 0
}

do_extra_clis() {
  if ! extra agents && ! extra ansible && ! extra aws && ! extra gcloud && ! extra terraform; then
    skip; return 0
  fi
  extra agents && python3 -m pip install --break-system-packages -q aider-chat >> "$LOG" 2>&1
  extra ansible && uv tool install --quiet ansible-core >> "$LOG" 2>&1
  if extra aws; then
    curl -fsSL --connect-timeout 20 --max-time 300 https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip -o /tmp/aws.zip >> "$LOG" 2>&1 \
      && python3 -c 'import zipfile; zipfile.ZipFile("/tmp/aws.zip").extractall("/tmp/aws")' \
      && sh /tmp/aws/install --update -i /usr/local/aws-cli -b /usr/local/bin >> "$LOG" 2>&1
    rm -rf /tmp/aws.zip /tmp/aws
  fi
  if extra gcloud; then
    curl -fsSL --connect-timeout 20 --max-time 600 https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm64.tar.gz -o /tmp/gcloud.tgz >> "$LOG" 2>&1 \
      && tar -C /usr/local -xzf /tmp/gcloud.tgz && ln -sf /usr/local/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud
    rm -f /tmp/gcloud.tgz
  fi
  return 0
}

do_docker() {
  if ! has docker; then
    curl -fsSL --connect-timeout 20 --max-time 300 https://download.docker.com/linux/static/stable/aarch64/docker-27.4.1.tgz -o /tmp/docker.tgz >> "$LOG" 2>&1 \
      && tar -C /tmp -xzf /tmp/docker.tgz && cp /tmp/docker/* /usr/local/bin/ 2>/dev/null
    rm -rf /tmp/docker /tmp/docker.tgz
  fi
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL --connect-timeout 20 --max-time 300 https://github.com/docker/compose/releases/download/v2.32.1/docker-compose-linux-aarch64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose >> "$LOG" 2>&1 && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  has docker || return 1
  docker --version >> "$LOG" 2>&1
}

do_k8s() {
  extra k8s || skip; return 0
  _kd=$(mktemp -d) || return 1
  _kv=$(curl -fsSL --retry 2 --connect-timeout 15 --max-time 30 https://dl.k8s.io/release/stable.txt 2>/dev/null | head -1)
  if [ -n "$_kv" ]; then
    # stage, verify it runs, then install: a truncated download must never
    # replace a working binary
    curl -fsSL --retry 2 --connect-timeout 15 --max-time 300 \
      "https://dl.k8s.io/release/$_kv/bin/linux/arm64/kubectl" -o "$_kd/kubectl" >> "$LOG" 2>&1 \
      && "$_kd/kubectl" version --client >/dev/null 2>&1 \
      && install -m0755 "$_kd/kubectl" /usr/local/bin/kubectl
  else
    note "k8s: could not resolve the stable kubectl version"
  fi
  curl -fsSL --retry 2 --connect-timeout 15 --max-time 300 https://get.helm.sh/helm-v3.17.1-linux-arm64.tar.gz \
    -o "$_kd/helm.tgz" >> "$LOG" 2>&1 \
    && tar -C "$_kd" -xzf "$_kd/helm.tgz" >> "$LOG" 2>&1 \
    && "$_kd/linux-arm64/helm" version >/dev/null 2>&1 \
    && install -m0755 "$_kd/linux-arm64/helm" /usr/local/bin/helm
  rm -rf "$_kd"
  return 0
}

# gh_asset REPO PATTERN [EXACT-ASSET...]
#   1. GitHub API: match PATTERN against the latest release's asset list
#   2. fallback: version-independent asset names via releases/latest/download
# Upstream renames these assets often, so both paths are tried.
gh_asset() {
  _repo="$1"; _pat="$2"; shift 2
  _u=$(curl -fsSL --connect-timeout 15 --max-time 45 "https://api.github.com/repos/$_repo/releases/latest" 2>/dev/null \
       | tr ',' '
' | grep -o "https://[^\"]*${_pat}[^\"]*" | head -1)
  [ -n "$_u" ] && { printf '%s' "$_u"; return 0; }
  for _cand in "$@"; do
    _c="https://github.com/$_repo/releases/latest/download/$_cand"
    curl -fsS --connect-timeout 10 --max-time 25 -r 0-0 -o /dev/null "$_c" 2>/dev/null \
      && { printf '%s' "$_c"; return 0; }
  done
  return 1
}

install_asset() { # name url [pattern-in-archive]
  has "$1" && { note "$1 already present"; return 0; }
  [ -n "$2" ] || { note "$1: no release asset matched"; return 1; }
  rm -rf /tmp/newvm-x; mkdir -p /tmp/newvm-x
  _file=${2##*/}
  _try=1
  while [ "$_try" -le 3 ]; do
    curl -fsSL --retry 2 --connect-timeout 15 --max-time 180 --speed-limit 10000 --speed-time 20 \
      "$2" -o "/tmp/newvm-x/$_file" >> "$LOG" 2>&1 && break
    note "$1: download attempt $_try failed"
    rm -rf /tmp/newvm-x; mkdir -p /tmp/newvm-x
    _try=$((_try+1))
  done
  if [ "$_try" -gt 3 ]; then note "$1: download failed"; rm -rf /tmp/newvm-x; return 1; fi
  case "$_file" in
    *.tar.gz) tar -C /tmp/newvm-x -xzf "/tmp/newvm-x/$_file" >> "$LOG" 2>&1 ;;
    *.tgz)    tar -C /tmp/newvm-x -xzf "/tmp/newvm-x/$_file" >> "$LOG" 2>&1 ;;
    *.gz)     gzip -dc "/tmp/newvm-x/$_file" > "/tmp/newvm-x/$1" 2>/dev/null ;;
    *)        cp "/tmp/newvm-x/$_file" "/tmp/newvm-x/$1" 2>/dev/null ;;
  esac
  _found=$(find /tmp/newvm-x -type f -name "$1" 2>/dev/null | head -1)
  if [ -n "$_found" ]; then
    cp "$_found" "/usr/local/bin/$1" && chmod +x "/usr/local/bin/$1"
    note "$1 installed from ${_file}"
  else
    note "$1: binary not found inside ${_file}"
    rm -rf /tmp/newvm-x
    return 1
  fi
  rm -rf /tmp/newvm-x
  return 0
}

do_shellx() {
  _bad=0
  install_asset starship "$(gh_asset starship/starship 'aarch64-unknown-linux-musl.tar.gz' starship-aarch64-unknown-linux-musl.tar.gz starship-x86_64-unknown-linux-gnu.tar.gz)" || _bad=1
  install_asset zoxide   "$(gh_asset ajeetdsouza/zoxide 'aarch64-unknown-linux-musl.tar.gz' zoxide-aarch64-unknown-linux-musl.tar.gz)" || _bad=1
  install_asset eza      "$(gh_asset eza-community/eza 'aarch64-unknown-linux-gnu.tar.gz' eza_aarch64-unknown-linux-gnu.tar.gz eza-aarch64-unknown-linux-gnu.tar.gz)" || _bad=1
  install_asset atuin    "$(gh_asset atuinsh/atuin 'aarch64-unknown-linux-gnu.tar.gz' atuin-aarch64-unknown-linux-gnu.tar.gz)" || _bad=1
  rm -rf /tmp/newvm-x
  if [ "$_bad" = "1" ]; then
    note "some shell extras were unreachable; 'new --with shellx' or newvm-with retries them later"
  fi
  return 0
}

do_browser() {
  if ! extra chromium && ! extra playwright; then skip; return 0; fi
  extra chromium && apt_install chromium
  extra playwright && has npx && npx --yes playwright@latest install --with-deps chromium >> "$LOG" 2>&1
  return 0
}

do_finish() {
  mkdir -p /etc/profile.d /root/.config /root/.local/share/newvm /workspace
  printf 'export PATH="$PATH:/root/.local/bin:/root/.cargo/bin:/root/.bun/bin:/usr/local/go/bin:/root/go/bin:$PATH"\n' \
    > /etc/profile.d/newvm.sh
  [ -f /root/.cargo/env ] && printf '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"\n' > /etc/profile.d/newvm-rust.sh
  [ -d /root/.bun/bin ] && printf 'export PATH="$PATH:$HOME/.bun/bin"\n' > /etc/profile.d/newvm-bun.sh
  [ -d /root/.deno/bin ] && printf 'export PATH="$PATH:$HOME/.deno/bin"\n' > /etc/profile.d/newvm-deno.sh
  mkdir -p /etc/profile.d
  {
    has starship && printf 'command -v starship >/dev/null && eval "$(starship init bash)"\n'
    has zoxide   && printf 'command -v zoxide   >/dev/null && eval "$(zoxide init bash)"\n'
    has atuin    && printf 'command -v atuin    >/dev/null && eval "$(atuin init)"\n'
    has eza      && printf 'alias ls="eza --icons=auto --group-directories-first"\n'
  } > /etc/profile.d/newvm-shell.sh
  chmod 644 /etc/profile.d/newvm-shell.sh
  apt-get clean >> "$LOG" 2>&1
  rm -rf /tmp/* >> "$LOG" 2>&1
  rm -rf /root/.cache/ms-playwright /var/lib/apt/lists/* >> "$LOG" 2>&1
  find "$LOGDIR" -name '*.log' -mtime +7 -delete 2>/dev/null
  npm cache clean --force >> "$LOG" 2>&1
  return 0
}

do_manifest() { bash "$LIB/manifest.sh" --write >> "$LOG" 2>&1; }

stage_ai() {
  printf '\n%s  stage 3/3  AI CLIs, container and shell tooling%s\n' "$C_B" "$C_0"
  step ai.home     home-and-dirs    -- do_prepare_dirs
  step ai.npm      agent-clis-npm   -- do_npm_ai
  step ai.uv       python-cli-tools -- do_uv_tools
  step ai.extra    extra-clis       -- do_extra_clis
  step polish.docker docker-cli-compose -- do_docker
  step polish.k8s   kubectl-helm    -- do_k8s
  step polish.shellx shell-extras    -- do_shellx
  step polish.browser browser-tools -- do_browser
  step polish.finish finalise        -- do_finish
  step polish.manifest manifest      -- do_manifest
}

run_stage() {
  case "$1" in
    1) stage_core ;;
    2) stage_langs ;;
    3) stage_ai ;;
    *) printf 'unknown stage %s\n' "$1" >&2; return 2 ;;
  esac
}

if [ "$ALL" = "1" ]; then
  printf '\n%s  building the full newvm toolchain (profile=%s extras=%s)%s\n' "$C_B" "$NEWVM_PROFILE" "$NEWVM_EXTRAS" "$C_0"
  i=1
  while [ "$i" -le 3 ]; do run_stage "$i"; i=$((i+1)); done
elif [ -n "$ARG1" ]; then
  run_stage "$ARG1"
else
  printf 'usage: provision.sh <1|2|3|--all> [--force]\n' >&2
  exit 2
fi

printf '\n'
if [ "$FAILS" -gt 0 ]; then
  printf '%s  %s step(s) failed - run "newvm-provision" inside the sandbox to retry%s\n' "$C_Y" "$FAILS" "$C_0"
  exit 1
fi
printf '%s  toolchain stage "%s" complete%s\n' "$C_G" "${ARG1:-all}" "$C_0"
exit 0