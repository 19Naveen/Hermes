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
  gum spin --title "Syncing with remote…" -- bash -c pull_latest
  sync_meta

  local excludes=()
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
    row=${row#✓ }; names+=("${row%% ·*}")
  done <<<"$chosen"

  echo
  gum style --foreground 6 "Backing up ${#names[@]} config(s):" "  ${names[*]}"
  gum confirm "Continue?" || exit 0

  local copied=() src
  for name in "${names[@]}"; do
    for item in "${items[@]}"; do
      [[ ${item%%|*} == "$name" ]] || continue
      src=${item#*|}
      if [[ -f $src ]]; then
        mkdir -p "$REPO/configs/$name" && cp "$src" "$REPO/configs/$name/"
      else
        mkdir -p "$REPO/configs/$name"
        rsync -a --delete --delete-excluded "${excludes[@]}" "$src/" "$REPO/configs/$name/"
      fi
      copied+=("$name")
      break
    done
  done

  gum spin --title "Committing…" -- bash -c "push_latest '${copied[*]}'"
  summary "Backed up" "${copied[*]}"
}
