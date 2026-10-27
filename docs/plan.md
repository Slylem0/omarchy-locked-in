# Locked In: plan de implementación

**Objetivo:** construir el plugin `slylem0.locked-in` descrito en `docs/design.md`.

**Arquitectura:** un servicio QML (`Service.qml`) es la única fuente de verdad y
ejecuta los efectos que decide `Model.js`, un archivo de lógica pura que corre
también en node para las pruebas. La isla, el widget y el panel solo leen el
estado del servicio y le piden acciones. `bin/locked-in` resuelve lo que
necesita el sistema (detectar el proyecto, estadísticas en texto, IPC).

**Tecnologías:** Quickshell/QML (Qt 6) dentro de `omarchy-shell`, JavaScript
ES5 en `Model.js` (lo carga QML), bash para `bin/` y `test/run`, node solo para
pruebas.

**Spec:** `docs/design.md`. Quien implemente lee los dos documentos.

## Restricciones globales

- Commits solo con `Pablo Nicolás Marín <pnicolasmarin2007@gmail.com>`, sin
  líneas `Co-Authored-By` y sin mencionar herramientas de IA en ningún archivo.
- `manifest.json`: `schemaVersion: 1`, `id: "slylem0.locked-in"`,
  `kinds: ["service", "bar-widget"]`, `entryPoints: {"service": "Service.qml", "barWidget": "BarWidget.qml"}`.
  Sin enlaces simbólicos en el repo.
- `Model.js` sin imports de QML, ES5 (sin `let`, sin flechas), y exporta con
  `if (typeof module !== "undefined") module.exports = {...}` como Screenshot Clip.
- Estado en `${XDG_STATE_HOME:-$HOME/.local/state}/locked-in/` (`state.json`,
  `history.jsonl`).
- Destino IPC `slylem0.locked-in`; namespace de capa `locked-in`; workspace
  especial `special:locked-in`.
- Ajustes y rangos exactos de la tabla de la sección 5 de la spec.
- Textos de interfaz en `en` y `es`, con las mismas claves en ambos.
- Seguir los patrones de Screenshot Clip: `BarWidget` + `WidgetButton`, panel
  con `KeyboardPanel` y `PanelKeyCatcher`, `Commons.Color` para los colores,
  `Style.space()` para medidas.

## Puntos de revisión

1. **Reinicio o suspensión a mitad de bloque:** al volver, el tiempo restante
   sale de `endsAt`; si ya pasó, el bloque se registra con su hora de fin real
   y no con la hora de regreso. Prueba en la tarea 2.
2. **No molestar ya activado antes del bloque:** al terminar debe seguir
   activado. Prueba de efectos en la tarea 2 (`silence-off` lleva el valor
   anterior).
3. **Términos de la lista negra demasiado amplios o vacíos:** `" , ,"` no
   bloquea nada; `"x"` no debe disparar con cualquier título que tenga una x
   (los términos de 1 letra se ignoran). Prueba en la tarea 4.
4. **Proyecto sin git, con espacios o desde ssh:** sin repo se usa el nombre de
   la carpeta; los espacios se conservan; si el proceso más profundo es `ssh`,
   se usa el cwd de la shell que lo lanzó. Prueba en la tarea 5.
5. **Rachas y días en hora local, incluido el cambio de hora:** un bloque a las
   23:50 cuenta para ese día; una racha no se rompe por un día de 23 o 25 h.
   Prueba en la tarea 3.

---

### Tarea 1: Esqueleto que valida

**Archivos:**
- Crear: `manifest.json`, `LICENSE`, `Model.js`, `Service.qml`, `BarWidget.qml`,
  `test/run`, `test/model.test.js`

**Interfaces:**
- Produce: `Model.PLUGIN_ID`, `Model.DEFAULTS`, `Model.STRINGS`,
  `Model.language(setting, locale) -> "en"|"es"`, `Model.tr(lang, key) -> string`,
  `Model.cleanSettings(raw) -> settings`,
  `Model.settingsFromShellConfig(text, id) -> object|null`.
  `test/run` con los ayudantes `ok`, `fail`, `stub` y el bloque final que corre
  `omarchy-plugin-validate` y node.

