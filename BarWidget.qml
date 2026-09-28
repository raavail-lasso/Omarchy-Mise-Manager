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
  property var suggestions: []
  property string filterText: ""
  property string activeTab: "updates"
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
  readonly property bool autoPrune: settings && settings.autoPrune === true
  readonly property var toolRows: Model.rows(installed, globals, updates, prunable, filterText)
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
        } else {
          updates = data
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

  function runAction(args, label, pruneUpgrade) {
    if (busy) return
    errorMessage = ""
    actionMessage = label + "…"
    actionLabel = label
    upgradeProgress = ({})
    actionErrOffset = 0
    actionErrLine = ""
    var command = ["mise", "-C", home, "-y"].concat(args)
    actionProc.command = pruneUpgrade ? ["env", "MISE_UPGRADE_AUTO_PRUNE=1"].concat(command) : command
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
    runAction(["upgrade"].concat(autoPrune ? [] : ["--no-prune"], names), label, autoPrune)
  }

  function setAutoPrune(value) {
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.autoPrune = value
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
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
    var query = addField.text.trim()
    if (query.length < 2 || query.indexOf("@") !== -1) { suggestions = []; return }
    if (searchProc.running) { searchPending = true; return }
    searchProc.currentQuery = query
    searchProc.command = ["mise", "search", "--no-header", "--match-type", "contains", query]
    searchProc.running = true
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
        root.actionMessage = root.actionLabel + " complete"
        if (root.actionLabel.indexOf("Installing ") === 0) addField.text = ""
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
      if (currentQuery === addField.text.trim())
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
            text: "Refresh"
            focusable: true
            enabled: !root.busy
            onClicked: root.refresh()
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

        ButtonGroup {
          options: [
            { value: "updates", label: "Updates" + (root.updateCount ? " (" + root.updateCount + ")" : "") },
            { value: "tools", label: "Tools" },
            { value: "add", label: "Add" }
          ]
          value: root.activeTab
          onChanged: function(value) { root.activeTab = value }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.2)
        }

        Column {
          visible: root.activeTab === "updates"
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            Text {
              text: "Available updates"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.fillWidth: true
            }
            Button {
              text: "Update all"
              focusable: true
              enabled: !root.busy && root.updateRows.length > 0
              onClicked: root.upgradeTools(root.updateRows.map(function(item) { return item.name }), "Updating tools")
            }
          }

          Flickable {
            width: parent.width
            height: Math.min(updateList.implicitHeight, Style.space(250))
            contentHeight: updateList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: updateList
              width: parent.width
              spacing: Style.space(3)

              Text {
                visible: root.updateRows.length === 0
                text: root.busy ? "Loading updates…" : "All global tools are up to date"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.updateRows
                Column {
                  id: updateRow
                  required property var modelData
                  width: updateList.width
                  spacing: Style.space(5)

                  Rectangle {
                    width: parent.width
                    height: 1
                    color: Util.alpha(root.foreground, 0.2)
                  }
                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)
                    Column {
                      Layout.fillWidth: true
                      Text {
                        text: updateRow.modelData.name
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                      Text {
                        text: "Latest " + updateRow.modelData.latest
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                    Button {
                      visible: root.upgradingTools.indexOf(updateRow.modelData.name) === -1
                      text: "Update"
                      focusable: true
                      enabled: !root.busy
                      onClicked: root.upgradeTools([updateRow.modelData.name], "Updating " + updateRow.modelData.name)
                    }
                    Column {
                      id: inlineProgress
                      readonly property var progress: root.upgradeProgress[updateRow.modelData.name]
                      visible: root.upgradingTools.indexOf(updateRow.modelData.name) !== -1
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
                  }
                }
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Auto-prune after updates"
            description: root.autoPrune
              ? "On · Mise removes eligible versions after its configured grace period."
              : "Off · Keep replaced versions installed."
            checked: root.autoPrune
            enabled: !root.busy
            onClicked: root.setAutoPrune(!root.autoPrune)
          }
        }

        TextField {
          id: filterField
          visible: root.activeTab === "tools"
          width: parent.width
          placeholderText: "Filter tools"
          onTextChanged: root.filterText = text
        }

        Flickable {
          visible: root.activeTab === "tools"
          width: parent.width
          height: Math.min(toolList.implicitHeight, Style.space(370))
          contentHeight: toolList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: toolList
            width: parent.width
            spacing: Style.space(4)

            Text {
              visible: root.toolRows.length === 0
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
                width: toolList.width
                spacing: Style.space(4)

                PanelSectionHeader {
                  visible: toolRow.index === 0 || root.toolRows[toolRow.index - 1].configured !== toolRow.tool.configured
                  text: toolRow.tool.configured ? "SELECTED GLOBALLY" : "INSTALLED, NOT SELECTED"
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

                  Repeater {
                    model: toolRow.tool.versions
                    RowLayout {
                      id: versionRow
                      required property var modelData
                      readonly property var version: modelData
                      width: toolRow.width
                      spacing: Style.space(5)
                      Text {
                        text: "  " + versionRow.version.version
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

                  Button {
                    visible: toolRow.tool.configured
                    text: "Unselect global"
                    tooltipText: "Remove from global config; keep installed versions"
                    focusable: true
                    enabled: !root.busy
                    onClicked: root.confirmAction(
                      ["unuse", "--global", "--no-prune", toolRow.tool.name],
                      "Unselecting " + toolRow.tool.name,
                      "Remove " + toolRow.tool.name + " from global mise configuration? Installed versions will stay.")
                  }
                }
              }
            }
          }
        }

        Column {
          visible: root.activeTab === "add"
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "SEARCH THE MISE REGISTRY"; foreground: root.foreground }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: addField
              placeholderText: "Search or enter tool@version"
              Layout.fillWidth: true
              onTextChanged: { root.suggestions = []; searchDelay.restart() }
              onAccepted: root.installTool(text)
            }
            Button {
              text: "Install"
              focusable: true
              enabled: !root.busy && Model.validToolSpec(addField.text)
              onClicked: root.installTool(addField.text)
            }
          }

          Repeater {
            model: root.suggestions
            Column {
              id: suggestionRow
              required property var modelData
              readonly property var suggestion: modelData
              width: content.width
              spacing: Style.space(4)
              Rectangle {
                width: parent.width
                height: 1
                color: Util.alpha(root.foreground, 0.2)
              }
              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                Column {
                  Layout.fillWidth: true
                  Text {
                    text: suggestionRow.suggestion.name
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    text: suggestionRow.suggestion.description
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }
                Button {
                  text: "Install"
                  focusable: true
                  enabled: !root.busy
                  onClicked: root.installTool(suggestionRow.suggestion.name)
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
