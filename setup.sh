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

# Hermes block art banner — uses gum when available, fallback to plain
hermes_banner() {
  if command -v gum >/dev/null 2>&1; then
    gum style --border rounded --border-foreground 99 --align center --width 62 --margin "1 0" \
      "$(gum style --bold --foreground 99 '██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗')" \
      "$(gum style --bold --foreground 99 '██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝')" \
      "$(gum style --bold --foreground 99 '███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗')" \
      "$(gum style --bold --foreground 99 '██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║')" \
      "$(gum style --bold --foreground 99 '██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║')" \
      "$(gum style --bold --foreground 99 '╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝')" \
      "$(gum style --faint 'config backup & restore  •  https://github.com/19Naveen/Hermes')" 2>&1 || true
  else
    cat <<'EOF' 2>&1 || true
 ██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗
 ██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝
 ███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗
 ██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║
 ██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║
 ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝
          config backup & restore
EOF
  fi
}

[[ $EUID -eq 0 ]] && die "don't run as root — install as your user"

has_tty() { [[ -t 0 || -t 1 ]] || (exec 3<> /dev/tty) 2>/dev/null; }
step() {
  if command -v gum >/dev/null 2>&1 && has_tty; then
    gum style --foreground 212 --bold "▸ $*" 2>&1 || say "$*"
  else
    say "$*"
  fi
}

# Show banner immediately — even when piped via curl|bash, stdout is still the terminal
hermes_banner
# Also set terminal title
printf '\033]0;HERMES — setup\007' 2>/dev/null || true
if command -v gum >/dev/null 2>&1 && has_tty; then
  gum style --faint --align center --width 62 "Interactive installer — press ctrl+c to cancel at any time" 2>&1 || true
fi

# --- locate source (repo checkout or download) -----------------------------
SRC=""
if [[ "$(basename "$0")" == "setup.sh" && -f "$(dirname "$0")/hermes" ]]; then
  SRC="$(cd "$(dirname "$0")" && pwd)"
else
  SRC="$(mktemp -d)"
  trap 'rm -rf "$SRC"' EXIT
  if command -v gum >/dev/null 2>&1; then
    gum spin --title "Downloading hermes…" -- git clone -q --depth 1 "$TOOL_REPO" "$SRC" || die "download failed — check your internet"
  else
    say "Downloading hermes…"
    git clone -q --depth 1 "$TOOL_REPO" "$SRC" || die "download failed — check your internet"
  fi
fi

# --- dependencies -----------------------------------------------------------
# Auto-installs missing deps: tries system package manager with sudo,
# falls back to user-local installs (no sudo) via apt download + GitHub releases.
# Never dies on missing gpg — hermes works without it (only `hermes secret` needs it).

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

install_gum_local() {
  say "Installing gum to $BIN_DIR/gum (no sudo)…"
  local tmp arch url ver
  tmp=$(mktemp -d)
  arch=$(uname -m); case $arch in x86_64|amd64) arch="x86_64" ;; aarch64|arm64) arch="arm64" ;; armv7*) arch="armv7" ;; *) arch="x86_64" ;; esac
  # try API for latest, fallback to known good version
  ver=$(curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest 2>/dev/null | grep -o '"tag_name": "v[^"]*"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  [[ -n $ver ]] || ver="2.0.0"
  for url in \
    "https://github.com/charmbracelet/gum/releases/download/v${ver}/gum_${ver}_Linux_${arch}.tar.gz" \
    "https://github.com/charmbracelet/gum/releases/download/v0.14.4/gum_0.14.4_Linux_${arch}.tar.gz"; do
    if curl -fsSL "$url" -o "$tmp/gum.tar.gz" 2>/dev/null && tar xzf "$tmp/gum.tar.gz" -C "$tmp" 2>/dev/null; then
      local bin; bin=$(find "$tmp" -type f -name "gum" | head -n1)
      if [[ -n $bin ]]; then install -m755 "$bin" "$BIN_DIR/gum" && ok "installed gum $ver → $BIN_DIR/gum" && rm -rf "$tmp" && return 0; fi
    fi
  done
  rm -rf "$tmp"; return 1
}

