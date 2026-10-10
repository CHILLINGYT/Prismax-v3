# Módulo Velocidad — personaje con transformación (Godot 4.7)

Módulo **autocontenido y reutilizable** del personaje con transformación
**Humano ↔ Velocista** (supervelocidad). Extraído del proyecto original
(`Leo/leo_jugador.tscn` + `ziba/` + `Leo/efecto_transformacion.gd`) conservando
su implementación y su comportamiento.

- **Godot requerido:** 4.7.x (probado en 4.7.2-stable). Renderer: Forward+.
- **Escena a instanciar:** `res://velocidad/Velocidad.tscn`
- **Autoloads/singletons:** ninguno. **Plugins obligatorios:** ninguno.

---

## 1. Qué contiene

```
res://velocidad/
├── Velocidad.tscn          <- ESCENA PRINCIPAL (instancia esto en tu mundo)
├── scripts/
│   ├── controlador_velocidad.gd   <- FSM Humano/Velocista, transformación, dash,
│   │                                 carga, combate, emote, movimiento, salto
│   ├── camara_velocidad.gd        <- cámara 3ª persona (yaw/pitch, zoom, FOV, vibración)
│   ├── trazador.gd                <- trazado y ejecución de rutas (Catmull-Rom)
│   ├── efectos_velocidad.gd       <- rayos, partículas, afterimages, orquesta distorsión
│   ├── combate.gd                 <- combos 1-2-3-4 + afterimage de golpe
│   ├── capa_velocidad.gd          <- control de intensidad del shader de distorsión
│   ├── rayos.gd                   <- rayos eléctricos procedurales
│   └── efecto_transformacion.gd   <- efecto visual de la transformación
├── modelos/
│   ├── Standing W_Briefcase Idle.fbx (+ _0.png)  <- modelo forma HUMANA
│   └── modelo_velocidad.fbx (+ _0..3.png)        <- modelo forma VELOCISTA
├── animaciones/
│   ├── leo_animations.tres        <- librería de la forma humana
│   └── *.tres                     <- 15 librerías de la forma velocista
│                                     (inactivo, caminar, combos, dash, carga,
│                                      salto, supervelocidad, emote…)
└── shaders/
    └── distorsion_velocidad.gdshader   <- post-proceso de supervelocidad
```

Los efectos (rayos, partículas, afterimages, siluetas) **no son escenas**: se
construyen en tiempo de ejecución desde los scripts. Por eso no hay
subcarpetas `escenas/`, `efectos/`, `materiales/`, `recursos/` ni
`configuracion/`: no había recursos reales que colocar en ellas.

---

## 2. Instalación en otro proyecto (pasos)

1. Copia **la carpeta completa `res://velocidad/`** dentro de tu proyecto
   (arrástrala en el panel FileSystem o cópiala al directorio del proyecto).
   La carpeta se llama `velocidad`, así que **no** pisa carpetas existentes.
2. Verifica las **acciones del Input Map** (ver §3). Sin ellas el personaje no
   recibe entrada.
3. Compila/abre el proyecto: Godot **reimporta** los dos `.fbx` y las texturas
   automáticamente (no copies `.godot/`). Las animaciones ya son recursos
   `.tres` de texto, así que **no dependen de ninguna caché**.
4. En tu escena 3D, instancia `res://velocidad/Velocidad.tscn` (botón
   *Instanciar escena hija*) y colócalo donde quieras que aparezca el personaje.
   El personaje necesita **un suelo con colisión** debajo.
5. Coloca al personaje a ~1 m sobre el suelo (su pivote está a 0; la cápsula a
   +0.95). Si tu mundo escala distinto, ajusta solo la posición, no el interior
   del módulo.

### Cómo debe quedar en tu escena

```
TuNivel (Node3D)
├── (tu suelo / geometría con colisión)
└── Velocidad  <- instancia de res://velocidad/Velocidad.tscn  (CharacterBody3D)
```

---

## 3. Acciones del Input Map requeridas

Crea estas acciones en **Proyecto > Configuración del Proyecto > Mapa de
entrada** (los nombres deben coincidir; el módulo no crea acciones solas para no
tocar la configuración global del anfitrión):

