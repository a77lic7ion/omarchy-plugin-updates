# Plugin Updates

A bar widget for the [Omarchy](https://omarchy.org) Quattro shell that checks every
installed shell plugin against the revision the Omarchy plugin marketplace has actually
reviewed, lists what is behind, and moves a plugin to that reviewed revision from a
terminal with the command pre-typed at the prompt.

Plugin id: `shaun.plugin-updater`

## What it does

- Sits in the bar (right section by default) with a small icon and a count badge of
  plugins that are behind their reviewed revision. The icon turns accent-coloured when
  there is something to do.
- Clicking it opens a panel: plugins whose reviewed revision is ahead of what is
  installed come first, then ones that could not be checked, then plugins the marketplace
  does not list or has not reviewed yet, then everything up to date.
- Each row with an update gets an **Update** button and shows the reviewed commit it would
  install. Pressing it opens a terminal with a command already typed that fetches that
  exact commit, checks it out, proves `HEAD` is that commit, runs Omarchy's own
  `omarchy plugin validate`, and only then reloads the shell. Nothing runs until you press
  Enter, so you can read it first, and the window stays open so any error text is readable.
- **Update all** does the same for every pending row, one terminal each, so a failure in
  one plugin cannot abort the others.
- **Check** (or the `r` key) re-checks immediately. Results are otherwise cached, so the
  badge appears instantly after a shell restart instead of waiting on network fetches.

## Why updates are pinned to reviewed revisions

An update never installs a branch head. The marketplace catalogue publishes a
`verificationCommit` for each listed plugin — the commit it has reviewed — and this widget
only ever offers that commit, showing it on the row. Branch heads move without review, so
"update to whatever upstream pushed" is precisely the supply-chain hole the marketplace
flags; pinning to the reviewed commit closes it.

What that means in practice:

- A plugin the catalogue does not list, or lists without a reviewed commit, is shown with
  the reason and gets no **Update** button.
- Checking is read-only: it fetches and compares. Nothing is executed until you press
  Enter in the terminal.
- If you already have commits the reviewed revision does not contain, the row says
  "ahead of reviewed revision …" and no update is offered — the widget never moves a
  plugin backwards.
- A dirty working tree stops the checkout before anything changes: git refuses rather than
  discarding your local edits.
- No password prompt is ever expected or used. Everything here runs as your normal user.

## Requirements

- Omarchy with the Quattro shell (this is a Quattro plugin).
- `bash`, `git`, `jq`, `curl` and a POSIX `timeout` (all present on a stock Omarchy install).
- `xdg-terminal-exec` for the terminal launch; a bare terminal emulator
  (`alacritty`, `foot`, `ghostty`, `kitty`, or `$TERMINAL`) is used as a fallback.
- Network access to `plugins.omarchy.org` (the catalogue) and to your plugins' git remotes.

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
| See what would be installed | The reviewed commit shown on each row |
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

It refreshes the marketplace catalogue at most once every six hours (override with the
`PLUGIN_UPDATER_CATALOG_TTL` environment variable, in seconds). The download is capped at
32 MiB **while streaming** — `curl --max-filesize` plus a hard byte limit on the pipe — so a
hostile, corrupted or simply grown endpoint cannot fill your cache directory, and an
oversized response is deleted rather than parsed (the last good catalogue is kept for that
case). Override the cap with `PLUGIN_UPDATER_CATALOG_MAX_BYTES` if the catalogue ever
outgrows it. Everything is cached under `${XDG_CACHE_HOME:-~/.cache}`:

- `omarchy-plugin-updater.json` — the last check result (delete it if a stale count
  ever bothers you)
- `omarchy-plugin-updater-catalog.json` — the downloaded marketplace catalogue
- `omarchy-plugin-updater-catalog-map.json` — the small id-to-reviewed-commit index built
  from it

## Remove

```bash
omarchy plugin remove shaun.plugin-updater
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/omarchy-plugin-updater{,-catalog,-catalog-map}.json
```

If you placed it by hand instead, delete
`~/.config/omarchy/plugins/shaun.plugin-updater` and remove its entry from
`~/.config/omarchy/shell.json`.

## Notes on what it touches

- Downloads the public marketplace catalogue from `https://plugins.omarchy.org/catalog.json`
  and caches the three files listed above. The download is byte-capped while streaming, so an
  oversized response is cut off and discarded instead of being written or parsed. No account,
  no token, no telemetry.
- Runs `git fetch` against each plugin directory in `~/.config/omarchy/plugins`. That is
  read-only on your files; it only adds fetched objects to each plugin's own git database.
- Never modifies a plugin directory itself. The one thing that changes a checkout is the
  command you confirm in the terminal, and that command only ever checks out the reviewed
  commit and refuses if the verification or Omarchy's validation fails.
- Skips its own directory while scanning, so it cannot try to update itself mid-operation.
- Removal leaves nothing behind except the three cache files above.

## License

MIT — see [LICENSE](LICENSE). Built against the Omarchy Quattro shell plugin API, which
is also MIT licensed.