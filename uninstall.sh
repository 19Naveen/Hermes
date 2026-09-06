#!/usr/bin/env bash
# hermes uninstaller — removes the tool; your dotfiles repo is opt-in.
#
#   curl -fsSL https://raw.githubusercontent.com/19Naveen/Hermes/master/uninstall.sh | bash
set -euo pipefail

BIN="$HOME/.local/bin/hermes"
SHARE_DIR="$HOME/.local/share/hermes"
REPO="${HERMES_REPO:-$HOME/.hermes-repo}"
ZSH_COMP="$HOME/.zsh/completions/_hermes"

say()  { printf '\033[1;35m⚡\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ⚠ %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] && { echo "don't run as root" >&2; exit 1; }

confirm_tty() { # confirm <question> — works even when piped
  local ans
  printf '\033[1;35m⚡\033[0m %s [y/N] ' "$1"
  read -r ans < /dev/tty 2>/dev/null || return 1
  [[ $ans =~ ^[Yy] ]]
}

say "Uninstalling hermes…"

rm -f  "$BIN"      && ok "removed $BIN"
rm -rf "$SHARE_DIR" && ok "removed $SHARE_DIR"
rm -f  "$ZSH_COMP" && ok "removed $ZSH_COMP"

# strip only the exact two lines setup.sh adds — the old broad patterns deleted
# any line mentioning .zsh/completions or .local/bin, including the user's own
for rc in ~/.zshrc ~/.bashrc; do
  [[ -f $rc ]] || continue
  if grep -qE '^fpath=\(~/\.zsh/completions \$fpath\)$|^export PATH="'"$HOME"'/\.local/bin:\$PATH"$' "$rc"; then
    sed -i.hermes-bak -e '/^fpath=(~\/\.zsh\/completions \$fpath)$/d' \
                      -e '\|^export PATH="'"$HOME"'/\.local/bin:\$PATH"$|d' "$rc" \
      && rm -f "$rc.hermes-bak"
    ok "cleaned $rc"
  fi
done

if [[ -d $REPO ]]; then
  # count what's actually in there (excluding .git)
  local_n=$(find "$REPO/configs" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
  secrets_n=$(find "$REPO/secrets" -name '*.gpg' 2>/dev/null | wc -l)
  echo
  warn "Found your backup repo: $REPO ($local_n configs, $secrets_n encrypted secrets)"
  warn "If a remote is configured, everything already lives on GitHub too."
  git -C "$REPO" config hermes.remote >/dev/null 2>&1 \
    && echo "     remote: $(git -C "$REPO" config hermes.remote)"
  if confirm_tty "Delete $REPO permanently?"; then
    rm -rf "$REPO" && ok "deleted $REPO"
  else
    ok "kept $REPO (delete manually anytime)"
  fi
fi

echo
ok "hermes removed. Thanks for trying it ⚡"
