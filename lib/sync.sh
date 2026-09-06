#!/usr/bin/env bash
# sync.sh — two-way reconcile (latest wins) + browse viewer

_local_mt() { # newest mtime among files in a path (epoch seconds)
  local t
  [[ -e $1 ]] || { echo 0; return; }
  # GNU find first, BSD/macOS stat as the fallback
  t=$( { find "$1" -type f -printf '%T@\n' 2>/dev/null \
         || find "$1" -type f -exec stat -f '%m' {} + 2>/dev/null; } \
       | sort -n | tail -1 | cut -d. -f1 )
  echo "${t:-0}"
}

_cloud_ct() { # last git commit time touching a repo config (epoch seconds)
  local t
  t=$(git -C "$REPO" log -1 --format=%ct -- "configs/$1" 2>/dev/null)
  echo "${t:-0}"
}

_hhmm() { # epoch → HH:MM, GNU then BSD
  (( $1 )) || { echo '-'; return; }
  date -d "@$1" +%H:%M 2>/dev/null || date -r "$1" +%H:%M 2>/dev/null || echo '-'
}

_color_action() { # color an action word for the plan view
  case "$1" in
    PUSH*)  gum style --foreground 2 --bold "$1" ;;
    PULL*)  gum style --foreground 6 --bold "$1" ;;
    skip*)  gum style --faint "$1" ;;
    *)      echo "$1" ;;
  esac
}

# _union_names — every config known locally or in the repo, deduped.
# Sets the globals `items` (name|path for local ones) and `union`.
_union_names() {
  items=(); union=()
  local lnames=() rnames=() i line
  while IFS= read -r line; do items+=("$line"); done < <(discover)
  for i in "${items[@]}"; do lnames+=("${i%%|*}"); done
  mapfile -t rnames < <(ls -1 "$REPO/configs" 2>/dev/null || true)
  mapfile -t union < <(printf '%s\n' "${lnames[@]}" "${rnames[@]}" | sort -u)
}

_local_path() { # <name> → discovered source path, or "" if not on this machine
  local i
  for i in "${items[@]}"; do [[ ${i%%|*} == "$1" ]] && { printf '%s' "${i#*|}"; return; }; done
}

_store_config() { # <name> — copy the live config into the repo
  local name=$1 src=$2
  mkdir -p "$REPO/configs/$name"
  if [[ -f $src ]]; then
    cp "$src" "$REPO/configs/$name/"
  else
    rsync -a --delete --delete-excluded "${excludes[@]}" "$src/" "$REPO/configs/$name/"
  fi
}

# do_sync — pull cloud, then per item:
#   local-only  → push
#   remote-only → pull
#   identical   → skip
#   diverged    → newer mtime wins (local mtime vs cloud commit time)
do_sync() {
  ensure_repo
  info "syncing with remote…"; pull_latest

  local excludes=()
  mapfile -t excludes < <(build_excludes)

  local items=() union=()
  _union_names
  (( ${#union[@]} )) || die "nothing to sync — no local configs and repo empty"

  banner
  echo " $(gum style --bold --foreground 99 'SYNC') $(gum style --faint "${#union[@]} items · latest mtime wins")"
  echo

  local name src lmt rct action plan=() lines=()
  local cnt_push=0 cnt_pull=0 cnt_skip=0
  for name in "${union[@]}"; do
    src=$(_local_path "$name")
    local has_local=0 has_remote=0
    [[ -n $src && -e $src ]] && has_local=1
    [[ -e $REPO/configs/$name ]] && has_remote=1
    lmt=0; rct=0

    if (( has_local && has_remote )); then
      lmt=$(_local_mt "$src"); rct=$(_cloud_ct "$name")
      if   same_config "$name"; then action="skip (in sync)"
      elif (( lmt > rct ));     then action="PUSH  (local newer)"
      elif (( rct > lmt ));     then action="PULL  (cloud newer)"
      else                           action="PUSH  (tie → local)"
      fi
    elif (( has_local ));  then action="PUSH  (local-only)"; lmt=$(_local_mt "$src")
    elif (( has_remote )); then action="PULL  (cloud-only)"; rct=$(_cloud_ct "$name")
    else                        action="?"
    fi

    case "$action" in
      PUSH*) cnt_push=$((cnt_push+1)) ;;
      PULL*) cnt_pull=$((cnt_pull+1)) ;;
      *)     cnt_skip=$((cnt_skip+1)) ;;
    esac
    lines+=("$(printf '  %-26s local %-6s cloud %-6s %s' \
      "$name" "$(_hhmm "$lmt")" "$(_hhmm "$rct")" "$(_color_action "$action")")")
    plan+=("$name|$action")
  done

  printf '%s\n' "${lines[@]}"
  echo
  gum style --bold "  Plan: $(gum style --foreground 2 "$cnt_push ↑ push") · $(gum style --foreground 6 "$cnt_pull ↓ pull") · $(gum style --faint "$cnt_skip = skip")"
  echo " $(gum style --faint "PUSH = upload to cloud   PULL = install from cloud   skip = identical")"

  (( cnt_push + cnt_pull )) || { ok "nothing to do — everything in sync"; return 0; }

  gum confirm "Apply this plan?" || exit 0

  local copied=() pulled=() p name2
  for p in "${plan[@]}"; do
    name2=${p%%|*}; action=${p#*|}
    case "$action" in
      PUSH*) src=$(_local_path "$name2")
             [[ -n $src ]] || continue
             _store_config "$name2" "$src"
             copied+=("$name2") ;;
      PULL*) place_config "$name2" && pulled+=("$name2") ;;
    esac
  done

  if (( ${#copied[@]} )); then
    info "committing…"; push_latest "${copied[*]}"
  fi
  install_secrets
  run_bootstrap

  # a PUSH that turned out to be a no-op must not be counted as work done
  (( HERMES_COMMITTED )) || copied=()
  local lines=("")
  (( ${#copied[@]} )) && lines+=("↑ pushed  ${copied[*]}")
  (( ${#pulled[@]} )) && lines+=("↓ pulled  ${pulled[*]}")
  if (( ${#copied[@]} + ${#pulled[@]} == 0 )); then
    summary "Already up to date" "" "nothing to push or pull"
  else
    lines+=("" "Restart shell / apps to pick up.")
    summary "Synced $(plural $(( ${#copied[@]} + ${#pulled[@]} )) config)" "${lines[@]}"
  fi
}

do_browse() {
  ensure_repo
  local items=() union=()
  _union_names
  (( ${#union[@]} )) || die "nothing to browse — no local configs and repo empty"

  banner
  echo " $(gum style --bold --foreground 99 'BROWSE') $(gum style --faint "${#union[@]} total")"
  echo

  local name src dst status lsize rsize
  for name in "${union[@]}"; do
    src=$(_local_path "$name")
    dst=$(dest_for "$name")
    lsize="-"; rsize="-"
    [[ -n $src && -e $src ]] && lsize=$(human_size "$src")
    [[ -e $REPO/configs/$name ]] && rsize=$(human_size "$REPO/configs/$name")

    if   [[ $lsize != - && $rsize != - ]]; then
      same_config "$name" && status="in sync" || status="DIFFERS"
    elif [[ $lsize != - ]]; then status="local-only"
    elif [[ $rsize != - ]]; then status="remote-only"
    else                         status="?"
    fi
    printf '  %-26s %-12s local %-8s repo %-8s → %s\n' \
      "$name" "$status" "$lsize" "$rsize" "$dst"
  done
}
