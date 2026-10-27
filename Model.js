// Pure helpers shared by Service.qml, Island.qml, BarWidget.qml and Panel.qml.
// No QML imports and ES5 only, so the test runner can load it under node too.

var PLUGIN_ID = "slylem0.locked-in"

var DEFAULTS = {
  language: "auto",
  style: "line",
  focusMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  longBreakEvery: 4,
  autoStartBreaks: true,
  autoStartFocus: false,
  silenceNotifications: true,
  distractionAction: "warn",
  blocklist: "youtube, discord, steam, reddit, x.com, instagram, twitch",
  islandPosition: "bar"
}

var STRINGS = {
  en: {
    start: "Start",
    pause: "Pause",
    resume: "Resume",
    skip: "Skip",
    reset: "Reset",
    tooltip: "Locked In",
    block: "Block %1",
    blockOf: "Block %1 of %2",
    onYourList: "%1 is on your list",
    closedIt: "Closed %1",
    closedNote: "It was on your list",
    left: "left",
    toFinish: "to finish the block",
    keepGoing: "Keep going",
    hide: "Hide",
    close: "Close",
    blockDone: "Block %1 done",
    blocksToday: "%1 blocks today",
    streak: "%1-day streak",
    heldFor: "%1 notifications arrived while you were focused",
    breakFor: "Break %1",
    anotherBlock: "Another block",
    breakShort: "Break",
    breakLong: "Long break",
    nextBlock: "Next: block %1 of %2",
    breakTip: "Stand up, drink some water, look far away.",
    skipBreak: "Skip break",
    ready: "Ready",
    focusMode: "Focus %1",
    breakMode: "Break %1",
    longMode: "Long %1",
    endsAt: "ends %1",
    weeks: "20 weeks",
    blocksCount: "%1 blocks",
    detected: "detected",
    projectHint: "What are you working on?",
    thisWeek: "this week · %1 blocks",
    noSilence: "Notifications are not being silenced",
    firstBlock: "Your first block will show up here.",
    stop: "Stop"
  },
  es: {
    start: "Empezar",
    pause: "Pausar",
    resume: "Seguir",
    skip: "Saltar",
    reset: "Reiniciar",
    tooltip: "Locked In",
    block: "Bloque %1",
    blockOf: "Bloque %1 de %2",
    onYourList: "%1 está en tu lista",
    closedIt: "Cerré %1",
    closedNote: "Estaba en tu lista",
    left: "te quedan",
    toFinish: "para cerrar el bloque",
    keepGoing: "Seguir igual",
    hide: "Esconder",
    close: "Cerrar",
    blockDone: "Bloque %1 listo",
    blocksToday: "%1 bloques hoy",
    streak: "racha de %1 días",
    heldFor: "%1 avisos llegaron mientras estabas en foco",
    breakFor: "Pausa %1",
    anotherBlock: "Otro bloque",
    breakShort: "Pausa",
    breakLong: "Pausa larga",
    nextBlock: "Después: bloque %1 de %2",
    breakTip: "Párate, toma agua, mira lejos.",
    skipBreak: "Saltar pausa",
    ready: "Lista",
    focusMode: "Foco %1",
    breakMode: "Pausa %1",
    longMode: "Larga %1",
    endsAt: "termina %1",
    weeks: "20 semanas",
    blocksCount: "%1 bloques",
    detected: "detectado",
    projectHint: "¿En qué estás trabajando?",
    thisWeek: "esta semana · %1 bloques",
    noSilence: "Las notificaciones no se están silenciando",
    firstBlock: "Tu primer bloque aparecerá aquí.",
    stop: "Detener"
  }
}

function language(setting, locale) {
  if (setting === "es" || setting === "en") return setting
  return String(locale || "").indexOf("es") === 0 ? "es" : "en"
}

function tr(lang, key) {
  var table = STRINGS[lang] || STRINGS.en
  return table[key] !== undefined ? table[key] : STRINGS.en[key]
}

