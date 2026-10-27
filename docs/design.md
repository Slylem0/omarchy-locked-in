# Locked In: diseño

Fecha: 2026-10-27 · Estado: borrador para revisar

## 1. Qué es y para quién

Locked In es un plugin del shell de Omarchy para trabajar por bloques
(Pomodoro). Vive en la barra, silencia las notificaciones mientras dura un
bloque, frena las apps que distraen y registra cuánto tiempo le dedicas a cada
proyecto.

Tiene que servir a dos públicos a la vez:

- **Su autor**, que programa a diario y quiere saber cuánto le dedica a cada
  repo sin anotar nada a mano.
- **Cualquier usuario de Omarchy**, desde la tienda de plugins: debe funcionar
  con la barra estándar o con otras barras, en inglés o en español, y sin tocar
  `~/.config/hypr`.

Hoy no hay ningún plugin de concentración en el catálogo de Omarchy.

### Criterios de éxito

1. Se instala con `omarchy plugin add` y funciona sin editar archivos a mano.
2. Empezar un bloque cuesta un clic o una tecla, y el proyecto ya viene puesto.
3. Durante un bloque no aparece ninguna notificación (salvo las críticas que
   Omarchy deja pasar), y al terminar ves cuáles llegaron.
4. Abrir una app de la lista negra durante un bloque produce la acción elegida
   (avisar, esconder o cerrar).
5. El historial sobrevive a reinicios del shell y del equipo.
6. `omarchy plugin validate` pasa y la suite de pruebas pasa sin tocar la
   pantalla, las notificaciones ni Hyprland reales.

### Fuera de alcance (v1)

- Sincronizar entre equipos o con servicios externos (Todoist, Toggl…).
- Sonidos.
- Modo enfoque visual (atenuar ventanas o esconder la barra). Se descartó en el
  diseño.
- Bloquear sitios web dentro del navegador. Se detectan por el título de la
  ventana, no por la URL.

## 2. Decisiones tomadas en el diseño

| Tema | Decisión |
|---|---|
| Tiempos | 25 / 5 / 15, pausa larga cada 4 bloques; todo configurable |
| Durante un bloque | Silenciar notificaciones + escudo contra distracciones + tiempo en la barra |
| Escudo | Cada usuario elige: avisar (por defecto), esconder o cerrar |
| Historial | Estadísticas (hoy, semana, racha) y tiempo por proyecto |
| Proyecto | Se detecta solo y se puede cambiar o escribir otro |
| Widget de barra | Dos estilos: línea (por defecto) y anillo |
| Panel | "Tablero": reloj, historial de 20 semanas, proyecto, tiempo por proyecto |
| Avisos | La isla central de la barra se transforma, con animación de resorte |
| Pausa | Se abre como isla expandida y se puede minimizar a una isla delgada |
| Idiomas | Inglés y español; `auto` sigue el idioma del sistema |
| Nombre | Locked In, id `slylem0.locked-in`, repo `Slylem0/omarchy-locked-in` |

Los bocetos aprobados son la referencia visual de la sección 6.

## 3. Requisitos de un plugin de Omarchy

Lo que exige el shell (`shell/services/PluginRegistry.qml`) y repite
`omarchy plugin validate`:

- `manifest.json` en la raíz del repo con `schemaVersion: 1` (número),
  `id`, `name`, `version`, `kinds` (arreglo no vacío) y `entryPoints`.
- El `id` no puede empezar por `omarchy.` y solo admite `[A-Za-z0-9._-]`.
- Cada entrada de `entryPoints` es una ruta relativa segura que existe.
  Ningún archivo del repo puede ser un enlace simbólico.
- Cada `kind` necesita su entrada: `service` → `service`,
  `bar-widget` → `barWidget`.
- Un `bar-widget` declara `barWidget` con `displayName`, `description`,
  `category`, `allowMultiple`, `defaultSection`, `defaults` y `schema`
  (los ajustes que muestra la interfaz de Omarchy).
