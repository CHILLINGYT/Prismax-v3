# `vuelo/` — Personaje volador (extraído de HARPY)

Carpeta **autónoma y modular** con el héroe volador de HARPY: vuelo 3D estilo
"héroe", cámara en tercera persona con apuntado over-the-shoulder, combate
cuerpo a cuerpo, guardia de alas, plumas proyectil, garras de los pies (agarre
aéreo), palmazo de viento y efectos de cámara. No requiere autoloads, plugins ni
el resto del proyecto HARPY. Está preparada para **copiarse tal cual** a otro
proyecto de Godot.

> **Estado:** verificado estáticamente (rutas, recursos, clases, contratos,
> carga de escenas). **No** se ha validado dentro de un proyecto de destino real;
> ver "D. Limitaciones".

---

## A. Contenido

```
res://personaje/transformaciones/vuelo/
├── README.md                     · esta guía
├── INPUT_MAP.md                  · tabla completa de las 19 acciones de entrada
├── vuelo_input_defaults.gd       · helper OPCIONAL (clase VueloInputDefaults)
├── player/
│   └── vuelo_player.tscn         · ESCENA PRINCIPAL a instanciar
├── scripts/                      · 14 scripts del personaje
│   ├── player_controller.gd               · movimiento terrestre + delega en vuelo
│   ├── player_flight_controller.gd        · VUELO 360 (despeque, boost, picado, planeo…)
│   ├── player_animation_controller.gd     · FSM de animación (tierra/vuelo) + overlay
│   ├── third_person_camera.gd             · cámara 3ª persona + OTS + FOV
│   ├── flight_arms_overlay.gd             · aleteo de brazos en vuelo
│   ├── head_aim.gd                        · la cabeza sigue la cámara (LookAtModifier3D)
│   ├── apuntado_ots.gd                    · apuntado OTS + mira dibujada por código
│   ├── ground_combat.gd                   · combo de 4 golpes + guardia de alas
│   ├── feather_ability.gd                 · disparo de plumas
│   ├── feather_projectile.gd             · proyectil con daño propio
│   ├── talons_ability.gd                  · garras de los pies (agarre aéreo)
│   ├── palmazo_viento.gd                  · golpe de viento (cono + onda)
│   ├── efectos_camaras.gd                 · screen shake y FOV kicks
│   └── ual2_animation_loader.gd           · PIPELINE de animación (carga/retarget/procedural)
├── projectiles/
│   └── feather_projectile.tscn
├── models/
│   └── maniqui_godot_baked.tscn  · modelo/esqueleto + 46 clips base (autocontenido)
└── animations/
    ├── UAL1/{_ALL_SOURCE_ANIMS_1.glb, UAL1_Standard.glb}
    └── UAL2/{_ALL_SOURCE_ANIMS_2.glb, UAL2_Standard.glb}
```

- **Escena principal:** `res://personaje/transformaciones/vuelo/player/vuelo_player.tscn`.
- **Modelo:** `res://personaje/transformaciones/vuelo/models/maniqui_godot_baked.tscn` — escena horneada del
  maniquí de Godot: esqueleto `GeneralSkeleton` (53 huesos con nombres Godot:
  `Root`, `Hips`, `LeftUpperArm`, …) y un `AnimationPlayer` con 46 clips base
  (`Idle`, `Jump`, `Push`, `Swim_Fwd`…), **todo embebido, sin dependencias externas**.
- **Habilidades incluidas:** vuelo en 8 direcciones, boost, picado + recuperación,
  planeo, aleteo, caída libre, movimiento terrestre + salto + sprint, cámara 3ª
  persona + OTS, combo de combate y guardia, plumas proyectil, garras de los pies,
  palmazo de viento, efectos de cámara.

### Nota sobre el modelo (por qué horneado)

El `.glb` original del proyecto HARPY (`AnimationLibrary_Godot_Standard.glb`) **no
contenía el esqueleto que el código espera**: sus bytes traen un rig distinto
(Rigify/Blender, huesos `DEF-*.L`, nodo `Skeleton3D`). HARPY original solo
funcionaba por un **caché de importación obsoleto** en su carpeta `.godot/`. Para
que esta carpeta sea portable y **no dependa de esa caché**, el modelo se horneó
a `maniqui_godot_baked.tscn`. La copia del `.glb` equivocado se retiró de la
carpeta. Si querés cambiar el modelo, reemplazá `maniqui_godot_baked.tscn` por tu
rig y conservá **nombres de hueso tipo Godot** (el loader genera los clips
procedurales a partir de esos nombres).

