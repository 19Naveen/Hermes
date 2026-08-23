#!/usr/bin/env bash
# install.sh — restore configs, secrets, bootstrap from the dotfiles repo

do_install() {
  [[ -d $REPO ]] || die "no repo at $REPO — run setup first: curl -fsSL $TOOL_REPO/raw/master/setup.sh | bash"
  gum spin --title "Pulling latest…" -- bash -c pull_latest

  local available=() chosen
  mapfile -t available < <(ls -1 "$REPO/configs" 2>/dev/null)
  (( ${#available[@]} )) || die "repo has nothing in configs/"

  banner
  echo " $(gum style --bold --foreground 3 'INSTALL') $(gum style --faint "${#available[@]} stored in repo · space/x toggle · ctrl+a all · type to search · enter confirm")"
  echo

  local row rows=() name src dst status
  for name in "${available[@]}"; do
    dst=$(dest_for "$name")
    src="$REPO/configs/$name"
    if [[ ! -e $dst ]]; then
      status="new      "
    elif diff -rq "$src" "$dst" >/dev/null 2>&1; then
      status="in sync  "
    else
      status="DIFFERS  "
    fi
    rows+=("$name · $status · → $dst ($(human_size "$src"))")
  done

  chosen=$(printf '%s\n' "${rows[@]}" | gum filter --no-limit --height 13 \
    --placeholder "Type to search…" \
    --header " INSTALL — pick what this machine needs ") || exit 0
  [[ -z $chosen ]] && die "nothing selected"

  echo
  gum style --foreground 6 "$(while IFS= read -r row; do echo "  ${row%% ·*}"; done <<<"$chosen")"
  gum confirm "Install these? (existing files will be overwritten)" || exit 0

  while IFS= read -r row; do
    name=${row%% ·*}
    dst=$(dest_for "$name")
    src="$REPO/configs/$name"
    mkdir -p "$(dirname "$dst")"
    if [[ $(find "$src" -maxdepth 1 -type f | wc -l) -eq 1 && $(ls "$src" | wc -l) -eq 1 ]]; then
      cp "$src"/$(ls "$src") "$dst" 2>/dev/null || { mkdir -p "$dst"; rsync -a "$src/" "$dst/"; }
    else
      rsync -a "$src/" "$dst/"
    fi
    [[ -d $dst ]] && resolve_alternates "$dst"
    ok "installed $name → $dst"
  done <<<"$chosen"

  install_secrets
  run_bootstrap
  summary "Installed" "Restart your shell / apps to pick everything up."
}

install_secrets() {
  local g f base dest
  command -v gpg >/dev/null || { warn "gpg missing — skipping secrets"; return 0; }
  for g in "$REPO"/secrets/*.gpg; do
    [[ -e $g ]] || return 0
    f=${g%.gpg}; base=$(basename "$f")
    [[ -f $REPO/secrets/$base.dest ]] || { warn "no .dest map for $base, skipping"; continue; }
    dest=$(cat "$REPO/secrets/$base.dest")
    mkdir -p "$(dirname "$dest")"
    if gum confirm "Install secret $base → $dest?" && \
       gpg -q -d -o /tmp/opencode/sec-tmp "$g" 2>/dev/null; then
      mv /tmp/opencode/sec-tmp "$dest" && chmod 600 "$dest"
      ok "secret installed: $dest"
    else
      rm -f /tmp/opencode/sec-tmp
      warn "skipped secret $base"
    fi
  done
}

run_bootstrap() {
  local b="$HOME/.config/hermes/bootstrap.sh"
  [[ -x $b ]] || return 0
  if gum confirm "Run bootstrap script? ($b)"; then
    bash "$b" && ok "bootstrap finished" || warn "bootstrap exited non-zero"
  fi
}

do_secret() {
  [[ ${2:-} != "" ]] || die "usage: hermes secret <file-to-encrypt>"
  local src=$2
  [[ -f $src ]] || die "not a file: $src"
  command -v gpg >/dev/null || die "gpg not installed (sudo apt install gnupg)"
  ensure_repo
  mkdir -p "$REPO/secrets"
  local base dest
  base=$(basename "$src")
  dest="$HOME${src#$HOME}"
  echo "$dest" > "$REPO/secrets/$base.dest"
  gum style --faint "Enter a passphrase when prompted…"
  gpg -c -o "$REPO/secrets/$base.gpg" "$src" || die "encryption failed"
  ok "encrypted → repo/secrets/$base.gpg (installs back to $dest)"
}
