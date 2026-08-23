#!/usr/bin/env bash
# common.sh — core vars, UI helpers, git plumbing

REPO="${HERMES_REPO:-$HOME/.hermes-repo}"
TOOL_REPO="https://github.com/19Naveen/Hermes"

die()  { gum style --foreground 1 "✖ $*"; exit 1; }
ok()   { gum style --foreground 2 "✔ $*"; }
warn() { gum style --foreground 3 "⚠ $*"; }

banner() {
  gum style --border rounded --border-foreground 99 --align center --width 40 \
    "$(gum style --bold --foreground 99 '⚡ H E R M E S')" \
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
  if [[ ! -d $REPO ]]; then
    mkdir -p "$REPO/configs" && git -C "$REPO" init -q
    echo ".git" > "$REPO/.gitignore"
  fi
  mkdir -p "$REPO/configs"
}

dotfiles_url() { git -C "$REPO" config hermes.remote 2>/dev/null || true; }

# check_auth <url> — prove the user can actually talk to this remote
check_auth() {
  local url=$1
  [[ $url =~ ^(git@|ssh://|https://) ]] || { warn "odd url format: $url"; return 1; }
  git ls-remote "$url" HEAD >/dev/null 2>&1
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

# gum spin execs its argument as an external binary and can't see shell
# functions or unexported vars — export both.
export REPO
export -f pull_latest push_latest check_auth