- [ ] **Paso 1: pruebas que fallan** en `test/model.test.js`:
  - `"settings fall back to defaults"`: `cleanSettings({})` y
    `cleanSettings(null)` son iguales a
    `{language:"auto", style:"line", focusMinutes:25, shortBreakMinutes:5, longBreakMinutes:15, longBreakEvery:4, autoStartBreaks:true, autoStartFocus:false, silenceNotifications:true, distractionAction:"warn", blocklist:"youtube, discord, steam, reddit, x.com, instagram, twitch", islandPosition:"bar"}`.
  - `"settings are clamped and typed"`: `{focusMinutes:500, shortBreakMinutes:0, longBreakEvery:"x", style:"donut", distractionAction:"nuke", autoStartFocus:"yes"}`
    da `focusMinutes:120, shortBreakMinutes:1, longBreakEvery:4, style:"line", distractionAction:"warn", autoStartFocus:true`.
  - `"picks the language"` y `"every string exists in both languages"`, como en Screenshot Clip.
  - `"reads this plugin's entry from shell.json"`: encuentra la entrada en
    `bar.layout.left|center|right`.
- [ ] **Paso 2:** `test/run` falla (no existe `Model.js`).
- [ ] **Paso 3:** escribir `Model.js` con esas funciones; `manifest.json` con el
  bloque `barWidget` (`displayName: "Locked In"`, `category: "Productivity"`,
  `allowMultiple: false`, `defaultSection: "right"`, `defaults` = DEFAULTS,
  `schema` con una entrada por ajuste, con `label` y `description` en inglés);
  `Service.qml` (un `Item` con `property var shell: null`) y `BarWidget.qml` (un
  `BarWidget` con un `WidgetButton` de ícono de reloj) mínimos; `LICENSE` MIT
  a nombre de Pablo Nicolas Marin Gonzalez, 2026.
- [ ] **Paso 4:** `test/run` muestra `all passed` y
  `omarchy plugin validate .` sale con 0.
- [ ] **Paso 5: commit** `Plugin skeleton: manifest, settings and test runner`.

### Tarea 2: Máquina de estados del bloque

**Archivos:** Modificar `Model.js`, `test/model.test.js`

**Interfaces:**
- Consume: `cleanSettings`.
- Produce:
  - `Model.initialState() -> {phase:"idle", running:false, endsAt:0, remainingMs:0, cycle:0, project:"", startedAt:0, dndBefore:null}`
  - `Model.next(state, event, now, settings) -> {state, effects}` con
    `event` en `{type:"start", project}`, `{type:"pause"}`, `{type:"resume"}`,
    `{type:"skip"}`, `{type:"stop"}`, `{type:"tick"}`, `{type:"dnd", value}`.
  - Efectos (cadenas u objetos): `{type:"silence-on"}`,
    `{type:"silence-off", restore:<bool>}`, `{type:"record", entry}`,
    `{type:"island", face:"start"|"done"|"pause"}`, `{type:"release-hidden"}`.
  - `Model.remainingMs(state, now) -> number`
  - `Model.rehydrate(saved, now, settings) -> {state, effects}`

- [ ] **Paso 1: pruebas que fallan:**
  - `"start begins a focus block"`: desde idle, `start` con proyecto `"api"` a
    `now=1000` da `phase:"focus", running:true, endsAt:1000+25*60000, project:"api"`
    y efectos `silence-on` e `island:start`.
  - `"tick at the end of focus records and moves to a short break"`: `record`
    con `{kind:"focus", completed:true, start, end:endsAt, project}`,
    `silence-off`, `release-hidden`, `island:done`, y fase `short` en marcha si
    `autoStartBreaks`.
  - `"every fourth block earns a long break"`: con `cycle:3` el siguiente
    descanso es `long` de 15 min.
  - `"break ends idle unless autoStartFocus"`.
  - `"pause keeps the remaining time and resume moves endsAt"`.
  - `"stop during focus records an unfinished block"`: `completed:false`.
  - `"silence restores the previous DND"`: con `dndBefore:true`,
    `silence-off` lleva `restore:true` (Punto 2).
  - `"rehydrate after a restart keeps counting"` y
    `"rehydrate after the block ended closes it at endsAt"`: `record.end`
    igual a `endsAt`, no a `now` (Punto 1).
- [ ] **Paso 2:** fallan.
- [ ] **Paso 3:** implementar en `Model.js`. `dndBefore` lo pone el servicio
  con el evento `dnd` antes del `start`.
- [ ] **Paso 4:** `test/run` pasa.
- [ ] **Paso 5: commit** `Focus/break state machine with restart recovery`.