function clampInt(value, low, high, fallback) {
  var n = Number(value)
  if (value === null || value === undefined || value === "" || typeof value === "boolean" || !isFinite(n)) return fallback
  return Math.max(low, Math.min(high, Math.round(n)))
}

function oneOf(value, options, fallback) {
  return options.indexOf(value) >= 0 ? value : fallback
}

function bool(value, fallback) {
  if (value === true || value === "true" || value === "yes" || value === 1) return true
  if (value === false || value === "false" || value === "no" || value === 0) return false
  return fallback
}

function cleanSettings(raw) {
  var s = raw || {}
  var d = DEFAULTS
  return {
    language: oneOf(s.language, ["auto", "en", "es"], d.language),
    style: oneOf(s.style, ["line", "ring"], d.style),
    focusMinutes: clampInt(s.focusMinutes, 5, 120, d.focusMinutes),
    shortBreakMinutes: clampInt(s.shortBreakMinutes, 1, 30, d.shortBreakMinutes),
    longBreakMinutes: clampInt(s.longBreakMinutes, 5, 60, d.longBreakMinutes),
    longBreakEvery: clampInt(s.longBreakEvery, 2, 8, d.longBreakEvery),
    autoStartBreaks: bool(s.autoStartBreaks, d.autoStartBreaks),
    autoStartFocus: bool(s.autoStartFocus, d.autoStartFocus),
    silenceNotifications: bool(s.silenceNotifications, d.silenceNotifications),
    distractionAction: oneOf(s.distractionAction, ["warn", "hide", "close", "off"], d.distractionAction),
    blocklist: typeof s.blocklist === "string" ? s.blocklist : d.blocklist,
    islandPosition: oneOf(s.islandPosition, ["bar", "below"], d.islandPosition)
  }
}

// The widget's settings live inline on its entry in ~/.config/omarchy/shell.json.
function settingsFromShellConfig(text, id) {
  var config
  try { config = JSON.parse(text) } catch (e) { return null }
  var layout = config && config.bar && config.bar.layout
  if (!layout) return null
  var sections = ["left", "center", "right"]
  for (var i = 0; i < sections.length; i++) {
    var entries = layout[sections[i]] || []
    for (var j = 0; j < entries.length; j++) {
      if (entries[j] && entries[j].id === id) return entries[j]
    }
  }
  return null
}

// --- Focus/break state machine ------------------------------------------------
//
// next() decides; Service.qml carries out the effects it returns. Time is kept
// as an absolute endsAt so a shell restart or a suspend never loses count.

var MINUTE = 60000
var PHASES = ["idle", "focus", "short", "long"]

function initialState() {
  return { phase: "idle", running: false, endsAt: 0, remainingMs: 0, durationMs: 0,
    cycle: 0, project: "", startedAt: 0, dndBefore: null, blocked: 0 }
}

function phaseMs(phase, settings) {
  if (phase === "focus") return settings.focusMinutes * MINUTE
  if (phase === "short") return settings.shortBreakMinutes * MINUTE
  if (phase === "long") return settings.longBreakMinutes * MINUTE
  return 0
}

function remainingMs(state, now) {
  if (state.phase === "idle") return 0
  return state.running ? Math.max(0, state.endsAt - now) : state.remainingMs
}

function copy(state) {
  var out = {}
  for (var k in state) out[k] = state[k]
  return out
}

function enter(state, phase, at, running, settings) {
  var st = copy(state)
  var ms = phaseMs(phase, settings)
  st.phase = phase
  st.running = running
  st.startedAt = at
  st.durationMs = ms
  st.endsAt = running ? at + ms : 0
  st.remainingMs = running ? 0 : ms
  if (phase === "focus") st.blocked = 0
  return st
}

function entryFor(state, end, completed, ms) {
  return { start: state.startedAt, end: end, kind: state.phase, project: state.project,
    completed: completed, ms: ms, blocked: state.phase === "focus" ? (state.blocked || 0) : 0 }
}

