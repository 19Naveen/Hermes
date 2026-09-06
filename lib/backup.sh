#!/usr/bin/env bash
# backup.sh — pick configs, snapshot into the dotfiles repo, push

sync_meta() {
  # backup repo holds ONLY user data — tool lives in the public repo
  [[ -f $REPO/README.md ]] || cat > "$REPO/README.md" <<EOF
# My dotfiles

Managed by [hermes]($TOOL_REPO).

## Restore on a new machine

\`\`\`bash
curl -fsSL $TOOL_REPO/raw/master/setup.sh | bash
hermes install
\`\`\`
EOF
}

do_backup() {
  ensure_repo
  info "syncing with remote…"; pull_latest
  sync_meta

  local excludes=()
  # shellcheck disable=SC2034  # read by _store_config through dynamic scope
  mapfile -t excludes < <(build_excludes)

  local items=() chosen
  while IFS= read -r line; do items+=("$line"); done < <(discover)
  (( ${#items[@]} )) || die "no configs found"

  banner
  local tracked=0 row rows=() name
  echo " $(gum style --bold --foreground 6 'BACKUP') $(gum style --faint "${#items[@]} discovered · space/x toggle · ctrl+a all · type to search · enter confirm")"
  for item in "${items[@]}"; do
    name=${item%%|*}
    [[ -e $REPO/configs/$name ]] && { tracked=$((tracked+1)); row="✓ "; } || row="  "
    rows+=("$row$name · ${item#*|} ($(human_size "${item#*|}"))")
  done
  (( tracked )) && echo " $(gum style --foreground 6 "$tracked already tracked")"

  chosen=$(printf '%s\n' "${rows[@]}" | gum filter --no-limit --height 13 \
    --placeholder "Type to search…" \
    --header " BACK UP — pick your configs ") || exit 0
  [[ -z $chosen ]] && die "nothing selected"

  local names=()
  while IFS= read -r row; do
    names+=("$(_row_name "$row")")
  done <<<"$chosen"

  echo
  gum style --foreground 6 "Backing up $(plural ${#names[@]} config):" "  ${names[*]}"
  gum confirm "Continue?" || exit 0

  local copied=() missed=() src
  for name in "${names[@]}"; do
    src=$(_local_path "$name")
    [[ -n $src && -e $src ]] || { missed+=("$name"); continue; }
    _store_config "$name" "$src"
    copied+=("$name")
  done
  (( ${#missed[@]} )) && warn "could not resolve: ${missed[*]}"

  (( ${#copied[@]} )) || die "nothing was copied"
  info "committing…"; push_latest "${copied[*]}"

  local lines=()
  mapfile -t lines < <(_stored_report "${copied[@]}")
  if (( HERMES_COMMITTED )); then
    summary "Backed up $(plural ${#copied[@]} config)" "${lines[@]}"
  else
    # nothing was committed — do not claim a backup that did not happen
    summary "Already up to date" "${lines[@]}"
  fi
}