### Tarea 3: Historial y estadísticas

**Archivos:** Modificar `Model.js`, `test/model.test.js`

**Interfaces:**
- Produce:
  - `Model.parseHistory(text) -> entry[]` (ignora líneas inválidas)
  - `Model.dayKey(ms) -> "YYYY-MM-DD"` en hora local
  - `Model.stats(entries, now) -> {today:{blocks, minutes}, week:{blocks, minutes}, streak}`
    (semana = lunes a hoy; solo cuentan `kind:"focus"` completados)
  - `Model.byProject(entries, now, days) -> [{project, minutes}]` de mayor a menor
  - `Model.heatmap(entries, now, weeks) -> number[]` de `weeks*7` niveles 0–4,
    columna = semana, fila = día (lunes primero), el último es hoy
  - `Model.recentProjects(entries, now, limit) -> string[]` (30 días, por uso)
  - `Model.clock(ms) -> "mm:ss"`, `Model.duration(minutes, lang) -> "2h 05m"`

- [ ] **Paso 1: pruebas que fallan:** `"history skips broken lines"`,
  `"today and week count completed focus only"`,
  `"streak counts consecutive days and survives an empty today"`,
  `"a block at 23:50 belongs to that day"` y
  `"streak survives a daylight saving change"` (con `TZ=America/Santiago` en
  `test/run` para esta prueba) (Punto 5), `"time per project sorted"`,
  `"heatmap has 140 cells ending today"`, `"clock and duration format"`.
- [ ] **Paso 2:** fallan.
- [ ] **Paso 3:** implementar; los niveles del mapa de calor: 0 bloques → 0,
  1 → 1, 2–3 → 2, 4–5 → 3, 6+ → 4.
- [ ] **Paso 4:** pasan.
- [ ] **Paso 5: commit** `History parsing, streaks, heatmap and per-project time`.

### Tarea 4: Lista negra y avisos perdidos

**Archivos:** Modificar `Model.js`, `test/model.test.js`

**Interfaces:**
- Produce:
  - `Model.parseBlocklist(text) -> string[]` en minúsculas, sin vacíos ni
    términos de 1 carácter
  - `Model.blockedBy(list, windowClass, title) -> string|""`: el término que
    coincide con la clase (igual o contenida) o con el título (contenido)
  - `Model.missedNotifications(fileNames, start, end) -> number`: cuenta
    nombres `<ms>-<id>.json` con `start <= ms < end`

- [ ] **Paso 1: pruebas que fallan:** `"blocklist ignores empty and one-letter terms"`
  (Punto 3), `"matches YouTube in a browser title"`
  (`blockedBy(["youtube"], "chromium", "Lo-fi - YouTube — Chromium")` = `"youtube"`),
  `"does not match unrelated windows"`, `"counts notifications inside the block"`.
- [ ] **Paso 2–4:** falla, implementar, pasa.
- [ ] **Paso 5: commit** `Blocklist matching and missed-notification count`.

### Tarea 5: `bin/locked-in`

**Archivos:** Crear `bin/locked-in`; modificar `test/run`

**Interfaces:**
- Produce la CLI:
  - `locked-in project` imprime el proyecto detectado o nada (sale 0 igual)
  - `locked-in start [project]|pause|resume|toggle|skip|stop|status|panel`
    llaman `omarchy-shell slylem0.locked-in <cmd> [arg]`
  - `locked-in stats [--week|--month]` lee `history.jsonl` y escribe barras por
    proyecto (`█`/`░`, 14 celdas), total y racha, en el idioma de
    `LOCKED_IN_LANG` o el sistema
- Variables para pruebas: `LOCKED_IN_PROC` (raíz que reemplaza `/proc`),
  `XDG_STATE_HOME`.

- [ ] **Paso 1: pruebas que fallan** en `test/run`, con `hyprctl` falso que
  devuelve `activewindow -j` de una kitty con PID 100 y un `/proc` falso
  (`100/task/100/children` → `200`, `200/cwd` → enlace a un repo temporal):
  `"project comes from the terminal's git repo"`,
  `"project falls back to the folder name"` (sin git; carpeta `"mi proyecto"`
  con espacio, se conserva) (Punto 4), `"ssh child uses the shell's cwd"`
  (Punto 4), `"project falls back to the last one used"`,
  `"start forwards to the shell"`, `"stats prints bars per project"`.
