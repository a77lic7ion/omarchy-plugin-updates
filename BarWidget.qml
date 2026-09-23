import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Owns the data for the plugin update panel: the check script runs here (once,
// not per panel open) so the bar icon badge and the panel list share one source
// of truth. The panel is loaded below and injected with `bar`/`anchorItem`.
BarWidget {
  id: root
  moduleName: "shaun.plugin-updater"

  readonly property string checkScript: String(Qt.resolvedUrl("check-updates.sh")).replace("file://", "")
  readonly property string runScript: String(Qt.resolvedUrl("run-in-terminal.sh")).replace("file://", "")
  readonly property string cacheDir: {
    var xdg = Quickshell.env("XDG_CACHE_HOME")
    return (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.cache"
  }
  readonly property string cacheFile: root.cacheDir + "/omarchy-plugin-updater.json"

  // [{id, dir, state, detail, behind, ahead, disabled, dirty}, ...]
  property var rows: []
  property bool checking: false
  property bool checked: false
  property string checkError: ""
  property double lastChecked: 0

  readonly property int updateCount: {
    var n = 0
    for (var i = 0; i < rows.length; i++) if (rows[i].state === "update") n++
    return n
  }
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }
  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }
  onBarChanged: injectPanel()

  // -- update checking ------------------------------------------------------

  function refresh(force) {
    if (checkProc.running) return
    // The panel calls this on every open; a check from the last two minutes is
    // fresh enough to reuse and keeps opens instant.
    if (!force && root.lastChecked > 0 && (Date.now() - root.lastChecked) < 120000) return
    root.checkError = ""
    root.checking = true
    checkProc.running = true
  }

  function applyResult(text) {
    var parsed = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.length === 0 || line.charAt(0) !== "{") continue
      try { parsed.push(JSON.parse(line)) } catch (e) { }
    }
    if (parsed.length > 0 || root.checked) root.rows = parsed
    root.checked = true
    root.lastChecked = Date.now()
  }

  function loadCache(text) {
    if (root.rows.length > 0) return
    var parsed = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.length === 0) continue
      try {
        var entry = JSON.parse(line)
        if (entry && entry.id) parsed.push(entry)
      } catch (e) { }
    }
    if (parsed.length > 0) {
      root.rows = parsed
      root.checked = true
    }
  }

  // -- updating ------------------------------------------------------------

  // Valid plugin ids only reach a shell buffer (defence against a hand-edited
  // cache file smuggling anything else into the command that gets typed).
  function safeId(value) {
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(value || ""))
  }

  function updateCommand(row) {
    // Refuse anything whose directory name isn't a plain plugin id, so a
    // hand-created folder name can't smuggle shell syntax into the command that
    // gets typed into the terminal.
    if (!safeId(row.dir)) return "echo 'Refusing to update: unsafe plugin directory name'"
    if (row.disabled) {
      // omarchy plugin update refuses ids whose directory is renamed, so a
      // disabled plugin is fast-forwarded directly instead.
      return "git -C \"$HOME/.config/omarchy/plugins/" + row.dir
        + "\" pull --ff-only && omarchy-shell shell rescanPlugins"
    }
    // --yes: skip the interactive diff + gum confirm. Without it the terminal
    // stops on "Changes for <id>:" and waits for a gum prompt, which reads like
    // a hang.
    return "omarchy plugin update " + row.id + " --yes"
  }

  function updateOne(row) {
    var command = updateCommand(row)
    // Logged so the exact command handed to the terminal is visible in the
    // shell journal (journalctl --user | grep plugin-updater) when diagnosing.
    console.log("shaun.plugin-updater: typing → " + command)
    Quickshell.execDetached([root.runScript, command])
  }

  function updateAll() {
    Quickshell.execDetached([root.runScript, "omarchy plugin update --yes"])
  }

  Process {
    id: checkProc
    command: ["bash", root.checkScript]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResult(text)
    }
    onExited: function (exitCode) {
      root.checking = false
      if (exitCode !== 0 && root.rows.length === 0)
        root.checkError = "Update check failed (exit " + exitCode + ")"
    }
  }

  Process {
    id: cacheRead
    command: ["cat", root.cacheFile]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadCache(text)
    }
  }

  Timer {
    interval: 1800000
    running: true
    repeat: true
    onTriggered: root.refresh(true)
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0ed"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    active: root.updateCount > 0
    tooltipText: root.updateCount > 0
      ? root.updateCount + " plugin update" + (root.updateCount === 1 ? "" : "s") + " available"
      : "Omarchy plugin updates"
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }
}