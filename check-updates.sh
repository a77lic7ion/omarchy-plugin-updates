#!/usr/bin/env bash
# Omarchy plugin update check, pinned to marketplace-reviewed revisions.
#
# Prints one JSON object per installed shell plugin under
# ~/.config/omarchy/plugins, one per line, updates first:
#
#   {"id":"chyld.pindeck","dir":"chyld.pindeck","state":"update",
#    "detail":"2 commits behind · reviewed fd3c85c","sha":"fd3c85c...",
#    "short":"fd3c85c","behind":2,"disabled":false,"dirty":false,
#    "coverage":"snapshot-verified"}
#
# state: update | error | unreviewed | unlisted | current | local
#
# Where the reviewed revision comes from: the marketplace catalogue publishes a
# `verificationCommit` per listed plugin — the exact commit it has reviewed. This
# script resolves every update to that commit and nothing else, so a plugin can
# only ever be moved to a revision the marketplace has already seen. Plugins the
# catalogue does not list, or lists without a reviewed commit, are reported but
# never offered an update.
#
# Read-only: it fetches from remotes (and from the catalogue) to compare. It
# never merges, pulls, checks out, hard-resets or writes inside a plugin
# directory.
#
# The catalogue download is byte-capped while streaming (CATALOG_MAX_BYTES, 32 MiB
# by default) and is deleted rather than parsed when it exceeds the cap, so a
# compromised or oversized endpoint cannot fill the cache filesystem or drive
# unbounded parser memory.

set -o pipefail

PLUGIN_DIR="${1:-$HOME/.config/omarchy/plugins}"
CATALOG_URL="https://plugins.omarchy.org/catalog.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CATALOG_CACHE="$CACHE_DIR/omarchy-plugin-updater-catalog.json"
CATALOG_MAP="$CACHE_DIR/omarchy-plugin-updater-catalog-map.json"
ROWS_CACHE="$CACHE_DIR/omarchy-plugin-updater.json"
CATALOG_TTL="${PLUGIN_UPDATER_CATALOG_TTL:-21600}"             # 6 hours
CATALOG_MAX_BYTES="${PLUGIN_UPDATER_CATALOG_MAX_BYTES:-33554432}" # 32 MiB streaming cap

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

[ -d "$PLUGIN_DIR" ] || exit 0
mkdir -p "$CACHE_DIR" 2>/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# -- the reviewed-revision evidence ------------------------------------------

catalog_is_usable() { jq -e '.plugins' "$1" >/dev/null 2>&1; }

# A catalogue we are willing to read: present, within the byte cap, parseable. The
# size is checked before jq ever sees the file — an oversized one is deleted, not
# parsed, so neither the parser nor the cache filesystem can be driven by it.
catalog_cache_ok() {
  [ -f "$1" ] || return 1
  if [ "$(wc -c <"$1" 2>/dev/null || echo 0)" -gt "$CATALOG_MAX_BYTES" ]; then
    rm -f "$1"
    return 1
  fi
  catalog_is_usable "$1"
}

refresh_catalog() {
  local now mtime age size
  now="$(date +%s)"
  mtime="$(stat -c %Y "$CATALOG_CACHE" 2>/dev/null || echo 0)"
  age=$((now - mtime))
  if [ "$age" -lt "$CATALOG_TTL" ] && catalog_cache_ok "$CATALOG_CACHE"; then
    return 0
  fi
  local tmpcat="$CATALOG_CACHE.tmp"
  rm -f "$tmpcat"
  # The cap is enforced while streaming, not after the fact. curl refuses a
  # response whose declared length is over the cap, and `head -c` stops the pipe
  # after cap+1 bytes, so a compressed, chunked or dishonest response cannot
  # stream unbounded bytes onto the cache filesystem — curl dies on the closed
  # pipe and `set -o pipefail` reports that as a failure. Whatever does arrive is
  # measured again and deleted if it is over the cap, before jq is allowed to
  # read it.
  if timeout 90 curl -fsSL --compressed --max-filesize "$CATALOG_MAX_BYTES" \
    "$CATALOG_URL" 2>/dev/null |
    head -c "$((CATALOG_MAX_BYTES + 1))" >"$tmpcat" &&
    size="$(wc -c <"$tmpcat" 2>/dev/null || echo 0)" &&
    [ "$size" -le "$CATALOG_MAX_BYTES" ] &&
    catalog_is_usable "$tmpcat"; then
    mv "$tmpcat" "$CATALOG_CACHE"
    return 0
  fi
  rm -f "$tmpcat"
  # Fall back to a stale copy rather than reporting nothing — bounded like any
  # other catalogue this script is willing to read.
  catalog_cache_ok "$CATALOG_CACHE"
}

build_map() {
  jq -c '[.plugins[] | {id: .id, sha: (.verificationCommit // ""), coverage: (.verificationCoverage // ""), name: (.name // "")}]' \
    "$CATALOG_CACHE" >"$CATALOG_MAP.tmp" 2>/dev/null && mv "$CATALOG_MAP.tmp" "$CATALOG_MAP"
}

CATALOG_STATE="ok"
if ! refresh_catalog; then
  CATALOG_STATE="unavailable"
