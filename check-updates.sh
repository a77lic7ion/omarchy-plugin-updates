#!/usr/bin/env bash
# Omarchy plugin update check.
#
# Prints one JSON object per installed shell plugin under
# ~/.config/omarchy/plugins, one per line, updates first:
#
#   {"id":"chyld.pindeck","dir":"chyld.pindeck","state":"update",
#    "detail":"2 commits behind","behind":2,"ahead":0,
#    "disabled":false,"dirty":false}
#
# state: update | current | local | error
#
# Read-only: fetches from each plugin's remote and compares. Never merges,
# pulls, hard-resets or writes anything inside a plugin directory.

set -o pipefail

PLUGIN_DIR="${1:-$HOME/.config/omarchy/plugins}"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

[ -d "$PLUGIN_DIR" ] || exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

emit() {
  # emit <state> <detail> <behind> <ahead> <dirty>
  jq -cn \
    --arg id "$LABEL" \
    --arg dir "$ID" \
    --arg state "$1" \
    --arg detail "$2" \
    --argjson behind "${3:-0}" \
    --argjson ahead "${4:-0}" \
    --argjson disabled "$DISABLED" \
    --argjson dirty "${5:-false}" \
    '{id:$id, dir:$dir, state:$state, detail:$detail, behind:$behind, ahead:$ahead, disabled:$disabled, dirty:$dirty}' \
    >"$tmp/$ID.json" 2>/dev/null
}

check_one() {
  local dir="$1" head upstream branch behind ahead dirty detail
  ID="$(basename "$dir")"
  LABEL="$ID"
  DISABLED=false
  case "$ID" in
  *.disabled)
    DISABLED=true
    LABEL="${ID%.disabled}"
    ;;
  esac

  # A plugin that isn't a git checkout (hand-written local plugin) can't be
  # compared against anything.
  if [ ! -d "$dir/.git" ]; then
    emit local "local plugin, not version controlled" 0 0 false
    return
  fi

  # timeout: a wedged remote must not hang the whole check.
  if ! timeout 25 git -C "$dir" fetch --quiet origin 2>/dev/null; then
    emit error "could not reach its remote" 0 0 false
    return
  fi

  head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  upstream="$(git -C "$dir" rev-parse --verify --quiet '@{upstream}' 2>/dev/null)"
  if [ -z "$upstream" ]; then
    branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [ -n "$branch" ]; then
      upstream="$(git -C "$dir" rev-parse --verify --quiet "origin/$branch" 2>/dev/null)"
    fi
  fi
  if [ -z "$upstream" ]; then
    emit error "no upstream branch tracked" 0 0 false
    return
  fi

  if [ "$head" = "$upstream" ]; then
    emit current "up to date" 0 0 false
    return
  fi

  behind="$(git -C "$dir" rev-list --count "$head..$upstream" 2>/dev/null)"
  ahead="$(git -C "$dir" rev-list --count "$upstream..$head" 2>/dev/null)"
  dirty=false
  [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] && dirty=true

  detail="${behind:-?} commit$([ "${behind:-0}" = "1" ] || echo s) behind"
  [ "${ahead:-0}" != "0" ] && detail="$detail, $ahead local"
  [ "$dirty" = true ] && detail="$detail · uncommitted changes"

  emit update "$detail" "${behind:-0}" "${ahead:-0}" "$dirty"
}

# Fetch a few plugins at a time so the panel fills in quickly without
# hammering GitHub with 16 parallel connections.
batch=0
for dir in "$PLUGIN_DIR"/*/; do
  [ -d "$dir" ] || continue
  check_one "$dir" &
  batch=$((batch + 1))
  if [ "$batch" -ge 4 ]; then
    wait
    batch=0
  fi
done
wait

# Updates first, then errors, then up-to-date, then local-only plugins.
jq -s -c '
  sort_by([(if .state == "update" then 0
            elif .state == "error" then 1
            elif .state == "current" then 2
            else 3 end), .id])[]
' "$tmp"/*.json 2>/dev/null

# Also drop a cache file (one JSON object per line, same shape as stdout) so the
# bar icon can show a count instantly on the next shell restart without waiting
# for a fresh round of fetches.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-plugin-updater.json"
mkdir -p "$(dirname "$cache")" 2>/dev/null
jq -s -c '.[]' "$tmp"/*.json >"$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache"