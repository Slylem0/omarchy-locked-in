import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model

// The brain of Locked In. Holds the focus/break session, runs its timer, and
// carries out what Model.next() decides: do-not-disturb, the history file, the
// distraction shield and the island. The bar widget, the panel and the island
// only read from here and call the functions below.
//
// The session is saved to $XDG_STATE_HOME/locked-in/state.json on every change
// and picked back up on load, so a shell restart or a suspend keeps the block.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string pluginPath: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string helper: pluginPath + "/bin/locked-in"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/locked-in"

  property var settings: Model.cleanSettings({})
  readonly property string lang: Model.language(settings.language, Qt.locale().name)

  // `state` is taken by Item, hence `session`.
  property var session: Model.initialState()
  property double now: Date.now()
  readonly property real remainingMs: Model.remainingMs(session, now)
  readonly property real fraction: session.durationMs > 0 ? Math.min(1, Math.max(0, 1 - remainingMs / session.durationMs)) : 0
  readonly property bool inFocus: session.phase === "focus"
  readonly property bool inBreak: session.phase === "short" || session.phase === "long"

  property string detectedProject: ""
  property var entries: []
  property int silenced: 0
  property var missed: []
  property bool dndAvailable: true
  onDndAvailableChanged: root.save()
  property var shield: null
  property string islandFace: "idle"
  property var hidden: []
  property var kept: ({})
  property bool loaded: false
  property string pendingProject: ""
  property bool detectBeforeStart: false
  property var pendingRecords: []
  property var pendingLines: []

  // --- controls ---------------------------------------------------------------

  // Without a project, look at the focused window right now: the one detected
  // at load time is stale by the time a key starts a block.
  function start(project) {
    if (root.inFocus) return
    var named = String(project || "")
    if (!named) {
      root.detectBeforeStart = true
      root.refreshProject()
      return
    }
    root.pendingProject = named
    root.queryDndAndBegin()
  }

  function queryDndAndBegin() {
    if (root.settings.silenceNotifications) dndQuery.running = true
    else root.beginFocus()
  }

  function beginFocus() {
    root.kept = ({})
    root.silenced = 0
    root.missed = []
    root.shield = null
    root.send({ type: "start", project: root.pendingProject })
  }

  function pause() { root.send({ type: "pause" }) }
  function resume() { root.send({ type: "resume" }) }
  function toggle() {
    if (root.session.phase === "idle") root.start("")
    else if (root.session.running) root.pause()
    else root.resume()
  }
  function skip() { root.send({ type: "skip" }) }
  function stop() { root.send({ type: "stop" }) }

  function refreshProject() {
    if (projectProc.running) return
    projectProc.running = true
  }

  // --- island faces -----------------------------------------------------------

  function openBreak() {
    if (root.inBreak && !root.session.running) root.resume()
    root.islandFace = root.inBreak ? "pause" : "idle"
  }
  function anotherBlock() { root.islandFace = "idle"; root.start(root.session.project) }
  function minimizePause() { if (root.inBreak) root.islandFace = "pause-min" }
  function expandPause() { if (root.inBreak) root.islandFace = "pause" }
  function dismissIsland() { root.islandFace = root.inBreak ? "pause-min" : "idle" }

  // Read the phase from the session itself: inFocus/inBreak may not have
  // caught up yet while this handler runs.
  onSessionChanged: {
    var phase = root.session.phase
    var face = root.islandFace
    if ((face === "pause" || face === "pause-min") && phase !== "short" && phase !== "long") root.islandFace = "idle"
    if (face === "shield" && phase !== "focus") { root.shield = null; root.islandFace = "idle" }
  }

  // --- the state machine and its effects ---------------------------------------

  function send(event) {
    root.now = Date.now()
    var result = Model.next(root.session, event, root.now, root.settings)
    root.session = result.state
    root.save()
    for (var i = 0; i < result.effects.length; i++) root.run(result.effects[i], true)
  }

  function run(effect, live) {
    switch (effect.type) {
    case "silence-on":
      if (root.dndAvailable) Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", "on"])
      break
    case "silence-off":
      if (root.dndAvailable && !effect.restore) Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", "off"])
      break
    case "record":
      root.pendingRecords = root.pendingRecords.concat([effect.entry])
      root.nextRecord()
      break
    case "release-hidden":
      root.releaseHidden()
      break
    case "rehide":
      for (var h = 0; h < root.hidden.length; h++)
        root.dispatch('hl.dsp.window.move({ workspace = "special:locked-in", follow = false, window = "address:' + root.hidden[h].address + '" })')
      break
    case "island":
      if (!live) break
      root.islandFace = effect.face
      if (effect.face === "start") startFaceTimer.restart()
      if (effect.face === "done") doneFaceTimer.restart()
      if (effect.face === "pause" && !root.inBreak) root.islandFace = "idle"
      break
    }
  }

  // Focus blocks wait for the missed-notification count before they are
  // written, so the history line carries it.
  function nextRecord() {
    if (missedProc.running || root.pendingRecords.length === 0) return
    var entry = root.pendingRecords[0]
    if (entry.kind !== "focus") {
      root.pendingRecords = root.pendingRecords.slice(1)
      root.append(entry)
      root.nextRecord()
      return
    }
    missedProc.command = [root.helper, "missed", String(entry.start), String(entry.end)]
    missedProc.running = true
  }

  // Lines go to the helper on stdin, one write at a time, so they stay out of
  // the process list and never interleave.
  function append(entry) {
    root.pendingLines = root.pendingLines.concat([JSON.stringify(entry)])
    root.flushLines()
  }

  function flushLines() {
    if (recordProc.running || root.pendingLines.length === 0) return
    recordProc.lines = root.pendingLines.join("\n") + "\n"
    root.pendingLines = []
    recordProc.stdinEnabled = true
    recordProc.running = true
  }

  function save() {
    if (!root.loaded) return
    stateFile.setText(JSON.stringify({ session: root.session, hidden: root.hidden, dndAvailable: root.dndAvailable }) + "\n")
  }

  // --- distraction shield -------------------------------------------------------

  function dispatch(lua) {
    Quickshell.execDetached(["hyprctl", "dispatch", lua])
  }

  function checkWindow(info) {
    if (!root.inFocus || !root.session.running || root.settings.distractionAction === "off") return
    if (!info || !info.address || root.kept[info.address]) return
    if (root.shield && root.shield.address === info.address) return
    var workspace = info.workspace ? String(info.workspace.name || info.workspace.id || "") : ""
    if (workspace.indexOf("special:locked-in") === 0) return
    var term = Model.blockedBy(Model.parseBlocklist(root.settings.blocklist), info["class"], info.title)
    if (!term) return

    var found = { term: term, title: String(info.title || info["class"] || ""), address: info.address, workspace: workspace, closed: false }
    root.send({ type: "blocked" })
    if (root.settings.distractionAction === "hide") {
      root.hideWindow(found)
    } else if (root.settings.distractionAction === "close") {
      root.dispatch('hl.dsp.window.close({ window = "address:' + found.address + '" })')
      found.closed = true
      root.shield = found
      root.islandFace = "shield"
      shieldNoticeTimer.restart()
    } else {
      root.shield = found
      root.islandFace = "shield"
    }
  }

  function hideWindow(found) {
    root.hidden = root.hidden.concat([{ address: found.address, workspace: found.workspace }])
    root.save()
    root.dispatch('hl.dsp.window.move({ workspace = "special:locked-in", follow = false, window = "address:' + found.address + '" })')
  }

  function releaseHidden() {
    for (var i = 0; i < root.hidden.length; i++) {
      var w = root.hidden[i]
      if (!w.workspace) continue
      root.dispatch('hl.dsp.window.move({ workspace = "' + w.workspace + '", follow = false, window = "address:' + w.address + '" })')
    }
    root.hidden = []
    root.save()
  }

  function shieldKeep() {
    if (!root.shield) return
    var next = Object.assign({}, root.kept)
    next[root.shield.address] = true
    root.kept = next
    root.shield = null
    root.islandFace = "idle"
  }

  function shieldHide() {
    if (!root.shield) return
    root.hideWindow(root.shield)
    root.shield = null
    root.islandFace = "idle"
  }

  function shieldClose() {
    if (!root.shield) return
    root.dispatch('hl.dsp.window.close({ window = "address:' + root.shield.address + '" })')
    root.shield = null
    root.islandFace = "idle"
  }

  // Frosted glass: Hyprland blurs the island's layer. Asked at load and after
  // every config reload, which drops runtime rules; ~/.config/hypr is untouched.
  function applyBlur() {
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.layer_rule({ match = { namespace = "^locked-in$" }, blur = true, ignore_alpha = 0.3, xray = false })'])
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") blurTimer.restart()
      if ((name === "openwindow" || name === "activewindowv2" || name === "windowtitlev2") && root.inFocus) shieldCheck.restart()
    }
  }

  Timer {
    id: blurTimer
    interval: 300
    onTriggered: root.applyBlur()
  }

  // Title changes come in bursts (a browser loading a page); look once they settle.
  Timer {
    id: shieldCheck
    interval: 300
    onTriggered: if (!activeProc.running) activeProc.running = true
  }

  Process {
    id: activeProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var info = null
        try { info = JSON.parse(text) } catch (e) { return }
        root.checkWindow(info)
      }
    }
  }

  // --- timers and processes -------------------------------------------------------

  Timer {
    interval: 250
    repeat: true
    running: root.loaded && root.session.running
    onTriggered: {
      root.now = Date.now()
      if (Model.remainingMs(root.session, root.now) <= 0) root.send({ type: "tick" })
    }
  }

  Timer {
    id: startFaceTimer
    interval: 2400
    onTriggered: if (root.islandFace === "start") root.islandFace = "idle"
  }

  Timer {
    id: doneFaceTimer
    interval: 20000
    onTriggered: if (root.islandFace === "done") root.dismissIsland()
  }

  Timer {
    id: shieldNoticeTimer
    interval: 3500
    onTriggered: if (root.islandFace === "shield" && root.shield && root.shield.closed) { root.shield = null; root.islandFace = "idle" }
  }

  Process {
    id: dndQuery
    command: ["omarchy-shell", "notifications", "dndState"]
    stdout: StdioCollector { id: dndOut; waitForEnd: true }
    onExited: {
      var reply = String(dndOut.text || "").trim()
      root.dndAvailable = reply === "on" || reply === "off"
      root.send({ type: "dnd", value: reply === "on" })
      root.beginFocus()
    }
  }

  Process {
    id: missedProc
    stdout: StdioCollector { id: missedOut; waitForEnd: true }
    onExited: {
      var entry = root.pendingRecords[0]
      root.pendingRecords = root.pendingRecords.slice(1)
      var result = { count: 0, items: [] }
      try { result = JSON.parse(missedOut.text) } catch (e) {}
      if (entry) {
        entry.silenced = result.count || 0
        root.silenced = entry.silenced
        root.missed = result.items || []
        root.append(entry)
      }
      root.nextRecord()
    }
  }

  Process {
    id: projectProc
    command: [root.helper, "project"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.detectedProject = String(text || "").trim()
        if (!root.detectBeforeStart) return
        root.detectBeforeStart = false
        root.pendingProject = root.detectedProject || root.session.project
        root.queryDndAndBegin()
      }
    }
  }

  // --- files ------------------------------------------------------------------

  // Settings are the bar widget's, stored inline in its shell.json entry. Read
  // them here so they apply even when the widget is not on the bar.
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.settings = Model.cleanSettings(Model.settingsFromShellConfig(text(), Model.PLUGIN_ID))
    onLoadFailed: root.settings = Model.cleanSettings({})
  }

  FileView {
    path: root.stateDir + "/history.jsonl"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.entries = Model.parseHistory(text())
    onLoadFailed: root.entries = []
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    onLoaded: root.restore(text())
    onLoadFailed: root.restore("")
  }

  function restore(text) {
    if (root.loaded) return
    var saved = null
    try { saved = JSON.parse(text) } catch (e) {}
    var result = Model.rehydrate(saved && saved.session, Date.now(), root.settings)
    root.session = result.state
    root.hidden = saved && saved.hidden instanceof Array ? saved.hidden : []
    root.loaded = true
    for (var i = 0; i < result.effects.length; i++) root.run(result.effects[i], false)
    root.save()
  }

  Process {
    id: mkdirProc
    command: [root.helper, "init"]
    onExited: stateFile.reload()
  }

  Process {
    id: recordProc
    property string lines: ""
    command: [root.helper, "record"]
    onStarted: {
      write(lines)
      stdinEnabled = false
    }
    onExited: root.flushLines()
  }

  Island { service: root }

  // --- IPC --------------------------------------------------------------------

  IpcHandler {
    target: Model.PLUGIN_ID
    function start(project: string): string { root.start(project); return "ok" }
    function pause(): string { root.pause(); return "ok" }
    function resume(): string { root.resume(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function skip(): string { root.skip(); return "ok" }
    function adjust(minutes: string): string { root.send({ type: "adjust", minutes: Number(minutes) }); return "ok" }
    function stop(): string { root.stop(); return "ok" }
    // The dashboard belongs to the bar widget, which registers its own target.
    function panel(): string { Quickshell.execDetached(["omarchy-shell", Model.PLUGIN_ID + ".panel", "toggle"]); return "ok" }
    // Show a face of the island, e.g. bind a key to "island pause".
    function island(face: string): string {
      if (face === "pause" || face === "pause-min") { if (!root.inBreak) return "none"; root.islandFace = face; return "ok" }
      if (face === "idle") { root.dismissIsland(); return "ok" }
      return "unknown"
    }
    function status(): string {
      return JSON.stringify({
        phase: root.session.phase, running: root.session.running,
        remaining: Model.clock(Model.remainingMs(root.session, Date.now())),
        project: root.session.project, cycle: root.session.cycle,
        silenced: root.dndAvailable && root.settings.silenceNotifications && root.inFocus,
        island: root.islandFace, blocked: root.session.blocked || 0
      })
    }
  }

  Component.onCompleted: {
    mkdirProc.running = true
    root.applyBlur()
    root.refreshProject()
  }

  // Disabled mid-block: give back do-not-disturb and the hidden windows.
  Component.onDestruction: {
    if (root.inFocus && root.settings.silenceNotifications && root.dndAvailable && root.session.dndBefore !== true)
      Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", "off"])
    if (root.hidden.length > 0) root.releaseHidden()
  }
}