else
  build_map || CATALOG_STATE="unavailable"
fi

# lookup <id> -> "<sha>|<coverage>|<name>", empty when the id is not listed
lookup() {
  [ -f "$CATALOG_MAP" ] || return 0
  jq -r --arg id "$1" '([.[] | select(.id == $id)][0]) // empty | "\(.sha)|\(.coverage)|\(.name)"' "$CATALOG_MAP" 2>/dev/null | head -1
}

# -- one plugin --------------------------------------------------------------

emit() {
  # emit <state> <detail> <behind> <dirty>
  jq -cn \
    --arg id "$LABEL" \
    --arg dir "$ID" \
    --arg state "$1" \
    --arg detail "$2" \
    --arg sha "${SHA:-}" \
    --arg short "${SHORT:-}" \
    --arg coverage "${COVERAGE:-}" \
    --argjson behind "${3:-0}" \
    --argjson disabled "$DISABLED" \
    --argjson dirty "${4:-false}" \
    '{id:$id, dir:$dir, state:$state, detail:$detail, sha:$sha, short:$short,
      coverage:$coverage, behind:$behind, disabled:$disabled, dirty:$dirty}' \
    >"$tmp/$ID.json" 2>/dev/null
}

check_one() {
  local dir="$1" entry head behind dirty
  ID="$(basename "$dir")"
  LABEL="$ID"
  DISABLED=false
  SHA=""
  SHORT=""
  COVERAGE=""
  case "$ID" in
  *.disabled)
    DISABLED=true
    LABEL="${ID%.disabled}"
    ;;
  esac

  # A plugin that isn't a git checkout (hand-written local plugin) has no
  # revisions to resolve.
  if [ ! -d "$dir/.git" ]; then
    emit local "local plugin, not version controlled" 0 false
    return
  fi

  if [ "$CATALOG_STATE" = "unavailable" ]; then
    emit error "marketplace catalogue unavailable — no reviewed revisions to compare" 0 false
    return
  fi

  entry="$(lookup "$LABEL")"
  if [ -z "$entry" ]; then
    emit unlisted "not in the marketplace catalogue — no update offered" 0 false
    return
  fi
  SHA="${entry%%|*}"
  COVERAGE="$(printf '%s' "$entry" | cut -d'|' -f2)"
  if ! printf '%s' "$SHA" | grep -Eq '^[0-9a-f]{40}$'; then
    SHA=""
    emit unreviewed "marketplace has not published a reviewed revision yet" 0 false
    return
  fi
  SHORT="${SHA:0:7}"

  # Fetching is read-only; it brings the reviewed revision into the object
  # database so it can be compared and later checked out by SHA.
  timeout 30 git -C "$dir" fetch --quiet origin 2>/dev/null || true
  if ! git -C "$dir" cat-file -e "$SHA^{commit}" 2>/dev/null; then
    # Force-pushed or pruned upstream: ask for the revision by name.
    timeout 30 git -C "$dir" fetch --quiet origin "$SHA" 2>/dev/null || true
  fi
  if ! git -C "$dir" cat-file -e "$SHA^{commit}" 2>/dev/null; then
    emit error "reviewed revision $SHORT is no longer available from its remote" 0 false
    return
  fi

  head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  dirty=false
  [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] && dirty=true

  if [ "$head" = "$SHA" ]; then
    emit current "on reviewed revision $SHORT" 0 "$dirty"
    return
  fi

  if git -C "$dir" merge-base --is-ancestor "$head" "$SHA" 2>/dev/null; then
    behind="$(git -C "$dir" rev-list --count "$head..$SHA" 2>/dev/null)"
    local detail="${behind:-?} commit$([ "${behind:-0}" = "1" ] || echo s) behind · reviewed $SHORT"
    [ "$dirty" = true ] && detail="$detail · uncommitted changes"
    emit update "$detail" "${behind:-0}" "$dirty"
    return
  fi

  if git -C "$dir" merge-base --is-ancestor "$SHA" "$head" 2>/dev/null; then
    emit current "ahead of reviewed revision $SHORT (local commits)" 0 "$dirty"
    return
  fi

  emit error "history diverged from reviewed revision $SHORT" 0 "$dirty"
}

# A few plugins at a time: fills the panel quickly without hammering GitHub.
refresh_catalog || true
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

# Updates first, then problems, then the rest that can be acted on, then
# checkouts nobody can offer an update for.
jq -s -c '
  sort_by([(if .state == "update" then 0
            elif .state == "error" then 1
            elif .state == "unreviewed" then 2
            elif .state == "unlisted" then 3
            elif .state == "current" then 4
            else 5 end), .id])[]
' "$tmp"/*.json 2>/dev/null

# Also drop a cache file (one JSON object per line, same shape as stdout) so the
# bar icon can show a count instantly on the next shell restart without waiting
# for a fresh round of fetches.
mkdir -p "$(dirname "$ROWS_CACHE")" 2>/dev/null
jq -s -c '.[]' "$tmp"/*.json >"$ROWS_CACHE.tmp" 2>/dev/null && mv "$ROWS_CACHE.tmp" "$ROWS_CACHE"