function startFocus(state, at, settings, effects) {
  if (settings.silenceNotifications) effects.push({ type: "silence-on" })
  effects.push({ type: "island", face: "start" })
  return enter(state, "focus", at, true, settings)
}

function endFocus(state, end, completed, ms, settings, effects) {
  effects.push({ type: "record", entry: entryFor(state, end, completed, ms) })
  if (settings.silenceNotifications) effects.push({ type: "silence-off", restore: state.dndBefore === true })
  effects.push({ type: "release-hidden" })
}

function afterFocus(state, end, completed, settings, effects) {
  var st = copy(state)
  if (completed) st.cycle = state.cycle + 1
  var kind = completed && st.cycle % settings.longBreakEvery === 0 ? "long" : "short"
  // A finished block gets its moment; a skipped one goes straight to the break.
  effects.push({ type: "island", face: completed ? "done" : "pause" })
  return enter(st, kind, end, settings.autoStartBreaks, settings)
}

// Auto-start only right after the break really ended; after a suspend or a
// shell outage, starting at a past time would invent blocks nobody worked.
var AUTO_START_GRACE = MINUTE

function afterBreak(state, end, now, settings, effects) {
  var st = copy(state)
  if (state.phase === "long") st.cycle = 0
  if (settings.autoStartFocus && now - end <= AUTO_START_GRACE) return startFocus(st, end, settings, effects)
  var idle = initialState()
  idle.cycle = st.cycle
  idle.project = st.project
  idle.dndBefore = st.dndBefore
  return idle
}

function next(state, event, now, settings) {
  var effects = []
  var st = state
  var left = remainingMs(state, now)

  switch (event.type) {
  case "dnd":
    st = copy(state)
    st.dndBefore = event.value === true
    break
  case "start":
    if (state.phase === "focus") break
    st = copy(state)
    if (event.project) st.project = event.project
    st = startFocus(st, now, settings, effects)
    break
  case "pause":
    if (!state.running || state.phase === "idle") break
    st = copy(state)
    st.running = false
    st.remainingMs = left
    break
  case "resume":
    if (state.running || state.phase === "idle") break
    st = copy(state)
    st.running = true
    st.endsAt = now + state.remainingMs
    break
  case "adjust": {
    // Wheel on the dashboard's ring: lengthen or shorten the current phase,
    // keeping at least a minute left and the phase within its settings range.
    if (state.phase === "idle") break
    var cap = { focus: 120, short: 30, long: 60 }[state.phase] * MINUTE
    var elapsed = state.durationMs - left
    var target = Math.max(MINUTE, Math.min(cap - elapsed, left + Math.round(Number(event.minutes) || 0) * MINUTE))
    var delta = target - left
    if (!delta) break
    st = copy(state)
    st.durationMs = state.durationMs + delta
    if (state.running) st.endsAt = state.endsAt + delta
    else st.remainingMs = target
    break
  }
  case "blocked":
    if (state.phase !== "focus") break
    st = copy(state)
    st.blocked = (state.blocked || 0) + 1
    break
  case "tick":
    if (!state.running || state.phase === "idle" || now < state.endsAt) break
    if (state.phase === "focus") {
      endFocus(state, state.endsAt, true, state.durationMs, settings, effects)
      st = afterFocus(state, state.endsAt, true, settings, effects)
    } else {
      effects.push({ type: "record", entry: entryFor(state, state.endsAt, true, state.durationMs) })
      st = afterBreak(state, state.endsAt, now, settings, effects)
    }
    break
  case "skip":
    if (state.phase === "focus") {
      endFocus(state, now, false, state.durationMs - left, settings, effects)
      st = afterFocus(state, now, false, settings, effects)
    } else if (state.phase !== "idle") {
      st = afterBreak(state, now, now, settings, effects)
    }
    break
  case "stop":
    if (state.phase === "focus") endFocus(state, now, false, state.durationMs - left, settings, effects)
    if (state.phase !== "idle") {
      st = initialState()
      st.project = state.project
      st.dndBefore = state.dndBefore
    }
    break
  }
  return { state: st, effects: effects }
}

