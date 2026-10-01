pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "raavail.mise-manager"
  ipcTarget: moduleName

  readonly property string home: Quickshell.env("HOME") || ""
  property var installed: ({})
  property var globals: ({})
  property var prunable: ({})
  property var updates: ({})
  property var miseSettings: ({})
  property var suggestions: []
  property string filterText: ""
  property bool showSettings: false
  readonly property string settingsLabel: "Saving mise settings"
  property string expandedTool: ""
  property string queryStage: ""
  property bool refreshPending: false
  property bool searchPending: false
  property string errorMessage: ""
  property string actionMessage: ""
  property string actionLabel: ""
  property var upgradingTools: []
  property var upgradeProgress: ({})
  property int actionErrOffset: 0
  property string actionErrLine: ""
  property var pendingArgs: []
  property string pendingLabel: ""
  property string pendingMessage: ""
  property double lastChecked: 0

  readonly property bool busy: queryStage !== "" || actionProc.running
  readonly property var upgradeSettings: miseSettings.upgrade || ({})
  readonly property bool autoPrune: upgradeSettings.auto_prune === true
  readonly property string pruneAfter: String(upgradeSettings.prune_after || "")
  readonly property string releaseAge: String(miseSettings.minimum_release_age || "")
  readonly property var releaseAgeExcludes: Array.isArray(miseSettings.minimum_release_age_excludes) ? miseSettings.minimum_release_age_excludes : []
  readonly property var prunePresets: [
    { value: "0s", label: "Now" }, { value: "1d", label: "1d" },
    { value: "7d", label: "7d" }, { value: "30d", label: "30d" }
  ]
  readonly property var cooldownPresets: [
    { value: "", label: "Off" }, { value: "1d", label: "1d" }, { value: "3d", label: "3d" },
    { value: "7d", label: "7d" }, { value: "14d", label: "14d" }
  ]
  readonly property var toolRows: Model.rows(installed, globals, updates, prunable, filterText)
  readonly property int prunableCount: Object.keys(prunable).reduce(function(count, name) {
    return count + (Array.isArray(prunable[name]) ? prunable[name].length : 0)
  }, 0)
  readonly property var addRows: Model.addRows(filterText, suggestions, Object.assign({}, installed, globals))
  readonly property var updateRows: Model.rows(installed, globals, updates, prunable, "").filter(function(item) { return item.latest !== "" })
  readonly property int updateCount: Model.updateCount(globals, updates)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    if (!busy && Date.now() - lastChecked > 300000) refresh()
    controller.show()
  }

  function refresh(clearError) {
    if (busy) { refreshPending = true; return }
    if (clearError !== false) errorMessage = ""
    lastChecked = Date.now()
    startQuery("installed", ["ls", "--installed", "--json"])
  }

  function startQuery(stage, args) {
    queryStage = stage
    queryProc.command = ["mise", "-C", home].concat(args)
    queryProc.running = true
  }

  function finishQuery(exitCode) {
    var stage = queryStage
    if (exitCode !== 0) {
      errorMessage = "mise " + stage + " failed: " + String(queryErr.text || queryOut.text || "unknown error").trim().slice(0, 240)
      queryStage = ""
    } else {
      try {
        var data = Model.objectFromJson(queryOut.text)
        if (stage === "installed") {
          installed = data
          Qt.callLater(function() { root.startQuery("global", ["ls", "--global", "--json"]) })
        } else if (stage === "global") {
          globals = data
          Qt.callLater(function() { root.startQuery("prunable", ["ls", "--prunable", "--json"]) })
        } else if (stage === "prunable") {
          prunable = data
          Qt.callLater(function() { root.startQuery("outdated", ["outdated", "--json"]) })
        } else if (stage === "outdated") {
          updates = data
          Qt.callLater(function() { root.startQuery("settings", ["settings", "ls", "--all", "--json"]) })
        } else {
          miseSettings = data
          lastChecked = Date.now()
          queryStage = ""
        }
      } catch (e) {
        errorMessage = "Could not read mise " + stage + " output: " + e
        queryStage = ""
      }
    }
    if (queryStage === "" && refreshPending) {
      refreshPending = false
      Qt.callLater(root.refresh)
    }
  }

  function runAction(args, label) {
    if (busy) return
    errorMessage = ""
    actionMessage = label + "…"
    actionLabel = label
    upgradeProgress = ({})
    actionErrOffset = 0
    actionErrLine = ""
    actionProc.command = ["mise", "-C", home, "-y"].concat(args)
    actionProc.running = true
  }

  function readActionProgress(output) {
    if (upgradingTools.length === 0) return
    if (output.length < actionErrOffset) { actionErrOffset = 0; actionErrLine = "" }
    var lines = (actionErrLine + output.slice(actionErrOffset)).split(/\r?\n/)
    actionErrOffset = output.length
    actionErrLine = lines.pop()
    for (var i = 0; i < lines.length; i++) {
      var progress = Model.upgradeProgressLine(lines[i], upgradingTools)
      if (!progress) continue
      var next = Object.assign({}, upgradeProgress)
      next[progress.name] = progress
      upgradeProgress = next
    }
  }

  function upgradeTools(names, label) {
    if (busy) return
    upgradingTools = names.slice()
    runAction(["upgrade"].concat(names), label)
  }

  // Writes ~/.config/mise/config.toml, so terminal `mise` follows these too.
  function setMiseSetting(key, value) {
    runAction(value === null ? ["settings", "unset", key] : ["settings", "set", key, String(value)], root.settingsLabel)
  }

  // Edits the version key only, so tool options like allow_builds survive.
  function setPinned(tool, pin) {
    runAction(["config", "set", "--global", "tools." + tool.name + ".version", pin ? tool.activeVersion : "latest"],
      (pin ? "Pinning " : "Unpinning ") + tool.name)
  }

  function toggleCooldownSkip(name) {
    var next = releaseAgeExcludes.filter(function(item) { return item !== name })
    if (next.length === releaseAgeExcludes.length) next.push(name)
    setMiseSetting("minimum_release_age_excludes", next.join(","))
  }

  function confirmAction(args, label, message) {
    if (busy) return
    pendingArgs = args
    pendingLabel = label
    pendingMessage = message
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
    Qt.callLater(function() { focusArea.forceActiveFocus() })
  }

  function installTool(spec) {
    var value = String(spec || "").trim()
    if (!Model.validToolSpec(value)) {
      errorMessage = "Enter one tool name or tool@version, with no spaces."
      return
    }
    runAction(["use", "--global", value], "Installing " + value)
  }

  function searchTools() {
    var query = searchField.text.trim()
    if (query.length < 2 || query.indexOf("@") !== -1) { suggestions = []; return }
    if (searchProc.running) { searchPending = true; return }
    searchProc.currentQuery = query
    searchProc.command = ["mise", "search", "--no-header", "--match-type", "contains", query]
    searchProc.running = true
  }

  onOpenedChanged: {
    if (opened || busy) return
    actionMessage = ""
    errorMessage = ""
  }

  // ponytail: each bar instance scans separately; share a service if multi-monitor polling becomes costly.
  Component.onCompleted: refresh()

  Timer {
    interval: 1800000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: messageTimer
    interval: 4000
    onTriggered: if (!actionProc.running) root.actionMessage = ""
  }

  Timer {
    id: searchDelay
    interval: 300
    onTriggered: root.searchTools()
  }

  Process {
    id: queryProc
    stdout: StdioCollector { id: queryOut; waitForEnd: true }
    stderr: StdioCollector { id: queryErr; waitForEnd: true }
    onExited: function(exitCode) { root.finishQuery(exitCode) }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: false
      onTextChanged: root.readActionProgress(text)
    }
    onExited: function(exitCode) {
      root.upgradingTools = []
      root.upgradeProgress = ({})
      if (exitCode === 0) {
        root.actionMessage = root.actionLabel === root.settingsLabel ? "" : root.actionLabel + " complete"
        messageTimer.restart()
        if (root.actionLabel.indexOf("Installing ") === 0) searchField.text = ""
      } else {
        root.errorMessage = root.actionLabel + " failed: " + String(actionErr.text || actionOut.text || "unknown error").trim().slice(0, 240)
        root.actionMessage = ""
      }
      root.refreshPending = false
      Qt.callLater(function() { root.refresh(false) })
    }
  }

  Process {
    id: searchProc
    property string currentQuery: ""
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (currentQuery === searchField.text.trim())
        root.suggestions = exitCode === 0 ? Model.searchResults(searchOut.text) : []
      if (root.searchPending) {
        root.searchPending = false
        Qt.callLater(root.searchTools)
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.bar && root.bar.vertical ? "󰏗" : "󰏗" + (root.updateCount ? " " + root.updateCount : "")
    active: root.updateCount > 0
    tooltipText: root.errorMessage || (root.updateCount ? root.updateCount + " mise updates available" : "Mise Manager")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: focusArea
    contentWidth: popup.fittedContentWidth(Style.space(500))
    contentHeight: popup.fittedContentHeight(Math.min(content.implicitHeight, Style.space(600)))

    Item {
      id: focusArea
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (confirmDialog.opened) {
          event.accepted = confirmDialog.handleKey(event)
        } else if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "Mise Manager"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              Layout.fillWidth: true
            }

            Button {
              visible: root.updateRows.length > 0
              text: "Update all (" + root.updateRows.length + ")"
              focusable: true
              enabled: !root.busy
              onClicked: root.upgradeTools(root.updateRows.map(function(item) { return item.name }), "Updating tools")
            }

            Button {
              iconText: "󰑐"
              tooltipText: "Refresh"
              focusable: true
              enabled: !root.busy
              onClicked: root.refresh()
            }

            Button {
              iconText: "󰒓"
              tooltipText: "Settings"
              focusable: true
              selected: root.showSettings
              onClicked: {
                root.showSettings = !root.showSettings
                focusArea.forceActiveFocus()  // Button keeps focus after a click, which looks selected.
              }
            }
          }

          Text {
            width: parent.width
            visible: root.errorMessage !== "" || (root.busy && (!actionProc.running || root.upgradingTools.length === 0)) || (!root.busy && root.actionMessage !== "")
            text: root.errorMessage || (root.busy ? (actionProc.running ? root.actionMessage : "Checking mise tools…") : root.actionMessage)
            textFormat: Text.PlainText
            color: root.errorMessage ? (root.bar ? root.bar.urgent : Color.urgent) : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.showSettings
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "Auto-prune"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              ToggleSwitch {
                checked: root.autoPrune
                busy: root.busy
                onToggled: root.setMiseSetting("upgrade.auto_prune", !root.autoPrune)
              }
              Item { Layout.fillWidth: true }
              ButtonGroup {
                visible: root.autoPrune
                options: Model.presetOptions(root.prunePresets, root.pruneAfter)
                value: root.pruneAfter
                fontSize: Style.font.bodySmall
                enabled: !root.busy
                onChanged: function(value) { root.setMiseSetting("upgrade.prune_after", value) }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "Release cooldown"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
              }
              ButtonGroup {
                options: Model.presetOptions(root.cooldownPresets, root.releaseAge)
                value: root.releaseAge
                fontSize: Style.font.bodySmall
                enabled: !root.busy
                onChanged: function(value) { root.setMiseSetting("minimum_release_age", value || null) }
              }
            }

            RowLayout {
              visible: root.prunableCount > 0
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: root.prunableCount + " unused versions installed"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
              }
              Button {
                text: "Clean up"
                focusable: true
                enabled: !root.busy
                onClicked: root.confirmAction(["prune"], "Removing unused versions",
                  "Delete " + root.prunableCount + " installed versions that no mise config uses? Versions used by your projects are kept.")
              }
            }
          }

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search tools or add tool@version"
            onTextChanged: {
              root.filterText = text
              root.suggestions = []
              searchDelay.restart()
            }
          }

          Flickable {
            width: parent.width
            height: Math.min(toolList.implicitHeight, Style.space(400))
            contentHeight: toolList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: toolList
              width: parent.width
              spacing: Style.space(4)

              Text {
                visible: root.toolRows.length === 0 && root.addRows.length === 0
                text: root.busy ? "Loading tools…" : "No matching mise tools"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.toolRows

                Column {
                  id: toolRow
                  required property var modelData
                  required property int index
                  readonly property var tool: modelData
                  readonly property bool upgrading: root.upgradingTools.indexOf(tool.name) !== -1
                  readonly property bool canPin: tool.configured && tool.activeVersion !== "" && tool.name.indexOf(".") === -1
                  readonly property bool canSkip: tool.configured && root.releaseAge !== ""
                  width: toolList.width
                  spacing: Style.space(4)

                  PanelSectionHeader {
                    visible: !toolRow.tool.configured && (toolRow.index === 0 || root.toolRows[toolRow.index - 1].configured)
                    text: "INSTALLED, NOT SELECTED"
                    foreground: root.foreground
                  }

                  Rectangle {
                    width: parent.width
                    height: 1
                    color: Util.alpha(root.foreground, 0.2)
                  }

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(5)
                    Text {
                      text: toolRow.tool.name
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Text {
                      text: toolRow.tool.displayVersion
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      visible: toolRow.tool.latest !== ""
                      text: "→ " + toolRow.tool.latest
                      textFormat: Text.PlainText
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      visible: toolRow.tool.pinned
                      text: "Pinned"
                      textFormat: Text.PlainText
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Text {
                      visible: toolRow.tool.configured && toolRow.tool.activeVersion === ""
                      text: "Not installed"
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Button {
                      visible: !toolRow.tool.configured && toolRow.tool.displayVersion !== ""
                      text: "Select"
                      focusable: true
                      enabled: !root.busy
                      onClicked: root.runAction(["use", "--global", toolRow.tool.name + "@" + toolRow.tool.displayVersion], "Selecting " + toolRow.tool.name + "@" + toolRow.tool.displayVersion)
                    }
                    Button {
                      visible: toolRow.tool.latest !== "" && !toolRow.upgrading
                      text: "Update"
                      focusable: true
                      enabled: !root.busy
                      onClicked: root.upgradeTools([toolRow.tool.name], "Updating " + toolRow.tool.name)
                    }
                    Column {
                      id: inlineProgress
                      readonly property var progress: root.upgradeProgress[toolRow.tool.name]
                      visible: toolRow.upgrading
                      Layout.preferredWidth: Style.space(110)
                      spacing: Style.space(4)
                      Text {
                        width: parent.width
                        text: inlineProgress.progress
                          ? inlineProgress.progress.phase.charAt(0).toUpperCase() + inlineProgress.progress.phase.slice(1)
                            + (inlineProgress.progress.percent === null ? "…" : " " + inlineProgress.progress.percent + "%")
                          : "Updating…"
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                      Rectangle {
                        id: progressTrack
                        width: parent.width
                        height: Style.space(3)
                        radius: height / 2
                        color: Util.alpha(root.foreground, 0.2)
                        Rectangle {
                          visible: !!inlineProgress.progress && inlineProgress.progress.percent !== null
                          width: parent.width * (inlineProgress.progress ? inlineProgress.progress.percent || 0 : 0) / 100
                          height: parent.height
                          radius: height / 2
                          color: Color.accent
                        }
                        Rectangle {
                          id: progressPulse
                          visible: !inlineProgress.progress || inlineProgress.progress.percent === null
                          width: parent.width * 0.35
                          height: parent.height
                          radius: height / 2
                          color: Color.accent
                          NumberAnimation on x {
                            from: 0
                            to: progressTrack.width - progressPulse.width
                            duration: 900
                            loops: Animation.Infinite
                            running: inlineProgress.visible && progressPulse.visible
                          }
                        }
                      }
                    }
                    Button {
                      visible: toolRow.tool.configured || toolRow.tool.versions.length > 0
                      text: root.expandedTool === toolRow.tool.name ? "⌃" : "⌄"
                      tooltipText: "Manage " + toolRow.tool.name + " versions"
                      focusable: true
                      onClicked: root.expandedTool = root.expandedTool === toolRow.tool.name ? "" : toolRow.tool.name
                    }
                  }

                  Column {
                    visible: root.expandedTool === toolRow.tool.name
                    width: parent.width
                    spacing: Style.space(3)

                    RowLayout {
                      visible: toolRow.tool.configured
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        visible: toolRow.canPin
                        text: "Pin version"
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                      ToggleSwitch {
                        visible: toolRow.canPin
                        checked: toolRow.tool.pinned
                        busy: root.busy
                        onToggled: root.setPinned(toolRow.tool, !toolRow.tool.pinned)
                      }
                      Text {
                        visible: toolRow.canSkip
                        Layout.leftMargin: toolRow.canPin ? Style.space(12) : 0
                        text: "Skip cooldown"
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                      ToggleSwitch {
                        visible: toolRow.canSkip
                        checked: root.releaseAgeExcludes.indexOf(toolRow.tool.name) !== -1
                        busy: root.busy
                        onToggled: root.toggleCooldownSkip(toolRow.tool.name)
                      }
                      Item { Layout.fillWidth: true }
                      Button {
                        text: "Uninstall"
                        tooltipText: "Remove from global config and delete unused versions"
                        focusable: true
                        enabled: !root.busy
                        onClicked: root.confirmAction(
                          ["unuse", "--global", toolRow.tool.name],
                          "Uninstalling " + toolRow.tool.name,
                          "Uninstall " + toolRow.tool.name + "? Versions used by your projects are kept.")
                      }
                    }

                    Repeater {
                      model: toolRow.tool.versions
                      RowLayout {
                        id: versionRow
                        required property var modelData
                        readonly property var version: modelData
                        width: toolRow.width
                        spacing: Style.space(5)
                        Text {
                          text: versionRow.version.version
                          textFormat: Text.PlainText
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          Layout.fillWidth: true
                        }
                        Button {
                          text: "Select"
                          tooltipText: "Select this version globally"
                          focusable: true
                          enabled: !root.busy
                          onClicked: root.runAction(["use", "--global", toolRow.tool.name + "@" + versionRow.version.version], "Selecting " + toolRow.tool.name + "@" + versionRow.version.version)
                        }
                        Button {
                          visible: versionRow.version.prunable
                          text: "Delete"
                          tooltipText: "Delete this unused installed version"
                          focusable: true
                          enabled: !root.busy
                          onClicked: root.confirmAction(
                            ["uninstall", toolRow.tool.name + "@" + versionRow.version.version],
                            "Deleting " + toolRow.tool.name + "@" + versionRow.version.version,
                            "Delete the installed " + toolRow.tool.name + "@" + versionRow.version.version + " files? mise currently reports this version as unused.")
                        }
                      }
                    }
                  }
                }
              }

              Repeater {
                model: root.addRows
                Column {
                  id: addRow
                  required property var modelData
                  width: toolList.width
                  spacing: Style.space(4)
                  Rectangle {
                    width: parent.width
                    height: 1
                    color: Util.alpha(root.foreground, 0.2)
                  }
                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      text: addRow.modelData.name
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      text: addRow.modelData.description
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    Button {
                      text: "Install"
                      focusable: true
                      enabled: !root.busy
                      onClicked: root.installTool(addRow.modelData.name)
                    }
                  }
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        message: root.pendingMessage
        onCanceled: opened = false
        onConfirmed: {
          opened = false
          root.runAction(root.pendingArgs, root.pendingLabel)
        }
      }
    }
  }
}
