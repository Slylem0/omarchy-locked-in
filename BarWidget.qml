import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Locked In in the bar. Two styles: "line" (project, progress, time and the
// blocks of the cycle) and "ring" (a small ring and the time). Outside a block
// it is just an icon. Left click opens the dashboard; right click starts,
// pauses or resumes.
BarWidget {
  id: root
  moduleName: Model.PLUGIN_ID

  // Third-party bars (Islands, for one) get no access to plugin services, so
  // the widget never talks to Service.qml directly: it follows the session the
  // service saves to state.json and sends its actions over IPC. That works
  // under any bar.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/locked-in"
  property var session: Model.initialState()
  property double now: Date.now()
  readonly property var config: Model.cleanSettings(root.settings)
  readonly property real remainingMs: Model.remainingMs(session, now)
  readonly property string lang: Model.language(config.language, Qt.locale().name)
  readonly property string style: config.style
  readonly property bool active: session.phase !== "idle"
  readonly property bool inBreak: session.phase === "short" || session.phase === "long"
  readonly property real leftFraction: session.durationMs > 0 ? Math.max(0, Math.min(1, remainingMs / session.durationMs)) : 0
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color tone: inBreak ? Util.alpha(ink, 0.9) : Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // There is one widget per screen; open the dashboard on the focused one.
  function toggleOnFocusedScreen() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    for (var i = 0; i < items.length; i++) {
      var win = items[i] && items[i].QsWindow ? items[i].QsWindow.window : null
      if (win && win.screen && win.screen.name === name && typeof items[i].toggle === "function") {
        items[i].toggle()
        return
      }
    }
    root.toggle()
  }

  IpcHandler {
    target: Model.PLUGIN_ID + ".panel"
    function toggle(): string { root.toggleOnFocusedScreen(); return "ok" }
    function open(): string { root.toggleOnFocusedScreen(); return "ok" }
  }

  function send(command) {
    Quickshell.execDetached(["omarchy-shell", Model.PLUGIN_ID, command])
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  FileView {
    path: root.stateDir + "/state.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.session = JSON.parse(text()).session || Model.initialState() } catch (e) {}
      root.now = Date.now()
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.session.running
    onTriggered: root.now = Date.now()
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.active ? "" : "\u{F051B}"
    hasVisualContent: true
    fixedWidth: root.active ? content.implicitWidth + Style.space(18) : -1
    tooltipText: root.active ? root.session.project || Model.tr(root.lang, "tooltip") : Model.tr(root.lang, "tooltip")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.send("toggle")
      else root.toggle()
    }

    Row {
      id: content
      visible: root.active
      anchors.centerIn: parent
      spacing: Style.space(7)
      opacity: root.session.running ? 1 : 0.6

      // Ring style
      Canvas {
        id: ring
        visible: root.style === "ring"
        width: Style.space(14)
        height: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        property real progress: 1 - root.leftFraction
        onProgressChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          var w = Math.max(2, width * 0.16)
          var r = width / 2 - w / 2 - 0.5
          c.lineWidth = w
          c.lineCap = "round"
          c.strokeStyle = Util.alpha(root.ink, 0.18)
          c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
          c.strokeStyle = root.tone
          c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress); c.stroke()
        }
      }

      // Line style
      Text {
        visible: root.style === "line" && root.session.project !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.session.project
        color: Util.alpha(root.ink, 0.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Math.min(implicitWidth, Style.space(140))
        elide: Text.ElideRight
      }
      Rectangle {
        visible: root.style === "line"
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(54)
        height: Style.space(3)
        radius: height / 2
        color: Util.alpha(root.ink, 0.16)
        Rectangle {
          height: parent.height
          radius: height / 2
          width: parent.width * (1 - root.leftFraction)
          color: root.tone
          Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Model.clock(root.remainingMs)
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Bold
        font.features: { "tnum": 1 }
      }

      Row {
        visible: root.style === "line"
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Repeater {
          model: root.config.longBreakEvery
          Rectangle {
            required property int index
            width: Style.space(4)
            height: Style.space(4)
            radius: width / 2
            color: index < root.session.cycle + (root.session.phase === "focus" ? 1 : 0) ? root.tone : Util.alpha(root.ink, 0.18)
          }
        }
      }
    }
  }
}