- [ ] **Paso 2:** fallan.
- [ ] **Paso 3:** implementar siguiendo el estilo de `bin/screenshot-clip`
  (`set -o pipefail`, funciones pequeñas, `case` al final).
- [ ] **Paso 4:** pasan y `shellcheck bin/locked-in` no da avisos.
- [ ] **Paso 5: commit** `CLI: project detection, controls and stats`.

### Tarea 6: Servicio

**Archivos:** Reescribir `Service.qml`

**Interfaces:**
- Consume: todo `Model.js`, `bin/locked-in project`.
- Produce, para la isla, el widget y el panel:
  propiedades `state`, `settings`, `lang`, `remainingMs`, `fraction`
  (0–1 avanzado), `project`, `detectedProject`, `entries`, `silenced`
  (avisos en el bloque actual), `missed` (`[{app, summary}]`), `dndAvailable`, `shield`
  (`{term, title, address}` o `null`), `islandFace`
  (`"idle"|"start"|"shield"|"done"|"pause"|"pause-min"`) y las funciones
  `start(project)`, `pause()`, `resume()`, `toggle()`, `skip()`, `stop()`,
  `shieldKeep()`, `shieldHide()`, `shieldClose()`, `minimizePause()`,
  `expandPause()`, `dismissIsland()`, `refreshProject()`.
  `IpcHandler { target: "slylem0.locked-in" }` con
  `start(project: string)`, `pause`, `resume`, `toggle`, `skip`, `stop`,
  `status` (JSON), `panel`.

- [ ] **Paso 1:** ajustes desde `shell.json` con `FileView` (como Screenshot
  Clip); un `Timer` de 250 ms que manda `tick`; `apply(result)` que guarda el
  estado y ejecuta cada efecto.
- [ ] **Paso 2:** persistencia: escribir `state.json` en cada cambio; agregar
  líneas a `history.jsonl` con `record`; al iniciar, `rehydrate`.
- [ ] **Paso 3:** No molestar con `omarchy-shell notifications dndState|setDnd`;
  si la llamada falla, `dndAvailable = false`. Al terminar un focus, listar
  `$XDG_STATE_HOME/omarchy/notifications/history/`, contar con
  `Model.missedNotifications` y leer los 3 más recientes del bloque para
  `missed` (`[{app, summary}]`), que muestra la cara `done`.
- [ ] **Paso 4:** escudo: `Connections` a `Hyprland.rawEvent` para
  `openwindow` y `activewindow`; `blockedBy`; según `distractionAction`
  mostrar la isla, mover a `special:locked-in`
  (`hl.dsp.window.move({ workspace = "special:locked-in", follow = false, window = "address:…" })`)
  o cerrar (`hl.dsp.window.close`). `release-hidden` devuelve cada ventana a su
  workspace guardado.
- [ ] **Paso 5:** regla de desenfoque con `hyprctl eval` al cargar y en cada
  `configreloaded`; en `Component.onDestruction`, restaurar No molestar y
  devolver las ventanas escondidas.
- [ ] **Paso 6: verificación manual** con el plugin activado:
  `omarchy-shell slylem0.locked-in start prueba` → `status` muestra
  `focus`; `omarchy-shell notifications dndState` → `on`; `stop` → vuelve al
  valor anterior y `history.jsonl` tiene una línea con `completed:false`;
  `omarchy restart shell` a mitad de bloque mantiene el tiempo restante.
- [ ] **Paso 7: commit** `Service: timers, persistence, do-not-disturb and shield`.

### Tarea 7: La isla

**Archivos:** Crear `Island.qml`; modificar `Service.qml` para instanciarla

**Interfaces:**
- Consume: las propiedades y funciones del servicio (tarea 6).
- Produce: `Island { service: root }`, una `PanelWindow` por pantalla
  (`Variants` sobre `Quickshell.screens`, visible solo en la enfocada),
  `WlrLayershell.namespace: "locked-in"`, capa `Overlay`, sin foco de teclado
  salvo en las caras con botones.

- [ ] **Paso 1:** forma base con la altura, el radio y el color de las islas
  (`Style`, `Commons.Color.bar`), y tamaños por cara copiados de los bocetos:
  idle 0 (oculta), start 470×alto de barra, shield 430×178, done 430×234,
  pause 340×196, pause-min 318×alto de barra. Con `islandPosition: "below"`
  la isla queda justo debajo de la barra en vez de encima de su centro.
