const assert = require("assert")
const Model = require("../Model.js")

const DEFAULTS = {
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

const cases = {
  "picks the language": () => {
    assert.strictEqual(Model.language("auto", "es_CO"), "es")
    assert.strictEqual(Model.language("auto", "en_US"), "en")
    assert.strictEqual(Model.language("es", "en_US"), "es")
    assert.strictEqual(Model.language("en", "es_ES"), "en")
    assert.strictEqual(Model.language("fr", "fr_FR"), "en")
    assert.strictEqual(Model.tr("es", "start"), "Empezar")
    assert.strictEqual(Model.tr("fr", "start"), "Start")
  },
  "every string exists in both languages": () => {
    assert.deepStrictEqual(Object.keys(Model.STRINGS.es).sort(), Object.keys(Model.STRINGS.en).sort())
  },
  "settings fall back to defaults": () => {
    assert.deepStrictEqual(Model.cleanSettings({}), DEFAULTS)
    assert.deepStrictEqual(Model.cleanSettings(null), DEFAULTS)
  },
  "settings are clamped and typed": () => {
    const s = Model.cleanSettings({
      focusMinutes: 500, shortBreakMinutes: 0, longBreakEvery: "x",
      style: "donut", distractionAction: "nuke", autoStartFocus: "yes"
    })
    assert.strictEqual(s.focusMinutes, 120)
    assert.strictEqual(s.shortBreakMinutes, 1)
    assert.strictEqual(s.longBreakEvery, 4)
    assert.strictEqual(s.style, "line")
    assert.strictEqual(s.distractionAction, "warn")
    assert.strictEqual(s.autoStartFocus, true)
    const t = Model.cleanSettings({ style: "ring", distractionAction: "close", islandPosition: "below", blocklist: "steam" })
    assert.strictEqual(t.style, "ring")
    assert.strictEqual(t.distractionAction, "close")
    assert.strictEqual(t.islandPosition, "below")
    assert.strictEqual(t.blocklist, "steam")
  },
  "reads this plugin's entry from shell.json": () => {
    const config = JSON.stringify({
      bar: { layout: {
        left: [{ id: "omarchy.clock" }],
        right: [{ id: "slylem0.screenshot-clip" }, { id: "slylem0.locked-in", focusMinutes: 50 }]
      } }
    })
    assert.deepStrictEqual(Model.settingsFromShellConfig(config, "slylem0.locked-in"),
      { id: "slylem0.locked-in", focusMinutes: 50 })
    assert.strictEqual(Model.settingsFromShellConfig("{}", "slylem0.locked-in"), null)
    assert.strictEqual(Model.settingsFromShellConfig("not json", "slylem0.locked-in"), null)
  }
}

let failed = 0
for (const [name, fn] of Object.entries(cases)) {
  try {
    fn()
    console.log("ok   " + name)
  } catch (e) {
    failed++
    console.log("FAIL " + name + "\n     " + String(e.message).split("\n").join("\n     "))
  }
}
process.exit(failed ? 1 : 0)
