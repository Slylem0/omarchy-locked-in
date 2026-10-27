import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The island over the centre of the bar. It grows sideways when a block
// starts, then stretches down into frosted glass when there is something to
// choose: a distraction, the end of a block, a break. Every face reads from
// Service.qml and calls back into it.
//
// Motion is springs throughout: size changes overshoot a little and settle,
// the island squashes for a moment as it grows, and each face fades in with
// its rows arriving one after another.
Scope {
  id: root

  required property var service

  readonly property string face: service ? service.islandFace : "idle"
  readonly property var session: service ? service.session : Model.initialState()
  readonly property var settings: service ? service.settings : Model.cleanSettings({})
  readonly property string lang: service ? service.lang : "en"
  readonly property real remaining: service ? service.remainingMs : 0
  readonly property real left: session.durationMs > 0 ? Math.max(0, Math.min(1, remaining / session.durationMs)) : 0

  function tr(key) { return Model.tr(root.lang, key) }

  // Theme colours; they follow `omarchy theme set`.
  readonly property color ink: Commons.Color.bar.text
  readonly property color inkDim: Util.alpha(ink, 0.55)
  readonly property color inkFaint: Util.alpha(ink, 0.32)
  readonly property color groove: Util.alpha(ink, 0.16)
  readonly property color edge: Util.alpha(ink, 0.14)
  readonly property color well: Qt.rgba(0, 0, 0, 0.22)
  readonly property color accent: Commons.Color.accent
  readonly property color alert: Commons.Color.bar.active
  property color rest: "#a3be8c"
  readonly property color glass: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 0.74)
  readonly property color tone: face === "shield" ? alert
    : (face === "done" || face === "pause" || face === "pause-min") ? rest : accent

  // Geometry, in the same units the bar uses.
  readonly property int restHeight: Style.bar.sizeHorizontal + Style.space(3) * 2
  readonly property int restRadius: Math.min(Style.cornerRadius > 0 ? Style.cornerRadius : 10, restHeight / 2)
  readonly property int edgeGap: Math.max(Style.space(6), Style.gapsOut)
  readonly property int topY: settings.islandPosition === "below" ? edgeGap + restHeight + Style.space(6) : edgeGap
  readonly property int pad: Style.space(16)
  readonly property bool hasMissed: service ? service.silenced > 0 : false

  function widthFor(name) {
    switch (name) {
    case "start": return Style.space(470)
    case "shield": return Style.space(430)
    case "done": return Style.space(430)
    case "pause": return Style.space(340)
    case "pause-min": return Style.space(318)
    }
    return Style.space(220)
  }

  function heightFor(name) {
    switch (name) {
    case "shield": return Style.space(178)
    case "done": return root.hasMissed ? Style.space(240) : Style.space(170)
    case "pause": return Style.space(196)
    }
    return root.restHeight
  }

  function capitalized(text) {
    var t = String(text || "")
    return t ? t.charAt(0).toUpperCase() + t.slice(1) : ""
  }

  // The theme's own green, for breaks and finished blocks.
  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var m = /^\s*green\s*=\s*"(#[0-9a-fA-F]{6})"/m.exec(text())
      if (m) root.rest = m[1]
    }
  }

  // --- building blocks ------------------------------------------------------------

  component Label: Text {
    color: root.ink
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }

  // Stroked 16x16 icons, drawn from the same paths as the design mockups.
  component Icon: Item {
    id: icon
    property string path: ""
    property color tint: root.ink
    property real stroke: 1.4
    implicitWidth: Style.space(15)
    implicitHeight: Style.space(15)
    Shape {
      width: 16
      height: 16
      preferredRendererType: Shape.CurveRenderer
      transform: Scale { xScale: icon.width / 16; yScale: icon.height / 16 }
      ShapePath {
        strokeColor: icon.tint
        strokeWidth: icon.stroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: icon.path }
      }
    }
  }

  readonly property string shieldPath: "M8 1.8 2.8 3.9v3.7c0 3.1 2.2 5.4 5.2 6.4 3-1 5.2-3.3 5.2-6.4V3.9z M6.2 6.2 9.8 9.8 M9.8 6.2 6.2 9.8"
  readonly property string checkPath: "M3.5 8.4 6.5 11.4 12.5 5"
  readonly property string cupPath: "M3 6h8v3.2A3.3 3.3 0 0 1 7.7 12.5h-1.4A3.3 3.3 0 0 1 3 9.2z M11 7h1a1.6 1.6 0 0 1 0 3.2h-1"
  readonly property string bellOffPath: "M4 11.5V7.5a4 4 0 0 1 8 0v4l1 1H3z M6.8 14a1.3 1.3 0 0 0 2.4 0 M2.5 2.5 13.5 13.5"
  readonly property string bellPath: "M4 11.5V7.5a4 4 0 0 1 8 0v4l1 1H3z M6.8 14a1.3 1.3 0 0 0 2.4 0"
  readonly property string upPath: "M4.5 9.5 8 6l3.5 3.5"
  readonly property string downPath: "M4.5 6.5 8 10l3.5-3.5"

  component Ring: Canvas {
    id: ring
    property real progress: 0
    property color tint: root.tone
    implicitWidth: Style.space(16)
    implicitHeight: Style.space(16)
    onProgressChanged: requestPaint()
    onTintChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      var w = Math.max(2, width * 0.15)
      var r = width / 2 - w / 2 - 0.5
      c.lineWidth = w
      c.lineCap = "round"
      c.strokeStyle = root.groove
      c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
      if (progress <= 0) return
      c.strokeStyle = tint
      c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, progress)); c.stroke()
    }
  }

  component Track: Rectangle {
    property real progress: 0
    property color tint: root.tone
    implicitHeight: Style.space(4)
    radius: height / 2
    color: root.groove
    clip: true
    Rectangle {
      height: parent.height
      radius: height / 2
      width: parent.width * Math.max(0, Math.min(1, parent.progress))
      color: parent.tint
      Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }
  }

  component Dots: Row {
    id: dots
    property int count: 4
    property int filled: 0
    spacing: Style.space(4)
    Repeater {
      model: dots.count
      Rectangle {
        required property int index
        width: Style.space(18)
        height: Style.space(4)
        radius: height / 2
        color: index < dots.filled ? root.tone : root.groove
      }
    }
  }

  component Pill: Rectangle {
    id: pill
    property string text: ""
    property bool solid: false
    signal clicked()
    implicitHeight: Style.space(30)
    radius: Style.space(9)
    color: solid ? root.tone : (mouse.containsMouse ? Util.alpha(root.ink, 0.11) : Util.alpha(root.ink, 0.06))
    border.width: solid ? 0 : 1
    border.color: root.edge
    scale: mouse.pressed ? 0.96 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.002 } }
    Behavior on color { ColorAnimation { duration: 120 } }
    Label {
      anchors.centerIn: parent
      text: pill.text
      color: pill.solid ? Commons.Color.bar.background : root.ink
      font.weight: pill.solid ? Font.Bold : Font.DemiBold
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  component RoundButton: Rectangle {
    id: rb
    property string path: ""
    signal clicked()
    width: Style.space(22)
    height: Style.space(22)
    radius: Style.space(7)
    color: rbMouse.containsMouse ? Util.alpha(root.ink, 0.12) : Util.alpha(root.ink, 0.06)
    border.width: 1
    border.color: root.edge
    Icon { anchors.centerIn: parent; path: rb.path; tint: root.inkDim; width: Style.space(12); height: Style.space(12) }
    MouseArea { id: rbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
  }

  // One face of the island: fades and grows in after the island has started
  // to change shape, and leaves quickly.
  component Face: Item {
    id: faceItem
    property string name: ""
    readonly property bool shown: root.face === name
    anchors.fill: parent
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94
    transformOrigin: Item.Top
    visible: opacity > 0.01
    enabled: shown
    Behavior on opacity {
      SequentialAnimation {
        PauseAnimation { duration: faceItem.shown ? 140 : 0 }
        NumberAnimation { duration: faceItem.shown ? 260 : 140; easing.type: Easing.OutCubic }
      }
    }
    Behavior on scale { SpringAnimation { spring: 4; damping: 0.42; epsilon: 0.002 } }
  }

  // A row inside an expanded face: arrives a beat after the one above it.
  component Reveal: Item {
    id: reveal
    property int index: 0
    property bool shown: false
    opacity: shown ? 1 : 0
    transform: Translate { y: reveal.shown ? 0 : -Style.space(7); Behavior on y { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.1 } } }
    Behavior on opacity {
      SequentialAnimation {
        PauseAnimation { duration: reveal.shown ? 200 + reveal.index * 55 : 0 }
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }
    }
  }

  // --- the island, once per screen; only the focused one shows it ---------------

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      readonly property bool here: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name === modelData.name : true
      readonly property bool interactive: root.face === "shield" || root.face === "done" || root.face === "pause" || root.face === "pause-min"

      screen: modelData
      visible: here && (root.face !== "idle" || island.opacity > 0.01)
      anchors { top: true; left: true; right: true }
      implicitHeight: root.topY + Style.space(270)
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "locked-in"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: interactive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
      mask: Region { item: island }

      Rectangle {
        id: island

        readonly property bool expanded: root.face === "shield" || root.face === "done" || root.face === "pause"

        x: Math.round((parent.width - width) / 2)
        y: root.topY
        width: root.widthFor(root.face)
        height: root.heightFor(root.face)
        radius: expanded ? Style.space(18) : root.restRadius
        color: root.glass
        border.width: 1
        border.color: root.face === "shield" ? Util.alpha(root.alert, 0.45) : root.edge
        opacity: root.face === "idle" ? 0 : 1
        clip: true

        transform: Scale { id: squash; origin.x: island.width / 2; origin.y: 0 }

        Behavior on width { SpringAnimation { spring: 3.6; damping: 0.32; epsilon: 0.5 } }
        Behavior on height { SpringAnimation { spring: 3.6; damping: 0.32; epsilon: 0.5 } }
        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 220 } }
        Behavior on opacity {
          SequentialAnimation {
            // On the way out, shrink back first, then disappear.
            PauseAnimation { duration: root.face === "idle" ? 230 : 0 }
            NumberAnimation { duration: root.face === "idle" ? 160 : 90; easing.type: Easing.OutCubic }
          }
        }

        onExpandedChanged: if (expanded) squish.restart()

        // Squash for a moment as it grows, like a drop.
        SequentialAnimation {
          id: squish
          ParallelAnimation {
            NumberAnimation { target: squash; property: "xScale"; to: 1.04; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: squash; property: "yScale"; to: 0.955; duration: 120; easing.type: Easing.OutQuad }
          }
          ParallelAnimation {
            SpringAnimation { target: squash; property: "xScale"; to: 1; spring: 4; damping: 0.4; epsilon: 0.001 }
            SpringAnimation { target: squash; property: "yScale"; to: 1; spring: 4; damping: 0.4; epsilon: 0.001 }
          }
        }

        // A thin highlight on the top edge, as real glass has.
        Rectangle {
          anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.radius; rightMargin: parent.radius; topMargin: 1 }
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.16) }
            GradientStop { position: 1; color: "transparent" }
          }
        }

        Item {
          focus: win.interactive
          anchors.fill: parent
          Keys.onEscapePressed: root.service.dismissIsland()
        }

        // --- start: grows sideways, then goes back ---------------------------------
        Face {
          name: "start"
          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: root.pad
            width: parent.width - root.pad * 2
            spacing: Style.space(10)
            Ring { anchors.verticalCenter: parent.verticalCenter; progress: root.left; tint: root.accent }
            Label { text: root.tr("block").arg(root.session.cycle + 1); font.weight: Font.DemiBold }
            Label { text: root.session.project; color: root.inkDim; width: Math.min(implicitWidth, Style.space(150)) }
            Track {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(Style.space(40), parent.width - x - Style.space(80))
              progress: root.left
              tint: root.accent
            }
            Label { text: Model.clock(root.remaining); font.weight: Font.Bold; font.features: { "tnum": 1 } }
            Icon { anchors.verticalCenter: parent.verticalCenter; path: root.bellOffPath; tint: root.inkDim; visible: root.settings.silenceNotifications }
          }
        }

        // --- shield: something on the list took focus -------------------------------
        Face {
          id: shieldFace
          name: "shield"
          readonly property var found: root.service ? root.service.shield : null
          Item {
            id: shieldHead
            width: parent.width
            height: root.restHeight
            Icon { id: shieldIcon; x: root.pad; anchors.verticalCenter: parent.verticalCenter; path: root.shieldPath; tint: root.alert }
            Label {
              anchors { left: shieldIcon.right; leftMargin: Style.space(9); right: shieldMeta.left; rightMargin: Style.space(9); verticalCenter: parent.verticalCenter }
              text: shieldFace.found && shieldFace.found.closed
                ? root.tr("closedIt").arg(root.capitalized(shieldFace.found.term))
                : root.tr("onYourList").arg(root.capitalized(shieldFace.found ? shieldFace.found.term : ""))
              font.weight: Font.DemiBold
            }
            Label {
              id: shieldMeta
              anchors { right: parent.right; rightMargin: root.pad; verticalCenter: parent.verticalCenter }
              text: root.tr("block").arg(root.session.cycle + 1) + (root.session.project ? " · " + root.session.project : "")
              color: root.inkDim
              font.pixelSize: Style.font.bodySmall
            }
          }
          Column {
            anchors { top: shieldHead.bottom; left: parent.left; right: parent.right; margins: root.pad; topMargin: Style.space(4) }
            spacing: Style.space(12)
            Reveal {
              index: 0; shown: shieldFace.shown
              width: parent.width; height: shieldBig.implicitHeight
              Label {
                id: shieldBig
                text: Model.clock(root.remaining)
                color: root.alert
                font.pixelSize: Style.space(44)
                font.weight: Font.Black
                font.letterSpacing: -Style.space(2)
                font.features: { "tnum": 1 }
              }
              Column {
                anchors { right: parent.right; bottom: parent.bottom; bottomMargin: Style.space(4) }
                Label { anchors.right: parent.right; text: root.tr("left"); font.weight: Font.DemiBold }
                Label { anchors.right: parent.right; text: root.tr("toFinish"); color: root.inkDim; font.pixelSize: Style.font.bodySmall }
              }
            }
            Reveal {
              index: 1; shown: shieldFace.shown
              width: parent.width; height: Style.space(4)
              Track { anchors.fill: parent; progress: root.left; tint: root.alert }
            }
            Reveal {
              index: 2; shown: shieldFace.shown
              visible: !(shieldFace.found && shieldFace.found.closed)
              width: parent.width; height: Style.space(30)
              Row {
                anchors.fill: parent
                spacing: Style.space(6)
                Pill { width: (parent.width - Style.space(12)) / 3; text: root.tr("keepGoing"); onClicked: root.service.shieldKeep() }
                Pill { width: (parent.width - Style.space(12)) / 3; text: root.tr("hide"); onClicked: root.service.shieldHide() }
                Pill { width: (parent.width - Style.space(12)) / 3; text: root.tr("close"); solid: true; onClicked: root.service.shieldClose() }
              }
            }
          }
        }

        // --- done: the block is finished --------------------------------------------
        Face {
          id: doneFace
          name: "done"
          readonly property var day: Model.stats(root.service ? root.service.entries : [], root.service ? root.service.now : 0)
          Item {
            id: doneHead
            width: parent.width
            height: root.restHeight
            Icon { id: doneIcon; x: root.pad; anchors.verticalCenter: parent.verticalCenter; path: root.checkPath; tint: root.rest; stroke: 1.7 }
            Label {
              id: doneTitle
              anchors { left: doneIcon.right; leftMargin: Style.space(9); verticalCenter: parent.verticalCenter }
              text: root.tr("blockDone").arg(Math.max(1, root.session.cycle))
              font.weight: Font.DemiBold
            }
            Label {
              anchors { left: doneTitle.right; leftMargin: Style.space(8); right: doneDots.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
              text: root.session.project
              color: root.inkDim
            }
            Dots {
              id: doneDots
              anchors { right: parent.right; rightMargin: root.pad; verticalCenter: parent.verticalCenter }
              count: root.settings.longBreakEvery
              filled: root.session.cycle === 0 ? count : root.session.cycle
            }
          }
          Column {
            anchors { top: doneHead.bottom; left: parent.left; right: parent.right; margins: root.pad; topMargin: Style.space(4) }
            spacing: Style.space(12)
            Reveal {
              index: 0; shown: doneFace.shown
              width: parent.width; height: doneBig.implicitHeight
              Label {
                id: doneBig
                text: Model.clock(root.settings.focusMinutes * 60000)
                color: root.rest
                font.pixelSize: Style.space(44)
                font.weight: Font.Black
                font.letterSpacing: -Style.space(2)
                font.features: { "tnum": 1 }
              }
              Column {
                anchors { right: parent.right; bottom: parent.bottom; bottomMargin: Style.space(4) }
                Label { anchors.right: parent.right; text: root.tr("blocksToday").arg(doneFace.day.today.blocks); font.weight: Font.DemiBold }
                Label { anchors.right: parent.right; text: root.tr("streak").arg(doneFace.day.streak); color: root.inkDim; font.pixelSize: Style.font.bodySmall }
              }
            }
            Reveal {
              index: 1; shown: doneFace.shown
              visible: root.hasMissed
              width: parent.width; height: missedBox.height
              Rectangle {
                id: missedBox
                width: parent.width
                height: missedCol.implicitHeight + Style.space(18)
                radius: Style.space(10)
                color: root.well
                border.width: 1
                border.color: Util.alpha(root.ink, 0.06)
                Column {
                  id: missedCol
                  anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(9) }
                  spacing: Style.space(6)
                  Row {
                    spacing: Style.space(6)
                    Icon { path: root.bellPath; tint: root.inkDim; width: Style.space(12); height: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                    Label { text: root.tr("heldFor").arg(root.service ? root.service.silenced : 0); color: root.inkDim; font.pixelSize: Style.font.bodySmall }
                  }
                  Repeater {
                    model: root.service ? root.service.missed.slice(0, 2) : []
                    Item {
                      id: missedRow
                      required property var modelData
                      required property int index
                      width: missedCol.width
                      height: Style.space(18)
                      readonly property var swatches: [root.accent, root.rest, root.alert, "#b48ead", "#ebcb8b", "#88c0d0"]
                      Rectangle {
                        id: avatar
                        width: Style.space(18); height: Style.space(18); radius: Style.space(5)
                        color: missedRow.swatches[String(missedRow.modelData.app || "?").length % missedRow.swatches.length]
                        Label { anchors.centerIn: parent; text: String(missedRow.modelData.app || "?").charAt(0).toUpperCase(); color: Commons.Color.bar.background; font.weight: Font.Black; font.pixelSize: Style.font.bodySmall }
                      }
                      Label { id: appName; anchors { left: avatar.right; leftMargin: Style.space(8); verticalCenter: parent.verticalCenter } text: missedRow.modelData.app || ""; font.pixelSize: Style.font.bodySmall }
                      Label {
                        anchors { left: appName.right; leftMargin: Style.space(10); right: parent.right; verticalCenter: parent.verticalCenter }
                        horizontalAlignment: Text.AlignRight
                        text: missedRow.modelData.summary || ""
                        color: root.inkDim
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                }
              }
            }
            Reveal {
              index: 2; shown: doneFace.shown
              width: parent.width; height: Style.space(30)
              Row {
                anchors.fill: parent
                spacing: Style.space(6)
                Pill {
                  width: (parent.width - Style.space(6)) / 2
                  solid: true
                  text: root.tr("breakFor").arg(Model.clock(root.service && root.service.inBreak ? root.remaining
                    : (root.session.cycle % root.settings.longBreakEvery === 0 ? root.settings.longBreakMinutes : root.settings.shortBreakMinutes) * 60000))
                  onClicked: root.service.openBreak()
                }
                Pill { width: (parent.width - Style.space(6)) / 2; text: root.tr("anotherBlock"); onClicked: root.service.anotherBlock() }
              }
            }
          }
        }

        // --- pause: the break, opened ----------------------------------------------
        Face {
          id: pauseFace
          name: "pause"
          Item {
            id: pauseHead
            width: parent.width
            height: root.restHeight
            Icon { id: pauseIcon; x: root.pad; anchors.verticalCenter: parent.verticalCenter; path: root.cupPath; tint: root.rest }
            Label {
              anchors { left: pauseIcon.right; leftMargin: Style.space(9); verticalCenter: parent.verticalCenter }
              text: root.session.phase === "long" ? root.tr("breakLong") : root.tr("breakShort")
              font.weight: Font.DemiBold
            }
            Label {
              anchors { right: pauseMin.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
              text: root.tr("nextBlock").arg(root.session.phase === "long" ? 1 : root.session.cycle + 1).arg(root.settings.longBreakEvery)
              color: root.inkDim
              font.pixelSize: Style.font.bodySmall
            }
            RoundButton { id: pauseMin; anchors { right: parent.right; rightMargin: Style.space(10); verticalCenter: parent.verticalCenter } path: root.upPath; onClicked: root.service.minimizePause() }
          }
          Column {
            anchors { top: pauseHead.bottom; left: parent.left; right: parent.right; margins: root.pad; topMargin: Style.space(2) }
            spacing: Style.space(10)
            Reveal {
              index: 0; shown: pauseFace.shown
              width: parent.width; height: pauseBig.implicitHeight
              Label {
                id: pauseBig
                anchors.horizontalCenter: parent.horizontalCenter
                text: Model.clock(root.remaining)
                color: root.rest
                font.pixelSize: Style.space(56)
                font.weight: Font.Black
                font.letterSpacing: -Style.space(2)
                font.features: { "tnum": 1 }
              }
            }
            Reveal {
              index: 1; shown: pauseFace.shown
              width: parent.width; height: Style.space(4)
              Track { anchors.fill: parent; progress: root.left; tint: root.rest }
            }
            Reveal {
              index: 2; shown: pauseFace.shown
              width: parent.width; height: pauseTip.implicitHeight
              Label { id: pauseTip; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.tr("breakTip"); color: root.inkDim }
            }
            Reveal {
              index: 3; shown: pauseFace.shown
              width: parent.width; height: skipLabel.implicitHeight
              Label {
                id: skipLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tr("skipBreak")
                color: skipMouse.containsMouse ? root.ink : root.inkFaint
                font.pixelSize: Style.font.bodySmall
                MouseArea { id: skipMouse; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.service.skip() }
              }
            }
          }
        }

        // --- pause-min: the break, folded into a thin island ---------------------------
        Face {
          name: "pause-min"
          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(12)
            width: parent.width - Style.space(22)
            spacing: Style.space(10)
            Icon { anchors.verticalCenter: parent.verticalCenter; path: root.cupPath; tint: root.rest }
            Label { text: root.session.phase === "long" ? root.tr("breakLong") : root.tr("breakShort") }
            Track {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(Style.space(40), parent.width - x - Style.space(96))
              progress: root.left
              tint: root.rest
            }
            Label { text: Model.clock(root.remaining); color: root.rest; font.weight: Font.Bold; font.features: { "tnum": 1 } }
            RoundButton { anchors.verticalCenter: parent.verticalCenter; path: root.downPath; onClicked: root.service.expandPause() }
          }
        }
      }
    }
  }
}
