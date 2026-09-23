# Plugin Updates

A bar widget for the [Omarchy](https://omarchy.org) Quattro shell that checks every
installed shell plugin for upstream updates, lists them in a panel, and updates them
one at a time by opening a terminal with the update command pre-typed at the prompt.

Plugin id: `shaun.plugin-updater`

## What it does

- Sits in the bar (right section by default) with a small icon and a count badge of
  plugins that have updates waiting. The icon turns accent-coloured when updates exist.
- Clicking it opens a panel listing every update first, then plugins whose remote could
  not be reached, then up-to-date ones, then plugins that are not git checkouts.
- Each row with an update gets an **Update** button. Pressing it opens a terminal with
  `omarchy plugin update <plugin-id> --yes` already typed at the prompt. Nothing runs
  until you press Enter, so you can read the command, edit it, or answer a password
  prompt in a real terminal, and the window stays open afterwards so any error text is readable.
- **Update all** queues every pending update, one terminal window each.
- **Check** (or the `r` key) re-checks immediately. Results are otherwise cached, so the
  badge appears instantly after a shell restart instead of waiting on network fetches.

Updates are applied with Omarchy's own `omarchy plugin update` CLI, so its validation
step and rollback of a bad revision are preserved. That command is `git fetch` plus a
fast-forward merge inside your home directory — **it runs as your normal user and never
asks for root access**. This widget never escalates privileges; if a system password
prompt ever appears, something else is involved, so read the command in the terminal
before pressing Enter.

Plugins whose folder has been renamed to `<id>.disabled` are refused by the Omarchy CLI
(as are hand-cloned directories that are not valid plugin ids), so those rows type a
plain `git -C <dir> pull --ff-only && omarchy-shell shell rescanPlugins` instead. Both
command forms are normalised by the launcher script before they are typed, so the
non-interactive `--yes` form is what always ends up at the prompt.

## Requirements

- Omarchy with the Quattro shell (this is a Quattro plugin).
- `bash`, `git`, `jq`, and a POSIX `timeout` (all present on a stock Omarchy install).
- `xdg-terminal-exec` for the terminal launch; a bare terminal emulator
  (`alacritty`, `foot`, `ghostty`, `kitty`, or `$TERMINAL`) is used as a fallback.
- Network access to your plugins' git remotes when checking.

## Install

```bash
omarchy plugin add https://github.com/a77lic7ion/omarchy-plugin-updates.git --enable
```

Already cloned it yourself? Move it into `~/.config/omarchy/plugins/shaun.plugin-updater`
and enable it:

```bash
omarchy plugin enable shaun.plugin-updater
omarchy bar move shaun.plugin-updater --after io.github.dgoran.omastart
```

## Usage

| Action | How |
| --- | --- |
| Check for updates | Click the bar icon (or press `r` in the panel for a fresh check) |
| Update one plugin | Its row's **Update** button, then press Enter in the terminal |
| Update everything | **Update all**, one terminal per plugin |
| Close the panel | `Escape`, or click the bar icon again |
| Open/close from a keybind | `omarchy-shell shell summon shaun.plugin-updater '{}'` / `omarchy-shell shell hide shaun.plugin-updater` |

Keyboard: `↑` / `↓` move, `Enter` activates, `r` re-checks, `Escape` closes.

## Configure

The widget only needs its bar placement — everything else follows your theme, because it
uses the shell's `Style` and `Color` tokens rather than hard-coded colours and sizes.

```bash
omarchy bar move shaun.plugin-updater --section right --index 0
```

Check results are cached at `${XDG_CACHE_HOME:-~/.cache}/omarchy-plugin-updater.json`.
Delete that file if a stale count ever bothers you.

## Remove

```bash
omarchy plugin remove shaun.plugin-updater
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-plugin-updater.json"
```

If you placed it by hand instead, delete
`~/.config/omarchy/plugins/shaun.plugin-updater` and remove its entry from
`~/.config/omarchy/shell.json`. Removal leaves nothing else behind: the widget writes
only that one cache file, and only ever launches terminals.

## Notes on what it touches

- The check script runs `git fetch` against each plugin directory in
  `~/.config/omarchy/plugins` (read-only on your files, network to the remotes) and
  writes the one cache file listed above.
- The widget never runs an update by itself. Every update is a command typed into a
  terminal that you confirm by pressing Enter.
- The plugin's own directory is skipped when scanning, so it cannot try to update itself
  mid-operation.

## License

MIT — see [LICENSE](LICENSE). Built against the Omarchy Quattro shell plugin API, which
is also MIT licensed.
