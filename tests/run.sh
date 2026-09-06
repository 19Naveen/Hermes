#!/usr/bin/env bash
# hermes self-checks — run: tests/run.sh
#
# Runs against a throwaway $HOME and $HERMES_REPO, and without gum, so it never
# touches real configs and keeps the no-gum path honest.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" HERMES_REPO="$SANDBOX/repo"
mkdir -p "$HOME/.config"

# shellcheck source=/dev/null
for f in common discover backup install extra sync; do source "$ROOT/lib/$f.sh"; done

# --- _row_name: BOTH picker markers must be stripped ------------------------
# a name left as "  zshrc" matches no discovered item and the backup silently
# copies nothing.
check_name() {
  local got; got=$(_row_name "$1")
  [[ $got == "$2" ]] || { echo "FAIL: _row_name ${1@Q} -> ${got@Q}, want ${2@Q}" >&2; exit 1; }
}
check_name "✓ zshrc · /home/me/.zshrc (4KB)"        "zshrc"
check_name "  zshrc · /home/me/.zshrc (4KB)"        "zshrc"
check_name "  Code Cache · /x (1MB)"                "Code Cache"
check_name "nvim · in sync   · → /home/me/.config/nvim (70KB)" "nvim"
echo "ok: _row_name strips both ✓ and blank markers"

# --- store → install round trip ---------------------------------------------
# A one-file DIRECTORY must come back as a directory. The old heuristic keyed on
# "the repo dir holds exactly one file" and replaced ~/.config/hypr with a FILE.
ensure_repo
excludes=()
# shellcheck disable=SC2034  # read by _store_config through dynamic scope
mapfile -t excludes < <(build_excludes)

mkdir -p "$HOME/.config/hypr"
echo 'monitor=eDP-1' > "$HOME/.config/hypr/hyprland.conf"
printf 'export A=1\n' > "$HOME/.zshrc"
items=(); while IFS= read -r l; do items+=("$l"); done < <(discover)

_store_config hypr  "$HOME/.config/hypr"
_store_config zshrc "$HOME/.zshrc"

same_config hypr  || { echo "FAIL: hypr should read as in sync" >&2; exit 1; }
same_config zshrc || { echo "FAIL: zshrc should read as in sync (file vs stored dir)" >&2; exit 1; }

rm -rf "$HOME/.config/hypr" "$HOME/.zshrc"
place_config hypr  >/dev/null
place_config zshrc >/dev/null

[[ -d $HOME/.config/hypr ]] || { echo "FAIL: one-file dir restored as a file" >&2; exit 1; }
[[ -f $HOME/.config/hypr/hyprland.conf ]] || { echo "FAIL: hypr contents missing" >&2; exit 1; }
[[ -f $HOME/.zshrc ]] || { echo "FAIL: zshrc not restored as a file" >&2; exit 1; }
grep -q 'export A=1' "$HOME/.zshrc" || { echo "FAIL: zshrc contents wrong" >&2; exit 1; }

echo 'changed' >> "$HOME/.zshrc"
same_config zshrc && { echo "FAIL: modified zshrc still reads as in sync" >&2; exit 1; }
echo "ok: store/install round trip keeps dirs as dirs and files as files"

# --- summary helpers --------------------------------------------------------
[[ $(plural 1 config) == "1 config"  ]] || { echo "FAIL: plural 1"  >&2; exit 1; }
[[ $(plural 2 config) == "2 configs" ]] || { echo "FAIL: plural 2"  >&2; exit 1; }
[[ $(plural 0 config) == "0 configs" ]] || { echo "FAIL: plural 0"  >&2; exit 1; }
for u in "git@github.com:19Naveen/dotfiles.git" \
         "https://github.com/19Naveen/dotfiles.git" \
         "https://TOKEN@github.com/19Naveen/dotfiles"; do
  [[ $(_repo_slug "$u") == "19Naveen/dotfiles" ]] \
    || { echo "FAIL: _repo_slug ${u@Q} -> $(_repo_slug "$u")" >&2; exit 1; }
done
[[ $(_repo_slug "ssh://git@gitlab.com/team/cfg.git") == "team/cfg" ]] \
  || { echo "FAIL: _repo_slug non-github" >&2; exit 1; }
echo "ok: summary helpers (plural, repo slug across url forms)"

# --- dangling symlinks and excluded junk are not differences ----------------
# diff -rq follows symlinks and exits 2 when the target is missing, which the
# old same_config read as DIFFERS. ~/.config/hypr is 138 links into a package
# that may not be installed, so it could never read as in sync.
mkdir -p "$HOME/.config/withlinks"
echo 'real' > "$HOME/.config/withlinks/real.conf"
ln -s /definitely/not/here/target.glsl "$HOME/.config/withlinks/dangling.glsl"
items=(); while IFS= read -r l; do items+=("$l"); done < <(discover)
_store_config withlinks "$HOME/.config/withlinks"

[[ -L $HERMES_REPO/configs/withlinks/dangling.glsl ]] \
  || { echo "FAIL: symlink not stored as a symlink" >&2; exit 1; }
same_config withlinks \
  || { echo "FAIL: dangling symlink reported as a difference" >&2; exit 1; }

# junk the backup excludes must not count as a difference either
mkdir -p "$HOME/.config/withlinks/node_modules/pkg"
echo 'junk' > "$HOME/.config/withlinks/node_modules/pkg/index.js"
same_config withlinks \
  || { echo "FAIL: excluded node_modules reported as a difference" >&2; exit 1; }

# a real edit still must register
echo 'changed' >> "$HOME/.config/withlinks/real.conf"
same_config withlinks \
  && { echo "FAIL: real content change reported as in sync" >&2; exit 1; }
echo "ok: same_config ignores dangling symlinks and excluded junk, catches real edits"

# --- push_latest actually commits ------------------------------------------
# It used to run inside `gum spin -- bash -c`, where dotfiles_url was not an
# exported function, so it died with "command not found" and every backup left
# the files uncommitted. With no remote set it must still commit locally.
before=$(git -C "$HERMES_REPO" rev-list --count HEAD)
push_latest "test-config" >/dev/null 2>&1
after=$(git -C "$HERMES_REPO" rev-list --count HEAD)
(( after == before + 1 )) || { echo "FAIL: push_latest made no commit ($before -> $after)" >&2; exit 1; }
git -C "$HERMES_REPO" log -1 --format=%s | grep -q 'test-config' \
  || { echo "FAIL: commit message lost the config list" >&2; exit 1; }
[[ -z $(git -C "$HERMES_REPO" status --porcelain) ]] \
  || { echo "FAIL: files left uncommitted after push_latest" >&2; exit 1; }
echo "ok: push_latest commits locally even with no remote configured"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
p="$tmp/pipe"; mkfifo "$p"

# writer keeps the fifo open so reads don't hit EOF immediately
exec 9<>"$p"
printf '\e[?2026;2$y\e[?2027;1$y' >&9

_hermes_drain "$p"

leftover=""
IFS= read -rsn 256 -t 0.05 leftover <"$p" 2>/dev/null || true
[[ -z $leftover ]] || { echo "FAIL: ${#leftover} bytes left undrained: ${leftover@Q}" >&2; exit 1; }
echo "ok: drain consumed the DECRQM replies"