- Los ajustes viven en la entrada del widget dentro de
  `~/.config/omarchy/shell.json`. No hay archivo de ajustes propio.
- Un plugin de terceros recibe por inyección `shell`, `manifest`, etc. como
  fachadas limitadas: solo puede controlar su propio servicio.
- El código de `~/.config/omarchy/plugins/` se recarga al guardar. Un servicio
  con `keepLoaded` solo se recarga al reiniciar el shell.
- Instalar = clonar el repo; actualizar = `git pull` de avance rápido. El repo
  es el plugin, así que en la raíz solo va lo que el plugin usa, más README,
  LICENSE, imágenes, pruebas y documentación.

## 4. Arquitectura

```
manifest.json        kinds: service + bar-widget
Service.qml          el cerebro: estado del bloque, temporizadores, historial,
                     No molestar, escudo, IPC; dibuja la isla
Island.qml           la isla dinámica (todas sus caras y animaciones)
BarWidget.qml        el widget de la barra (línea o anillo); abre el panel
Panel.qml            el tablero
Model.js             lógica pura sin QML: máquina de estados, ajustes,
                     estadísticas, mapa de calor, formato, textos en/es
bin/locked-in        CLI: start/pause/stop/status/stats y detección de proyecto
test/run             pruebas del CLI con comandos falsos + Model.js con node
test/model.test.js
docs/design.md       este documento
README.md  LICENSE  preview.png  demo.gif
```

Una sola fuente de verdad: `Service.qml`. El widget, el panel y la isla solo
leen su estado y le piden acciones. Toda la lógica que se puede probar sin
pantalla (transiciones, cálculos, textos) vive en `Model.js`, como en
Screenshot Clip.

### 4.1 Máquina de estados (Model.js)

Estados: `idle`, `focus`, `short`, `long`, cada uno `running` o `paused`.

```
idle --start--> focus
focus --fin--> short | long (long si el bloque completado es múltiplo de longEvery)
short/long --fin--> focus (si autoStartFocus) o idle
cualquiera --stop--> idle      (un focus cortado se guarda como no completado)
cualquiera --skip--> siguiente fase
running <--pause/resume--> paused
```

`Model.next(state, event, now, settings)` devuelve el estado nuevo y una lista
de efectos (`"silence-on"`, `"silence-off"`, `"record"`, `"island:done"`, …).
El servicio ejecuta los efectos. Así las transiciones se prueban con node sin
QML.

El tiempo se guarda como `endsAt` (época en ms), no como un contador. Si el
shell se reinicia o el equipo se suspende, el resto se calcula de nuevo con el
reloj. Si al volver el bloque ya terminó, se cierra como completado con su hora
real de fin.

### 4.2 Persistencia

En `$XDG_STATE_HOME/locked-in/` (por defecto `~/.local/state/locked-in/`):

- `state.json`: el bloque en curso, para sobrevivir a un reinicio del shell:
  `{phase, running, endsAt, remainingMs, cycle, project, dndBefore, hidden[]}`.
- `history.jsonl`: una línea por bloque terminado o cortado:
  `{"start":…, "end":…, "kind":"focus", "project":"screenshot-clip", "completed":true, "silenced":3, "blocked":1}`.
  Solo se agregan líneas, nunca se reescribe. Una línea corrupta se ignora y el
  resto se sigue leyendo.

Las estadísticas (hoy, semana, racha, 20 semanas, por proyecto) se calculan en
`Model.js` a partir de `history.jsonl`, en la zona horaria local. La racha
cuenta días seguidos con al menos un bloque completado; hoy cuenta aunque
todavía no tenga bloques.

### 4.3 Silenciar notificaciones

- Al empezar un focus: guardar `omarchy-shell notifications dndState` en
  `dndBefore` y llamar `setDnd on`.
- Al terminar o cortar: `setDnd` al valor de `dndBefore`. Si el usuario ya
  tenía No molestar activado, sigue activado.
