pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The dashboard: the current block on a big ring, twenty weeks of focus as a
// heatmap, the project (detected, or typed), time per project this week and
// the controls. Like the bar widget it follows state.json and history.jsonl
// and sends actions over IPC, so it works under any bar.
Panel {
  id: root
  moduleName: Model.PLUGIN_ID
  ipcTarget: Model.PLUGIN_ID + ".panel"
  // BarWidget.qml owns the IPC target so it can open on the focused screen.
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/locked-in"
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/locked-in").toString().replace(/^file:\/\//, ""))
  readonly property var config: hostWidget ? hostWidget.config : Model.cleanSettings({})
  readonly property string lang: hostWidget ? hostWidget.lang : "en"

  property var session: Model.initialState()
  property bool dndAvailable: true
  property var entries: []
  property string detected: ""
  property string project: ""
  property double now: Date.now()

  readonly property real remaining: Model.remainingMs(session, now)
  readonly property real done: session.durationMs > 0 ? Math.max(0, Math.min(1, 1 - remaining / session.durationMs)) : 0
  readonly property bool active: session.phase !== "idle"
  readonly property var week: Model.stats(entries, now)
  readonly property var heat: Model.heatmap(entries, now, 20)
  readonly property var projects: Model.byProject(entries, now, 7).slice(0, 3)
  readonly property var suggestions: Model.recentProjects(entries, now, 5).filter(function(p) { return p !== root.project }).slice(0, 4)
  readonly property int heatBlocks: {
    var since = now - 140 * 86400000, n = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].kind === "focus" && entries[i].completed && entries[i].start >= since) n++
    return n
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Util.alpha(foreground, 0.6)
  readonly property color faint: Util.alpha(foreground, 0.32)
  readonly property color well: Util.alpha(foreground, 0.05)
  readonly property color groove: Util.alpha(foreground, 0.1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function tr(key) { return Model.tr(root.lang, key) }
  function send(command, arg) {
    Quickshell.execDetached(arg === undefined ? ["omarchy-shell", Model.PLUGIN_ID, command] : ["omarchy-shell", Model.PLUGIN_ID, command, arg])
  }
  function primary() {
    if (!root.active) root.send("start", root.project)
    else root.send("toggle")
  }
  function endsLabel() {
    var d = new Date(root.now + root.remaining)
    return root.tr("endsAt").arg(Qt.formatTime(d, "HH:mm"))
  }

  onOpenedChanged: {
    if (!opened) return
    root.now = Date.now()
    if (!projectProc.running) projectProc.running = true
  }

  FileView {
    path: root.stateDir + "/state.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        root.session = saved.session || Model.initialState()
        root.dndAvailable = saved.dndAvailable !== false
        if (root.session.phase !== "idle" && root.session.project) root.project = root.session.project
      } catch (e) {}
    }
  }

  FileView {
    path: root.stateDir + "/history.jsonl"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.entries = Model.parseHistory(text())
    onLoadFailed: root.entries = []
  }

  Process {
    id: projectProc
    command: [root.helper, "project"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.detected = String(text || "").trim()
        if (!root.active && root.detected) root.project = root.detected
      }
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  component Label: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }

  component Well: Rectangle {
    radius: Style.space(10)
    color: root.well
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.06)
  }

  component Button: Rectangle {
    id: btn
    property string text: ""
    property bool solid: false
    signal clicked()
    height: Style.space(32)
    radius: Style.space(9)
    color: solid ? root.accent : (btnMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : Util.alpha(root.foreground, 0.05))
    border.width: solid ? 0 : 1
    border.color: Util.alpha(root.foreground, 0.1)
    scale: btnMouse.pressed ? 0.97 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.002 } }
    Label {
      anchors.centerIn: parent
      text: btn.text
      color: btn.solid ? Commons.Color.background : root.foreground
      font.weight: btn.solid ? Font.Bold : Font.DemiBold
    }
    MouseArea { id: btnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(18)
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: projectInput.activeFocus
      onActivateRequested: root.primary()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") root.send("stop")
        else if (t === "s") root.send("skip")
        else if (t === "p") projectInput.forceActiveFocus()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        // Title and where we are in the cycle.
        Item {
          width: parent.width
          height: titleLabel.implicitHeight
          Label { id: titleLabel; text: "LOCKED IN"; font.weight: Font.Black; font.letterSpacing: Style.space(1) }
          Label {
            anchors.right: parent.right
            text: root.active ? root.tr("blockOf").arg(root.session.phase === "focus" ? root.session.cycle + 1 : Math.max(1, root.session.cycle)).arg(root.config.longBreakEvery)
              : root.tr("ready")
            color: root.dim
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Phase lengths, the current one lit.
        Rectangle {
          width: parent.width
          height: Style.space(30)
          radius: Style.space(10)
          color: Util.alpha(root.foreground, 0.04)
          Row {
            anchors.fill: parent
            anchors.margins: Style.space(3)
            Repeater {
              model: [
                { phase: "focus", label: root.tr("focusMode").arg(root.config.focusMinutes) },
                { phase: "short", label: root.tr("breakMode").arg(root.config.shortBreakMinutes) },
                { phase: "long", label: root.tr("longMode").arg(root.config.longBreakMinutes) }
              ]
              Rectangle {
                id: modeCell
                required property var modelData
                width: parent.width / 3
                height: parent.height
                radius: Style.space(7)
                color: root.session.phase === modelData.phase ? Util.alpha(root.foreground, 0.12) : "transparent"
                Label {
                  anchors.centerIn: parent
                  text: modeCell.modelData.label
                  color: root.session.phase === modeCell.modelData.phase ? root.foreground : root.dim
                  font.pixelSize: Style.font.bodySmall
                  font.weight: root.session.phase === modeCell.modelData.phase ? Font.Bold : Font.Normal
                }
              }
            }
          }
        }

        // Ring and heatmap.
        Row {
          width: parent.width
          spacing: Style.space(16)

          Item {
            id: ringBox
            width: Style.space(128)
            height: width

            // Wheel: 5 minutes per notch. With a block running it stretches or
            // shortens that block; otherwise it sets the length of your blocks.
            property real wheelRest: 0
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.NoButton
              onWheel: function(wheel) {
                var r = Util.wheelSteps(ringBox.wheelRest, wheel.angleDelta.y)
                ringBox.wheelRest = r.remainder
                if (!r.steps) return
                if (root.active) {
                  root.send("adjust", String(r.steps * 5))
                } else {
                  var next = Model.cleanSettings({ focusMinutes: root.config.focusMinutes + r.steps * 5 }).focusMinutes
                  if (next !== root.config.focusMinutes)
                    Quickshell.execDetached(["omarchy", "bar", "set", Model.PLUGIN_ID, "focusMinutes", String(next), "--json"])
                }
              }
            }
            Canvas {
              id: bigRing
              anchors.fill: parent
              property real progress: root.done
              onProgressChanged: requestPaint()
              onPaint: {
                var c = getContext("2d")
                c.reset()
                var w = Style.space(7)
                var r = width / 2 - w / 2 - 1
                c.lineWidth = w
                c.lineCap = "round"
                c.strokeStyle = root.groove
                c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
                if (progress <= 0) return
                c.strokeStyle = root.accent
                c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress); c.stroke()
              }
            }
            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Model.clock(root.active ? root.remaining : root.config.focusMinutes * 60000)
                font.pixelSize: Style.space(26)
                font.weight: Font.Black
                font.features: { "tnum": 1 }
              }
              Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.active && root.session.running
                text: root.endsLabel()
                color: root.dim
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Column {
            width: parent.width - ringBox.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Item {
              width: parent.width
              height: heatLabel.implicitHeight
              Label { id: heatLabel; text: root.tr("weeks"); color: root.dim; font.pixelSize: Style.font.bodySmall }
              Label { anchors.right: parent.right; text: root.tr("blocksCount").arg(root.heatBlocks); font.pixelSize: Style.font.bodySmall; font.weight: Font.DemiBold }
            }
            Grid {
              id: heatGrid
              rows: 7
              flow: Grid.TopToBottom
              spacing: Style.space(2)
              readonly property real cell: (parent.width - spacing * 19) / 20
              Repeater {
                model: root.heat
                Rectangle {
                  required property var modelData
                  width: heatGrid.cell
                  height: heatGrid.cell
                  radius: Style.space(2)
                  visible: modelData >= 0
                  color: modelData <= 0 ? Util.alpha(root.foreground, 0.07)
                    : Util.alpha(root.accent, [0, 0.3, 0.52, 0.78, 1][modelData])
                }
              }
            }
          }
        }

        // Project: detected, typed, or picked from recent ones.
        Column {
          width: parent.width
          spacing: Style.space(8)
          Well {
            width: parent.width
            height: Style.space(36)
            border.color: projectInput.activeFocus ? root.accent : Util.alpha(root.accent, 0.3)
            TextInput {
              id: projectInput
              anchors { left: parent.left; right: detectedTag.left; leftMargin: Style.space(12); rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
              text: root.project
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              clip: true
              selectByMouse: true
              readOnly: root.session.phase === "focus"
              onTextEdited: root.project = text
              Keys.onReturnPressed: { focus = false; root.primary() }
              Keys.onEscapePressed: focus = false
              Label {
                visible: !projectInput.text
                text: root.tr("projectHint")
                color: root.faint
              }
            }
            Label {
              id: detectedTag
              anchors { right: parent.right; rightMargin: Style.space(10); verticalCenter: parent.verticalCenter }
              visible: root.detected !== "" && root.project === root.detected
              text: root.tr("detected")
              color: Commons.Color.accent
              font.pixelSize: Style.font.bodySmall
            }
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.session.phase !== "focus" && root.suggestions.length > 0
            Repeater {
              model: root.suggestions
              Rectangle {
                id: chip
                required property string modelData
                width: chipLabel.implicitWidth + Style.space(16)
                height: Style.space(22)
                radius: Style.space(6)
                color: chipMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : Util.alpha(root.foreground, 0.05)
                Label { id: chipLabel; anchors.centerIn: parent; text: chip.modelData; color: root.dim; font.pixelSize: Style.font.bodySmall }
                MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.project = chip.modelData }
              }
            }
          }
        }

        // Time per project this week, with the streak.
        Well {
          width: parent.width
          height: statsCol.implicitHeight + Style.space(20)
          Column {
            id: statsCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(11) }
            spacing: Style.space(7)
            Label {
              visible: root.projects.length === 0
              text: root.tr("firstBlock")
              color: root.dim
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.projects
              Item {
                id: projRow
                required property var modelData
                required property int index
                width: statsCol.width
                height: Style.space(16)
                Label { id: projName; width: Style.space(120); anchors.verticalCenter: parent.verticalCenter; text: projRow.modelData.project; font.pixelSize: Style.font.bodySmall }
                Rectangle {
                  anchors { left: projName.right; leftMargin: Style.space(8); right: projTime.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
                  height: Style.space(5)
                  radius: height / 2
                  color: Util.alpha(root.foreground, 0.08)
                  Rectangle {
                    height: parent.height
                    radius: height / 2
                    width: parent.width * (root.projects[0].minutes > 0 ? projRow.modelData.minutes / root.projects[0].minutes : 0)
                    color: Util.alpha(root.accent, [1, 0.75, 0.55][projRow.index])
                  }
                }
                Label { id: projTime; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: Model.duration(projRow.modelData.minutes); color: root.dim; font.pixelSize: Style.font.bodySmall; font.features: { "tnum": 1 } }
              }
            }
            Item {
              width: parent.width
              height: weekLabel.implicitHeight
              visible: root.projects.length > 0
              Label { id: weekLabel; text: root.tr("thisWeek").arg(root.week.week.blocks); color: root.dim; font.pixelSize: Style.font.bodySmall }
              Label { anchors.right: parent.right; text: root.tr("streak").arg(root.week.streak); color: "#d5967a"; font.pixelSize: Style.font.bodySmall; font.weight: Font.DemiBold }
            }
          }
        }

        Label {
          visible: !root.dndAvailable && root.config.silenceNotifications
          width: parent.width
          text: root.tr("noSilence")
          color: Commons.Color.urgent
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // Controls.
        Row {
          width: parent.width
          spacing: Style.space(6)
          readonly property real third: (width - spacing * 2) / 3
          Button { width: parent.third; text: root.tr("stop"); onClicked: root.send("stop") }
          Button {
            width: parent.third
            solid: true
            text: !root.active ? root.tr("start") : root.session.running ? root.tr("pause") : root.tr("resume")
            onClicked: root.primary()
          }
          Button { width: parent.third; text: root.tr("skip"); onClicked: root.send("skip") }
        }
      }
    }
  }
}
