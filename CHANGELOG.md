# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-02

First public release.

### Added
- `new` boots an ephemeral Linux microVM (shuru) for any folder, 8 CPUs / 8 GB /
  100 GB by default, with a prebuilt toolchain: Codex, Claude Code, OpenCode,
  Gemini, Copilot, Node 22, Python 3.13 + uv, Rust, Bun, JDK 21, Docker, gh,
  ripgrep, fzf, neovim, tmux, zsh, starship.
- Three-stage, resumable toolchain image build (`new build`, `new build 3`).
- Sessions save themselves as a per-folder checkpoint and resume in ~0.3 s.
- `new snapshot`, `restore`, `enter`, `delete`, `clean`, `list`, `status`, `env`,
  `secrets`, `tools`, `doctor`, `logs`, `purge-auth`, `unlock`, `upgrade`.
- On-demand tool installation: `new --with <tool>` and `newvm-with` in the guest.
- API keys wired through shuru's proxy so the real values never enter the VM.
- Host agent credentials can be synced into a sandbox (`--sync-auth`, default).
- Test suite with a fake `shuru` on PATH: no VM, no network.
- `install.sh` / `uninstall.sh`, no `sudo` required.

### Security notes
- A `shuru.json` in the project folder is ignored: `new` always passes its own
  `--config`, so a cloned repository cannot redefine mounts, network policy or
  secrets.
- The shared toolchain image never receives credentials; they are applied per
  sandbox only. `new purge-auth` scrubs any that an older version left behind.
