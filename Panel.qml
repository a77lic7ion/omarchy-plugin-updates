import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Panel half of the Plugin Updates widget. The BarWidget owns the data (the
// check runs once for both the bar badge and this list) and injects itself as
// `hostWidget`; this panel just renders it and forwards update clicks.
Panel {
  id: root
  moduleName: "shaun.plugin-updater"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(root.barForeground, 1.5)
  readonly property color dimmer: Qt.darker(root.barForeground, 1.8)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var rows: root.hostWidget ? root.hostWidget.rows : []
  readonly property bool checking: root.hostWidget ? root.hostWidget.checking : false
  readonly property string checkError: root.hostWidget ? root.hostWidget.checkError : ""
  readonly property int updateCount: root.hostWidget ? root.hostWidget.updateCount : 0
  readonly property int problemCount: {
    var n = 0
    for (var i = 0; i < rows.length; i++)
      if (rows[i].state === "error" || rows[i].state === "dirty") n++
    return n
  }

  property int selectedIndex: 0
  property bool cursorActive: false

  // Fixed row height keeps the list's own height deterministic: binding the
  // list height to ListView.contentHeight feeds back into delegate creation and
  // reports a bogus height on first layout.
  readonly property real rowHeight: Math.max(Style.space(44), Math.round(Style.font.body * 2.4))

  readonly property string statusText: {
    if (root.checking) return "Checking every installed plugin…"
    if (root.checkError !== "") return root.checkError
    if (rows.length === 0) return "Nothing to check yet"
    if (root.updateCount === 0 && root.problemCount > 0) return root.problemCount + " need attention"
    if (root.updateCount === 0) return "All " + rows.length + " plugins are up to date"
    return root.updateCount + " update" + (root.updateCount === 1 ? "" : "s")
      + " available" + (root.problemCount > 0 ? " · " + root.problemCount + " need attention" : "")
  }

  function open() {
    controller.show()
    if (root.hostWidget) root.hostWidget.refresh(true)
    root.selectedIndex = 0
    Qt.callLater(function () { catcher.forceActiveFocus() })
  }
  function close() { controller.hide() }
  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function"
      ? bar.switchPanelFrom(root.hostWidget || root, direction) : false
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(rows.length - 1, root.selectedIndex + delta))
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateSelected() {
    var row = rows[root.selectedIndex]
    if (!row || row.state !== "update" || !root.hostWidget) return
    root.hostWidget.updateOne(row)
    root.close()
  }

  function updateOne(row) {
    if (!root.hostWidget) return
    root.hostWidget.updateOne(row)
    root.close()
  }

  KeyboardPanel {
    id: popout
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: popout.fittedContentWidth(Style.space(430))
    contentHeight: popout.fittedContentHeight(body.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "r" || t === "R") { if (root.hostWidget) root.hostWidget.refresh(true) }
      }

      Column {
        id: body
        width: parent.width
        spacing: Style.spacing.panelGap

        // ------------------------------------------------------------ header
        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Column {
            width: parent.width - checkButton.width - parent.spacing
            spacing: Style.space(2)

            Text {
              text: "Plugin updates"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.statusText
              color: root.updateCount > 0 ? root.barForeground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Button {
            id: checkButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Check"
            iconText: "\uf021"
            iconSpinning: root.checking
            enabled: !root.checking
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.fontFamily
            tooltipText: "Re-check every plugin (r)"
            onClicked: { if (root.hostWidget) root.hostWidget.refresh(true) }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // -------------------------------------------------------------- list
        ListView {
          id: list
          width: parent.width
          implicitHeight: Math.min(Style.space(360),
            Math.max(Style.space(48), root.rows.length * (root.rowHeight + spacing)))
          model: root.rows
          spacing: Style.spacing.xs
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: CursorSurface {
            id: rowItem
            required property var modelData
            required property int index

            width: list.width
            implicitHeight: root.rowHeight
            foreground: root.barForeground
            accent: Color.accent
            hasCursor: root.cursorActive && root.selectedIndex === rowItem.index

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.selectedIndex = rowItem.index
              }
            }

            onHasCursorChanged: if (hasCursor) list.positionViewAtIndex(rowItem.index, ListView.Contain)

            Item {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              implicitHeight: labelColumn.implicitHeight

              PanelActionButton {
                id: rowAction
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: rowItem.modelData.state === "update"
                iconText: "\uf019"
                tooltipText: "Update " + rowItem.modelData.id
                foreground: root.barForeground
                fontFamily: root.fontFamily
                onHovered: function (isHovered) {
                  if (isHovered) { root.cursorActive = true; root.selectedIndex = rowItem.index }
                }
                onClicked: root.updateOne(rowItem.modelData)
              }

              Text {
                id: stateGlyph
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !rowAction.visible
                text: rowItem.modelData.state === "current" ? "\uf00c"
                  : (rowItem.modelData.state === "error" || rowItem.modelData.state === "dirty"
                     ? "\uf071" : "\uf1b2")
                color: (rowItem.modelData.state === "error" || rowItem.modelData.state === "dirty")
                  ? root.urgent : root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                id: labelColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Row {
                  width: parent.width
                  spacing: Style.spacing.sm

                  Text {
                    text: rowItem.modelData.id
                    color: rowItem.modelData.state === "current" ? root.dim : root.barForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: rowItem.modelData.state === "update"
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - (disabledTag.visible ? disabledTag.width + parent.spacing : 0))
                  }

                  Text {
                    id: disabledTag
                    visible: rowItem.modelData.disabled === true
                    text: "· disabled"
                    color: root.dimmer
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  text: rowItem.modelData.detail
                  color: (rowItem.modelData.state === "error" || rowItem.modelData.state === "dirty")
                    ? root.urgent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        // ------------------------------------------------------------ footer
        Column {
          width: parent.width
          spacing: Style.spacing.sm

          Button {
            width: parent.width
            leftAlign: true
            visible: root.updateCount > 1
            text: "Update all " + root.updateCount + " in a terminal"
            iconText: "\uf0ed"
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.fontFamily
            tooltipText: "One terminal per plugin, each installing its reviewed revision"
            onClicked: { if (root.hostWidget) root.hostWidget.updateAll(); root.close() }
          }

          Text {
            width: parent.width
            text: "Update buttons install the revision the marketplace has reviewed "
              + "for that plugin — the commit shown on the row — and the terminal "
              + "verifies both HEAD and the folder itself match it before reloading the shell. "
              + "A plugin folder with local changes is refused: nothing is overwritten or deleted. "
              + "Plugins with no reviewed revision are left alone. Nothing runs "
              + "until you press Enter, and the window stays open so you can read the result."
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}