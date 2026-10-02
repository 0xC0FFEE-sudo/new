#!/usr/bin/env bash
# manifest.sh - inventory of the sandbox toolchain. Runs inside the guest.
export HOME=/root
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:/usr/local/go/bin:$PATH"
#   newvm-manifest          print the table
#   manifest.sh --write     also store it in /var/lib/newvm/manifest.txt

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; off=$'\033[0m'
[ -t 1 ] || { bold=""; dim=""; green=""; red=""; off=""; }

row() { # group command label
  _label="$1"; shift
  _have=0
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then
      _have=1
      _v=$("$c" --version 2>/dev/null | head -1 | cut -c1-60)
      [ -z "$_v" ] && _v=$(command -v "$c")
      printf '  %-10s %-16s %s%s%s\n' "$_label" "$c" "$dim" "$_v" "$off"
      return 0
    fi
  done
  [ "$_have" = "1" ] || printf '  %-10s %-16s %snot installed%s\n' "$_label" "$*" "$red" "$off"
}

if [ "${1:-}" = "--write" ]; then
  exec > /var/lib/newvm/manifest.txt
fi

printf '\n%s  newvm sandbox manifest%s  (built %s)\n\n' "$bold" "$off" "$(cat /var/lib/newvm/build.conf /newvm-build/build.conf 2>/dev/null | sed -n 's/^NEWVM_BUILT=//p' | head -1)"
printf '  %-10s %-16s %s\n' "GROUP" "TOOL" "VERSION" 2>/dev/null

printf '\n'
row shell bash;      row shell zsh;       row shell sh
printf '\n'
row core git;        row core curl;      row core jq;       row core rg
row core fzf;        row core bat;       row core fd;       row core tmux
row core nvim;       row core htop;      row core tree;     row core gh
printf '\n'
row build gcc;       row build g++;      row build make;    row build cmake
row build ninja;     row build cargo;    row build rustc;   row build pkg-config
printf '\n'
row node node;       row node npm;       row node bun;      row node deno
printf '\n'
row python python3;  row python pip;      row python uv;     row python ruff
printf '\n'
row go go;           row java java;      row dotnet dotnet
printf '\n'
row agent codex;     row agent claude;   row agent gemini
row agent copilot;   row agent opencode; row agent aider
printf '\n'
row docker docker;   row k8s kubectl;   row k8s helm
printf '\n'
row shellx starship; row shellx zoxide;  row shellx eza;    row shellx atuin
printf '\n'
row tools ruff;      row tools llm;      row tools ansible; row tools aws
row tools age;       row tools sops;     row tools yq;      row tools lazygit
printf '\n'
row extra chromium;  row extra php;      row extra ruby;    row extra elixir
row extra psql;      row extra mysql;    row extra redis-cli; row extra terraform

printf '\n'
printf '  %sstep sentinels: %s%s\n' "$dim" "$(ls /var/lib/newvm/steps 2>/dev/null | wc -l | tr -d ' ')" "$off"
printf '  %simage recipe:   %s%s\n' "$dim" "$(cat /var/lib/newvm/recipe 2>/dev/null || echo unknown)" "$off"
printf '  %scredential snapshot: %s%s\n' "$dim" "$(cat /var/lib/newvm/auth 2>/dev/null || echo none)" "$off"
printf '\n'