// Picks a saved state back up after a shell restart, closing every phase that
// ended while the shell was down at the time it really ended.
function rehydrate(saved, now, settings) {
  if (!saved || typeof saved !== "object" || PHASES.indexOf(saved.phase) < 0 || saved.phase === "idle") {
    var idle = initialState()
    if (saved && typeof saved.project === "string") idle.project = saved.project
    if (saved && typeof saved.cycle === "number" && PHASES.indexOf(saved.phase) >= 0) idle.cycle = saved.cycle
    return { state: idle, effects: [] }
  }
  var st = copy(initialState())
  for (var k in saved) st[k] = saved[k]
  var effects = []
  for (var i = 0; i < 16; i++) {
    var r = next(st, { type: "tick" }, now, settings)
    if (r.effects.length === 0) break
    st = r.state
    effects = effects.concat(r.effects)
  }
  // A focus block survived the restart: silence and hidden windows were given
  // back when the old service went away, so put them back.
  if (st.phase === "focus") {
    if (settings.silenceNotifications) effects.push({ type: "silence-on" })
    effects.push({ type: "rehide" })
  }
  return { state: st, effects: effects }
}

// --- History and statistics ---------------------------------------------------
//
// history.jsonl holds one block per line. Days are local calendar days, stepped
// with Date arithmetic (never 24 h) so daylight saving changes cannot break a
// streak.

function parseHistory(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var e
    try { e = JSON.parse(line) } catch (err) { continue }
    if (!e || typeof e !== "object" || e instanceof Array) continue
    if (typeof e.start !== "number" || typeof e.end !== "number" || typeof e.kind !== "string") continue
    if (typeof e.ms !== "number") e.ms = Math.max(0, e.end - e.start)
    if (typeof e.project !== "string") e.project = ""
    out.push(e)
  }
  return out
}

function pad(n) { return (n < 10 ? "0" : "") + n }

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function dayStart(ms, offsetDays) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + (offsetDays || 0)).getTime()
}

// Monday = 0 … Sunday = 6
function weekday(ms) { return (new Date(ms).getDay() + 6) % 7 }

function isCompletedFocus(e) { return e.kind === "focus" && e.completed === true }

function minutesOf(e) { return Math.round(e.ms / MINUTE) }

function blocksPerDay(entries) {
  var days = {}
  for (var i = 0; i < entries.length; i++) {
    if (!isCompletedFocus(entries[i])) continue
    var k = dayKey(entries[i].start)
    days[k] = (days[k] || 0) + 1
  }
  return days
}

function stats(entries, now) {
  var today = dayKey(now)
  var weekStart = dayStart(now, -weekday(now))
  var s = { today: { blocks: 0, minutes: 0 }, week: { blocks: 0, minutes: 0 }, streak: 0 }
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (!isCompletedFocus(e)) continue
    if (dayKey(e.start) === today) { s.today.blocks++; s.today.minutes += minutesOf(e) }
    if (e.start >= weekStart && e.start <= now) { s.week.blocks++; s.week.minutes += minutesOf(e) }
  }
  var days = blocksPerDay(entries)
  var offset = days[today] ? 0 : -1
  while (days[dayKey(dayStart(now, offset))]) { s.streak++; offset-- }
  return s
}

function byProject(entries, now, days) {
  var since = dayStart(now, -(days - 1))
  var totals = {}
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e.kind !== "focus" || !e.project || e.start < since || e.start > now) continue
    totals[e.project] = (totals[e.project] || 0) + e.ms
  }
  var out = []
  for (var p in totals) out.push({ project: p, minutes: Math.round(totals[p] / MINUTE) })
  out.sort(function(a, b) { return b.minutes - a.minutes || (a.project < b.project ? -1 : 1) })
  return out
}

