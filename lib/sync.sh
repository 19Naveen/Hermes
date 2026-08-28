#!/usr/bin/env bash
# sync.sh — two-way reconcile (latest wins) + browse viewer

_local_mt() { # newest mtime among files in a path (epoch seconds)
  [[ -e $1 ]] || { echo 0; return; }
  find "$1" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1
}

_cloud_ct() { # last git commit time touching a repo config (epoch seconds)
  local t
  t=$(git -C "$REPO" log -1 --format=%ct -- "configs/$1" 2>/dev/null)
  echo "${t:-0}"
}

_color_action() { # color an action word for the plan view
  case "$1" in
    PUSH*)  gum style --foreground 2 --bold "$1" ;;
    PULL*)  gum style --foreground 6 --bold "$1" ;;
    skip*)  gum style --faint "$1" ;;
    *)      echo "$1" ;;
  esac
}

# do_sync — pull cloud, then per item:
#   local-only  → push
#   remote-only → pull
#   identical   → skip
#   diverged    → newer mtime wins (local mtime vs cloud commit time)
do_sync() {
  ensure_repo
  gum spin --title "Syncing with remote…" -- bash -c pull_latest 2>/dev/null || true

  local excludes=()
  mapfile -t excludes < <(build_excludes)

  local items=() lnames=()
  while IFS= read -r line; do items+=("$line"); done < <(discover)
  for i in "${items[@]}"; do lnames+=("${i%%|*}"); done

  local rnames=()
  mapfile -t rnames < <(ls -1 "$REPO/configs" 2>/dev/null || true)

  local union=()
  mapfile -t union < <(printf '%s\n' "${lnames[@]}" "${rnames[@]}" | sort -u)
  (( ${#union[@]} )) || die "nothing to sync — no local configs and repo empty"

  local name src dst lmt rct action plan=()
  local cnt_push=0 cnt_pull=0 cnt_skip=0
  for name in "${union[@]}"; do
    src=""; for i in "${items[@]}"; do [[ ${i%%|*} == "$name" ]] && { src=${i#*|}; break; }; done
    dst=$(dest_for "$name")
    local has_local=0 has_remote=0
    [[ -n $src && -e $src ]] && has_local=1
    [[ -e $REPO/configs/$name ]] && has_remote=1

    if (( has_local && has_remote )); then
      if diff -rq "$REPO/configs/$name" "$dst" >/dev/null 2>&1; then action="skip (in sync)"; lmt=$(_local_mt "$src"); rct=$(_cloud_ct "$name")
      else
        lmt=$(_local_mt "$src"); rct=$(_cloud_ct "$name")
        if   (( lmt > rct )); then action="PUSH  (local newer)"
        elif (( rct > lmt )); then action="PULL  (cloud newer)"
        else action="PUSH  (tie → local)"; fi
      fi
    elif (( has_local && ! has_remote )); then action="PUSH  (local-only)";  lmt=$(_local_mt "$src"); rct=0
    elif (( ! has_local && has_remote )); then action="PULL  (cloud-only)";  lmt=0; rct=$(_cloud_ct "$name")
    else action="?"; lmt=0; rct=0
    fi

    case "$action" in PUSH*) cnt_push=$((cnt_push+1)) ;; PULL*) cnt_pull=$((cnt_pull+1)) ;; *) cnt_skip=$((cnt_skip+1)) ;; esac
    local atime ctime
    atime=$(date -d @$lmt +%H:%M 2>/dev/null || echo '-')
    ctime=$(date -d @$rct +%H:%M 2>/dev/null || echo '-')
    printf '  %-26s local %-6s cloud %-6s %s\n' "$name" "$atime" "$ctime" "$(_color_action "$action")"
    plan+=("$name|$action")
  done

  banner
  echo " $(gum style --bold --foreground 99 'SYNC') $(gum style --faint "${#union[@]} items · latest mtime wins")"
  echo
  gum style --bold "  Plan: $(gum style --foreground 2 "$cnt_push ↑ push") · $(gum style --foreground 6 "$cnt_pull ↓ pull") · $(gum style --faint "$cnt_skip = skip")"
  echo " $(gum style --faint "PUSH = upload to cloud   PULL = install from cloud   skip = identical")"

  local acts=$((cnt_push + cnt_pull))
  (( acts == 0 )) && { ok "nothing to do — everything in sync"; return 0; }

  gum confirm "Apply this plan?" || exit 0

  local copied=() name2 src2 dst2
  for p in "${plan[@]}"; do
    name2=${p%%|*}; action=${p#*|}
    case "$action" in
      PUSH*)
        for i in "${items[@]}"; do [[ ${i%%|*} == "$name2" ]] || continue
          src2=${i#*|}
          if [[ -f $src2 ]]; then mkdir -p "$REPO/configs/$name2" && cp "$src2" "$REPO/configs/$name2/"
          else mkdir -p "$REPO/configs/$name2"; rsync -a --delete --delete-excluded "${excludes[@]}" "$src2/" "$REPO/configs/$name2/"; fi
          break
        done
        copied+=("$name2")
        ;;
      PULL*)
        [[ -e $REPO/configs/$name2 ]] || continue
        dst2=$(dest_for "$name2"); src2="$REPO/configs/$name2"
        mkdir -p "$(dirname "$dst2")"
        if [[ $(find "$src2" -maxdepth 1 -type f 2>/dev/null | wc -l) -eq 1 && $(ls "$src2" 2>/dev/null | wc -l) -eq 1 ]]; then
          cp "$src2"/$(ls "$src2") "$dst2" 2>/dev/null || { mkdir -p "$dst2"; rsync -a "$src2/" "$dst2/"; }
        else rsync -a "$src2/" "$dst2/"; fi
        [[ -d $dst2 ]] && resolve_alternates "$dst2"
        ok "installed $name2 → $dst2"
        ;;
    esac
  done

  (( ${#copied[@]} )) && gum spin --title "Committing…" -- bash -c "push_latest '${copied[*]}'"
  install_secrets
  run_bootstrap
  summary "Synced" "Restart shell / apps to pick up"
}

do_browse() {
  ensure_repo
  local excludes=()
  mapfile -t excludes < <(build_excludes)
  local items=() lnames=()
  while IFS= read -r line; do items+=("$line"); done < <(discover)
  for i in "${items[@]}"; do lnames+=("${i%%|*}"); done
  local rnames=()
  mapfile -t rnames < <(ls -1 "$REPO/configs" 2>/dev/null || true)
  local union=()
  mapfile -t union < <(printf '%s\n' "${lnames[@]}" "${rnames[@]}" | sort -u)
  (( ${#union[@]} )) || die "nothing to browse — no local configs and repo empty"
  banner
  echo " $(gum style --bold --foreground 99 'BROWSE') $(gum style --faint "${#union[@]} total · ${#lnames[@]} local · ${#rnames[@]} in repo")"
  echo
  local name src dst status lsize rsize
  for name in "${union[@]}"; do
    src=""; for i in "${items[@]}"; do [[ ${i%%|*} == "$name" ]] && { src=${i#*|}; break; }; done
    dst=$(dest_for "$name")
    local has_local=0 has_remote=0
    [[ -n $src && -e $src ]] && has_local=1
    [[ -e $REPO/configs/$name ]] && has_remote=1
    if (( has_local && has_remote )); then
      if diff -rq "$REPO/configs/$name" "$dst" >/dev/null 2>&1; then status="in sync"; else status="DIFFERS"; fi
    elif (( has_local )); then status="local-only"
    elif (( has_remote )); then status="remote-only"; else status="?"; fi
    lsize=$(( has_local ? $(human_size "$src") : "-"))
    rsize=$(( has_remote ? $(human_size "$REPO/configs/$name") : "-"))
    printf '%s · %s · local %s → remote %s · → %s\n' "$name" "$status" "$lsize" "$rsize" "$dst"
  done
}
