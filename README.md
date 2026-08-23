# ⚡ Hermes

One-script config backup & restore with a fuzzy picker UI.
Back up your Linux/macOS configs to **your own private git repo**, restore
them on any machine in minutes. No config language, no daemons — just bash,
git and gum.

> The tool is public. Your dotfiles stay in YOUR private repo.

## Why?

Copying `~/.config` wholesale into git doesn't work — half of it is caches,
binaries and build output. Hermes tracks only what's needed to reproduce your
setup (configs, lockfiles, skills) and skips everything reproducible:
`node_modules`, Rust `target/`, plugin downloads, logs…

Your nvim config is ~70KB; its plugins are ~700MB. You only need the first one.

## Requirements

- Linux or macOS
- `git`, `rsync`, `gpg`
- [`gum`](https://github.com/charmbracelet/gum) (picker UI)
- an SSH key on GitHub ([add one](https://github.com/settings/keys))

## Quickstart

**1. Create your dotfiles repo**

On GitHub: [github.com/new](https://github.com/new) → name it e.g. `dotfiles`
→ set **Private** → don't initialize with README.

**2. Install hermes**

```bash
curl -fsSL https://raw.githubusercontent.com/19Naveen/Hermes/master/setup.sh | bash
```

Setup checks dependencies, installs the binary + libs, adds PATH and zsh
completions, then asks for **your** dotfiles repo URL and verifies your SSH
access before using it (`git ls-remote` auth check).

**3. Back up**

```bash
hermes backup
```

A picker lists every config found on your system with its size. Toggle with
`space`/`x`, select-all with `ctrl+a`, type to fuzzy-search, `enter` to
confirm. Selected configs are copied into `~/.hermes-repo` and pushed.

**4. Restore on any machine**

```bash
hermes install
```

Same picker, showing each item's status: `new` / `in sync` / `DIFFERS`.
Pick only what that machine needs — per-machine selectivity is the point.

## Commands

| Command                | What it does                                    |
|------------------------|--------------------------------------------------|
| `hermes backup`        | pick installed configs → commit & push          |
| `hermes install`       | pick stored configs → install locally           |
| `hermes list`          | show what's in the backup repo                  |
| `hermes remote <url>`  | set + verify your private dotfiles repo         |
| `hermes secret <file>` | passphrase-encrypt a file into the repo         |
| `hermes update`        | update hermes from this repo                    |
| `hermes completion`    | print zsh completions                           |

## Features

### Smart junk filtering

Sizes in the picker guide you: **KB** = ideal · **MB** = judgment call ·
**GB** = app data with its own sync — leave it out.
Built-in ignore list strips `node_modules`, `target/`, `.git`, caches, logs
and build outputs from anything you back up.

### Alternates (per-machine variants)

Name any file with a condition suffix; on install the matching variant
replaces the base file, non-matching ones are removed:

```
hyprland.conf##host=work-laptop   # only that hostname
kitty.conf##os=Darwin             # only macOS
```

### Encrypted secrets

```bash
hermes secret ~/.ssh/id_ed25519
```

Symmetric GPG (passphrase, no key server). Secrets land in
`repo/secrets/*.gpg`; installing asks per-file consent and restores with
`chmod 600`. Never commit unencrypted private keys.

### Bootstrap

Keep an executable `~/.config/hermes/bootstrap.sh` (it gets backed up like
any config). After every `hermes install`, hermes offers to run it — package
lists, symlink setup, whatever you script.

## Customizing

Don't edit the lib (updates overwrite it). Hermes reads two user files:

**`~/.config/hermes/extras`** — extra paths outside `~/.config`,
one `name|$HOME/path` per line:

```
tmux-conf|$HOME/.tmux.conf
cargo|$HOME/.cargo/config.toml
notes|$HOME/Documents/notes
```

**`~/.config/hermes/ignore`** — extra junk patterns, one per line.

Both survive `hermes update`.

## Security model

- Your configs go **only** to the private repo you configure — nothing else
- Remote is verified at setup and on every operation; broken SSH fails loudly
- Secrets are encrypted at rest in the repo, decrypted only after consent
- No telemetry; network access = git push/pull to your repo + GitHub for updates

## License

MIT
