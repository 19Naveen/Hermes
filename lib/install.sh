#!/usr/bin/env bash
# install.sh — restore configs, secrets, bootstrap from the dotfiles repo

# A single-file config (zshrc, claude-settings, any file-valued extras entry) is
# stored as configs/<name>/<basename of dest>. Everything else is a tree. Both
# helpers below must agree on that shape — deciding it from "the repo dir holds
# exactly one file" alone installs a one-file DIRECTORY as a file and destroys
# the directory (~/.config/hypr with only hyprland.conf in it, say).
_stored_file() {                        # <name> → path of the single stored file, or ""
  local src="$REPO/configs/$1" base
  base=$(basename "$(dest_for "$1")")
  if [[ -f $src/$base && $(find "$src" -mindepth 1 | wc -l) -eq 1 ]]; then
    printf '%s' "$src/$base"
  fi
  return 0   # a "no single file" answer is not a failure — set -e would abort
}

# same_config <name> — is the installed copy identical to the stored one?
# diff -rq between a stored DIRECTORY and a file destination always reports a
# difference, which made every file-type config read as DIFFERS forever.
same_config() {
  local name=$1 dst src f ex=() out
  dst=$(dest_for "$name"); src="$REPO/configs/$name"
  [[ -e $dst ]] || return 1
  f=$(_stored_file "$name")
  if [[ -f $dst ]]; then
    [[ -n $f ]] && cmp -s "$f" "$dst"
    return
  fi
  # rsync -n, not diff -rq: diff follows symlinks and exits 2 on a dangling one
  # (~/.config/hypr is 138 links into /usr/share/aether, which is not installed),
  # and it knows nothing about the excludes the backup applied — so such a config
  # read DIFFERS forever. This is the backup command with --dry-run, so "nothing
  # to do" is the honest definition of in sync. Lines starting with "." are
  # attribute-only (mtime, perms) and do not count as a content difference.
  mapfile -t ex < <(build_excludes)
  out=$(rsync -ain --delete --delete-excluded "${ex[@]}" "$dst/" "$src/" 2>/dev/null \
        | grep -v '^\.') || true
  [[ -z $out ]]
}

# place_config <name> — restore configs/<name> to its destination
place_config() {
  local name=$1 dst src f
  dst=$(dest_for "$name"); src="$REPO/configs/$name"
  [[ -e $src ]] || { warn "not in repo: $name"; return 0; }
  mkdir -p "$(dirname "$dst")"
  f=$(_stored_file "$name")
  if [[ -n $f && ! -d $dst ]]; then
    cp "$f" "$dst"
  else
    rsync -a "$src/" "$dst/"
  fi
  [[ -d $dst ]] && resolve_alternates "$dst"
  ok "installed $name → $dst"
  return 0
}

do_install() {
  [[ -d $REPO ]] || die "no repo at $REPO — run setup first: curl -fsSL $TOOL_REPO/raw/master/setup.sh | bash"
  info "pulling latest…"; pull_latest

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
    elif same_config "$name"; then
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
    place_config "$(_row_name "$row")"
  done <<<"$chosen"

  install_secrets
  run_bootstrap
  summary "Installed" "Restart your shell / apps to pick everything up."
}

install_secrets() {
  local g f base dest tmp
  command -v gpg >/dev/null || { warn "gpg missing — skipping secrets"; return 0; }
  for g in "$REPO"/secrets/*.gpg; do
    [[ -e $g ]] || return 0
    f=${g%.gpg}; base=$(basename "$f")
    [[ -f $REPO/secrets/$base.dest ]] || { warn "no .dest map for $base, skipping"; continue; }
    dest=$(cat "$REPO/secrets/$base.dest")
    mkdir -p "$(dirname "$dest")"
    # decrypt to a private temp file, never a predictable shared path
    tmp=$(mktemp) && chmod 600 "$tmp"
    if gum confirm "Install secret $base → $dest?" && gpg -q -d -o "$tmp" "$g"; then
      mv "$tmp" "$dest" && chmod 600 "$dest"
      ok "secret installed: $dest"
    else
      rm -f "$tmp"
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
  # absolute path first: "hermes secret ./key" used to record "$HOME./key"
  src=$(cd "$(dirname "$src")" && printf '%s/%s' "$PWD" "$(basename "$src")")
  base=$(basename "$src")
  dest=$src
  [[ -e $REPO/secrets/$base.gpg ]] && \
    warn "overwriting existing secret $base (was → $(cat "$REPO/secrets/$base.dest" 2>/dev/null))"
  echo "$dest" > "$REPO/secrets/$base.dest"
  gum style --faint "Enter a passphrase when prompted…"
  gpg -c -o "$REPO/secrets/$base.gpg" "$src" || die "encryption failed"
  ok "encrypted → repo/secrets/$base.gpg (installs back to $dest)"
}