| Acción | Tecla/entrada sugerida | Uso |
|---|---|---|
| `mover_adelante` | W | Moverse (ambas formas) |
| `mover_atras` | S | Moverse |
| `mover_izquierda` | A | Moverse |
| `mover_derecha` | D | Moverse |
| `saltar` | Espacio | Salto |
| `dash` | Shift | Dash (solo velocista) |
| `atacar` | Clic izquierdo | Combo (solo velocista) |
| `cargar_poder` | Clic derecho | Cargar poder / trazar ruta (solo velocista) |
| `emote` | 2 | Emote (solo velocista) |
| `transformacion_velocidad` | G | Alternar Humano ↔ Velocista |

`ui_cancel` (ESC) lo usa el propio módulo para liberar/recapturar el ratón.

**Nota:** si tu proyecto ya usa estos nombres con otras teclas, el módulo
funciona igual; solo respeta los nombres de acción.

---

## 4. Cámara

El módulo **crea su propia cámara** (nodo `PivoteCamara/Brazo/Camara`, con el
script `camara_velocidad.gd`). No necesitas añadir una cámara externa. Se
controla con el ratón y **solo gira con el ratón capturado**
(`Input.MOUSE_MODE_CAPTURED`), que el módulo activa en `_ready()`. Pulsa **ESC**
para liberar el ratón.

La cámara es apaño interno del personaje; para usos con otra cámara, desactiva o
reemplaza el nodo `PivoteCamara` (el resto del módulo no depende de él salvo el
control de movimiento relativo a la cámara y la carga/trazado).

---

## 5. Transformación

Tecla **G** (`transformacion_velocidad`): reproduce el efecto
(`efecto_transformacion.gd`), cambia de forma en el pico del efecto y devuelve
el control al terminar. La forma de arranque es **Humana**.

- **Humana:** movimiento/correr (Shift), agacharse (Ctrl), salto, animaciones de
  `leo_animations.tres`.
- **Velocista:** dash, caída-dash, carga de poder + trazado de ruta (clic
  derecho), supervelocidad, combos (clic izquierdo), emote (2), efectos y
  distorsión de pantalla.

---

## 6. Requisitos de configuración (física / render)

- **Física 3D:** funciona con la física por defecto de Godot y con **Jolt
  Physics** (el proyecto de origen usa Jolt). No requiere ajustes.
- **Render:** Forward+. El shader de distorsión es `canvas_item` con
  `hint_screen_texture`; funciona en Forward+ y Mobile.
- **Gravedad:** el velocista usa su propia `gravedad` exportada; la forma humana
  usa `constants.H_GRAVEDAD`. No depende de `physics/3d/default_gravity`.

---

## 7. Dependencias externas

**Ninguna.** El módulo:
- No usa autoloads ni singletons.
- No referencia rutas fuera de `res://velocidad/`.
- No busca nodos del mundo anfitrión (no depende de un `Mapa` ni de rutas
  `../`).
- No declara `class_name` global, por lo que **no colisiona** con clases del
  proyecto anfitrión y puede convivir con otras copias.

Toda su comunicación hacia afuera (si se desea) puede hacerse por señales o
consultando sus métodos públicos (`forma_actual()`, `esta_transformado()`).

---

## 8. Recursos que deben acompañar obligatoriamente a la carpeta

Copia **la carpeta `velocidad/` entera**. En concreto no pueden faltar:
- Los dos `.fbx` de `modelos/` **y** sus `.import` (se regeneran al abrir el
  proyecto destino; en cualquier caso deben viajar los `.fbx`).
- Todos los `.tres` de `animaciones/` (librerías de animación).
- El shader de `shaders/`.
- Todos los `.gd` de `scripts/`.

---

## 9. Limitaciones y notas

- **Animaciones recuperadas de la caché:** los `.fbx` fuente de las animaciones
  del velocista **no existen** en el proyecto original (solo quedaban
  `.fbx.import` + caché). Para que el módulo sea portable, esas animaciones se
  **recuperaron desde `res://.godot/imported/*.res` y se guardaron como
  `animaciones/*.tres`** (recursos de texto, autocontenidos). Por eso el módulo
  **no necesita** los `.fbx` de animación ni la caché. No se sustituyó ni cambió
  ninguna animación.
- Las animaciones conservan sus rutas de hueso relativas
  (`Skeleton3D:mixamorig_…`), por lo que se reproducen sobre el modelo del
  velocista incluido.
- El post-proceso de pantalla (`CapaVelocidad/Distorsion`) es un `CanvasLayer`
  propio del personaje; funciona sin configuración extra.