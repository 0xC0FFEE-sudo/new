# Security

`new` runs a Linux microVM on your Mac and, by default, copies a small number of
credential files from your host into it. This document describes exactly what
crosses that boundary and what stays put. It is meant to be read before you
enable the credential syncing on a shared machine.

## TL;DR

| Thing | Enters the VM? | Stored on disk? |
|---|---|---|
| API keys you export (`OPENAI_API_KEY`, …) | **No** — a placeholder goes in; shuru's proxy substitutes the value per request | No |
| Agent login files (`~/.codex/auth.json`, …) | **Yes, by default** | Yes — inside the sandbox checkpoint image, mode `0600` |
| `~/.gitconfig` | Yes (opt-out: `NEW_SYNC_GITCONFIG=0`) | Yes |
| `~/.ssh/id_*` | Only with `NEW_SYNC_SSH=1` (default off) | Yes, mode `0600` |
| Anything else on your host | No | No |

## The proxy mechanism

`new --secret NAME=ENV_VAR@host` (and the built-in list, editable in
`~/.config/newvm/secrets.conf`) passes **only a name and a host** to shuru. The
guest receives a 30-byte placeholder token; the proxy substitutes the real value
from the host environment when it forwards an HTTPS request to a listed host.
The real value is never placed in guest memory or on guest disk.

Substitution applies to the request line and header values only. Request bodies
are streamed untouched.

## What is copied into the sandbox

With `NEW_SYNC_AUTH=1` (the default) these files are packed into a payload,
carried into the guest, and written into `/root`:

```
~/.claude/.credentials.json          ~/.codex/auth.json
~/.claude/settings.json              ~/.codex/config.toml
~/.gemini/oauth_creds.json           ~/.local/share/opencode/auth.json
~/.config/gh/hosts.yml               ~/.gitconfig
~/.ssh/id_*                          (only when NEW_SYNC_SSH=1)
```

Inside the guest they are mode `0600` under a mode `0700` `/root`.

**They are written into the sandbox's checkpoint image**, which lives in
`~/.local/share/shuru/checkpoints/`. Anything that can read your home directory —
a backup agent, a cloud-sync folder, another local user on a multi-user Mac —
can read them. That is the same trust boundary as the credential files you
already have in your home directory, but it is worth being deliberate about.

The shared toolchain image (`newvm-base`) never contains credentials. If one was
staged there by an older version, `new purge-auth` rewrites every checkpoint with
the credential files removed.

### Reducing exposure

```sh
new --no-sync-auth            # per session
NEW_SYNC_AUTH=0               # in ~/.config/newvm/config.env
NEW_SYNC_SSH=0                # keep SSH keys out (already the default)
NEW_SYNC_GITCONFIG=0          # keep ~/.gitconfig out
new purge-auth                # scrub credentials from existing images
new clean all                # delete every newvm checkpoint
```

## Other security-relevant behaviour

- **A `shuru.json` in your project folder is ignored.** `new` always passes its
  own `--config`. Without that, a cloned repository containing a `shuru.json`
  could redefine mounts, network restrictions, or inject a secret sourced from
  an arbitrary host environment variable and forwarded to an arbitrary host.
- **`/root/.codex/config.toml` is appended to** with
  `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`, because
  Codex would otherwise try to nest its own sandbox inside the VM. If the file
  already contains `sandbox_mode`, it is left alone.
- **`new --rw` grants the guest write access to your project folder.** Combined
  with network access and agent tooling, that is effectively code execution
  against your working tree. The default (`NEW_MOUNT=ro`) mounts the folder
  read-only with writes going to a RAM overlay that is discarded on exit.
- **Downloads are not checksum-verified.** The toolchain builder runs
  `apt-get` (which verifies Debian's own signatures) and then `curl | sh` for the
  rustup, Bun, Deno, .NET and NodeSource installers, plus release archives
  resolved from the GitHub API. All over HTTPS, but there is no signature or
  hash pinning. Downloads use stall detection and retries, and are staged
  before being installed, so a truncated download cannot be mistaken for a good
  one.
- **A project-local `shuru.json` cannot change mounts**, but a malicious
  `.envrc`/`direnv` file inside a project you mount read-write *is* sourced by
  an interactive shell in the guest if `direnv` is installed. That is direnv's
  model, not this project's.
- **`~/.config/newvm/secrets.conf` is parsed with `eval`** to read host
  environment variables. It is your own file; do not accept one you did not
  write.

## Reporting a vulnerability

Open a GitHub issue describing the problem and its impact. Please do not include
real tokens or keys — a redacted reproduction is all we need.