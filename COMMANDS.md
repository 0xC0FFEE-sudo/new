# `new` — complete command reference

Everything `new` can do, every flag, every setting, and every command you get
inside the sandbox.

- [The 30-second version](#the-30-second-version)
- [Install](#install)
- [Commands](#commands)
- [Flags](#flags)
- [Settings](#settings)
- [Secrets](#secrets)
- [Inside the sandbox](#inside-the-sandbox)
- [Extra tools](#extra-tools)
- [How it works](#how-it-works)
- [Exit codes](#exit-codes)
- [Troubleshooting](#troubleshooting)

---

## The 30-second version

```sh
brew tap superhq-ai/tap && brew install shuru   # once
git clone https://github.com/0xC0FFEE-sudo/new.git && cd new && ./install.sh

cd ~/your/project
new          # boots the sandbox
...work...
exit         # saves it

new          # next time: back in 0.3s
```

The first `new` builds the toolchain image and takes 10–30 minutes. Every `new`
after that takes about 0.3 seconds.

---

## Install

```sh
./install.sh
```

What it does:

| | |
|---|---|
| copies the program to | `~/.local/share/newvm/` |
| creates the launcher | `~/.local/bin/new` |
| seeds your settings | `~/.config/newvm/config.env` |
| seeds the secrets file | `~/.config/newvm/secrets.conf` (only if missing — never overwritten) |
| needs `sudo` | no |

If `~/.local/bin` is not on your `PATH`, the installer prints the exact line to
add to your `~/.zshrc`.

Requirements: macOS 14+ on Apple Silicon, and `shuru` installed. Confirm with:

```sh
new doctor
```

Remove it later:

```sh
./uninstall.sh            # program and settings (asks first)
./uninstall.sh --images   # also delete the sandbox images
```

---

## Commands

`new COMMAND` does something without booting a VM. `new` on its own boots one.

### Starting a session

| Command | What it does |
|---|---|
| `new` | Boot a sandbox for the current folder, resume the saved one if there is one |
| `new DIR` | Same, for another folder |
| `new --cmd "CMD"` | Run one command and leave instead of opening a shell |
| `new shell` | Explicitly the same as `new` |
| `new run -- CMD` | Shortcut for `new --cmd CMD` |
| `new enter` | Go back into this folder's sandbox |
| `new enter NAME` | Go inside a named checkpoint and write your changes back to it |
| `new restore NAME` | Open a checkpoint read-only; nothing is saved |

### Saving and restoring

| Command | What it does |
|---|---|
| `new snapshot` | Instant named copy of this folder's sandbox (`snap-20261002-143012`) |
| `new snapshot NAME` | Same, with a name you choose |
| `new delete` | Delete this folder's sandbox |
| `new delete NAME` | Delete a named checkpoint |

Snapshots are free: they are APFS clones, so they cost no extra space until you
change them.

### Images

| Command | What it does |
|---|---|
| `new build` | Build the toolchain image now (instead of on first use) |
| `new build N` | Build only up to stage N (1, 2 or 3) |
| `new rebuild` | Throw the image away and build it again |
| `new rebuild N` | Keep stages 1–N and rebuild from N+1 |
| `new upgrade` | Upgrade `shuru`, then tell you if the image needs rebuilding |

`--rebuild-base` is the same as `new rebuild`.

### Housekeeping

| Command | What it does |
|---|---|
| `new list` | Every image and sandbox, with sizes |
| `new status` | What would happen if you typed `new` right now |
| `new clean project` | Forget this folder's sandbox |
| `new clean stages` | Delete the build stages, keep the finished image |
| `new clean base` | Delete the toolchain image (next `new` rebuilds it) |
| `new clean cache` | Remove build logs and leftovers from crashed VMs |
| `new clean all` | Remove every `new` checkpoint |
| `new unlock` | Clear a lock left behind by a crashed session |

`new delete` and `new clean project` are the same thing.

### Information

| Command | What it does |
|---|---|
| `new --help` / `new help` | The full option list |
| `new --version` | Version of `new` and `shuru` |
| `new doctor` | Health check: host, image, tools, secrets |
| `new env` | Every resolved setting, one per line |
| `new secrets` | Which API keys are wired in and whether they are set |
| `new tools` | The list of tools `--with` can install |
| `new logs [N]` | Tail the last build log (default 100 lines) |
| `new purge-auth` | Remove copied credentials from every checkpoint |

`new --help`, `new --version` and `new doctor` all work even when `shuru` is not
installed.

Any of these work after flags too: `new --memory 16384 env` is the same as
`new env --memory 16384`.

---

## Flags

### Resources

| Flag | Default | Notes |
|---|---|---|
| `-m`, `--memory MB` | `8192` | RAM for the sandbox |
| `-c`, `--cpus N` | `min(8, your cores)` | Processor cores |
| `-d`, `--disk MB` | `102400` | Logical disk. Sparse: about 5 GB is really used |

```sh
new --memory 16384 --cpus 12 --disk 204800
```

### Session

| Flag | Notes |
|---|---|
| `--cmd "CMD"` | Run a command instead of a shell. Everything after it is joined |
| `--shell NAME` | Shell to start: `bash` (default) or `zsh` |
| `--save MODE` | `auto` (default), `always`, `never` |
| `--no-save`, `--ephemeral` | Same as `--save never` |
| `--save-always` | Same as `--save always` |
| `--fresh` | Ignore the saved sandbox and start clean |
| `-n`, `--name NAME` | Name the checkpoint for this project |
| `--from NAME` | Boot from a specific checkpoint |
| `--with TOOL` | Install a tool at session start. Repeatable |
| `--profile core\|full` | Recorded in the image build; `full` is the default |

`auto` means: save, unless you explicitly asked not to. A folder that has never
had a sandbox yet gets one saved on first exit.

### Filesystem

| Flag | What happens |
|---|---|
| *(default)* | Mount the folder read-only; guest writes go to a RAM scratch area and are discarded on exit |
| `--rw` | Mount read-write: guest writes land in the real folder |
| `--isolated` | Same as the default, said explicitly |
| `--no-mount` | No host folder at all; `/workspace` is empty |

`--rw` gives the sandbox write access to your project. With network access and
agent tooling running, that is effectively code execution against your working
tree. See `SECURITY.md`.

### Network

| Flag | Notes |
|---|---|
| *(default)* | Network on |
| `--no-net` | No network device at all |
| `--net-hosts a,b,c` | Only these domains are reachable |
| `--ports 3000,8080:80` | Forward host ports into the sandbox |
| `--secret N=ENV@hosts` | Wire a host environment variable through the proxy. Repeatable |
| `--no-secrets` | Wire no keys at all |
| `--allow-net` | Passed through to `shuru` (it is on by default) |

Port mapping: `--ports 3000` means host `3000` → guest `3000`. `--ports 8080:80`
means host `8080` → guest `80`. Then open `http://localhost:8080` on your Mac.

### Images and credentials

| Flag | Notes |
|---|---|
| `--rebuild-base` | Rebuild the toolchain image |
| `--no-build` | Fail instead of building a missing image |
| `--sync-auth` | Copy host agent logins into the sandbox (default) |
| `--no-sync-auth` | Do not copy host credentials |
| `--extras a,b` | Tool groups to bake into the image |
| `--base NAME` | Use a different image name |

### Anything else

| Flag | Notes |
|---|---|
| `--unlock` | Clear a stale lock |
| `--no-color` | Plain output |
| `-- CMD` | Everything after `--` is the command to run in the sandbox |
| `-h`, `--help` | Help |
| `-V`, `--version` | Version |

Unknown options are passed to `shuru` with a warning, so `new -v` (verbose
kernel output) works.

---

## Settings

Your settings live in `~/.config/newvm/config.env`. Edit them, then run `new`
again — they apply to the next session.

```sh
NEW_MEM=8192
NEW_CPUS=
NEW_DISK=102400
NEW_MOUNT=ro
NEW_SAVE=auto
NEW_BASE=newvm-base
NEW_PROFILE=full
NEW_EXTRAS=
NEW_NET=on
NEW_HOSTS=
NEW_PORTS=
NEW_SECRETS=on
NEW_SYNC_AUTH=1
NEW_SYNC_GITCONFIG=1
NEW_SYNC_SSH=0
NEW_SHELL=bash
```

| Setting | Values | Meaning |
|---|---|---|
| `NEW_MEM` | MB | RAM per sandbox |
| `NEW_CPUS` | number, or empty | Cores; empty means min(8, your core count) |
| `NEW_DISK` | MB | Logical disk size |
| `NEW_MOUNT` | `ro` `rw` `none` | `ro` = RAM scratch, `rw` = write through to the host |
| `NEW_SAVE` | `auto` `always` `never` | Whether sessions save on exit |
| `NEW_BASE` | name | Which image to boot |
| `NEW_PROFILE` | `core` `full` | Recorded in the image build |
| `NEW_EXTRAS` | comma list | Tool groups baked into the image |
| `NEW_NET` | `on` `off` | Network device |
| `NEW_HOSTS` | comma list | Allowed domains |
| `NEW_PORTS` | comma list | Port forwards |
| `NEW_SECRETS` | `on` `off` | Wire host API keys into the sandbox |
| `NEW_SYNC_AUTH` | `0` `1` | Copy agent login files into the sandbox |
| `NEW_SYNC_GITCONFIG` | `0` `1` | Copy `~/.gitconfig` |
| `NEW_SYNC_SSH` | `0` `1` | Copy `~/.ssh/id_*` (off by default) |
| `NEW_SHELL` | name | Shell to start |

Precedence: **environment variable → `~/.config/newvm/config.env` → built-in
default**. A flag on the command line beats all of them.

```sh
NEW_MEM=16384 new          # just this once
```

Check what resolved:

```sh
new env
```

---

## Secrets

Two separate mechanisms.

### API keys stay on your Mac

`new` reads a mapping from `~/.config/newvm/secrets.conf`:

```
# NAME_IN_VM=HOST_ENV_VAR@host1,host2
OPENAI_API_KEY=OPENAI_API_KEY@api.openai.com
```

If `OPENAI_API_KEY` is exported in your shell and that mapping exists, `new`
tells `shuru` about it. Inside the sandbox the agent sees a placeholder like
`shuru_tok_1a2b…`, and the proxy swaps in the real value on HTTPS requests to
`api.openai.com`. The key never enters the virtual machine and is never written
to disk inside it.

Built-in mappings (present unless you delete them):

```
OPENAI_API_KEY        → api.openai.com
ANTHROPIC_API_KEY     → api.anthropic.com
CLAUDE_CODE_OAUTH_TOKEN → api.anthropic.com
GEMINI_API_KEY        → generativelanguage.googleapis.com, aistudio.googleapis.com
GOOGLE_API_KEY        → generativelanguage.googleapis.com
XAI_API_KEY           → api.x.ai
GROQ_API_KEY          → api.groq.com
OPENROUTER_API_KEY    → openrouter.ai
MISTRAL_API_KEY       → api.mistral.ai
DEEPSEEK_API_KEY      → api.deepseek.com
TOGETHER_API_KEY      → api.together.xyz
PERPLEXITY_API_KEY    → api.perplexity.ai
COHERE_API_KEY        → api.cohere.ai
FIREWORKS_API_KEY     → api.fireworks.ai
GITHUB_TOKEN          → api.github.com, github.com, codeload…, raw.githubusercontent…
GH_TOKEN              → api.github.com, github.com, codeload…, raw.githubusercontent…
NPM_TOKEN             → registry.npmjs.org
DOCKERHUB_TOKEN       → registry-1.docker.io, auth.docker.io
```

Only keys that are actually set get wired in. Add your own by appending lines
to `~/.config/newvm/secrets.conf`.

```sh
new secrets                 # what is set
new --no-secrets            # this once
```

### Agent logins are copied in

By default `new` copies these host files into the sandbox so `codex` and
`claude` are already logged in:

```
~/.claude/.credentials.json     ~/.codex/auth.json
~/.claude/settings.json         ~/.codex/config.toml
~/.gemini/oauth_creds.json      ~/.local/share/opencode/auth.json
~/.config/gh/hosts.yml          ~/.gitconfig
~/.ssh/id_*                     (only with NEW_SYNC_SSH=1)
```

They are written into that project's sandbox file on your Mac at mode `0600`.
The shared toolchain image never contains them.

```sh
new --no-sync-auth          # this once
NEW_SYNC_AUTH=0             # turn it off for good
new purge-auth              # strip them from sandboxes that already exist
```

Full details in `SECURITY.md`.

---

## Inside the sandbox

### Commands you get

| Command | What it does |
|---|---|
| `newvm-doctor` | System info plus a table of tool versions |
| `newvm-manifest` | The full inventory of what is installed |
| `newvm-with TOOL` | Install another tool now. No argument lists them |
| `newvm-apt install PKG` | `apt-get install` with the index update done for you |
| `newvm-provision` | Re-run the toolchain builder (idempotent) |
| `newvm-rebuild` | Re-run it ignoring the sentinels, from scratch |
| `newvm-info` | Which session am I in (shell function) |
| `newvm-help` | This list (shell function) |
| `ncodex` | `codex` with its own sandbox disabled — you are already inside one |
| `vmexit` | Alias for `exit` |

`newvm-apt` also handles `remove`, `purge`, `update` and `upgrade`.

### Layout inside

| Path | What |
|---|---|
| `/workspace` | Your project folder, as mounted |
| `/root` | Home. Holds your agent logins, `~/.codex`, `~/.claude`, `~/.config` |
| `/usr/local/lib/newvm/` | The toolchain builder, tool installer and inventory scripts |
| `/usr/local/bin/newvm-*` | The commands above |
| `/var/lib/newvm/steps/` | Sentinels: which build steps already ran |
| `/var/lib/newvm/recipe` | Which version of the host's toolchain this image matches |
| `/var/log/newvm/` | Provisioning logs from inside the sandbox |

---

## Extra tools

Anything not in the base image can be added when you need it. The install is
remembered in that sandbox.

```sh
new --with rust
new --with playwright
new --with kubernetes
new --with rust --with go       # repeatable
new tools                       # the list
```

| Tool | Installs |
|---|---|
| `docker` | Docker CLI, containerd, runc, compose plugin |
| `k8s` | kubectl, helm |
| `rust` | rustup and the Rust toolchain |
| `bun` / `deno` | Bun / Deno |
| `dotnet` | .NET SDK 9 |
| `go` | Latest Go toolchain |
| `java` | OpenJDK 21 |
| `php` | PHP CLI, composer |
| `ruby` | Ruby, full |
| `elixir` | Elixir and Erlang |
| `terraform` | Terraform 1.10 |
| `chromium` | Chromium and its driver |
| `playwright` | Playwright with Chromium |
| `postgres` / `mysql` / `redis` | Database clients |
| `aws` | AWS CLI v2 |
| `gcloud` | Google Cloud CLI |
| `ansible` | ansible-core |
| `shellx` | starship, zoxide, eza, atuin |
| `tools` | shfmt, hadolint, just, yq, sd, age, sops, direnv, lazygit, bottom, delta |

### Baked into the image instead

These are installed while the toolchain image is built. To include them:

```sh
new --extras k8s,java,ruby,go,deno,dotnet,db,php,elixir,playwright,chromium,agents,aws,gcloud,terraform,ansible
```

Then rebuild so the change takes effect:

```sh
new rebuild
```

Extra names: `agents` installs aider, `db` installs the database clients.

### Edit the package lists yourself

```
tools/apt-core.txt     everything stage 1 installs
tools/npm-ai.txt       the agent CLIs
tools/uv-tools.txt      Python CLI tools
```

Edit, then `new rebuild`.

---

## How it works

Four separate layers. Knowing which one you are changing avoids surprises.

**1. The toolchain image** (`newvm-base`, about 5 GB)
Built once, in three stages, each saved as its own checkpoint so a failed
download does not cost the stages before it:

| Stage | Installs |
|---|---|
| 1 | apt packages, build-essential, git, gh, ripgrep, fzf, bat, neovim, tmux, zsh, JDK 21, python3 |
| 2 | Node 22, uv, Rust, Bun |
| 3 | codex, claude, opencode, gemini, copilot, Docker + compose, starship, zoxide, eza, atuin, ruff, llm |

Sessions never modify this image.

**2. The sandbox disk**
A throwaway clone made on every boot. Changes are discarded unless the session
saves a checkpoint on exit, which is the default.

**3. `/workspace`**
Read-only by default, with guest writes going to a RAM scratch area that
disappears on exit. `--rw` writes straight through to the host folder.

**4. Checkpoints on disk**
One roughly 5 GB file per project folder, plus a one-deep rollback copy while a
session is running. `new list` shows them; `new clean` removes them.

`new --ephemeral` discards layer 2 only. It does not delete the image or any
saved checkpoint.

### Session life

```
new                      boots a clone of the image, mounts this folder
...                      work, install, run agents
exit                     the sandbox saves itself as a checkpoint
new                      boots that checkpoint again, ~0.3s
new --fresh              ignores it, starts from the image again
```

### What a `shuru.json` in your project does

Nothing. `new` always passes its own `--config`, so a `shuru.json` in a cloned
repository cannot change your mounts, network policy or secrets.

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Runtime failure — build failed, VM failed, checkpoint missing |
| `2` | Usage error — bad flag, missing directory, invalid value |

```sh
new --save bogus; echo $?      # 2
```

---

## Troubleshooting

**`new: command not found`**
`~/.local/bin` is not on your PATH:
```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```
Or use the full path: `~/.local/bin/new`.

**`shuru not found`**
```sh
brew tap superhq-ai/tap && brew install shuru
```

**`another session is already running`**
Either another `new` really is open, or a crashed one left the lock:
```sh
new unlock
```

**`the toolchain image is not ready`**
The build failed. Read the last lines, fix, run `new` again — it resumes at the
stage that failed:
```sh
new logs 100
```

**`another'new' is already on your PATH`**
The command name is short and collides. Either use the other one, or alias:
```sh
alias newvm='new'
```

**Disk space**
Each sandbox is a separate file of roughly 5 GB:
```sh
shuru checkpoint list     # see them all
new clean all             # remove every one of them
```

**`recipe changed - run new rebuild`**
You edited the toolchain builder or the package lists. The old image still
works; rebuild when convenient.

**Checking everything at once**
```sh
new doctor
```

**Starting over completely**
```sh
new clean all       # all sandboxes
new clean base      # the toolchain image too (rebuilds on next use, 10-30 min)
```