- [ ] **Paso 2:** animaciones: `SpringAnimation { spring: 3.6; damping: 0.32 }`
  en ancho y alto; aplastado al crecer (`scale` x 1.04 / y 0.955 durante
  130 ms); contenido saliente con opacidad y escala a 0.94, entrante en cascada
  (55 ms entre filas); con `Qt.styleHints` sin animaciones, solo fundidos.
- [ ] **Paso 3:** las caras con sus textos (`Model.tr`), colores del tema
  (acento para foco, verde para pausa y fin, `Commons.Color.bar.active` para
  el escudo) y botones conectados al servicio. `start` vuelve sola a idle a
  los 2,4 s.
- [ ] **Paso 4: verificación manual:** `start` → la isla se estira y vuelve;
  abrir una ventana con "YouTube" en el título → escudo; `skip` → fin de
  bloque; Enter → pausa; minimizar y expandir; cambiar de tema y ver que los
  colores siguen al tema; `qmllint Island.qml` sin avisos nuevos.
- [ ] **Paso 5: commit** `Dynamic island with spring animations`.

### Tarea 8: Widget de barra

**Archivos:** Reescribir `BarWidget.qml`

**Interfaces:**
- Consume: el servicio (por `shell` inyectado, buscando el servicio del propio
  plugin) y `setting("style")`.
- Produce: `open()`, `close()`, `toggle()`, `closeForPopoutSwitch()` como en
  Screenshot Clip, y carga `Panel.qml` con `Loader`.

- [ ] **Paso 1:** estilo `line`: proyecto, barra de 54 px, `mm:ss`, puntos del
  ciclo; estilo `ring`: aro de 14 px y `mm:ss`; fuera de bloque, ícono de reloj.
- [ ] **Paso 2:** clic izquierdo abre el panel; clic derecho `toggle()` del
  servicio.
- [ ] **Paso 3: verificación manual:** `omarchy bar put slylem0.locked-in`,
  los dos estilos desde los ajustes del widget, clic izquierdo y derecho.
- [ ] **Paso 4: commit** `Bar widget in line and ring styles`.

### Tarea 9: Panel tablero

**Archivos:** Crear `Panel.qml`

**Interfaces:**
- Consume: servicio (estado, `entries`, `detectedProject`), `Model.stats`,
  `Model.heatmap(entries, now, 20)`, `Model.byProject(entries, now, 7)`,
  `Model.recentProjects(entries, now, 4)`.

- [ ] **Paso 1:** estructura de los bocetos: selector de fase, anillo de 128 px
  con hora de fin, mapa de calor de 20×7, campo de proyecto con "detectado" y
  4 sugerencias, tiempo por proyecto (3 filas), semana y racha, botones
  Reiniciar / Pausar / Saltar; aviso "notificaciones no silenciadas" si
  `dndAvailable` es falso.
- [ ] **Paso 2:** teclado con `PanelKeyCatcher`: Espacio pausar o seguir, R
  reiniciar, S saltar, Esc cerrar; escribir en el campo cambia el proyecto.
- [ ] **Paso 3: verificación manual:** abrir con clic y con
  `omarchy-shell slylem0.locked-in panel`, recorrer con teclado, empezar un
  bloque desde el panel con otro proyecto.
- [ ] **Paso 4: commit** `Dashboard panel with heatmap and per-project time`.

### Tarea 10: Publicación

**Archivos:** Crear `README.md`, `preview.png`, `demo.gif`; modificar
`manifest.json` (`version: "1.0.0"`)

- [ ] **Paso 1:** README en inglés con sección en español, en el mismo orden
  que Screenshot Clip: por qué, cómo funciona, instalar, ajustes (tabla de la
  spec), teclado y atajos (`o.bind` de ejemplo), línea de comandos, requisitos,
  pruebas, licencia.
- [ ] **Paso 2:** `preview.png` = la portada aprobada (1200×800);
  `demo.gif` grabado con `omarchy capture` de un bloque corto
  (`focusMinutes` temporal de 1).
- [ ] **Paso 3:** `test/run` pasa, `omarchy plugin validate .` pasa,
  `qmllint` sin avisos nuevos, prueba manual completa de la sección 8 de la spec.
- [ ] **Paso 4: commit** `README, preview and demo for 1.0.0`, etiqueta
  `v1.0.0`, y hacer público el repo solo cuando el autor lo confirme.