function recentProjects(entries, now, limit) {
  var since = dayStart(now, -29)
  var counts = {}
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e.kind !== "focus" || !e.project || e.start < since) continue
    counts[e.project] = (counts[e.project] || 0) + 1
  }
  var names = Object.keys(counts)
  names.sort(function(a, b) { return counts[b] - counts[a] || (a < b ? -1 : 1) })
  return names.slice(0, limit)
}

function level(blocks) {
  if (!blocks) return 0
  if (blocks === 1) return 1
  if (blocks <= 3) return 2
  if (blocks <= 5) return 3
  return 4
}

// weeks * 7 cells, column by column (one column per week, Monday on top).
// The last column is the current week; its days after today are -1.
function heatmap(entries, now, weeks) {
  var days = blocksPerDay(entries)
  var firstMonday = dayStart(now, -weekday(now) - (weeks - 1) * 7)
  var today = dayKey(now)
  var cells = []
  var past = true
  for (var i = 0; i < weeks * 7; i++) {
    var key = dayKey(dayStart(firstMonday, i))
    cells.push(past ? level(days[key]) : -1)
    if (key === today) past = false
  }
  return cells
}

function clock(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  return pad(Math.floor(total / 60)) + ":" + pad(total % 60)
}

function duration(minutes) {
  var m = Math.max(0, Math.round(minutes))
  if (m < 60) return m + "m"
  return Math.floor(m / 60) + "h " + pad(m % 60) + "m"
}

// --- Distractions and missed notifications ------------------------------------

function parseBlocklist(text) {
  var out = []
  var parts = String(text || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var term = parts[i].trim().toLowerCase()
    // One letter would match nearly every title.
    if (term.length > 1 && out.indexOf(term) < 0) out.push(term)
  }
  return out
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// Whole words only, so "discord" leaves "discord-bot" alone; a term with a dot
// is a domain, so "x.com" does not catch "dropbox.com" or "netflix.com".
function termPattern(term) {
  var left = term.indexOf(".") >= 0 ? "(^|[^a-z0-9_.-])" : "(^|[^a-z0-9_-])"
  return new RegExp(left + escapeRegExp(term) + "($|[^a-z0-9_-])")
}

// The term that flags a window, matched against its class (which may carry a
// suffix, as in steam_app_123) or its title (so YouTube counts inside any
// browser), or "" when the window is fine.
function blockedBy(list, windowClass, title) {
  var cls = String(windowClass || "").toLowerCase()
  var ttl = String(title || "").toLowerCase()
  for (var i = 0; i < list.length; i++) {
    var pattern = termPattern(list[i])
    if (cls && (cls.indexOf(list[i]) === 0 || pattern.test(cls))) return list[i]
    if (ttl && pattern.test(ttl)) return list[i]
  }
  return ""
}

// Omarchy keeps every notification, silenced ones included, as
// <epoch-ms>-<id>.json in its history folder.
function missedNotifications(fileNames, start, end) {
  var count = 0
  for (var i = 0; i < fileNames.length; i++) {
    var m = /^(\d+)-\d+\.json$/.exec(fileNames[i])
    if (!m) continue
    var ms = Number(m[1])
    if (ms >= start && ms < end) count++
  }
  return count
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    DEFAULTS: DEFAULTS,
    STRINGS: STRINGS,
    language: language,
    tr: tr,
    cleanSettings: cleanSettings,
    settingsFromShellConfig: settingsFromShellConfig,
    initialState: initialState,
    next: next,
    remainingMs: remainingMs,
    rehydrate: rehydrate,
    parseHistory: parseHistory,
    dayKey: dayKey,
    stats: stats,
    byProject: byProject,
    recentProjects: recentProjects,
    heatmap: heatmap,
    clock: clock,
    duration: duration,
    parseBlocklist: parseBlocklist,
    blockedBy: blockedBy,
    missedNotifications: missedNotifications
  }
}
