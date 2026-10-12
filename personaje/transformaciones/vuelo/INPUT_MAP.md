# Input Map — acciones del personaje volador

Estas son las **19 acciones** que utiliza el héroe, con sus asignaciones
**exactas** en el proyecto HARPY original. No inventes teclas: verificadas
leyendo `project.godot` de HARPY.

> `physical_keycode` = la tecla es **independiente de la distribución del
> teclado** (la posición física). Godot la muestra por su nombre (W, A, S…) para
> el layout QWERTY.

| Acción | Teclado | Mouse | Gamepad | deadzone | Usada por |
|---|---|---|---|---|---|
| `move_forward` | W (físico) | — | Stick izq. arriba (eje 1, −) | 0.2 | player_controller, player_flight_controller |
| `move_back` | S (físico) | — | Stick izq. abajo (eje 1, +) | 0.2 | idem |
| `move_left` | A (físico) | — | Stick izq. izq (eje 0, −) | 0.2 | idem |
| `move_right` | D (físico) | — | Stick izq. der (eje 0, +) | 0.2 | idem |
| `jump` | Espacio | — | Botón 0 (A / Cruz) | 0.2 | player_controller, player_flight_controller |
| `fly_down` | C | — | Botón 1 (B / Círculo) | 0.2 | player_flight_controller |
| `toggle_flight` | F | — | Botón 3 (Y / Triángulo) | 0.2 | player_flight_controller |
| `sprint` | Shift | — | Botones 9 y 7 (L1 / L3) | 0.2 | player_controller, player_flight_controller, player_animation_controller |
| `respawn` | R | — | Botón 4 (Back / Select) | 0.2 | player_controller |
| `look_left` | — | — | Stick der. izq (eje 2, −) | 0.2 | third_person_camera |
| `look_right` | — | — | Stick der. der (eje 2, +) | 0.2 | third_person_camera |
| `look_up` | — | — | Stick der. arriba (eje 3, −) | 0.2 | third_person_camera |
| `look_down` | — | — | Stick der. abajo (eje 3, +) | 0.2 | third_person_camera |
| `aim` | — | Botón DERECHO | Gatillo L2 (eje 4, +) | 0.2 | third_person_camera, feather_ability, ground_combat, talons_ability |
| `feather_fire` | — | Botón IZQUIERDO | Gatillo R2 (eje 5, +) | 0.2 | feather_ability, ground_combat, talons_ability |
| `melee_light` | — | Botón IZQUIERDO | Botón 2 (X / Cuadrado) | 0.2 | ground_combat |
| `guard` | Q | — | Botón 10 (RB / R1) | 0.2 | ground_combat |
| `grab` | E o G | — | Botón 2 (X / Cuadrado) | 0.2 | talons_ability |
| `palmazo` | V | — | — | 0.2 | palmazo_viento |

## Notas

- **Eje del stick derecho**: `look_left/right` = eje 2; `look_up/down` = eje 3.
- **Gatillos**: `aim` = eje 4; `feather_fire` = eje 5.
- El **botón izquierdo del mouse** dispara a la vez `melee_light` y
  `feather_fire`; el sistema decide por contexto (apuntando → pluma; si no →
  golpe; con presa en garras → lanzamiento).
- El **botón 2 de gamepad** (X/Cuadrado) se comparte entre `melee_light` y
  `grab`; igual que arriba, el contexto (volando con presa cercana) decide.

## Posibles conflictos con acciones comunes de Godot/destino

Godot no trae acciones incorporadas de juego (solo `ui_*`), así que el riesgo es
con las acciones **propias del proyecto destino**:

| Acción de `vuelo/` | Nombre típico en otros proyectos | Riesgo |
|---|---|---|
| `jump`, `sprint`, `move_*` | Muy comunes | El nombre puede existir; `VueloInputDefaults` **no** las toca (usa las tuyas). |
| `aim`, `feather_fire`, `melee_light`, `guard`, `grab` | Comunes en acción/aventura | Idem; verificá que disparen lo que el héroe espera. |
| `fly_down`, `toggle_flight`, `palmazo`, `respawn` | Poco comunes | Probablemente se agreguen solas. |

## Cómo registrar sin sobrescribir

```gdscript
# En el _ready() del nivel que instancia al héroe (o en un script de arranque):
VueloInputDefaults.registrar_acciones_faltantes()
```

`VueloInputDefaults.registrar_acciones_faltantes()` (en
`res://personaje/transformaciones/vuelo/vuelo_input_defaults.gd`) recorre las 19 acciones y **solo agrega
las que falten**, replicando los bindings de esta tabla. Devuelve un
`PackedStringArray` con los nombres de las que agregó. No duplica eventos si se
vuelve a llamar (saltea las acciones que ya existen).

### Auditar sin modificar nada

```gdscript
var faltan := VueloInputDefaults.acciones_faltantes()    # todas las que faltan
var opc   := VueloInputDefaults.opcionales_faltantes()   # solo grab y palmazo
```

### Acciones obligatorias vs. opcionales

- **Obligatorias** (sin ellas el personaje no responde): `move_forward`,
  `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `toggle_flight`,
  `fly_down`, `aim`, `feather_fire`, `melee_light`, `guard`, `respawn`,
  `look_left`, `look_right`, `look_up`, `look_down`.
- **Opcionales** (habilitan habilidades concretas): `grab` (garras de los pies)
  y `palmazo` (golpe de viento).

### Botones de gamepad: índices exactos (enum `JoyButton`)

`A=0, B=1, X=2, Y=3, Back/Select=4, L3=7, R3=8, L1=9, R1=10`. Las asignaciones
de arriba fueron corregidas para coincidir con el `project.godot` original:
`sprint` = L1(9) + L3(7); `grab` = X(2); `respawn` = Back(4).