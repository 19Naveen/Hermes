#!/usr/bin/env bash
# hermes installer — https://github.com/19Naveen/Hermes
#
#   curl -fsSL https://raw.githubusercontent.com/19Naveen/Hermes/master/setup.sh | bash
#
# Installs the tool, then walks you through YOUR private dotfiles repo:
# ask url → verify SSH access → clone (or init) → done.
set -euo pipefail

TOOL_REPO="https://github.com/19Naveen/Hermes"
BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share/hermes"
REPO="$HOME/.hermes-repo"

say()  { printf '\033[1;35m⚡\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ⚠ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m ✖ %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "don't run as root — install as your user"

# --- locate source (repo checkout or download) -----------------------------
SRC=""
if [[ "$(basename "$0")" == "setup.sh" && -f "$(dirname "$0")/hermes" ]]; then
  SRC="$(cd "$(dirname "$0")" && pwd)"
else
  say "Downloading hermes…"
  SRC="$(mktemp -d)"
  trap 'rm -rf "$SRC"' EXIT
  git clone -q --depth 1 "$TOOL_REPO" "$SRC" || die "download failed — check your internet"
fi

# --- dependencies -----------------------------------------------------------
missing=()
for dep in git rsync gpg gum; do
  command -v "$dep" >/dev/null || missing+=("$dep")
done
if ((${#missing[@]})); then
  say "Missing dependencies: ${missing[*]}"
  echo "  Debian/Ubuntu: sudo apt install git rsync gnupg"
  echo "    gum:         curl -fsSL https://github.com/charmbracelet/gum/releases/latest/download/gum_Linux_x86_64.tar.gz | tar xz -C /tmp && sudo install -m755 /tmp/gum_*/gum /usr/local/bin/gum"
  echo "  Fedora/RHEL:   sudo dnf install git rsync gnupg  (+ gum from charm releases)"
  echo "  Arch:          sudo pacman -S git rsync gnupg gum"
  die "install these and re-run setup"
fi
ok "dependencies present"

# --- install binary + lib ---------------------------------------------------
mkdir -p "$BIN_DIR" "$SHARE_DIR"
install -m 755 "$SRC/hermes" "$BIN_DIR/hermes"
rm -rf "$SHARE_DIR/lib" && cp -r "$SRC/lib" "$SHARE_DIR/lib"
export PATH="$BIN_DIR:$PATH"
ok "installed $BIN_DIR/hermes"

# --- PATH --------------------------------------------------------------------
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR" && ! grep -qs 'local/bin' ~/.zshrc ~/.bashrc 2>/dev/null; then
  for rc in ~/.zshrc ~/.bashrc; do
    [[ -f $rc ]] && ! grep -qs '.local/bin' "$rc" && { echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$rc"; ok "added PATH to $rc"; }
  done
fi

# --- zsh completions ----------------------------------------------------------
mkdir -p ~/.zsh/completions
"$BIN_DIR/hermes" completion > ~/.zsh/completions/_hermes
if [[ -f ~/.zshrc ]] && ! grep -qs '.zsh/completions' ~/.zshrc; then
  if grep -q 'compinit' ~/.zshrc; then
    sed -i 's|^\(.*compinit.*\)$|fpath=(~/.zsh/completions $fpath)\n\1|' ~/.zshrc
  else
    echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
  fi
fi
ok "zsh completions installed"

# --- dotfiles repo: ask → verify → clone/init ----------------------------------
DOTFILES_URL="${HERMES_DOTFILES:-}"
ask_url() {
  printf '\033[1;35m⚡\033[0m git url of YOUR private dotfiles repo\n   (e.g. git@github.com:YOU/dotfiles.git — created via github.com/new, keep it Private): '
  read -r DOTFILES_URL < /dev/tty || DOTFILES_URL=""
}
[[ -n ${DOTFILES_URL// } ]] || ask_url

mkdir -p "$REPO/configs"
while [[ -n ${DOTFILES_URL// } ]] && ! git ls-remote "$DOTFILES_URL" HEAD >/dev/null 2>&1; do
  warn "cannot access $DOTFILES_URL"
  echo "  · does the repo exist on GitHub?"
  echo "  · is your SSH key added? https://github.com/settings/keys"
  echo "  · test it:            ssh -T git@github.com"
  printf 'Try another url (or empty to set up later): '
  read -r DOTFILES_URL < /dev/tty || DOTFILES_URL=""
done

if [[ -n ${DOTFILES_URL// } ]]; then
  git -C "$REPO" config hermes.remote "$DOTFILES_URL"
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && [[ $(ls -A "$REPO" | grep -vc '^\.') -gt 2 ]]; then
    # existing repo with content — pull instead of clobbering
    git -C "$REPO" remote remove origin 2>/dev/null || true
    git -C "$REPO" remote add origin "$DOTFILES_URL"
    git -C "$REPO" pull -q origin HEAD 2>/dev/null || warn "pull failed — run 'git -C $REPO pull origin HEAD' manually"
    ok "linked existing backup repo to $DOTFILES_URL"
  elif [[ $REPO/.git/exists ]] 2>/dev/null || git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && [[ -n $(git -C "$REPO" log --oneline -1 2>/dev/null) ]]; then
    git -C "$REPO" push -q origin HEAD 2>/dev/null && ok "pushed local backups to $DOTFILES_URL" ||
      warn "couldn't push existing local backups — run: git -C $REPO push origin HEAD"
  else
    say "Cloning your dotfiles…"
    rm -rf "$REPO"
    git clone -q "$DOTFILES_URL" "$REPO" || die "clone failed unexpectedly"
    git -C "$REPO" config hermes.remote "$DOTFILES_URL"
  fi
  ok "dotfiles repo verified & ready: $DOTFILES_URL"
else
  warn "skipped repo setup — when ready:"
  echo "  1. create a PRIVATE repo on github.com/new"
  echo "  2. hermes remote git@github.com:YOU/dotfiles.git"
fi

say "Done! Try: hermes backup   (or: hermes install)"
