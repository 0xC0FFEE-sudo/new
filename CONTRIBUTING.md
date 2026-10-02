# Contributing

## Development

```sh
./tests/run-tests.sh   # the test suite: fast, no VM, no network
./install.sh           # install to ~/.local/share/newvm, link ~/.local/bin/new

for f in new lib/*.sh; do bash -n "$f"; done   # syntax check
brew install shellcheck && shellcheck -S warning new lib/*.sh install.sh uninstall.sh
```

The test suite puts a fake `shuru` on `PATH` and a throwaway `HOME` in place, so
it never boots a VM and never touches your real checkpoints. **Please keep it
that way**: every behaviour worth testing should be reachable without a VM.

## Ground rules

- **macOS bash 3.2.** No associative arrays, no `mapfile`, no `${var,,}`.
  Indexed arrays (`arr+=(x)`, `${arr[@]:0:4}`) are fine.
- **The guest is Debian arm64 with `HOME` unset.** Every script under `lib/`
  sets `HOME=/root` and fixes `PATH` itself.
- **No unpinned downloads that run as root.** `apt-get` is fine (signed).
  For `curl | sh` installers, prefer the dynamic `gh_asset` resolver and keep
  the stall guard (`--speed-limit`/`--speed-time`) in place.
- **Never let a value from the project folder reach shuru's argv unquoted.**
  Builds use `"${RUN_ARGV[@]}"`.
- **Anything you copy from the host into the VM is a credential.** Keep those
  files `0600`, keep them out of the golden image, and document them in
  SECURITY.md.
- Add a test in `tests/run-tests.sh` for every behaviour you add or fix.
- This project has no automation. Nothing should be added that runs on a
  schedule, on a remote machine, or on pull requests.

## Manual verification

```sh
make install
cd ~/some/project && new            # interactive
new --cmd 'echo ok' --save never   # one-shot
new doctor                         # health check
new clean project                  # tidy up
```

Reporting bugs: open an issue. Please do not paste real tokens into one.
