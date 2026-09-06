#!/usr/bin/env bash
# common.sh — core vars, UI helpers, git plumbing

REPO="${HERMES_REPO:-$HOME/.hermes-repo}"
# both are read from the other lib files and from `hermes` itself
# shellcheck disable=SC2034
TOOL_REPO="https://github.com/19Naveen/Hermes"
# shellcheck disable=SC2034
HERMES_VERSION="0.2.0"

# type -P, not command -v: `gum` is also the name of our wrapper function below,
# and command -v would happily find that instead of the binary
_have_gum() { type -P gum >/dev/null 2>&1; }

# plain printf, not gum: these are called on paths where gum may be missing
# (and the banner alone would otherwise fork gum seven times just to colour it)
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
info() { printf '\033[2m… %s\033[0m\n' "$*"; }

_ascii() {
  cat <<'EOF'
██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗
██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝
███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗
██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║
██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝
EOF
}

banner() {                     # the entrypoint already sets the terminal title
  _have_gum || { _ascii; echo " — config backup & restore"; return 0; }
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
  _have_gum || { printf '\n%s\n  %s\n' "$title" "$*"; return 0; }
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

# _row_name <picker row> — config name out of "[✓ |  ]name · … (size)".
# Both markers must go: leaving the untracked "  " in place makes the name
# match no discovered item, and the selection is silently dropped.
_row_name() {
  local r=${1%% ·*}
  r=${r#✓}
  r="${r#"${r%%[![:space:]]*}"}"
  r="${r%"${r##*[![:space:]]}"}"
  printf '%s' "$r"
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

# normalize_url <url> — return canonical url
normalize_url() {
  local url; url=$(echo "$1" | xargs); url=${url%/}
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
  # commit first, unconditionally: the no-remote branch used to claim
  # "committed locally only" and then return before committing anything
  git -C "$REPO" add -A
  if git -C "$REPO" diff --cached --quiet; then
    warn "No changes since last backup."
    return 0
  fi
  # a machine with no global git identity would otherwise fail the commit
  git -C "$REPO" -c user.name="${GIT_AUTHOR_NAME:-hermes}" \
                 -c user.email="${GIT_AUTHOR_EMAIL:-hermes@local}" \
                 commit -qm "backup $(date +%F-%H:%M): $msg"
  ok "committed: $msg"
  if [[ -z $url ]]; then
    warn "No dotfiles repo set — committed locally only."
    echo "  Run: hermes remote git@github.com:YOU/dotfiles.git"
    return 0
  fi
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
#
# NOTE: `read -t 0` only *tests* whether input is pending — it never consumes
# a byte. Draining needs `-n <count>` with a real timeout.
# shellcheck disable=SC2120  # $1 is optional; test.sh passes a fifo, the gum
# wrapper and the EXIT trap rely on the /dev/tty default
_hermes_drain() {
  local tty=${1:-/dev/tty} junk t=0.15
  [[ -r $tty ]] || return 0
  # first window covers the reply round-trip, then drain until quiet
  # shellcheck disable=SC2034  # `junk` is the discard sink, never read back
  while IFS= read -rsn 256 -t "$t" junk <"$tty" 2>/dev/null; do t=0.03; done
  return 0
}

# Draining alone is not enough: the reply arrives after gum has restored the
# terminal, and the tty echoes incoming bytes to the screen as they land — that
# is the ^[[?2026;2$y printed mid-output. So turn echo OFF before gum starts;
# gum saves that state and restores echo-off on exit, the reply arrives
# silently, we drain it, then put the terminal back.
#
# Only the bubbletea-backed subcommands probe the terminal; `gum style` and
# friends don't, and wrapping each would add 150ms per banner line.
_HERMES_TTY_SAVED=$(stty -g 2>/dev/null </dev/tty || true)

gum() {
  _have_gum || die "gum is required for '${1:-}' — install it: https://github.com/charmbracelet/gum"
  case ${1:-} in
    spin|filter|confirm|input|choose|write|file|pager|table) ;;
    *) command gum "$@"; return ;;
  esac
  stty -echo 2>/dev/null </dev/tty || true
  command gum "$@"
  local _ret=$?
  _hermes_drain
  [[ -n $_HERMES_TTY_SAVED ]] && stty "$_HERMES_TTY_SAVED" 2>/dev/null </dev/tty
  return $_ret
}

# always hand the terminal back, even on ctrl-c or a die()
trap '_hermes_drain 2>/dev/null; [[ -n $_HERMES_TTY_SAVED ]] && stty "$_HERMES_TTY_SAVED" 2>/dev/null </dev/tty; true' EXIT

# pull_latest/push_latest/check_auth used to run inside `gum spin -- bash -c`,
# a fresh shell that only sees exported functions. dotfiles_url was never in
# that list, so both silently no-op'd: every backup copied files into the repo
# and never committed them. They run in-process now, which removes the need for
# `export -f` entirely and stops the trap from coming back the next time a
# helper is added. REPO stays exported for the user's bootstrap.sh.
export REPO
