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
    tooltip: "Locked In"
  },
  es: {
    start: "Empezar",
    pause: "Pausar",
    resume: "Seguir",
    skip: "Saltar",
    reset: "Reiniciar",
    tooltip: "Locked In"
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

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    DEFAULTS: DEFAULTS,
    STRINGS: STRINGS,
    language: language,
    tr: tr,
    cleanSettings: cleanSettings,
    settingsFromShellConfig: settingsFromShellConfig
  }
}