install_rsync_local() {
  say "Installing rsync to $BIN_DIR/rsync (no sudo)…"
  local tmp deb
  tmp=$(mktemp -d)
  if command -v apt >/dev/null 2>&1; then
    (cd "$tmp" && apt download rsync 2>/dev/null) || return 1
    deb=$(find "$tmp" -name "rsync*.deb" | head -n1)
    [[ -n $deb ]] || return 1
    dpkg-deb -x "$deb" "$tmp/extract" 2>/dev/null || return 1
    install -m755 "$tmp/extract/usr/bin/rsync" "$BIN_DIR/rsync" 2>/dev/null && ok "installed rsync → $BIN_DIR/rsync" && rm -rf "$tmp" && return 0
  fi
  rm -rf "$tmp"; return 1
}

install_gpg_local() {
  say "Installing gpg to $BIN_DIR/gpg (no sudo, with wrappers)…"
  local tmp
  tmp=$(mktemp -d)
  if ! command -v apt >/dev/null 2>&1; then rm -rf "$tmp"; return 1; fi
  (cd "$tmp" && apt download gpg gpg-agent dirmngr gpgsm gpgconf libassuan9 libnpth0t64 2>/dev/null) || { rm -rf "$tmp"; return 1; }
  mkdir -p "$tmp/extract" "$HOME/.local/lib"
  for deb in "$tmp"/*.deb; do dpkg-deb -x "$deb" "$tmp/extract" 2>/dev/null || true; done
  # libs
  cp -f "$tmp/extract/usr/lib/"*"/libassuan"* "$HOME/.local/lib/" 2>/dev/null || true
  cp -f "$tmp/extract/usr/lib/"*"/libnpth"* "$HOME/.local/lib/" 2>/dev/null || true
  # bins — wrap to inject LD_LIBRARY_PATH
  for bin in gpg gpg-agent dirmngr gpgsm gpgconf gpg-connect-agent dirmngr-client; do
    if [[ -f "$tmp/extract/usr/bin/$bin" ]]; then
      install -m755 "$tmp/extract/usr/bin/$bin" "$BIN_DIR/$bin.bin" 2>/dev/null || true
      cat > "$BIN_DIR/$bin" <<EOS
#!/bin/sh
export LD_LIBRARY_PATH="\$HOME/.local/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "\$HOME/.local/bin/$bin.bin" "\$@"
EOS
      chmod +x "$BIN_DIR/$bin"
    fi
  done
  rm -rf "$tmp"
  command -v gpg >/dev/null && gpg --version >/dev/null 2>&1 && ok "installed gpg → $BIN_DIR/gpg" && return 0
  return 1
}

ensure_deps() {
  local missing=() pkg
  for dep in git rsync gpg gum; do command -v "$dep" >/dev/null || missing+=("$dep"); done
  ((${#missing[@]}==0)) && { ok "dependencies present"; return 0; }

  say "Missing dependencies: ${missing[*]} — attempting auto-install…"

  # 1) try system package manager if sudo is available
  local pkgs=() has_apt=0 has_dnf=0 has_pacman=0
  command -v apt >/dev/null && has_apt=1
  command -v dnf >/dev/null && has_dnf=1
  command -v pacman >/dev/null && has_pacman=1

  for dep in "${missing[@]}"; do
    case $dep in
      git)   pkgs+=(git) ;;
      rsync) pkgs+=(rsync) ;;
      gpg)   pkgs+=(gnupg) ;;
      gum)   pkgs+=(gum) ;;
    esac
  done

  if (( has_apt || has_dnf || has_pacman )); then
    local can_sudo=0
    if sudo -n true 2>/dev/null; then
      can_sudo=1
      say "Trying system install with sudo (cached) for: ${pkgs[*]}…"
    elif [[ -e /dev/tty ]]; then
      say "Need sudo to install: ${pkgs[*]}"
      # cache credentials via /dev/tty so curl|bash still prompts correctly
      if sudo -v < /dev/tty > /dev/tty 2>&1; then
        can_sudo=1
      else
        warn "sudo denied — falling back to user-local installs"
      fi
    else
      warn "no tty for sudo — will try user-local installs"
    fi
    if (( can_sudo )); then
      if (( has_apt )); then
        sudo apt update -qq 2>/dev/null || sudo apt update
        sudo apt install -y "${pkgs[@]}" 2>&1 | tail -n 20 || true
      elif (( has_dnf )); then sudo dnf install -y "${pkgs[@]}" 2>&1 | tail -n 20 || true
      elif (( has_pacman )); then sudo pacman -Sy --noconfirm "${pkgs[@]}" 2>&1 | tail -n 20 || true
      fi
    fi
  fi

  # 2) fallback: user-local installs for anything still missing
  for dep in git rsync gpg gum; do
    if ! command -v "$dep" >/dev/null; then
      case $dep in
        gum)   install_gum_local || warn "gum auto-install failed — install manually: https://github.com/charmbracelet/gum" ;;
        rsync) install_rsync_local || warn "rsync auto-install failed — try: sudo apt install rsync" ;;
        gpg)   install_gpg_local || warn "gpg auto-install failed — try: sudo apt install gnupg (only needed for 'hermes secret')" ;;
        git)   warn "git still missing — please install git manually" ;;
      esac
    fi
  done

  # 3) final check — only hard-fail on rsync/gum (core), gpg is optional
  local still_missing=() core_missing=()
  for dep in git rsync gpg gum; do command -v "$dep" >/dev/null || still_missing+=("$dep"); done
  for dep in "${still_missing[@]}"; do [[ $dep == gpg ]] || core_missing+=("$dep"); done

  if ((${#core_missing[@]})); then
    say "Still missing core dependencies: ${core_missing[*]}"
    echo "  Debian/Ubuntu: sudo apt install git rsync gnupg gum"
    echo "  Fedora/RHEL:   sudo dnf install git rsync gnupg  (+ gum from charm releases)"
    echo "  Arch:          sudo pacman -S git rsync gnupg gum"
    echo "  Or re-run with sudo, or install gum locally via the installer fallback."
    die "install these and re-run setup"
  fi
  if ((${#still_missing[@]})); then
    warn "Optional dependency missing: ${still_missing[*]} — continuing (only 'hermes secret' needs gpg)"
  else
    ok "dependencies present (auto-installed)"
  fi
}

ensure_deps

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
# Supports: HERMES_DOTFILES env (for curl|bash non-interactive), gum input, or classic read.
# When piped (curl|bash) but with a tty, we read/write via /dev/tty so the prompt isn't lost.
DOTFILES_URL="${HERMES_DOTFILES:-}"

has_tty() { [[ -t 0 || -t 1 ]] || (exec 3<> /dev/tty) 2>/dev/null; }

normalize_url() {
  local url=$(echo "$1" | xargs); url=${url%/}
  if [[ $url =~ ^github\.com[:/] ]]; then
    local path=${url#github.com:}; path=${path#github.com/}
    url="https://github.com/$path"
  elif [[ $url =~ ^[^/:]+/[^/]+$ ]]; then
    url="https://github.com/$url"
  fi
  echo "$url"
}

# Interactive header for dotfiles step — Hermes styled
if command -v gum >/dev/null 2>&1 && has_tty; then
  gum style --border rounded --border-foreground 99 --align center --width 62 --margin "1 0" \
    "$(gum style --bold --foreground 212 '◆ Dotfiles Repository')" \
    "$(gum style --faint 'Where your configs will live — private GitHub repo')" \
    "$(gum style --faint 'ssh: git@github.com:YOU/dotfiles.git  •  https: https://github.com/YOU/dotfiles.git')" 2>&1 || true
fi

# Reuse already-configured remote if present (handles "already configured github" — don't ask again)
if [[ -z "${DOTFILES_URL// }" ]]; then
  _existing_remote=$(git -C "$REPO" config hermes.remote 2>/dev/null || true)
  if [[ -n "${_existing_remote:-}" ]]; then
    if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git ls-remote "$_existing_remote" >/dev/null 2>&1 || GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git ls-remote "${_existing_remote}.git" >/dev/null 2>&1; then
      say "✔ already configured: $_existing_remote (reusing — run 'hermes remote <url>' to change)"
      DOTFILES_URL="$_existing_remote"
    else
      # check if ssh is working but https wasn't — hint
      if [[ $_existing_remote == https://* ]] && ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        warn "existing remote $_existing_remote not reachable via https, but SSH auth is working — consider: hermes remote git@github.com:${_existing_remote#https://github.com/}"
      fi
    fi
  fi
  unset _existing_remote
fi

if [[ -z "${DOTFILES_URL// }" ]]; then
  if ! has_tty; then
    # truly non-interactive (CI/no tty) — skip prompt entirely, no noise
    DOTFILES_URL=""
  elif command -v gum >/dev/null 2>&1; then
    # gum: stdin from /dev/tty (so curl|bash works), UI on stderr to /dev/tty, result on stdout captured
    DOTFILES_URL=$(gum input --placeholder "git@github.com:YOU/dotfiles.git or https://github.com/YOU/dotfiles.git (empty to skip)" --prompt "⚡ Private dotfiles repo URL: " --width 70 < /dev/tty 2> /dev/tty || true)
    DOTFILES_URL=$(echo "$DOTFILES_URL" | xargs 2>/dev/null || echo "$DOTFILES_URL")
  else
    printf '\033[1;35m⚡\033[0m git url of YOUR private dotfiles repo\n   ssh:  git@github.com:YOU/dotfiles.git\n   https: https://github.com/YOU/dotfiles.git (private: use https://TOKEN@github.com/YOU/dotfiles.git or gh auth login)\n   (create via github.com/new, keep it Private): ' > /dev/tty 2>&1 || true
    read -r DOTFILES_URL < /dev/tty 2> /dev/tty || DOTFILES_URL=""
  fi
fi

mkdir -p "$REPO/configs"
while [[ -n ${DOTFILES_URL// } ]] && ! GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git ls-remote "$DOTFILES_URL" >/dev/null 2>&1 && ! GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git ls-remote "${DOTFILES_URL}.git" >/dev/null 2>&1; do
  warn "cannot access $DOTFILES_URL"
  if [[ $DOTFILES_URL == https://* ]]; then
    echo "  · for private https: use https://TOKEN@github.com/YOU/dotfiles.git or run: gh auth login"
    echo "  · or switch to ssh: git@github.com:YOU/dotfiles.git (needs SSH key on github.com/settings/keys)"
  elif [[ $DOTFILES_URL == git@* || $DOTFILES_URL == ssh://* ]]; then
    echo "  · is your SSH key added? https://github.com/settings/keys"
    echo "  · test it:            ssh -T git@github.com"
    echo "  · or try https: https://github.com/YOU/dotfiles.git"
  else
    echo "  · does the repo exist on GitHub?"
    echo "  · ssh:  git@github.com:YOU/dotfiles.git  (SSH key) | https: https://github.com/YOU/dotfiles.git (token/gh auth)"
  fi
  if ! has_tty; then
    DOTFILES_URL=""; break
  elif command -v gum >/dev/null 2>&1; then
    DOTFILES_URL=$(gum input --placeholder "git@github.com:YOU/dotfiles.git or https://github.com/YOU/dotfiles.git (empty to skip)" --prompt "Try another URL: " --width 70 < /dev/tty 2> /dev/tty || true)
    DOTFILES_URL=$(echo "$DOTFILES_URL" | xargs 2>/dev/null || echo "$DOTFILES_URL")
  else
    printf 'Try another url (or empty to set up later): ' > /dev/tty 2>&1 || true
    read -r DOTFILES_URL < /dev/tty 2> /dev/tty || DOTFILES_URL=""
  fi
done

if [[ -n ${DOTFILES_URL// } ]]; then
  # normalize shorthand (USER/REPO, github.com/USER/REPO) to https
  DOTFILES_URL=$(normalize_url "$DOTFILES_URL")
  git -C "$REPO" config hermes.remote "$DOTFILES_URL"
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && [[ $(ls -A "$REPO" | grep -vc '^\.') -gt 2 ]]; then
    # existing repo with content — pull instead of clobbering
    git -C "$REPO" remote remove origin 2>/dev/null || true
    git -C "$REPO" remote add origin "$DOTFILES_URL"
    git -C "$REPO" pull -q origin HEAD 2>/dev/null || warn "pull failed — run 'git -C $REPO pull origin HEAD' manually"
    ok "linked existing backup repo to $DOTFILES_URL"
  elif [[ -e $REPO/.git ]] || git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && [[ -n $(git -C "$REPO" log --oneline -1 2>/dev/null) ]]; then
    git -C "$REPO" push -q origin HEAD 2>/dev/null && ok "pushed local backups to $DOTFILES_URL" ||
      warn "couldn't push existing local backups — run: git -C $REPO push origin HEAD"
  else
    if command -v gum >/dev/null 2>&1 && has_tty; then
      gum spin --title "Cloning your dotfiles… ($DOTFILES_URL)" -- bash -c "
        rm -rf \"$REPO\"
        if [[ \"$DOTFILES_URL\" == https://* ]]; then
          GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git clone -q \"$DOTFILES_URL\" \"$REPO\"
        else
          GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git clone -q \"$DOTFILES_URL\" \"$REPO\"
        fi
      " || {
        if [[ $DOTFILES_URL == https://* ]] && ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
          die "clone failed — https needs a token (https://TOKEN@github.com/... or 'gh auth login'), but SSH works, try: git@github.com:${DOTFILES_URL#https://github.com/}"
        elif [[ $DOTFILES_URL == https://* ]]; then
          die "clone failed — https private repo needs token or gh auth login; or use ssh: git@github.com:${DOTFILES_URL#https://github.com/}"
        else
          die "clone failed — check ssh key: ssh -T git@github.com"
        fi
      }
    else
      say "Cloning your dotfiles… ($DOTFILES_URL)"
      rm -rf "$REPO"
      if [[ $DOTFILES_URL == https://* ]]; then
        GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git clone -q "$DOTFILES_URL" "$REPO" || {
          if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            die "clone failed — https needs a token (https://TOKEN@github.com/... or 'gh auth login'), but SSH works, try: git@github.com:${DOTFILES_URL#https://github.com/}"
          else
            die "clone failed — https private repo needs token or gh auth login; or use ssh: git@github.com:${DOTFILES_URL#https://github.com/}"
          fi
        }
      else
        GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo git clone -q "$DOTFILES_URL" "$REPO" || die "clone failed — check ssh key: ssh -T git@github.com"
      fi
    fi
    git -C "$REPO" config hermes.remote "$DOTFILES_URL"
  fi
  if command -v gum >/dev/null 2>&1 && has_tty; then
    gum style --border rounded --border-foreground 2 --align center --width 62 --margin "1 0" \
      "$(gum style --bold --foreground 2 '✔ Dotfiles ready: '"$DOTFILES_URL")" \
      "$(gum style --faint 'Run: hermes backup  •  hermes install')" 2>&1 || ok "dotfiles repo verified & ready: $DOTFILES_URL"
  else
    ok "dotfiles repo verified & ready: $DOTFILES_URL"
  fi
  if [[ $DOTFILES_URL == https://* ]]; then
    echo "  tip: ssh alternative is git@github.com:${DOTFILES_URL#https://github.com/}"
  elif [[ $DOTFILES_URL == git@* ]]; then
    echo "  tip: https alternative is https://github.com/${DOTFILES_URL#git@github.com:}"
  fi
else
  if command -v gum >/dev/null 2>&1 && has_tty; then
    gum style --border rounded --border-foreground 3 --align center --width 62 --margin "1 0" \
      "$(gum style --bold --foreground 3 '⚠ Skipped dotfiles setup')" \
      "$(gum style --faint 'Create a private repo, then:')" \
      "$(gum style --faint 'hermes remote git@github.com:YOU/dotfiles.git')" 2>&1 || true
    echo "  or: hermes remote https://github.com/YOU/dotfiles.git"
    echo "  non-interactive:"
    echo "    HERMES_DOTFILES=git@github.com:YOU/dotfiles.git curl -fsSL $TOOL_REPO/raw/master/setup.sh | bash"
  else
    warn "skipped repo setup — when ready:"
    echo "  1. create a PRIVATE repo on github.com/new"
    echo "  2. hermes remote git@github.com:YOU/dotfiles.git          # ssh (needs SSH key)"
    echo "     hermes remote https://github.com/YOU/dotfiles.git      # https (needs token or gh auth login)"
    echo "     or non-interactive:"
    echo "       HERMES_DOTFILES=git@github.com:YOU/dotfiles.git curl -fsSL $TOOL_REPO/raw/master/setup.sh | bash"
    echo "       HERMES_DOTFILES=https://TOKEN@github.com/YOU/dotfiles.git curl -fsSL $TOOL_REPO/raw/master/setup.sh | bash"
  fi
fi

# Interactive footer — Hermes styled
if command -v gum >/dev/null 2>&1 && has_tty; then
  gum style --border rounded --border-foreground 99 --align center --width 62 --margin "1 0" \
    "$(gum style --bold --foreground 99 'H E R M E S — ready')" \
    "$(gum style --faint 'hermes backup  •  hermes install  •  hermes list')" 2>&1 || true
else
  say "Done! Try: hermes backup   (or: hermes install)"
fi
