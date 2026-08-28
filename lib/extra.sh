#!/usr/bin/env bash
# extra.sh — remote management, list, update, completions

do_list() {
  ensure_repo
  local cfgs=()
  mapfile -t cfgs < <(ls -1 "$REPO/configs" 2>/dev/null || true)
  if (( ${#cfgs[@]} == 0 )) || [[ -z "${cfgs[0]:-}" ]]; then
    gum style --foreground 3 "No configs backed up yet" 2>&1 || echo "No configs backed up yet"
    echo "  Run: hermes backup"
    echo "  Repo: $REPO/configs"
    return 0
  fi
  printf '%s\n' "${cfgs[@]}"
  echo ""
  gum style --faint "${#cfgs[@]} config(s) in $REPO/configs" 2>&1 || true
}

do_remote() {
  [[ -n ${2:-} ]] || die "usage: hermes remote <git-url>  (ssh: git@github.com:USER/REPO.git  or https: https://github.com/USER/REPO.git)"
  local url=$2 norm
  norm=$(normalize_url "$url")
  # prefer normalized for storage but keep original if user used ssh
  [[ $url == git@* || $url == ssh://* ]] && norm="$url"
  ensure_repo
  if ! gum spin --title "Checking access to $url…" -- bash -c "check_auth '$url'"; then
    if [[ $url == https://* ]]; then
      die "cannot access $url — for private https repos: use a token (https://TOKEN@github.com/USER/REPO.git) or 'gh auth login', or switch to ssh: git@github.com:USER/REPO.git"
    elif [[ $url == git@* || $url == ssh://* ]]; then
      die "cannot access $url — add your SSH key on github.com/settings/keys, test with: ssh -T git@github.com"
    else
      die "cannot access $url — check the url and your auth (ssh key or https token)"
    fi
  fi
  git -C "$REPO" config hermes.remote "$norm"
  ok "remote saved and verified: $norm"
  if [[ $norm == https://* ]]; then
    echo "  (ssh alternative: git@github.com:${norm#https://github.com/})"
  elif [[ $norm == git@github.com:* ]]; then
    echo "  (https alternative: https://github.com/${norm#git@github.com:})"
  fi
}

do_update() {
  local tmp=/tmp/opencode/hermes-update
  mkdir -p "$tmp"
  gum spin --title "Downloading latest hermes…" -- bash -c "git clone -q --depth 1 '$TOOL_REPO' '$tmp/src'"
  [[ -f $tmp/src/hermes ]] || die "update failed — check your internet"
  local self; self=$(readlink -f "$0")
  if [[ -w $(dirname "$self") ]]; then
    install -m 755 "$tmp/src/hermes" "$self"
    mkdir -p "$(dirname "$self")/../share/hermes"
    rm -rf "$(dirname "$self")/../share/hermes/lib"
    cp -r "$tmp/src/lib" "$(dirname "$self")/../share/hermes/lib"
    ok "updated hermes + lib"
  else
    sudo install -m 755 "$tmp/src/hermes" "$self" &&
      sudo cp -r "$tmp/src/lib" "$(dirname "$self")/../share/hermes/" &&
      ok "updated hermes + lib (sudo)"
  fi
  rm -rf "$tmp"
}

do_completion() {
  cat <<'EOF'
#compdef hermes
_hermes() {
  local -a cmds
  cmds=('backup:pick installed configs to back up and push'
        'install:pick stored configs to install'
        'sync:unified chooser (backup/install/browse)'
        'list:show stored configs + install picker (alias of install)'
        'remote:set and verify the dotfiles repo url'
        'secret:encrypt a file into repo secrets/'
        'completion:print shell completions'
        'update:update hermes from the public repo')
  if (( CURRENT == 2 )); then
    _describe 'command' cmds
  elif [[ $words[2] == remote ]]; then
    _message 'git url of YOUR private dotfiles repo'
  elif [[ $words[2] == secret ]]; then
    _files
  elif [[ $words[2] == install ]]; then
    local -a cfgs
    cfgs=(${(f)"$(ls ~/.hermes-repo/configs 2>/dev/null)"})
    _describe 'stored config' cfgs
  fi
}
compdef _hermes hermes
EOF
}

usage() {
  # set terminal title to HERMES
  printf '\033]0;HERMES\007'
  cat <<EOF
██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗
██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝
███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗
██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║
██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝
 — config backup & restore ($TOOL_REPO)

  hermes                   show this help
  hermes sync              two-way reconcile (latest wins) — push/pull per item
  hermes backup            pick installed configs → commit & push
  hermes install           pick stored configs → install locally
  hermes browse            read-only union view (local + repo, with status)
  hermes list              show stored configs and pick to install (alias of install)
  hermes remote <url>      set + verify your private dotfiles repo
  hermes secret <file>     passphrase-encrypt a file into the repo
  hermes completion        print zsh completions
  hermes update            update hermes from the public repo
EOF
}
