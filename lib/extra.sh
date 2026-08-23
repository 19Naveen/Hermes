#!/usr/bin/env bash
# extra.sh — remote management, list, update, completions

do_list() {
  ensure_repo
  ls -1 "$REPO/configs" 2>/dev/null || echo "empty"
}

do_remote() {
  [[ -n ${2:-} ]] || die "usage: hermes remote <git-url>"
  local url=$2
  ensure_repo
  gum spin --title "Checking access to $url…" -- bash -c "check_auth '$url'" \
    || die "cannot access $url — add your SSH key on github.com/settings/keys first"
  git -C "$REPO" config hermes.remote "$url"
  ok "remote saved and verified: $url"
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
        'list:show what is backed up in the repo'
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
  cat <<EOF
⚡ hermes — config backup & restore ($TOOL_REPO)

  hermes backup            pick installed configs → commit & push
  hermes install           pick stored configs → install locally
  hermes list              show what's in the backup repo
  hermes remote <url>      set + verify your private dotfiles repo
  hermes secret <file>     passphrase-encrypt a file into the repo
  hermes completion        print zsh completions
  hermes update            update hermes from the public repo
EOF
}