### Recursos por habilidad (auditoría de dependencias)

| Habilidad | Script(s) | Recursos propios (dentro de `vuelo/`) | Dependencias externas |
|---|---|---|---|
| Vuelo y movimiento | `player_controller.gd`, `player_flight_controller.gd` | ninguno | — |
| Animación | `ual2_animation_loader.gd`, `player_animation_controller.gd`, `flight_arms_overlay.gd`, `head_aim.gd` | `models/maniqui_godot_baked.tscn` + GLB `animations/UAL1`, `animations/UAL2` | — |
| Cámara + apuntado OTS | `third_person_camera.gd`, `apuntado_ots.gd` | ninguno (mira dibujada por código) | — |
| Combate + guardia | `ground_combat.gd` | ninguno (esfera de impacto creada por código) | grupo `maniqui` |
| Plumas proyectil | `feather_ability.gd`, `feather_projectile.gd` | `projectiles/feather_projectile.tscn` (malla, material y shape **embebidos**) | grupo `maniqui`, capa de colisión 1 |
| Garras / agarre aéreo | `talons_ability.gd` | ninguno | grupo `agarrables` |
| Palmazo de viento | `palmazo_viento.gd` | ninguno (`TorusMesh` + material creados por código) | grupos `maniqui`, `agarrables` |
| Efectos de cámara | `efectos_camaras.gd` | ninguno | cámara del personaje |

**Ninguna habilidad carga recursos fuera de `res://personaje/transformaciones/vuelo/`.** Comprobado
instanciando las tres escenas y recolectando el `resource_path` de scripts,
materiales, mallas, shapes y librerías de animación: **0 recursos externos**.
Los proyectiles **no** instancian escenas secundarias ni usan partículas,
texturas, materiales o sonidos externos: su malla, material y colisión viven
inline en `feather_projectile.tscn`.

---

## B. Instalación

1. **Qué copiar:** la carpeta `res://personaje/transformaciones/vuelo/` completa.
2. **Dónde:** al mismo nivel dentro del destino, como `res://personaje/transformaciones/vuelo/`
   (podés renombrarla, pero entonces ajustá las rutas si editás scripts).
3. **Versión de Godot:** se creó con **Godot 4.7.2**. Usa características
   modernas (escena en `format=4` con atributos `unique_id`, y `LookAtModifier3D`
   en `head_aim.gd`), por lo que se requiere **Godot 4.7 o superior**.
4. **Después de copiar:** abrí el proyecto y dejá que Godot **importe** los `.glb`
   de `vuelo/animations/` (aparecen en el panel *FileSystem* sin errores rojos).
5. Los `.uid` de los scripts viajan con la carpeta; si faltaran, Godot los
   regenera. Las escenas referencian scripts **por ruta** (no por `uid://`), así
   que no dependen de la caché de HARPY.
6. **Comprobar importación:** revisá la pestaña *Output*. No debe haber
   "Failed loading resource" para rutas `res://personaje/transformaciones/vuelo/…`.

---

## C. Configuración

### C.1 Instanciar el personaje
Instanciá `res://personaje/transformaciones/vuelo/player/vuelo_player.tscn` como nodo dentro de tu escena:

```
TuNivel (Node3D)
└── VueloPlayer (instancia de res://personaje/transformaciones/vuelo/player/vuelo_player.tscn)
```

Colocá un suelo con colisión para que aterrice. No requiere autoloads.

### C.2 Controles (Input Map)
El personaje usa **19 acciones** (nombres originales). Están todas en
`INPUT_MAP.md`. Podés:

- **Registrar automáticamente solo las que falten** (no pisa las tuyas):
  ```gdscript
  # Una vez, p. ej. en el _ready() del nivel que instancia al héroe:
  VueloInputDefaults.registrar_acciones_faltantes()
  ```
- **Auditar sin modificar nada:**
  ```gdscript
  var faltan := VueloInputDefaults.acciones_faltantes()
  var opc    := VueloInputDefaults.opcionales_faltantes()
  ```

