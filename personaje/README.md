# `res://personaje/` — arquitectura del personaje y sus transformaciones

Esta carpeta es el **centro de organización** de todo lo relacionado con el
personaje jugable y sus formas (transformaciones). Su objetivo es que cada
sistema tenga un lugar claro y que los componentes **compartidos** no queden
duplicados dentro de cada forma.

> Esta carpeta se creó **reorganizando** recursos que antes vivían en `Leo/`,
> `ziba/`, `hud/`, `hud de transformaciones/`, `ui tranformacion/`,
> `aquatic_transformation/`, `Fuerza (1)/` y `personaje/` (raíz). No se cambió
> ninguna lógica, mecánica, `class_name`, señal, método público, grupo ni acción
> de entrada. Solo se movieron archivos y se actualizaron las rutas.

## Estructura

```
res://personaje/
├── README.md
├── base/                         Componentes COMPARTIDOS por todas las formas
│   ├── escenas/                  leo_jugador.tscn (escena principal multi-forma)
│   ├── scripts/                  controlador_leo.gd, receptor_acuatico.gd
│   ├── camara/                   camara_jugador.gd (CámaraZiba, usada por la base)
│   └── efectos/                  efecto_transformacion.gd (transición entre formas)
├── hud_transformacion/           HUD del personaje (vida/resistencia + iconos)
│   ├── escenas/                  HUDCircular.tscn
│   ├── scripts/                  hud_circular.gd, estadisticas_jugador.gd, indicador_anillo.gd
│   └── iconos/                   iconos de forma usados por el HUD circular
├── ui_transformacion/            Interfaz de selección de transformaciones (menú radial)
│   ├── escenas/                  MenuTransformaciones.tscn
│   ├── scripts/                  menu_transformaciones.gd
│   └── iconos/                   iconos del menú radial (uso distinto al HUD)
└── transformaciones/            Una carpeta por FORMA del personaje
    ├── humano/                   Leo humano (modelo, animaciones, escena propia)
    ├── velocidad/                Sistema velocista (+ prototipos antiguos separados)
    ├── acuatica/                 Módulo acuático completo (Pes)
    └── fuerza/                   Paquete del personaje Fuerza (Tanque)
```

## Componentes compartidos vs. propios de cada forma

**`base/` — compartido.** El eje es `ControladorLeo` (`base/scripts/controlador_leo.gd`),
un **único `CharacterBody3D`** que representa las cuatro formas cambiando solo la
representación visual y las capacidades. La escena principal es
`base/escenas/leo_jugador.tscn` e integra a las cuatro formas; **no** se ha
convertido cada transformación en un personaje independiente.

La regla aplicada fue:

- Si un script/efecto/cámara tiene **responsabilidad compartida** (lo usa la base
  o varias formas) → `base/`.
  - `controlador_leo.gd`: coordina las cuatro formas.
  - `camara_jugador.gd` (`CamaraZiba`): es **la cámara del jugador base** (todas
    las formas la usan; antes vivía en `ziba/scripts/`).
  - `efecto_transformacion.gd`: transición visual común a todos los cambios de forma.
  - `receptor_acuatico.gd`: puente entre la escena base y el módulo acuático.
- Si un recurso lo usa **solo una forma** → su carpeta en `transformaciones/`.

**`hud_transformacion/` vs `ui_transformacion/`.** Son dos interfaces distintas y
se mantienen separadas aunque usen imágenes parecidas:

- El **HUD** (`hud_transformacion/`) muestra vida, resistencia y el icono de la
  forma activa; lee `EstadisticasJugador` y `ControladorLeo.id_forma()`.
- El **menú radial** (`ui_transformacion/`) elige la transformación (tecla F) y
  emite `transformacion_elegida` hacia el controlador.

Los iconos del HUD y los del menú radial son **conjuntos distintos**
(`hud_transformacion/iconos/` y `ui_transformacion/iconos/`) y no se han mezclado.

## Mapa de archivos principales (ubicación anterior → nueva)

### Base

| Antes | Ahora |
| --- | --- |
| `Leo/leo_jugador.tscn` | `personaje/base/escenas/leo_jugador.tscn` |
| `Leo/scripts/controlador_leo.gd` | `personaje/base/scripts/controlador_leo.gd` |
| `Leo/scripts/receptor_acuatico.gd` | `personaje/base/scripts/receptor_acuatico.gd` |
| `ziba/scripts/camara_jugador.gd` | `personaje/base/camara/camara_jugador.gd` |
| `Leo/efecto_transformacion.gd` | `personaje/base/efectos/efecto_transformacion.gd` |

### HUD y UI de transformación

| Antes | Ahora |
| --- | --- |
| `hud/scenes/HUDCircular.tscn` | `personaje/hud_transformacion/escenas/HUDCircular.tscn` |
| `hud/scripts/hud_circular.gd` | `personaje/hud_transformacion/scripts/hud_circular.gd` |
| `hud/scripts/estadisticas_jugador.gd` | `personaje/hud_transformacion/scripts/estadisticas_jugador.gd` |
| `hud/scripts/indicador_anillo.gd` | `personaje/hud_transformacion/scripts/indicador_anillo.gd` |
| `hud de transformaciones/*` | `personaje/hud_transformacion/iconos/*` |
| `ui/scenes/MenuTransformaciones.tscn` | `personaje/ui_transformacion/escenas/MenuTransformaciones.tscn` |
| `ui/scripts/menu_transformaciones.gd` | `personaje/ui_transformacion/scripts/menu_transformaciones.gd` |
| `ui tranformacion/*` | `personaje/ui_transformacion/iconos/*` |

