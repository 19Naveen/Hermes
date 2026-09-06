#!/usr/bin/env bash
# hermes self-checks — run: ./test.sh
set -euo pipefail
cd "$(dirname "$0")"

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" HERMES_REPO="$SANDBOX/repo"
mkdir -p "$HOME/.config"

# shellcheck source=/dev/null
for f in common discover backup install extra sync; do source "lib/$f.sh"; done

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
