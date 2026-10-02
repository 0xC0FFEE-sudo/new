#!/usr/bin/env bash
# with.sh - on-demand tool installers, run inside a newvm sandbox.
#
#   newvm-with docker k8s        install now (idempotent, downloads are resumed
#                                by the checkpoint when the session is saved)
#
# TOOLS: docker k8s rust bun deno dotnet go java php ruby elixir terraform chromium playwright postgres mysql redis aws gcloud ansible shellx tools

# The host reads this line to list the available --with tools.

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
export HOME=/root USER=root LOGNAME=root
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"

LIB=/usr/local/lib/newvm
LOGDIR=/var/log/newvm
mkdir -p "$LOGDIR" 2>/dev/null
mkdir -p /var/lib/newvm/with 2>/dev/null

cyan=$(printf '\033[36m'); green=$(printf '\033[32m'); red=$(printf '\033[31m')
dim=$(printf '\033[2m'); off=$(printf '\033[0m')
[ -t 1 ] || { cyan=""; green=""; red=""; dim=""; off=""; }

ALL_TOOLS="docker k8s rust bun deno dotnet go java php ruby elixir terraform chromium
           playwright postgres mysql redis aws gcloud ansible shellx tools"

name_of() {
  case "$1" in
    docker)     echo docker ;;
    k8s|kube)   echo k8s ;;
    rust)       echo rust ;;
    bun)        echo bun ;;
    deno)       echo deno ;;
    dotnet)     echo dotnet ;;
    go|golang)  echo go ;;
    java|jdk)   echo java ;;
    php)        echo php ;;
    ruby)       echo ruby ;;
    elixir)     echo elixir ;;
    terraform)  echo terraform ;;
    chromium)   echo chromium ;;
    playwright) echo playwright ;;
    postgres)   echo postgres ;;
    mysql)      echo mysql ;;
    redis)      echo redis ;;
    aws)        echo aws ;;
    gcloud)     echo gcloud ;;
    ansible)    echo ansible ;;
    shellx)     echo shellx ;;
    tools)      echo tools ;;
    *)          echo "" ;;
  esac
}

log()   { printf '  %s%s%s\n' "$dim" "$*" "$off"; }
note()  { printf '  %s%s%s\n' "$dim" "$*" "$off"; }

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

# Downloads get a stall guard: abort if throughput drops under 5 KB/s for 30s so
# a dead proxy connection cannot look like a hang.
CURL_OPTS="-fsSL --retry 2 --retry-delay 3 --connect-timeout 15 --max-time 240 --speed-limit 10000 --speed-time 20"

install_asset() { # name url
  command -v "$1" >/dev/null 2>&1 && { note "$1 already present"; return 0; }
  if [ -z "$2" ]; then printf '  %s%s: no release asset matched%s\n' "$red" "$1" "$off"; return 1; fi
  rm -rf /tmp/newvm-x; mkdir -p /tmp/newvm-x
  _f=${2##*/}
  _try=1
  while [ "$_try" -le 3 ]; do
    curl $CURL_OPTS "$2" -o "/tmp/newvm-x/$_f" && break
    printf '  %s%s: download attempt %s failed, retrying%s\n' "$dim" "$1" "$_try" "$off"
    rm -rf /tmp/newvm-x; mkdir -p /tmp/newvm-x
    _try=$((_try+1))
  done
  if [ "$_try" -gt 3 ]; then
    printf '  %s%s: download failed%s\n' "$red" "$1" "$off"; rm -rf /tmp/newvm-x; return 1
  fi
  case "$_f" in
    *.tar.gz|*.tgz) tar -C /tmp/newvm-x -xzf "/tmp/newvm-x/$_f" 2>/dev/null ;;
    *.gz)           gzip -dc "/tmp/newvm-x/$_f" > "/tmp/newvm-x/$1" 2>/dev/null ;;
    *)              cp "/tmp/newvm-x/$_f" "/tmp/newvm-x/$1" 2>/dev/null ;;
  esac
  _p=$(find /tmp/newvm-x -type f -name "$1" 2>/dev/null | head -1)
  if [ -z "$_p" ]; then
    printf '  %s%s: not found inside %s%s\n' "$red" "$1" "$_f" "$off"; rm -rf /tmp/newvm-x; return 1
  fi
  if cp "$_p" /usr/local/bin/"$1" && chmod +x /usr/local/bin/"$1"; then
    rm -rf /tmp/newvm-x
    printf '  %s%s installed%s\n' "$green" "$1" "$off"; return 0
  fi
  printf '  %s%s: could not write /usr/local/bin/%s%s\n' "$red" "$1" "$1" "$off"
  rm -rf /tmp/newvm-x; return 1
}
fetch() { curl -fsSL --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 600 --speed-limit 8000 --speed-time 25 "$1" -o "$2"; }
have()  { command -v "$1" >/dev/null 2>&1; }
aptq()  { apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq --no-install-recommends "$@" >/dev/null 2>&1; }

