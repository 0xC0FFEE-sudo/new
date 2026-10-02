# new

**Type one word. Get a complete Linux dev machine that throws itself away when you're done.**

```
cd ~/code/my-app
new
```

That's it. Your project folder opens inside a real Linux virtual machine with
every tool you need already installed. Nothing gets installed on your Mac, and
nothing you do can break your Mac.

When you're finished, type `exit`. The machine saves itself. Type `new` again
later and you're back where you left off — in under a second.

---

## Install

You need two things: Homebrew, and a small helper called `shuru` (this project
uses it to run virtual machines).

```sh
brew tap superhq-ai/tap && brew install shuru
```

Then install `new`:

```sh
git clone https://github.com/0xC0FFEE-sudo/new.git
cd new
./install.sh
```

`install.sh` does not need `sudo`. It puts the program in
`~/.local/share/newvm`, links `new` into `~/.local/bin`, and creates your own
settings file at `~/.config/newvm/config.env`.

Check it worked:

```sh
new --version
```

If `new` says "command not found", your `~/.local/bin` folder is not on your
PATH. The installer prints the exact line to add.

---

## First run takes a while

The very first `new` downloads a big toolchain and sets it up. It takes about
**10 to 30 minutes**, and it uses roughly **5 GB** of disk.

That happens **once**. After that every session starts in about **0.3 seconds**.

If you don't want to wait for it, do it ahead of time:

```sh
new build          # builds it, then stops
```

If it fails halfway, just run `new` again. It picks up where it stopped.

---

## Using it

```sh
cd ~/your/project
new
```

You land in a normal shell. Everything works like you expect:

```sh
codex              # AI coding agent
claude             # AI coding agent
opencode           # AI coding agent
npm install
python script.py
git status
```

Leave with `exit`. Come back with `new`. That's the whole idea.

### Things you might want

| What you want | Type |
|---|---|
| Let the sandbox write into your project folder | `new --rw` |
| Scratch space, your folder stays untouched | `new` (default) |
| Start completely over | `new --fresh` |
| Throw the session away when you exit | `new --ephemeral` |
| Run one command and leave | `new --cmd 'codex exec "write tests"'` |
| Add another tool | `new --with kubernetes` |
| See a dev server from your browser | `new --ports 3000` |
| Open a different project | `new ~/code/other-project` |
| Save a point in time | `new snapshot before-refactor` |
| Go back to that point | `new restore before-refactor` |

### Looking around

```sh
new list        # what sandboxes and images exist
new status      # what would happen if I typed new right now
new doctor      # is everything healthy?
new tools       # the list of extra tools you can add
```

Inside the sandbox you also get:

```sh
newvm-doctor      # what is installed, with versions
newvm-manifest    # the full inventory
newvm-with rust   # add a tool right now
newvm-apt install cowsay   # install a package
```

---

## What's in the machine

Every session already has:

**AI coding agents** — codex, claude, opencode, gemini, copilot

**Languages** — Node 22, Python 3.13, uv, Rust, Bun, Java 21, Go (on demand)

**Build tools** — gcc, g++, make, cmake, ninja, cargo

**Everyday tools** — git, gh, curl, jq, ripgrep, fd, fzf, bat, neovim, tmux, htop, tree, zsh, starship, zoxide, eza, atuin

**Containers** — docker and docker compose

Extra tools you can add when you need them:

```sh
new --with kubernetes
new --with playwright
new --with rust
new --with postgres
new tools          # see them all
```

---

## How the "throwaway" part actually works

There are four separate things going on. Knowing which one you are changing
saves surprises.

**1. The toolchain image** (`newvm-base`, ~5 GB)
Built once. Sessions never change it. Deleting it means a rebuild.

**2. The machine you work in**
Created fresh every time. Anything you install inside it is thrown away unless
the session is saved on exit, which is the default.

**3. Your project folder**
By default it is mounted read-only, and anything the sandbox writes goes into a
scratch area in memory that disappears when you exit. Your Mac is never touched.
Use `--rw` if you want the sandbox to write straight into the folder.

**4. Saved sandboxes on disk**
One ~5 GB file per project folder. This is what makes the next `new` instant.

If you want to be tidy:

```sh
new clean project   # forget this folder's sandbox
new clean all       # remove everything
new list            # see what's there
```

---

## Settings

Your settings live in `~/.config/newvm/config.env`. The most useful ones:

```sh
NEW_MEM=8192        # memory per sandbox
NEW_CPUS=8          # processor cores per sandbox
NEW_DISK=102400     # disk size (sparse: uses about 5 GB, not 100 GB)
NEW_MOUNT=ro        # ro = scratch space, rw = write to the real folder
NEW_SYNC_AUTH=1     # keep codex/claude logged in inside the sandbox
```

Change it, then run `new` again. It applies to the next session.

---

## About your API keys and logins

Two different things, and it is worth being clear about both.

**API keys stay on your Mac.** If you have `OPENAI_API_KEY` in your shell, `new`
hands it to `shuru`'s network proxy. Inside the virtual machine the agent only
sees a random placeholder, and the real key is swapped in at the moment a request
goes out. The key never enters the machine and is never written to disk inside it.

**Agent logins are copied in.** By default `new` copies your existing sign-in
files (`~/.codex/auth.json`, `~/.claude/.credentials.json`, and similar) into
the sandbox so codex and claude are already logged in. These are real login
tokens. They live inside the sandbox file on your Mac, readable by you and by
anything that backs up your home folder.

If that is not what you want:

```sh
new --no-sync-auth          # this once
NEW_SYNC_AUTH=0             # or turn it off for good, in config.env
new purge-auth              # remove them from sandboxes that already exist
```

The shared toolchain image never contains them.

Full details, including what happens with `--rw` and how downloads are verified,
are in [SECURITY.md](SECURITY.md).

---

## Uninstalling

```sh
cd new
./uninstall.sh              # asks first
./uninstall.sh --images     # also delete the sandbox images
```

It leaves `shuru` installed, since that is a separate project.

---

## Every command

Full reference for every command, flag, setting and troubleshooting case:
[COMMANDS.md](COMMANDS.md).

## Working on the code

```sh
./tests/run-tests.sh    # 103 checks, about a second, no VM, no network
./install.sh            # install to ~/.local/share/newvm
```

The tests put a fake `shuru` on the PATH, so they never start a virtual machine
and never download anything. Please keep it that way.

`CONTRIBUTING.md` has the details.

---

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

`new` is not made by, or affiliated with, the makers of shuru. It just calls it.