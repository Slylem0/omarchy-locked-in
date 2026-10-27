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

const MIN = 60000
const types = effects => effects.map(e => e.type === "island" ? "island:" + e.face : e.type)

// Local-time helpers: the runner sets TZ, so these follow its clock changes.
const at = (y, mo, d, h, mi) => new Date(y, mo - 1, d, h || 0, mi || 0).getTime()
const focus = (start, project, completed) => ({
  start, end: start + 25 * MIN, kind: "focus", project: project || "api",
  completed: completed !== false, ms: 25 * MIN, blocked: 0
})

const cases = {

  "history skips broken lines": () => {
    const text = [
      JSON.stringify({ start: 1, end: 2, kind: "focus", project: "a", completed: true, ms: 1 }),
      "{oops",
      "",
      JSON.stringify({ start: "x", end: 2, kind: "focus" }),
      JSON.stringify([1, 2]),
      JSON.stringify({ start: 3, end: 4, kind: "short", project: "a", completed: true, ms: 1 })
    ].join("\n")
    const entries = Model.parseHistory(text)
    assert.strictEqual(entries.length, 2)
    assert.strictEqual(entries[1].kind, "short")
    assert.deepStrictEqual(Model.parseHistory(""), [])
  },
  "today and week count completed focus only": () => {
    const now = at(2026, 10, 28, 18) // Wednesday
    const entries = [
      focus(at(2026, 10, 28, 9), "api"),
      focus(at(2026, 10, 28, 10), "api", false),
      { start: at(2026, 10, 28, 11), end: at(2026, 10, 28, 11, 5), kind: "short", project: "api", completed: true, ms: 5 * MIN },
      focus(at(2026, 10, 26, 9), "web"),     // Monday, same week
      focus(at(2026, 10, 25, 9), "web")      // Sunday, last week
    ]
    const s = Model.stats(entries, now)
    assert.deepStrictEqual(s.today, { blocks: 1, minutes: 25 })
    assert.deepStrictEqual(s.week, { blocks: 2, minutes: 50 })
  },
  "streak counts consecutive days and survives an empty today": () => {
    const now = at(2026, 10, 28, 8)
    const entries = [focus(at(2026, 10, 27, 9)), focus(at(2026, 10, 26, 9)), focus(at(2026, 10, 24, 9))]
    assert.strictEqual(Model.stats(entries, now).streak, 2)
    assert.strictEqual(Model.stats(entries.concat([focus(at(2026, 10, 28, 7))]), now).streak, 3)
    assert.strictEqual(Model.stats([focus(at(2026, 10, 20, 9))], now).streak, 0)
    assert.strictEqual(Model.stats([], now).streak, 0)
  },
  "a block at 23:50 belongs to that day": () => {
    const e = focus(at(2026, 10, 27, 23, 50))
    assert.strictEqual(Model.dayKey(e.start), "2026-10-27")
    assert.strictEqual(Model.stats([e], at(2026, 10, 27, 23, 59)).today.blocks, 1)
    assert.strictEqual(Model.stats([e], at(2026, 10, 28, 0, 30)).today.blocks, 0)
  },
  "streak survives a daylight saving change": () => {
    // Chile moves its clocks forward on Sunday 2026-09-06: that day has 23 hours.
    const entries = [focus(at(2026, 9, 5, 23)), focus(at(2026, 9, 6, 23)), focus(at(2026, 9, 7, 0, 30))]
    assert.strictEqual(Model.stats(entries, at(2026, 9, 7, 12)).streak, 3)
    assert.strictEqual(Model.dayKey(at(2026, 9, 6, 23, 59)), "2026-09-06")
  },
  "time per project sorted": () => {
    const now = at(2026, 10, 28, 18)
    const entries = [
      focus(at(2026, 10, 28, 9), "api"), focus(at(2026, 10, 27, 9), "api"),
      focus(at(2026, 10, 27, 10), "web"), Object.assign(focus(at(2026, 10, 27, 11), "web", false), { ms: 10 * MIN }),
      focus(at(2026, 10, 10, 9), "old")
    ]
    assert.deepStrictEqual(Model.byProject(entries, now, 7), [
      { project: "api", minutes: 50 }, { project: "web", minutes: 35 }
    ])
    assert.deepStrictEqual(Model.recentProjects(entries, now, 4), ["api", "web", "old"])
    assert.deepStrictEqual(Model.recentProjects(entries, now, 1), ["api"])
  },
  "heatmap has 140 cells ending this week": () => {
    const now = at(2026, 10, 28, 18) // Wednesday
    const entries = [focus(at(2026, 10, 28, 9)), focus(at(2026, 10, 28, 10)), focus(at(2026, 10, 26, 9))]
    for (let i = 0; i < 6; i++) entries.push(focus(at(2026, 10, 27, 8 + i)))
    const cells = Model.heatmap(entries, now, 20)
    assert.strictEqual(cells.length, 140)
    const monday = 19 * 7
    assert.deepStrictEqual(cells.slice(monday, monday + 7), [1, 4, 2, -1, -1, -1, -1])
    assert.strictEqual(cells[0], 0)
  },
  "clock and duration format": () => {
    assert.strictEqual(Model.clock(25 * MIN), "25:00")
    assert.strictEqual(Model.clock(25 * MIN - 200), "25:00")
    assert.strictEqual(Model.clock(61000), "01:01")
    assert.strictEqual(Model.clock(0), "00:00")
    assert.strictEqual(Model.clock(-5), "00:00")
    assert.strictEqual(Model.duration(125), "2h 05m")
    assert.strictEqual(Model.duration(45), "45m")
    assert.strictEqual(Model.duration(0), "0m")
  },

  "start begins a focus block": () => {
    const S = Model.cleanSettings({})
    const r = Model.next(Model.initialState(), { type: "start", project: "api" }, 1000, S)
    assert.strictEqual(r.state.phase, "focus")
    assert.strictEqual(r.state.running, true)
    assert.strictEqual(r.state.endsAt, 1000 + 25 * MIN)
    assert.strictEqual(r.state.project, "api")
    assert.deepStrictEqual(types(r.effects), ["silence-on", "island:start"])
  },
  "start without silence does not touch do-not-disturb": () => {
    const S = Model.cleanSettings({ silenceNotifications: false })
    const r = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S)
    assert.deepStrictEqual(types(r.effects), ["island:start"])
  },
  "tick at the end of focus records and moves to a short break": () => {
    const S = Model.cleanSettings({})
    const st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    assert.deepStrictEqual(Model.next(st, { type: "tick" }, 25 * MIN - 1, S).effects, [])
    const r = Model.next(st, { type: "tick" }, 25 * MIN + 500, S)
    const rec = r.effects.filter(e => e.type === "record")[0]
    assert.deepStrictEqual(rec.entry, { start: 0, end: 25 * MIN, kind: "focus", project: "api", completed: true, ms: 25 * MIN, blocked: 0 })
    assert.deepStrictEqual(types(r.effects), ["record", "silence-off", "release-hidden", "island:done"])
    assert.strictEqual(r.state.phase, "short")
    assert.strictEqual(r.state.running, true)
    assert.strictEqual(r.state.endsAt, 30 * MIN)
    assert.strictEqual(r.state.cycle, 1)
  },
  "every fourth block earns a long break": () => {
    const S = Model.cleanSettings({})
    let st = Object.assign(Model.initialState(), { phase: "focus", running: true, startedAt: 0, endsAt: 25 * MIN, cycle: 3, project: "api" })
    const r = Model.next(st, { type: "tick" }, 25 * MIN, S)
    assert.strictEqual(r.state.phase, "long")
    assert.strictEqual(r.state.endsAt, 40 * MIN)
    assert.strictEqual(r.state.cycle, 4)
    const after = Model.next(r.state, { type: "tick" }, 40 * MIN, S)
    assert.strictEqual(after.state.cycle, 0)
  },
  "break waits when autoStartBreaks is off": () => {
    const S = Model.cleanSettings({ autoStartBreaks: false })
    const st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    const r = Model.next(st, { type: "tick" }, 25 * MIN, S)
    assert.strictEqual(r.state.phase, "short")
    assert.strictEqual(r.state.running, false)
    assert.strictEqual(Model.remainingMs(r.state, 99 * MIN), 5 * MIN)
  },
  "break ends idle unless autoStartFocus": () => {
    const S = Model.cleanSettings({})
    const brk = Object.assign(Model.initialState(), { phase: "short", running: true, startedAt: 0, endsAt: 5 * MIN, cycle: 1, project: "api" })
    const idle = Model.next(brk, { type: "tick" }, 5 * MIN, S)
    assert.strictEqual(idle.state.phase, "idle")
    assert.strictEqual(idle.state.project, "api")
    assert.strictEqual(idle.state.cycle, 1)
    const auto = Model.next(brk, { type: "tick" }, 5 * MIN, Model.cleanSettings({ autoStartFocus: true }))
    assert.strictEqual(auto.state.phase, "focus")
    assert.strictEqual(auto.state.endsAt, 30 * MIN)
    assert.deepStrictEqual(types(auto.effects), ["record", "silence-on", "island:start"])
  },
  "pause keeps the remaining time and resume moves endsAt": () => {
    const S = Model.cleanSettings({})
    let st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    st = Model.next(st, { type: "pause" }, 10 * MIN, S).state
    assert.strictEqual(st.running, false)
    assert.strictEqual(Model.remainingMs(st, 50 * MIN), 15 * MIN)
    assert.deepStrictEqual(Model.next(st, { type: "tick" }, 60 * MIN, S).effects, [])
    st = Model.next(st, { type: "resume" }, 20 * MIN, S).state
    assert.strictEqual(st.endsAt, 35 * MIN)
    const done = Model.next(st, { type: "tick" }, 35 * MIN, S)
    assert.strictEqual(done.effects[0].entry.ms, 25 * MIN)
  },
  "stop during focus records an unfinished block": () => {
    const S = Model.cleanSettings({})
    const st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    const r = Model.next(st, { type: "stop" }, 10 * MIN, S)
    assert.strictEqual(r.state.phase, "idle")
    assert.deepStrictEqual(r.effects[0].entry, { start: 0, end: 10 * MIN, kind: "focus", project: "api", completed: false, ms: 10 * MIN, blocked: 0 })
    assert.deepStrictEqual(types(r.effects), ["record", "silence-off", "release-hidden"])
  },
  "skip during focus goes to the break without counting the block": () => {
    const S = Model.cleanSettings({})
    const st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    const r = Model.next(st, { type: "skip" }, 10 * MIN, S)
    assert.strictEqual(r.effects[0].entry.completed, false)
    assert.strictEqual(r.state.phase, "short")
    assert.strictEqual(r.state.cycle, 0)
  },
  "blocked distractions are counted in the record": () => {
    const S = Model.cleanSettings({})
    let st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    st = Model.next(st, { type: "blocked" }, 1, S).state
    st = Model.next(st, { type: "blocked" }, 2, S).state
    assert.strictEqual(Model.next(st, { type: "stop" }, 3, S).effects[0].entry.blocked, 2)
  },
  "silence restores the previous do-not-disturb": () => {
    const S = Model.cleanSettings({})
    let st = Model.next(Model.initialState(), { type: "dnd", value: true }, 0, S).state
    st = Model.next(st, { type: "start", project: "api" }, 0, S).state
    const off = Model.next(st, { type: "stop" }, MIN, S).effects.filter(e => e.type === "silence-off")[0]
    assert.deepStrictEqual(off, { type: "silence-off", restore: true })
    let plain = Model.next(Model.initialState(), { type: "dnd", value: false }, 0, S).state
    plain = Model.next(plain, { type: "start", project: "api" }, 0, S).state
    assert.strictEqual(Model.next(plain, { type: "stop" }, MIN, S).effects[1].restore, false)
  },
  "rehydrate after a restart keeps counting": () => {
    const S = Model.cleanSettings({})
    const st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    const r = Model.rehydrate(JSON.parse(JSON.stringify(st)), 10 * MIN, S)
    assert.strictEqual(r.state.phase, "focus")
    assert.strictEqual(Model.remainingMs(r.state, 10 * MIN), 15 * MIN)
    assert.deepStrictEqual(r.effects, [])
  },
  "rehydrate after the block ended closes it at endsAt": () => {
    const S = Model.cleanSettings({})
    const st = Model.next(Model.initialState(), { type: "start", project: "api" }, 0, S).state
    const r = Model.rehydrate(st, 3 * 60 * MIN, S)
    const recs = r.effects.filter(e => e.type === "record")
    assert.strictEqual(recs[0].entry.end, 25 * MIN)
    assert.strictEqual(recs[0].entry.completed, true)
    assert.strictEqual(recs[1].entry.kind, "short")
    assert.strictEqual(r.state.phase, "idle")
  },
  "rehydrate ignores garbage": () => {
    const S = Model.cleanSettings({})
    assert.deepStrictEqual(Model.rehydrate(null, 0, S).state, Model.initialState())
    assert.deepStrictEqual(Model.rehydrate({ phase: "nap" }, 0, S).state, Model.initialState())
  },
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