install_tool() {
  case "$1" in
    docker)
      aptq containerd runc || true
      _dd=$(mktemp -d) || return 1
      if ! have docker; then
        fetch https://download.docker.com/linux/static/stable/aarch64/docker-27.4.1.tgz "$_dd/d.tgz" \
          && tar -C "$_dd" -xzf "$_dd/d.tgz" && cp "$_dd"/docker/* /usr/local/bin/ 2>/dev/null
      fi
      mkdir -p /usr/local/lib/docker/cli-plugins
      if ! [ -x /usr/local/lib/docker/cli-plugins/docker-compose ]; then
        fetch https://github.com/docker/compose/releases/download/v2.32.1/docker-compose-linux-aarch64 "$_dd/compose" \
          && install -m0755 "$_dd/compose" /usr/local/lib/docker/cli-plugins/docker-compose
      fi
      rm -rf "$_dd"
      ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null
      have docker || return 1
      [ -x /usr/local/lib/docker/cli-plugins/docker-compose ] || { printf '  %sdocker: compose plugin missing%s\n' "$red" "$off"; return 1; }
      return 0 ;;
    k8s)
      _kv=$(curl -fsSL --connect-timeout 20 --max-time 30 https://dl.k8s.io/release/stable.txt)
      fetch "https://dl.k8s.io/release/$_kv/bin/linux/arm64/kubectl" /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
      fetch https://get.helm.sh/helm-v3.17.1-linux-arm64.tar.gz /tmp/h.tgz \
        && tar -C /tmp -xzf /tmp/h.tgz && cp /tmp/linux-arm64/helm /usr/local/bin/helm && rm -rf /tmp/h.tgz /tmp/linux-arm64
      have kubectl && have helm ;;
    rust)
      [ -f /tmp/rustup.sh ] || fetch https://sh.rustup.rs /tmp/rustup.sh
      sh /tmp/rustup.sh -y --profile minimal --no-modify-path
      [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
      have rustc ;;
    bun)
      [ -f /tmp/bun.sh ] || fetch https://bun.sh/install /tmp/bun.sh
      bash /tmp/bun.sh
      [ -x "$HOME/.bun/bin/bun" ] && ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
      have bun ;;
    deno)
      [ -f /tmp/deno.sh ] || fetch https://deno.land/install.sh /tmp/deno.sh
      sh /tmp/deno.sh -y
      [ -x "$HOME/.deno/bin/deno" ] && ln -sf "$HOME/.deno/bin/deno" /usr/local/bin/deno
      have deno ;;
    dotnet)
      [ -f /tmp/dotnet.sh ] || fetch https://dot.net/v1/dotnet-install.sh /tmp/dotnet.sh
      sh /tmp/dotnet.sh --channel 9.0 --install-dir /usr/share/dotnet
      ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
      have dotnet ;;
    go)
      _v=$(curl -fsSL --connect-timeout 20 --max-time 30 'https://go.dev/VERSION?m=text' | head -1)
      [ -n "$_v" ] || return 1
      _d=$(mktemp -d) || return 1
      fetch "https://go.dev/dl/${_v}.linux-arm64.tar.gz" "$_d/go.tgz" || { rm -rf "$_d"; return 1; }
      tar -tzf "$_d/go.tgz" >/dev/null 2>&1 || { printf '  %sgo: corrupt download%s\n' "$red" "$off"; rm -rf "$_d"; return 1; }
      # unpack beside the old install and swap only once the new tree is whole
      rm -rf /usr/local/go.new
      tar -C /usr/local -xzf "$_d/go.tgz" && mv /usr/local/go /usr/local/go.old 2>/dev/null \
        && mv /usr/local/go /usr/local/go.new && rm -rf /usr/local/go.old || { rm -rf "$_d" /usr/local/go.new; return 1; }
      rm -rf "$_d"
      ln -sf /usr/local/go/bin/go /usr/local/bin/go; ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
      have go ;;
    java)    aptq openjdk-21-jdk-headless && have java ;;
    php)     aptq php-cli php-xml php-mbstring php-curl composer && have php ;;
    ruby)    aptq ruby-full && have ruby ;;
    elixir)  aptq elixir && have elixir ;;
    terraform)
      fetch https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_arm64.zip /tmp/tf.zip \
        && python3 -c 'import zipfile;zipfile.ZipFile("/tmp/tf.zip").extractall("/usr/local/bin")' \
        && chmod +x /usr/local/bin/terraform && have terraform ;;
    chromium)
      aptq chromium chromium-driver && (have chromium || have chromium-browser) ;;
    playwright)
      have npx || { log "node is required for playwright"; return 1; }
      npx --yes playwright@latest install --with-deps chromium
      npx --yes playwright@latest install-deps || true
      mkdir -p /usr/local/lib/node_modules && npm install -g --silent playwright 2>/dev/null
      have playwright || have npx ;;
    postgres) aptq postgresql-client && have psql ;;
    mysql)    aptq default-mysql-client && have mysql ;;
    redis)    aptq redis-tools && have redis-cli ;;
    aws)
      [ -f /tmp/aws.zip ] || fetch https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip /tmp/aws.zip
      python3 -c 'import zipfile;zipfile.ZipFile("/tmp/aws.zip").extractall("/tmp/aws")'
      sh /tmp/aws/install --update -i /usr/local/aws-cli -b /usr/local/bin
      have aws ;;
    gcloud)
      [ -f /tmp/gcloud.tgz ] || fetch https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm64.tar.gz /tmp/gcloud.tgz
      tar -C /usr/local -xzf /tmp/gcloud.tgz
      ln -sf /usr/local/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud
      have gcloud ;;
    ansible)
      have uv || { log "uv is missing (it ships with the base image)"; return 1; }
      uv tool install ansible-core
      [ -e "$HOME/.local/bin/ansible" ] && ln -sf "$HOME/.local/bin/ansible" /usr/local/bin/ansible
      have ansible ;;
    shellx)
      _bad=0
      install_asset starship "$(gh_asset starship/starship 'aarch64-unknown-linux-musl.tar.gz' starship-aarch64-unknown-linux-musl.tar.gz starship-x86_64-unknown-linux-gnu.tar.gz)" || _bad=1
      install_asset zoxide   "$(gh_asset ajeetdsouza/zoxide 'aarch64-unknown-linux-musl.tar.gz' zoxide-aarch64-unknown-linux-musl.tar.gz)" || _bad=1
      install_asset eza      "$(gh_asset eza-community/eza 'aarch64-unknown-linux-gnu.tar.gz' eza_aarch64-unknown-linux-gnu.tar.gz eza-aarch64-unknown-linux-gnu.tar.gz)" || _bad=1
      install_asset atuin    "$(gh_asset atuinsh/atuin 'aarch64-unknown-linux-gnu.tar.gz' atuin-aarch64-unknown-linux-gnu.tar.gz)" || _bad=1
      [ "$_bad" = "1" ] && log "some shell extras were unreachable - run 'newvm-with shellx' again to retry"
      return 0 ;;
    tools)
      have gh        || log "gh not found - install it with: newvm-apt install gh"
      have shellcheck|| aptq shellcheck
      have shfmt     || (install_asset shfmt "$(gh_asset mvdan/sh 'linux_arm64' shfmt_v3.10.0_linux_arm64)")
      have hadolint  || (install_asset hadolint "$(gh_asset hadolint/hadolint 'Linux-arm64' hadolint-Linux-arm64)")
      have just      || (install_asset just "$(gh_asset casey/just 'aarch64-unknown-linux-musl' just-1.40.0-aarch64-unknown-linux-musl)")
      have yq        || (install_asset yq "$(gh_asset mikefarah/yq 'linux_arm64' yq_linux_arm64)")
      have sd        || (install_asset sd "$(gh_asset chmln/sd 'linux-arm64' sd-1.0.0-linux-arm64)")
      have age       || (fetch https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-arm64.tar.gz /tmp/age.tgz && tar -C /usr/local/bin -xzf /tmp/age.tgz age && chmod +x /usr/local/bin/age && rm -f /tmp/age.tgz)
      have sops      || (install_asset sops "$(gh_asset getsops/sops 'linux.arm64' sops-v3.10.1.linux.arm64)")
      have direnv    || (fetch https://github.com/direnv/direnv/releases/download/v2.35.0/direnv.linux-arm64 /usr/local/bin/direnv && chmod +x /usr/local/bin/direnv)
      have lazygit   || (install_asset lazygit "$(gh_asset jesseduffield/lazygit 'Linux_arm64.tar.gz' lazygit_0.44.1_Linux_arm64.tar.gz)")
      have bottom    || (install_asset bottom "$(gh_asset ClementTsang/bottom 'x86_64-unknown-linux-gnu.tar.gz' bottom-aarch64-unknown-linux-gnu.tar.gz)")
      have delta     || (install_asset delta "$(gh_asset dandavison/delta 'aarch64-unknown-linux-gnu.tar.gz' delta-0.18.2-aarch64-unknown-linux-gnu.tar.gz)")
      return 0 ;;
    *) return 2 ;;
  esac
}

list_tools() {
  printf '  %s' "$cyan"
  printf '%s' "$ALL_TOOLS" | tr -s ' \n' ' '
  printf '%s\n' "$off"
}

if [ $# -eq 0 ]; then
  printf '\n  usage: newvm-with <tool> [tool...]\n\n  available:\n'
  list_tools
  printf '\n'
  exit 0
fi

rc=0
for arg in "$@"; do
  tool=$(name_of "$arg")
  if [ -z "$tool" ]; then
    printf '  %sunknown tool: %s%s\n' "$red" "$arg" "$off"
    rc=1
    continue
  fi
  if [ -f "/var/lib/newvm/with/$tool.done" ]; then
    printf '  %s%s already installed%s\n' "$dim" "$tool" "$off"
    continue
  fi
  printf '  %s-> %s%s\n' "$cyan" "$tool" "$off"
  _log="$LOGDIR/with-$tool.log"
  if install_tool "$tool" >> "$_log" 2>&1; then
    touch "/var/lib/newvm/with/$tool.done"
    printf '  %s   %s ready%s\n' "$green" "$tool" "$off"
  else
    printf '  %s   %s failed (log: %s)%s\n' "$red" "$tool" "$_log" "$off"
    rc=1
  fi
done
exit $rc