Acciones **obligatorias**: `move_forward/back/left/right`, `jump`, `sprint`,
`toggle_flight`, `fly_down`, `aim`, `feather_fire`, `melee_light`, `guard`,
`respawn`, `look_left/right/up/down`.
Acciones **opcionales** (habilitan habilidades): `grab`, `palmazo`.

> `vuelo_input_defaults.gd` **no** se ejecuta solo ni toca `project.godot`.
> Si tu proyecto ya define alguna de estas acciones, el héroe usará **tu**
> binding (verificá que dispare lo que esperás).

### C.3 Cámara
La cámara es **parte de la escena del personaje**:

```
VueloPlayer/CameraPivot        (third_person_camera.gd)
└── SpringArm3D
    └── Camera3D
```

- No necesita un "target" externo: sigue a su nodo padre (`VueloPlayer`).
- **No roba la cámara activa por defecto accidentalmente:** la `Camera3D` ya no
  está marcada `current` en la escena; se hace activa al iniciar solo si
  `third_person_camera.hacer_current_al_iniciar = true` (por defecto). Si tu
  proyecto ya tiene su cámara de jugador, poné **`hacer_current_al_iniciar = false`**
  (y, si querés, quitá `CameraPivot` para que no se cree una segunda cámara).
- **Mouse:** `third_person_camera.capturar_mouse_al_iniciar = true` por defecto
  (captura el ratón en `_ready`, lo libera con **ESC** y lo recaptura con clic
  izquierdo). Si tu proyecto gestiona el ratón, poné **`false`**.
- **Apuntado OTS** (`ApuntadoOTS`): al mantener `aim`, corre la cámara al hombro,
  gira el cuerpo hacia la mira y dibuja la **mira** en un `CanvasLayer` de
  `layer = 100` (por encima del HUD). Si tu HUD usa capas altas, bajá ese layer.
- **Efectos** (`EfectosCamaras`): aplican shake/FOV **sobre la cámara del
  personaje** (`camera_path` = `../CameraPivot/SpringArm3D/Camera3D`), no sobre
  "la cámara activa" ajena. Si tu cámara del héroe vive en otra ruta, cambiá
  `camera_path` en el Inspector.

> Si preferís usar tu propia cámara: conservá el nodo `CameraPivot` (representa
> la orientación que usan el vuelo y el movimiento) y desactivá
> `hacer_current_al_iniciar` y `capturar_mouse_al_iniciar`.

> Nota: además de los efectos, varios sistemas de **dirección** (apuntado del
> palmazo, orientación del combate y lanzamiento de garras) leen la **cámara
> activa** del viewport para saber hacia dónde mirás. Si usás tu propia cámara,
> esos sistemas apuntarán según ella (comportamiento esperado).

### C.4 Grupos, enemigos y objetos
Para que las habilidades que interactúan con el mundo funcionen:

- **Grupo `"maniqui"`** — objetivos que reciben daño. Deben implementar:
  ```gdscript
  func recibir_golpe(danio: int, direccion: Vector3, fuerza: float) -> void: ...
  ```
  Lo usan el combate melee, las plumas y el palmazo.
- **Grupo `"agarrables"`** — `RigidBody3D` que las garras pueden agarrar y el
  palmazo empujar. Las garras usan `freeze`, `collision_layer`, `reparent` y
  `linear_velocity`.
- **Grupo `"ual2_overlay_player"`** — lo crea el propio loader en runtime; **no**
  lo agregues a mano.

### C.5 Capas y máscaras de colisión
- El **proyectil** (`feather_projectile.gd`) usa `collision_layer = 0` y
  `collision_mask = mascara_colision` (**por defecto 1**). Si tus objetivos están
  en otra capa, cambiá `mascara_colision` en el Inspector del proyectil.
- La **esfera del melee** (`ground_combat.gd`) consulta la **máscara 1** fija. Si
  movés tus personajes/enemigos a otra capa, ajustá esa máscara en el código.
- El `CharacterBody3D` del héroe usa las capas por defecto de Godot.

---

## D. Limitaciones

### Verificado estáticamente
- Todas las rutas `res://` de `vuelo/` apuntan a `res://personaje/transformaciones/vuelo/…` (0 dependencias
  externas de archivos).
- No hay autoloads ni plugins.
- El modelo horneado carga, contiene `Rig/GeneralSkeleton` (53 huesos) y 46 clips
  base; la escena `vuelo_player.tscn` carga y contiene todos los nodos que los
  scripts esperan.
