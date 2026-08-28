#!/usr/bin/env bash
# common.sh — core vars, UI helpers, git plumbing

REPO="${HERMES_REPO:-$HOME/.hermes-repo}"
TOOL_REPO="https://github.com/19Naveen/Hermes"

die()  { gum style --foreground 1 "✖ $*"; exit 1; }
ok()   { gum style --foreground 2 "✔ $*"; }
warn() { gum style --foreground 3 "⚠ $*"; }

banner() {
  printf '\033]0;HERMES\007'
  gum style --border rounded --border-foreground 99 --align center --width 62 \
    "$(gum style --bold --foreground 99 '██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗')" \
    "$(gum style --bold --foreground 99 '██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝')" \
    "$(gum style --bold --foreground 99 '███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗')" \
    "$(gum style --bold --foreground 99 '██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║')" \
    "$(gum style --bold --foreground 99 '██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║')" \
    "$(gum style --bold --foreground 99 '╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝')" \
    "$(gum style --faint 'config backup & restore')"
}

summary() {
  local title=$1; shift
  gum style --border rounded --border-foreground 2 --padding "0 2" --margin "1 0" \
    "$(gum style --bold "$title")" "$*"
}

human_size() {
  local kb=$(( $(du -sk "$1" 2>/dev/null | cut -f1) ))
  if   (( kb >= 1048576 )); then awk -v n="$kb" 'BEGIN{printf "%.1fGB", n/1048576}'
  elif (( kb >= 1024 ));    then awk -v n="$kb" 'BEGIN{printf "%.1fMB", n/1024}'
  else                           echo "${kb}KB"
  fi
}

ensure_repo() {
  if [[ ! -d $REPO/.git ]]; then
    mkdir -p "$REPO/configs"
    # init if not already a git repo (covers existing dir without .git)
    if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
      git init -q "$REPO" 2>/dev/null || git -C "$REPO" init -q 2>/dev/null || {
        rm -rf "$REPO/.git" 2>/dev/null; git init -q "$REPO"
      }
    fi
    [[ -f $REPO/.gitignore ]] || echo ".git" > "$REPO/.gitignore"
    # ensure initial commit exists so remote can be added later
    if ! git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
      git -C "$REPO" add .gitignore 2>/dev/null || true
      git -C "$REPO" -c user.name="hermes" -c user.email="hermes@local" commit -qm "init hermes repo" 2>/dev/null || true
    fi
  fi
  mkdir -p "$REPO/configs"
}

dotfiles_url() { git -C "$REPO" config hermes.remote 2>/dev/null || true; }

# check_auth <url> — prove the user can actually talk to this remote
# Supports: ssh (git@github.com:USER/REPO.git, ssh://) and https (https://github.com/USER/REPO.git)
# Also handles shorthand github.com/USER/REPO or USER/REPO, auto-appends .git if needed.
# Uses GIT_TERMINAL_PROMPT=0 to avoid interactive Username/Password prompts.
check_auth() {
  local url=$1
  url=$(echo "$url" | xargs)          # trim
  url=${url%/}                         # strip trailing slash
  # normalize shorthand forms
  if [[ $url =~ ^(git@|ssh://|https?://|git://) ]]; then
    : # already fully qualified
  elif [[ $url =~ ^github\.com[:/] ]]; then
    # strip github.com: or github.com/ prefix → USER/REPO
    local path=${url#github.com:}
    path=${path#github.com/}
    url="https://github.com/$path"
  elif [[ $url =~ ^[^/:]+/[^/]+$ ]]; then
    # USER/REPO shorthand
    url="https://github.com/$url"
  else
    warn "odd url format: $url"
    echo "  expected: git@github.com:USER/REPO.git (ssh) or https://github.com/USER/REPO.git (https)" >&2
    return 1
  fi
  # avoid interactive username/password prompts — fail fast
  local git_env="GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo"
  # try as-is, then with .git suffix — no HEAD so empty repos pass
  if env $git_env git ls-remote "$url" >/dev/null 2>&1; then return 0; fi
  if [[ $url != *.git ]]; then
    env $git_env git ls-remote "$url.git" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# has_github_auth — quick check if user already has GitHub auth (ssh or gh)
has_github_auth() {
  # ssh: BatchMode avoids password prompt
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then return 0; fi
  # gh cli
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then return 0; fi
  # credential helper cached
  if git credential fill >/dev/null 2>&1 <<<"protocol=https
host=github.com
" | grep -q "username="; then return 0; fi
  return 1
}

# normalize_url <url> — return canonical url
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

pull_latest() {
  local url; url=$(dotfiles_url)
  [[ -z $url ]] && return 0
  if ! check_auth "$url"; then
    warn "cannot reach $url — working offline with local copy only"
    return 0
  fi
  git -C "$REPO" remote remove origin 2>/dev/null || true
  git -C "$REPO" remote add origin "$url"
  git -C "$REPO" pull -q origin HEAD 2>/dev/null || true
}

push_latest() {
  local msg=$1 url
  url=$(dotfiles_url)
  if [[ -z $url ]]; then
    warn "No dotfiles repo set — committed locally only."
    echo "  Run: hermes remote git@github.com:YOU/dotfiles.git"
    return 0
  fi
  git -C "$REPO" add -A
  if git -C "$REPO" diff --cached --quiet; then
    warn "No changes since last backup."
    return 0
  fi
  git -C "$REPO" commit -qm "backup $(date +%F-%H:%M): $msg"
  ok "committed: $msg"
  if git -C "$REPO" push -q origin HEAD 2>/dev/null; then
    ok "pushed to $url"
  else
    warn "push failed — run 'git -C $REPO push origin HEAD' to see why"
  fi
}

# --- hermes: contain gum's terminal probes ---
# gum (charm) queries the terminal with DECRQM \e[?2026$p etc. to enable
# Synchronized Output. The terminal replies \e[?2026;2$y etc. If gum exits
# before the reply arrives, those bytes leak into the shell's input buffer
# and show as ^[[?2026;2$y on the next prompt. We wrap the `gum` binary
# to drain any pending reply immediately after each call, and also on EXIT.
_hermes_drain() {
  local _c _tty="/dev/tty"
  [[ -c $_tty ]] || _tty="/dev/stdin"
  # only when attached to a tty; non-blocking reads so we never hang
  if [[ -t 0 || -t 1 || -c $_tty ]]; then
    # first, check if anything is waiting without blocking
    while IFS= read -r -t 0 -n 1 _c 2>/dev/null <"$_tty"; do
      if [[ $_c == $'\e' ]]; then
        # consume the full DECRPM sequence until trailing 'y'
        while IFS= read -r -t 0.02 -n 1 _c 2>/dev/null <"$_tty"; do
          [[ $_c == "y" ]] && break
        done || true
      fi
      # drain any spill-over bytes that arrived in the same burst
      while IFS= read -r -t 0.01 -n 1 _c 2>/dev/null <"$_tty"; do :; done || true
    done || true
    # second tiny window for a reply that arrived just after the first burst
    while IFS= read -r -t 0.05 -n 1 _c 2>/dev/null <"$_tty"; do :; done || true
  fi
}

gum() {
  command gum "$@"
  local _ret=$?
  _hermes_drain || true
  return $_ret
}

trap '_hermes_drain 2>/dev/null || true' EXIT

# gum spin execs its argument as an external binary and can't see shell
# functions or unexported vars — export both.
export REPO
export -f pull_latest push_latest check_auth normalize_url has_github_auth _hermes_drain gum