### Humano

| Antes | Ahora |
| --- | --- |
| `Leo/models/*` | `personaje/transformaciones/humano/models/*` |
| `Leo/animations/*` | `personaje/transformaciones/humano/animations/*` |
| `Leo/leo.tscn` | `personaje/transformaciones/humano/escenas/leo.tscn` |
| `Leo/scripts/leo.gd` | `personaje/transformaciones/humano/scripts/leo.gd` |
| `Leo/scripts/camara_tercera_persona.gd` | `personaje/transformaciones/humano/camara/camara_tercera_persona.gd` |
| `Leo/previews/*` | `personaje/transformaciones/humano/previews/*` |
| `Leo/README.md` | `personaje/transformaciones/humano/README.md` |

### Velocidad

| Antes | Ahora |
| --- | --- |
| `ziba/scripts/jugador.gd` | `personaje/transformaciones/velocidad/scripts/jugador.gd` |
| `ziba/scripts/combate.gd` | `personaje/transformaciones/velocidad/scripts/combate.gd` |
| `ziba/scripts/trazador.gd` | `personaje/transformaciones/velocidad/scripts/trazador.gd` |
| `ziba/scripts/efectos_velocidad.gd` | `personaje/transformaciones/velocidad/scripts/efectos_velocidad.gd` |
| `ziba/scripts/capa_velocidad.gd` | `personaje/transformaciones/velocidad/scripts/capa_velocidad.gd` |
| `ziba/scripts/rayos.gd` | `personaje/transformaciones/velocidad/scripts/rayos.gd` |
| `ziba/shaders/distorsion_velocidad.gdshader` | `personaje/transformaciones/velocidad/shaders/distorsion_velocidad.gdshader` |
| `ziba/animaciones/*` | `personaje/transformaciones/velocidad/animaciones/*` |
| `ziba/velocista/*` | `personaje/transformaciones/velocidad/velocista/*` |
| `ziba/escenas/jugador.tscn` | `personaje/transformaciones/velocidad/escenas/jugador.tscn` |
| `personaje/modelo_velocidad.fbx` (+ texturas) | `personaje/transformaciones/velocidad/modelo/*` |
| `personaje/gd/personaje.gd` | `personaje/transformaciones/velocidad/prototipos/personaje.gd` |
| `personaje/modelo/velocista.gd` | `personaje/transformaciones/velocidad/prototipos/velocista.gd` |
| `personaje/modelo/velocista.tscn` | `personaje/transformaciones/velocidad/prototipos/velocista.tscn` |
| `personaje/character_body_3d.tscn` | `personaje/transformaciones/velocidad/prototipos/character_body_3d.tscn` |

`velocidad/prototipos/` guarda **prototipos antiguos** separados del sistema
activo (no se eliminan). El sistema activo es el que usa la escena base y los
scripts de `velocidad/scripts/`.

### Acuática (Pes)

| Antes | Ahora |
| --- | --- |
| `aquatic_transformation/*` | `personaje/transformaciones/acuatica/*` |

Se conserva la estructura interna del módulo (`character/`, `abilities/`,
`water/`, `vfx/`, `ui/`, `models/`, `animations/`, `scenes/`, `docs/`) y sus
cuatro habilidades acuáticas.

### Fuerza (Tanque)

| Antes | Ahora |
| --- | --- |
| `Fuerza (1)/*` | `personaje/transformaciones/fuerza/*` |

Se conservan los nombres internos con sufijo `(1)` (p. ej. `scripts (1)/`,
`model (1)/`); **no** se hicieron renombrados masivos. Las referencias externas
(por ejemplo en la escena base) apuntan a las rutas nuevas.

## Lo que **no** se movió (a propósito)

- `ziba/escenas/ziba_prototipo.tscn`: es la **escena del mundo**, no una forma del
  personaje. Se quedó en `ziba/` (el mundo instancia el personaje desde
  `personaje/base/escenas/leo_jugador.tscn`).
- `ziba/tests/*`: pruebas ligadas al prototipo del mundo; se conservan donde estaban.
- `ui/scenes/MainMenu.tscn`, `PauseMenu.tscn`, `VideoBackground.tscn`,
  `GameLogo.tscn` y los scripts generales (`main_menu.gd`, `menu_option.gd`,
  `pause_menu.gd`): menú general, fuera de `personaje/`.
- Sistemas ajenos al personaje: `NPCs/`, `generador_ciudad.gd`, `camara_libre.gd`,
  `ciudad2.tscn`, `Exports/glTF (Godot)/`, `Textures/`, `assets/`, `npc assetss/`,
  `addons/ziva_agent/`. No se tocaron.

## Notas

- Las rutas de los recursos **se actualizaron** en escenas, scripts y
  documentación. Los identificadores (`uid://`), `class_name`, nombres de nodos,
  señales y acciones de entrada se conservaron.
- Los archivos `.import` se movieron junto a su recurso, pero su campo interno
  `source_file` puede seguir mostrando la ruta antigua; es un campo gestionado por
  Godot que se reconcilia al volver a escanear el proyecto (no se editó a mano).
- La **transformación Velocidad sigue con problemas funcionales** (ya existían
  antes de esta reorganización). No se reparó aquí.