- Sin referencias a las clases globales originales; sin duplicados de `class_name`.

### Probado realmente (dentro de HARPY)
- La escena del personaje se ejecutó en el editor y regeneró **todos** los clips
  procedurales (GuardiaAlas, PatadaGarra, Planeo, AleteoAlas, PosePicado,
  VueloHeroe, PalmazoPush, CaidaLibre) igual que el original.

### Requiere prueba manual en el proyecto de destino
- Integración real con tu escena, tu Input Map y tu HUD/cámara.
- Coexistencia de cámara/ratón con la gestión del destino.
- Daño real a tus enemigos y agarre de tus objetos.
- Comportamiento de gamepad con un mando físico (las asignaciones se
  replican por índice, pero **no** se probaron en hardware).
- Rendimiento del arranque (el loader reconstruye los clips procedurales al
  iniciar).

### Dependencias que debe proporcionar el destino
- Las **19 acciones de Input Map** (helper provisto).
- Los grupos `"maniqui"` (con `recibir_golpe`) y `"agarrables"`, para las
  habilidades que interactúan con el mundo.
- Godot **4.7+**.
- **Motor físico (recomendado Jolt):** el proyecto original usa
  `physics/3d/physics_engine = "Jolt Physics"`. El personaje usa
  `CharacterBody3D` y los objetos agarrables/empujables son `RigidBody3D`; con
  otro motor el "feel" de empujes, agarres e impactos puede variar levemente.
  Es un ajuste de `project.godot` del destino (no un archivo a copiar).

---

## E. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| El personaje no responde a teclas | Faltan acciones de Input Map | Llamá `VueloInputDefaults.registrar_acciones_faltantes()` o revisá `INPUT_MAP.md` |
| No anima / errores `UAL2 loader: sin huesos…` | El modelo no tiene `Rig/GeneralSkeleton` con huesos Godot | Usá `maniqui_godot_baked.tscn` (o un rig con esos nombres de hueso) |
| `Failed loading resource: res://personaje/transformaciones/vuelo/animations/…` | GLB sin importar | Dejá que Godot importe la carpeta (panel *FileSystem*) y reintentá |
| Dos cámaras pelean / el ratón se bloquea | El destino ya tiene su cámara/ratón | `hacer_current_al_iniciar = false` y `capturar_mouse_al_iniciar = false` |
| El shake afecta a la cámara equivocada | `camera_path` mal apuntado | Ajustá `camera_path` en `EfectosCamaras` |
| Los golpes/plumas no dañan | Sin objetos en el grupo `"maniqui"` o sin `recibir_golpe` | Agregá tus enemigos al grupo e implementá el método |
| Las garras no agarran nada | Sin `RigidBody3D` en el grupo `"agarrables"` | Sumá tus objetos al grupo |
| El proyectil atraviesa todo | Capas de colisión distintas | Ajustá `mascara_colision` del proyectil (y la máscara del melee) |
| La mira tapa mi HUD | `CanvasLayer` de la mira en `layer 100` | Bajá ese layer en `apuntado_ots.gd` |
| La cabeza no mira a la cámara | `skeleton_path` no encontrado | Verificá `HeadAim.skeleton_path` (`../VisualRoot/AnimationLibrary_Godot_Standard/Rig/GeneralSkeleton`) |

---

## Integración paso a paso

1. Copiá `res://personaje/transformaciones/vuelo/` a tu proyecto (al mismo nivel).
2. Abrí el proyecto y dejá que **importe** los `.glb`.
3. Configurá el Input Map (`VueloInputDefaults.registrar_acciones_faltantes()` o a mano).
4. Instanciá `res://personaje/transformaciones/vuelo/player/vuelo_player.tscn` en tu nivel.
5. Colocá un suelo con colisión; ajustá cámara/ratón si ya tenés los tuyos.
6. Agregá objetos a `"maniqui"` (con `recibir_golpe`) y `"agarrables"` si querés combate/agarre.
7. Probá: WASD, F (volar), Space/C, Shift (boost), RMB+LMB (plumas), Q (guardia), E (garras volando), V (palmazo).
8. Ajustá perillas en el Inspector (todas con `@export`).
9. **No** sobrescribas `project.godot`, tu escena principal ni tus autoloads.