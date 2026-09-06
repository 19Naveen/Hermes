# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

Hermes is a pure-bash dotfiles backup/restore CLI. No build step. Dependencies are `git`, `rsync`,
`gpg`, and [`gum`](https://github.com/charmbracelet/gum) for the interactive pickers only —
everything else degrades to plain text when gum is absent.

## Commands

```bash
./tests/run.sh                       # self-checks (row parsing, store/install round trip, tty drain)
bash -n hermes setup.sh uninstall.sh lib/*.sh tests/*.sh    # syntax check everything
shellcheck -S warning hermes setup.sh uninstall.sh lib/*.sh tests/*.sh   # see note below
./setup.sh                      # install from a local checkout (detects it and skips the git clone)
HERMES_LIB=./lib ./hermes browse # run the working tree directly, without installing
HERMES_REPO=/tmp/hermes-test HERMES_LIB=./lib ./hermes backup  # sandbox away from ~/.hermes-repo
```

**Match CI's shellcheck version or you will chase ghosts.** CI pins it in
`.github/workflows/ci.yml` (`SHELLCHECK_VERSION`); releases disagree about which warnings to emit —
0.9.0 flags SC2120 on `_hermes_drain`, 0.11.0 does not. A distro package is whatever it happens to
be. `npx --yes shellcheck` pulls the latest, which may not be the pin.

`tests/run.sh` runs against a throwaway `$HOME` and `$HERMES_REPO`, so it never touches real configs.
The interactive flows (`backup`/`install`/`sync`) need a TTY and are not covered — verify those by
hand with `HERMES_REPO` pointed at a scratch dir.

## Two repos, never confuse them

- **This repo** (public, `TOOL_REPO` in `lib/common.sh`) — the tool. `hermes update` re-clones it.
- **`$HERMES_REPO`** (default `~/.hermes-repo`, private, user-owned) — the *data*: `configs/<name>/`,
  `secrets/*.gpg` + `*.dest`. Its remote URL lives in git config key `hermes.remote`, **not** in
  `origin` — `pull_latest`/`push_latest` re-add `origin` from that key on every call.

## Architecture

`hermes` is an argv dispatcher only; it sources `lib/{common,discover,backup,install,extra,sync}.sh`
from `$HERMES_LIB`, else `../share/hermes/lib` (installed layout), else `./lib`. Every subcommand is
a `do_*` function.

- **`lib/common.sh`** — `REPO`, output helpers (`die`/`ok`/`warn` are plain printf; `banner`/
  `summary` use gum when present), the `gum` wrapper + tty handling, `_row_name`, `ensure_repo`,
  URL normalization + `check_auth`, `pull_latest`/`push_latest`.
- **`lib/discover.sh`** — the single source of truth for *what is trackable*: every child of
  `~/.config`, plus `SPECIALS` (`name|$HOME/path`, `$HOME` kept literal) merged with the user's
  `~/.config/hermes/extras`. `dest_for <name>` is the inverse map (name → install path);
  `build_excludes` emits rsync `--exclude=` from `IGNORES` + `~/.config/hermes/ignore`.
  `resolve_alternates` implements the yadm-style `file##host=x` / `file##os=Darwin` suffixes,
  applied to the *installed* tree after rsync.
- **`lib/backup.sh` / `install.sh` / `sync.sh`** — the three flows share one shape:
  `discover` → build gum-filter rows → `_row_name` the chosen row → store or place.
  `sync.sh` is the two-way reconcile: local newest-file mtime vs. the repo's last commit time for
  `configs/<name>` (`_local_mt` / `_cloud_ct`), newer wins, ties go local.
- **`lib/extra.sh`** — `do_remote`, `do_update`, `do_completion` (heredoc'd zsh compdef), `usage`.

Shared across flows — change once, every flow gets it:

| helper | in | used by |
|---|---|---|
| `_row_name` | `common.sh` | backup, install (strips **both** the `✓ ` and `  ` row markers) |
| `_store_config` / `_local_path` / `_union_names` | `sync.sh` | backup, sync, browse |
| `place_config` / `same_config` / `_stored_file` | `install.sh` | install, sync, browse |
| `install_secrets` / `run_bootstrap` | `install.sh` | install, sync |

**A single-file config is stored as `configs/<name>/<basename of dest>`, not as a bare file.**
`_stored_file` is the only thing that decides file-vs-tree; do not re-derive it from "the repo dir
holds exactly one file" — that installs a one-file *directory* as a file and destroys it.

## Conventions and traps

- Rows in the pickers are `[marker]name · … (size)` and are parsed back by `_row_name`. Route every
  new row parse through it; the markers are easy to forget and a stale one silently matches nothing.
- **`set -e` is on everywhere.** A helper whose "not found" answer is a false `[[ ]]` returns 1, and
  `x=$(helper)` then aborts the whole run. End such helpers with an explicit `return 0`.
- `ok`/`warn`/`die`/`banner`/`summary` must work **without gum** — CI runs `tests/run.sh` before gum is
  installed, precisely to keep that true. Only the interactive Bubble Tea subcommands may require
  it, and the `gum` wrapper dies with an install hint when they do. Check for the binary with
  `type -P gum` (`_have_gum`), never `command -v gum` — `gum` is also the name of the wrapper
  function, and `command -v` finds that instead.
- `gum spin` execs its argument as an external process, so anything it calls must be in the
  `export -f` list at the bottom of `lib/common.sh`. Pass data positionally
  (`bash -c 'f "$1"' _ "$val"`), never interpolated into the command string.
- `gum` is shadowed by a shell function in `common.sh`. For the Bubble Tea subcommands only
  (`spin`/`filter`/`confirm`/…) it sets `stty -echo` first, then drains after. Two distinct problems:
  Bubble Tea probes the terminal (DECRQM `\e[?2026$p`) and exits before the reply lands, so the
  reply is (a) echoed to the screen by the tty and (b) left in the input buffer for the next prompt.
  `stty -echo` kills the echo, `_hermes_drain` clears the buffer. Note `read -t 0` only *tests* for
  input and never consumes it — draining needs `-n <count>` with a real timeout.
- Adding a subcommand means four edits: the `case` in `hermes`, the `do_*` function, the `cmds`
  array in `do_completion`, and `usage`.
- Users are told not to edit `lib/` (updates overwrite it); user-facing extension points are
  `~/.config/hermes/{extras,ignore,bootstrap.sh}` only. `extras` is parsed by substitution, never
  `eval` — it is a user-editable file.
- Portability: prefer GNU with a BSD fallback (`find -printf` → `stat -f`, `date -d` → `date -r`),
  and use `sed -i.bak … && rm -f *.bak`, the one in-place form both seds accept. macOS is untested.
