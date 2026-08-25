#!/usr/bin/env bash
# sync.sh — unified chooser: backup vs install vs browse (union)
# Keeps do_backup/do_install for scriptability; do_sync is the interactive entry.

do_sync() {
  ensure_repo
  # pull latest for accurate status, but don't block if offline
  gum spin --title "Syncing with remote…" -- bash -c pull_latest 2>/dev/null || true
  banner
  local choice
  choice=$(gum choose --height 6 --header " HERMES — what to do? (per-machine: skip opencode on laptop etc.) " \
    "↑  Backup  — pick local configs → push" \
    "↓  Install — pick from repo → this machine" \
    "↔  Browse  — union (local + repo) with status" \
    "≣  List    — show repo contents" 2>&1 || true)
  [[ -z $choice ]] && exit 0
  case "$choice" in
    *Backup*)  do_backup ;;
    *Install*) do_install ;;
    *Browse*)  do_browse ;;
    *List*)    do_list; gum confirm "Done — press enter" 2>&1 || true ;;
  esac
}

do_browse() {
  ensure_repo
  local excludes=()
  mapfile -t excludes < <(build_excludes)

  # local discover
  local items=() lnames=()
  while IFS= read -r line; do items+=("$line"); done < <(discover)
  for i in "${items[@]}"; do lnames+=("${i%%|*}"); done

  # remote
  local rnames=()
  mapfile -t rnames < <(ls -1 "$REPO/configs" 2>/dev/null || true)

  # union
  local union=()
  mapfile -t union < <(printf '%s\n' "${lnames[@]}" "${rnames[@]}" | sort -u)

  (( ${#union[@]} )) || die "nothing to browse — no local configs and repo empty"

  banner
  echo " $(gum style --bold --foreground 99 'BROWSE') $(gum style --faint "${#union[@]} total · ${#lnames[@]} local · ${#rnames[@]} in repo · space/x toggle · type to search")"
  echo

  local rows=() name src dst status lsize rsize
  for name in "${union[@]}"; do
    # find local src
    src=""
    for i in "${items[@]}"; do [[ ${i%%|*} == "$name" ]] && { src=${i#*|}; break; }; done
    dst=$(dest_for "$name")
    local has_local=0 has_remote=0
    [[ -n $src && -e $src ]] && has_local=1
    [[ -e $REPO/configs/$name ]] && has_remote=1

    if (( has_local && has_remote )); then
      if diff -rq "$REPO/configs/$name" "$dst" >/dev/null 2>&1; then status="in sync"
      else status="DIFFERS"
      fi
    elif (( has_local && ! has_remote )); then status="local-only"
    elif (( ! has_local && has_remote )); then status="remote-only"
    else status="?"
    fi

    if (( has_local )); then lsize=$(human_size "$src" 2>/dev/null || echo "?")
    else lsize="-"
    fi
    if (( has_remote )); then rsize=$(human_size "$REPO/configs/$name" 2>/dev/null || echo "?")
    else rsize="-"
    fi

    rows+=("$name · $status · local $lsize → remote $rsize · → $dst")
  done

  local chosen
  chosen=$(printf '%s\n' "${rows[@]}" | gum filter --no-limit --height 14 \
    --placeholder "Type to filter…" \
    --header " BROWSE — pick configs, then choose action ") || exit 0
  [[ -z $chosen ]] && die "nothing selected"

  local names=()
  while IFS= read -r row; do names+=("${row%% ·*}"); done <<<"$chosen"

  local action
  action=$(gum choose --header "Action for ${#names[@]} selected:" "↑ Backup to repo" "↓ Install to this machine" "Cancel" 2>&1 || true)
  [[ -z $action || $action == Cancel ]] && exit 0

  if [[ $action == *Backup* ]]; then
    echo
    gum style --foreground 6 "Backing up ${#names[@]} config(s):  ${names[*]}"
    gum confirm "Continue backup?" || exit 0
    local copied=() src2
    for name in "${names[@]}"; do
      for i in "${items[@]}"; do
        [[ ${i%%|*} == "$name" ]] || continue
        src2=${i#*|}
        if [[ -f $src2 ]]; then
          mkdir -p "$REPO/configs/$name" && cp "$src2" "$REPO/configs/$name/"
        else
          mkdir -p "$REPO/configs/$name"
          rsync -a --delete --delete-excluded "${excludes[@]}" "$src2/" "$REPO/configs/$name/"
        fi
        copied+=("$name")
        break
      done
      # if name not in local (remote-only picked for backup), skip
      if [[ ! " ${lnames[*]} " =~ " $name " ]]; then
        warn "skip $name — not present locally"
      fi
    done
    (( ${#copied[@]} )) || die "nothing to backup"
    gum spin --title "Committing…" -- bash -c "push_latest '${copied[*]}'"
    summary "Backed up" "${copied[*]}"
  else
    echo
    gum style --foreground 6 "Installing ${#names[@]} config(s):"
    printf '  %s\n' "${names[@]}" | gum style --faint 2>&1 || true
    gum confirm "Install these? (overwrites existing)" || exit 0
    local name2 dst2 src2
    for name2 in "${names[@]}"; do
      if [[ ! -e $REPO/configs/$name2 ]]; then
        warn "skip $name2 — not in repo (local-only)"
        continue
      fi
      dst2=$(dest_for "$name2")
      src2="$REPO/configs/$name2"
      mkdir -p "$(dirname "$dst2")"
      if [[ $(find "$src2" -maxdepth 1 -type f 2>/dev/null | wc -l) -eq 1 && $(ls "$src2" 2>/dev/null | wc -l) -eq 1 ]]; then
        cp "$src2"/$(ls "$src2") "$dst2" 2>/dev/null || { mkdir -p "$dst2"; rsync -a "$src2/" "$dst2/"; }
      else
        rsync -a "$src2/" "$dst2/"
      fi
      [[ -d $dst2 ]] && resolve_alternates "$dst2"
      ok "installed $name2 → $dst2"
    done
    install_secrets
    run_bootstrap
    summary "Installed" "Restart shell/apps to pick up"
  fi
}