- Avisos perdidos: Omarchy guarda en
  `$XDG_STATE_HOME/omarchy/notifications/history/` también los que silenció,
  y cada archivo empieza por su hora en ms. Se cuentan los que caen dentro del
  bloque y se muestran los 3 más recientes (app y resumen).
- Si el destino `notifications` no responde (otro demonio de notificaciones),
  el bloque funciona igual, el panel indica "notificaciones no silenciadas" y
  la fila de avisos perdidos no aparece.

### 4.4 Escudo contra distracciones

- Ajuste `blocklist`: lista separada por comas. Cada término se compara, sin
  distinguir mayúsculas, con la clase de la ventana o con su título (para
  "YouTube" dentro de un navegador). Por defecto: `youtube, discord, steam,
  reddit, x.com, instagram, twitch`.
- Se escuchan los eventos `openwindow` y `activewindow` de Hyprland
  (`Quickshell.Hyprland`). Solo actúa durante un focus en marcha.
- Acciones (`distractionAction`):
  - `warn`: la isla se expande con el escudo. Seguir igual / Esconder / Cerrar.
  - `hide`: la ventana va a `special:locked-in` y vuelve a su workspace al
    terminar el bloque. Las direcciones se guardan en `state.json`.
  - `close`: se cierra la ventana (`hl.dsp.window.close`), con la isla
    explicando qué pasó.
  - `off`: sin escudo.
- "Seguir igual" deja en paz a esa ventana hasta el fin del bloque. Cada
  intervención suma 1 a `blocked` en el historial.

### 4.5 Detección de proyecto (bin/locked-in project)

En orden, lo primero que dé un nombre:

1. Ventana con foco de una terminal (kitty, ghostty, alacritty, foot): tomar su
   PID, bajar al proceso hijo más profundo (`/proc/<pid>/task/*/children`),
   leer su `cwd` y usar el nombre de `git rev-parse --show-toplevel`. Si no es
   un repo, el nombre de la carpeta.
2. Editores con el proyecto en el título (VS Code, Zed, Neovim en terminal):
   la parte del título que coincide con un repo en `~/Projects`, `~/code` o
   `~/src`.
3. El último proyecto usado.

El panel muestra el resultado con la etiqueta "detectado", sugiere los 4
proyectos más usados de los últimos 30 días y permite escribir uno nuevo.

### 4.6 La isla (Island.qml)

Una `PanelWindow` de capa `overlay`, anclada arriba y centrada, con namespace
`locked-in`. Toma la altura y el radio de las islas de la barra
(`Style`/`Commons`) para quedar encima del centro de la barra, como el OSD.
Ajuste `islandPosition`: `bar` (encima del centro de la barra, por defecto) o
`below` (justo debajo).

Caras: `start` (se estira a los lados 2,4 s y vuelve), `shield`, `done`,
`pause`, `pause-min`. Las animaciones usan `SpringAnimation` (amortiguamiento
cercano a 0,7, rebote corto). Al crecer, la isla se aplasta un instante; el
contenido sale desenfocado y entra en cascada. Con `reducedMotion` del sistema
se reemplaza todo por fundidos cortos.

El vidrio: al cargar, el servicio pide a Hyprland desenfocar su capa con
`hyprctl eval 'hl.layer_rule({ match = { namespace = "^locked%-in$" }, blur = true, ignore_alpha = 0.3 })'`
(el mismo método con el que Screenshot Clip asigna su tecla). No toca
`~/.config/hypr`.

### 4.7 Widget de barra y panel

- **Línea (por defecto):** proyecto · barra de progreso · `mm:ss` · puntos del
  ciclo. **Anillo:** aro de 14 px y `mm:ss`. Fuera de un bloque, un ícono de
  reloj.
- Clic izquierdo: abrir o cerrar el panel. Clic derecho: empezar o pausar.

