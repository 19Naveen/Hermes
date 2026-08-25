#!/usr/bin/env bash
# discover.sh — what gets tracked, and the alternates engine

# folders whose children each become a pickable item
SOURCES=(
  "$HOME/.config"
)

# exact paths OUTSIDE .config worth backing up: name|path
# ($HOME written literally keeps them portable across machines)
SPECIALS=(
  "zshrc|\$HOME/.zshrc"
  "claude-settings|\$HOME/.claude/settings.json"
)

# user's own additions — survives hermes update; one name|path per line
USER_EXTRAS="$HOME/.config/hermes/extras"
if [[ -f $USER_EXTRAS ]]; then
  while IFS= read -r line; do
    [[ $line =~ ^[^\#\|]+\|.+ ]] && SPECIALS+=("$line")
  done < "$USER_EXTRAS"
fi

# junk never backed up (matched anywhere inside a config dir)
IGNORES=(
  node_modules __pycache__ .venv venv .cache cache Cache CachedData
  GPUCache "Code Cache" .terraform target .git *.log *.tmp
  .DS_Store Thumbs.db dist build out .next
)

discover() {
  (
    local src s spath
    for src in "$HOME/.config"/*; do
      [[ -e $src ]] || continue
      echo "$(basename "$src")|$src"
    done
    for s in "${SPECIALS[@]}"; do
      spath=$(eval echo "${s#*|}")
      [[ -e $spath ]] && echo "${s%%|*}|$spath"
    done
  ) | sort -u
}

dest_for() {
  local s spath
  for s in "${SPECIALS[@]}"; do
    [[ ${s%%|*} == "$1" ]] && { eval echo "${s#*|}"; return; }
  done
  echo "$HOME/.config/$1"
}

build_excludes() {
  local pat
  for pat in "${IGNORES[@]}"; do printf '%s\n' "--exclude=$pat"; done
  if [[ -f $HOME/.config/hermes/ignore ]]; then
    while IFS= read -r pat; do
      [[ -n $pat && $pat != \#* ]] && printf '%s\n' "--exclude=$pat"
    done < "$HOME/.config/hermes/ignore"
  fi
}

# ---- alternates (yadm-inspired) -------------------------------------------
# foo.conf##host=work or foo.conf##os=Darwin replaces foo.conf on matching
# machines. Resolved against the INSTALLED tree after rsync.
_alt_matches() {
  case $1 in
    os=*)   [[ $(uname -s) == "${1#os=}" ]] ;;
    host=*) [[ ${HOSTNAME%%.*} == "${1#host=}" ]] ;;
    *)      return 1 ;;
  esac
}

resolve_alternates() {
  local root=$1 f base cond winner
  while IFS= read -r f; do
    base=${f%%##*}
    winner=""
    while IFS= read -r cand; do
      cond=${cand##*##}
      _alt_matches "$cond" && winner=$cand
    done < <(find "$(dirname "$f")" -maxdepth 1 -name "$(basename "$base")##*" 2>/dev/null)
    if [[ -n $winner ]]; then
      rm -rf "$base"
      mv "$winner" "$base"
      ok "alternate: $(basename "$base") ← $(basename "$winner")"
    fi
  done < <(find "$root" -name '*##*' 2>/dev/null)
  find "$root" -name '*##*' -exec rm -rf {} + 2>/dev/null || true
}
