#!/usr/bin/env bash
# Opens a terminal with COMMAND pre-typed at the prompt. Nothing runs until the
# user presses Enter, so they can read it, edit it, and answer any prompt in a
# real terminal. Mirrors omarchy-launch-floating-terminal-with-presentation
# (setsid + uwsm-app + xdg-terminal-exec) so the window behaves like every other
# Omarchy terminal launch, and falls back to a bare terminal emulator if that
# launcher is missing.
#
# Usage: run-in-terminal.sh <command...>

set -o pipefail

# The command is passed through exactly as the widget built it, which always
# pins a plugin to a marketplace-reviewed commit and verifies it after checkout.
# There is deliberately nothing here that could turn into a branch-head update.
command_text="$*"
[ -n "$command_text" ] || exit 1

# Build a bash single-quoted literal of the command. Our commands never contain
# quotes, but escape them anyway so the buffer can't break out of the literal.
escaped="${command_text//\'/\'\\\'\'}"

script="printf '\033[2mPress Enter to run, or edit the command first.\033[0m\n\n'"
script="$script; read -e -i '$escaped' -p '' typed || true"
script="$script; if [ -n \"\$typed\" ]; then printf '\n'; eval \"\$typed\"; fi"
script="$script; exec bash"

title="Omarchy plugin update"

if command -v xdg-terminal-exec >/dev/null 2>&1; then
  if command -v uwsm-app >/dev/null 2>&1; then
    exec setsid uwsm-app -- xdg-terminal-exec \
      --app-id=org.omarchy.terminal \
      --title="$title" \
      -e bash -c "$script"
  fi
  exec setsid xdg-terminal-exec \
    --app-id=org.omarchy.terminal \
    --title="$title" \
    -e bash -c "$script"
fi

# Fallback for a desktop without xdg-terminal-exec.
for term in "${TERMINAL:-}" alacritty foot ghostty; do
  [ -n "$term" ] || continue
  command -v "$term" >/dev/null 2>&1 || continue
  exec setsid "$term" --title="$title" -e bash -c "$script"
done
if command -v kitty >/dev/null 2>&1; then
  exec setsid kitty --title="$title" bash -c "$script"
fi

echo "run-in-terminal: no terminal emulator found (looked for xdg-terminal-exec, \$TERMINAL, alacritty, foot, ghostty, kitty)" >&2
exit 1