- **Panel (tablero):** selector de fase, anillo grande con hora de fin, mapa de
  calor de 20 semanas, proyecto detectado con sugerencias, tiempo por proyecto
  de la semana y racha, y Reiniciar / Pausar / Saltar. Teclado: Espacio
  pausar, R reiniciar, S saltar, Esc cerrar.

### 4.8 IPC y CLI

`IpcHandler` con destino `slylem0.locked-in`: `start [project]`, `pause`,
`resume`, `toggle`, `skip`, `stop`, `status` (JSON), `panel`. `bin/locked-in`
los envuelve y agrega `stats [--week|--month]` con la salida en texto del
boceto (barras por proyecto, racha). El README muestra cómo asignar teclas:

```lua
o.bind("SUPER + ALT + P", "Locked In", "omarchy-shell slylem0.locked-in toggle")
```

El plugin no asigna teclas por su cuenta, para no pisar las del usuario.

## 5. Ajustes (schema del widget)

| Clave | Tipo | Por defecto |
|---|---|---|
| `language` | enum auto/en/es | `auto` |
| `style` | enum line/ring | `line` |
| `focusMinutes` | integer 5–120 | 25 |
| `shortBreakMinutes` | integer 1–30 | 5 |
| `longBreakMinutes` | integer 5–60 | 15 |
| `longBreakEvery` | integer 2–8 | 4 |
| `autoStartBreaks` | boolean | true |
| `autoStartFocus` | boolean | false |
| `silenceNotifications` | boolean | true |
| `distractionAction` | enum warn/hide/close/off | `warn` |
| `blocklist` | string | `youtube, discord, steam, reddit, x.com, instagram, twitch` |
| `islandPosition` | enum bar/below | `bar` |

`Model.cleanSettings` acota los números a sus rangos y vuelve al valor por
defecto ante cualquier dato inválido.

## 6. Referencia visual

Los bocetos aprobados (isla de vidrio sobre la barra, panel tablero, escudo,
fin de bloque, pausa y pausa minimizada) definen colores, tamaños y
movimientos. Los colores salen del tema activo (`Commons.Color`): el acento
para el foco, verde para pausa y fin de bloque, el color de alerta de la barra
para el escudo. Así el plugin cambia de color con cada tema de Omarchy.

## 7. Errores y casos límite

- Shell reiniciado a mitad de bloque: se rehidrata desde `state.json`; si el
  bloque ya terminó, se cierra con su hora real.
- Suspensión: igual que lo anterior, gracias a `endsAt`.
- `history.jsonl` dañado o ausente: se ignoran las líneas malas y las
  estadísticas empiezan vacías.
- Hyprland recarga su configuración: se vuelve a pedir la regla de
  desenfoque, igual que Screenshot Clip vuelve a asignar su tecla.
- Ventanas escondidas que ya no existen al terminar: se ignoran.
- Plugin desactivado a mitad de bloque: se restaura No molestar y las ventanas
  escondidas vuelven a su sitio en `Component.onDestruction`.

## 8. Pruebas

- `test/model.test.js` (node, sin dependencias): transiciones y efectos,
  rehidratación tras reinicio, limpieza de ajustes, estadísticas, racha con
  zonas horarias y días sin bloques, mapa de calor, formato, que todos los
  textos existan en en y es.
- `test/run` (bash): `bin/locked-in` contra `omarchy-shell`, `hyprctl` y `git`
  falsos; detección de proyecto con un `/proc` simulado mediante una variable
  de entorno de raíz; salida de `stats`.
- `omarchy plugin validate .` dentro de `test/run`.
- `qmllint` sobre los `.qml`, sin advertencias nuevas.
- Prueba manual antes de publicar: bloque completo con pausa, escudo en sus
  tres modos, reinicio del shell a mitad de bloque, cambio de tema.

## 9. Publicación

README en inglés con sección en español (como Screenshot Clip), `preview.png`
(la portada), `demo.gif`, LICENSE MIT, versión `1.0.0` en el manifest. El repo
se crea privado y se hace público al publicar la 1.0.
