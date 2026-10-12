# Personaje 3D base — guía del sistema y del reemplazo de modelo

Este documento explica el sistema de personaje 3D del proyecto, cómo funciona y
**cómo reemplazar el modelo por otro** sin rehacer movimiento, cámara, colisiones
ni la máquina de estados.

> **NOTA DE ORGANIZACIÓN (reorganización para entrega).**
> Este documento describe el sistema tal y como se construyó y sigue siendo válido
> como explicación del diseño. Después se reorganizó el proyecto para entregarlo:
> el personaje acuático vive ahora en `res://personaje/transformaciones/acuatica/`, los assets
> de origen en `res://source_assets/` y las herramientas en `res://tools/`.
> Algunas rutas de este documento pueden referirse a la estructura anterior.
> El mapa autoritativo de archivos está en
> `res://personaje/transformaciones/acuatica/docs/FILE_MAP.md`, y la guía para integrar el
> módulo en otro proyecto, en
> `res://personaje/transformaciones/acuatica/docs/INTEGRATION_GUIDE.md`.

---

## 1. Archivos que forman el sistema

```
res://personaje/transformaciones/acuatica/          ← EL MÓDULO ACUÁTICO (lo que se entrega)
├── character/
│   ├── player.tscn                    Escena del jugador (CharacterBody3D + cámara + animación)
│   ├── player.gd                      Movimiento, gravedad, salto, agachado, daño, natación
│   │                                  y máquina de estados
│   ├── player_animation.gd            Puente estado → AnimationTree + foot lock + adaptación al modelo
│   ├── character_model.gd             SLOT del modelo visual (skeleton, huesos, cambio de modelo)
│   └── camera_rig.gd                  Cámara en tercera persona (ratón + SpringArm3D)
├── abilities/                         LAS CUATRO HABILIDADES ACUATICAS
│   ├── water_ability.gd               Base: el objeto de la habilidad (vuela, choca, hace daño)
│   ├── water_projectile.gd            (tecla 1) proyectil que revienta al chocar
│   ├── water_burst.gd                 (tecla 2) esfera que explota y deja una zona que dura
│   ├── water_prison.gd                (tecla 3) prisión que ATRAPA al objetivo
│   ├── water_surge.gd                 (tecla 4) oleada: la más fuerte
│   └── water_ability_manager.gd       Enfriamientos, lanzamiento y aviso a la animación
├── water/
│   ├── water_detection.gd             Detecta el agua y calcula la profundidad y la inmersión
│   ├── water_zone.gd                  Volumen de agua (profundidad + olas, capa 8)
│   ├── lake.tscn                      El lago: agua, fondo y playa de entrada
│   └── water_surface.gdshader         Agua nativa: olas, refracción, espuma, reflejo
├── vfx/
│   ├── water_effects.gd               Fábrica de efectos (salpicaduras, anillos, espuma…)
│   ├── water_charge.gd                Agua que se junta en las manos al cargar un hechizo
│   ├── underwater_view.gd             Vista subacuática (niebla + velo + motas)
│   ├── water_particle.gdshader        Gota de agua procedural
│   ├── water_ring.gdshader            Anillo que se abre sobre el agua
│   ├── water_orb.gdshader             Orbe/burbuja de agua (con refracción)
│   └── underwater_overlay.gdshader    Velo de pantalla bajo el agua
├── ui/
│   └── aim_reticle.gd                 Retícula de apuntado (modo F)
├── models/
│   └── futuristic_armor_character.tscn   PERSONAJE ACTUAL (armadura futurista, malla skinned)
├── animations/
│   ├── player_animations.tres         AnimationLibrary (todos los clips del personaje)
│   └── player_animation_tree.tres     AnimationNodeStateMachine con crossfades
├── scenes/
│   ├── player_test.tscn               ESCENA DE PRUEBA/DESARROLLO (suelo, rampas,
│   │                                  plataformas, el lago y tres maniquíes)
│   └── training_dummy.gd / .tscn      Maniquí de entrenamiento (vida, daño, ATRAPADO)
└── docs/                              Esta guía + INTEGRATION_GUIDE.md + FILE_MAP.md
res://source_assets/aura_pack/         PACK A: 34 FBX de Mixamo (walk, walk back, todo el daño)
res://source_assets/standard_library/  PACK B: 46 clips (idle, jog, sprint, agachado, salto,
									   golpes y la voltereta de esquiva)
res://source_assets/character_model_fbx/   Modelo de origen (FBX + texturas PNG)
res://source_assets/                        ASSETS DE ORIGEN (no hacen falta para ejecutar)
├── movements_update/                  PACK M: respiración, caminata, carrera, golpes
├── attacks_update/                    PACK A2: apuntado con la bola + magia 1H/2H
├── swim_clips/                        PACK W: natación (Treading Water, Swimming…)
├── ability_clips/                     PACK H: los cuatro ataques mágicos
├── legacy_armor_obj/                  OBJ del personaje antiguo (LEGACY)
└── unreferenced_textures/             Texturas sueltas sin referencia (se conservan)
res://tests/
└── test_player_system.gd              Pruebas del sistema (19 pruebas: estructura, huesos,
									   postura, pies, locomoción, agachado, salto, daño,
									   combo, esquiva, agua y habilidades acuáticas)
res://tools/
├── animation/                         SISTEMA DE ANIMACIÓN
│   ├── pack_animation_builder.gd      Hornea TODOS los clips de los packs y escribe la
│   │                                  librería y el árbol de estados
│   ├── build_pack_animations.gd       Runner: godot --headless --script res://tools/animation/build_pack_animations.gd
│   ├── clip_baker.gd                  Retargeting: copia la rotación acumulada de cada hueso
│   ├── rig_baker.gd                   Adaptador de rig (mapa de 22 huesos estándar, alias, .L/.R)
│   ├── stance_fixer.gd                Postura de pie y de andar (ver §2.9.1)
│   ├── build_stance_fix.gd            Runner: godot --headless --script res://tools/animation/build_stance_fix.gd
│   ├── idle_arms.gd                   Capa aditiva que separa los brazos del reposo
│   ├── state_sheet_builder.gd         Hoja de contactos de los estados (revisión visual)
│   ├── clip_probe_builder.gd          Hoja de contactos de clips crudos de los packs
│   ├── clip_probe_column.gd           Script de columna de esas hojas
│   └── _run_rebuild.gd / .tscn        Runner TODO-EN-UNO (horneado + postura + brazos)
├── model/
│   ├── model_scene_builder.gd         Crea la escena del modelo (orientación, escala y
│   │                                  REPARACIÓN de los vértices con skin a cero)
│   └── build_model_character.gd       Runner: godot --headless --script res://tools/model/build_model_character.gd
├── review/                            Hojas de revisión (regenerables, no hacen falta para jugar)
│   ├── hoja_locomocion.tscn           Revision de los estados finales
│   ├── hoja_aire_acciones.tscn
│   ├── hoja_dano.tscn
│   ├── probe_clips.tscn               Clips crudos de los packs (retargeting)
│   ├── probe_phases.tscn              Barrido de fases de un clip
│   ├── probe_model.tscn               Comprobación de orientación del modelo
│   ├── probe_models.tscn              Comparación del FBX original
│   └── check_model_mesh.tscn          Comprobación de la malla (vértices sin peso)
└── legacy/                            TUBERÍAS ANTIGUAS (no se usan para el juego actual)
	├── placeholder_generator.gd       Generador de clips procedurales (respaldo)
	├── generate_placeholder_character.gd
	├── generate_model_animations.gd   OJO: sobrescribe la librería y el árbol actuales
	├── idle_polish.gd                 OJO: rehace el idle (sustituido por Breathing Idle)
	├── build_idle_polish.gd
	├── armor_rig_builder.gd           Conversión del OBJ original
	├── build_armor_character.gd
	├── armor_character_legacy.tscn    Personaje antiguo construido desde el OBJ
	├── armor_preview.tscn             Vista previa de ese modelo (4 ángulos)
	└── placeholder_character.tscn     Modelo humanoide de cajas (alternativa de pruebas)
```

Estructura de nodos de `player.tscn`:

```
Player (CharacterBody3D)          ← player.gd  (movimiento + estado)
├── CollisionShape3D              ← cápsula de colisión (radio 0.32, alto 1.72)
├── Visual (CharacterModel)       ← character_model.gd : SLOT del modelo visual
│   └── CharacterModel            ← instancia del modelo actual (armadura futurista)
│       ├── Armature
│       └── Skeleton3D            ← 65 huesos de Mixamo (mixamorig_*)
│           └── MeshInstance3D    ← malla skinned (Skin + material PBR)
├── AnimationPlayer               ← animaciones (los 23 clips del apartado 2)
├── AnimationTree                 ← BlendTree: [SpeedScale] → máquina de estados
├── AnimationController           ← player_animation.gd
└── CameraPivot (PlayerCameraRig) ← camera_rig.gd — top_level = true (NO hereda el
	└── SpringArm3D                 giro del personaje: solo el ratón la rota)
		└── Camera3D
```

> **Convención importante:** el nodo raíz del modelo se llama siempre
> **`CharacterModel`** y su esqueleto **`Skeleton3D`**. Gracias a eso los tracks de
> animación (`Visual/CharacterModel/Skeleton3D:Hips`, …) valen para *cualquier*
> modelo sin reescribir nada ni llenar la consola de avisos del `AnimationMixer`.
> Si tu modelo no sigue la convención, `PlayerAnimationController` reescribe las
> rutas solo y avisa con un informe (no hace falta tocar código).

**Separación de controles (importante):**

| Entrada | Quién la usa | Qué hace |
| --- | --- | --- |
| W A S D | `player.gd` → `CharacterBody3D` | mover al personaje (relativo a la cámara) |
| Ratón | `camera_rig.gd` | rotar la cámara (yaw en el pivote, pitch en el SpringArm3D) |
| Espacio | `player.gd` | saltar (y levantarse del suelo). **En el agua**: subir, despegarse del fondo, y trepar por el borde si hay uno delante |
| Shift | `player.gd` | correr; mantenido, pasa a esprintar (o alternar, con `run_toggle_mode`) |
| Ctrl o C | `player.gd` | agacharse. **En el agua**: hundirse (y al soltar, mantiene la profundidad) |
| Clic izquierdo | `player.gd` → `request_attack()` | golpe (solo con input, nunca automático). Volver a hacer clic mientras golpeas **encadena el combo** |
| Q | `player.gd` → `request_dodge()` | esquivar: voltereta en la dirección en la que te mueves |
| 1 2 3 4 | `player.gd` → `request_ability()` | las cuatro habilidades acuáticas (proyectil / esfera / prisión / oleada). Funcionan en tierra y en el agua |
| F | `player.gd` → `surface_walk` | alternar **caminar por encima del agua** (ver §11.3.2) |
| H / G / J / U / K / L | `player.gd` | (pruebas) golpe leve / lateral / fuerte / cabeza / derribo / muerte |

Las seis últimas teclas existen para poder probar el sistema de daño sin combate:
llaman a `request_damage(...)` exactamente igual que lo hará el sistema de combate
cuando exista. Se pueden quitar borrando esas acciones del mapa de entrada.

`CameraPivot` es `top_level = true`, así que **no** hereda la rotación del
`CharacterBody3D`: girar el personaje con A/D o W/S no gira la cámara. El pivote
solo copia la **posición** del jugador en `_physics_process` (el mismo tick en
que el jugador se movió), de modo que no hay retardo ni temblor. El ratón es lo
único que rota la cámara; la cámara nunca mueve al personaje: solo aporta la
orientación para calcular su dirección de movimiento.

---

## 2. Cómo funciona la animación

El personaje tiene **34 animaciones**, todas horneadas al mismo esqueleto a partir
de los **packs** que ya traía el proyecto (ver §2.1). Son estas, y cada una se
llama igual que su estado en el `AnimationTree` y que su estado en el jugador (una
sola lista de nombres, sin traducciones):

```
idle  walk  run  sprint  walk_back  crouch_idle  crouch_walk
jump  fall  landing
hit_light  hit_head  hit_side  hit_heavy  stagger  knockdown  ground  get_up  death
attack  attack_2  dodge  recovery
swim_idle  swim_forward  swim_back  swim_up  swim_down  enter_water  exit_water
ability_1  ability_2  ability_3  ability_4
```

* `AnimationPlayer` (hijo de `Player`) contiene una `AnimationLibrary`
  (`player_animations.tres`) con esos 34 clips.
* `AnimationTree` tiene como raíz un `AnimationNodeBlendTree` con un
  `AnimationNodeTimeScale` llamado `SpeedScale` delante de la
  `AnimationNodeStateMachine`. Las transiciones usan
  `advance_mode = Enabled`, es decir **solo se recorren cuando el código llama a
  `travel()`**: el jugador decide el estado y el árbol solo hace el crossfade.
* `PlayerAnimationController.play_state("walk")` es la única API que necesita el
  jugador. `travel()` provoca el crossfade; nunca se corta una animación en seco.
* `landing`, `attack`, `attack_2`, `dodge`, los golpes y `get_up` no son bucle: su
  duración se lee del propio clip (`get_state_length(...)`), así que si cambias el
  clip el tiempo se ajusta solo.
* **El combo de golpes son dos estados**, `attack` y `attack_2`, que se apuntan el
  uno al otro. Tiene que ser así: `travel()` solo reinicia un clip si hay una
  transición de verdad, y viajar *al mismo* estado no hace nada. Con dos estados
  que se alternan, el segundo golpe encadena con el primero en vez de reiniciarlo
  en seco (ver §5, `combo_window`).
* El estado `AnimationNodeAnimation` referencia la animación **por nombre**, no
  por pistas: por eso puedes sustituir las animaciones por las tuyas (con los
  mismos nombres) y el árbol sigue siendo válido.

### 2.1. De dónde sale cada clip (reparto de los packs)

**No se ha elegido un pack: se usan todos**, buscando para cada estado el clip que
mejor le va. El retargeting (`tools/clip_baker.gd`) copia la rotación *acumulada*
de cada hueso, así que un esqueleto de 53 huesos de Blender mueve exactamente igual
a uno de 65 de Mixamo: el resultado se ve como **un solo personaje**, no como dos.

| Estado | Clip | Pack | Por qué |
| --- | --- | --- | --- |
| `idle`, `recovery` | `Idle` | B | Idle neutro; el pack A no tiene idle quieto |
| `walk` | `Walking` | A | Ciclo más humano |
| `walk_back` | `Walking Backwards` | A | No existe en el pack B |
| `run` | `Jog_Fwd` | B | Ciclo limpio |
| `sprint` | `Sprint` | B | No existe en el pack A |
| `crouch_idle`, `crouch_walk` | `Crouch_Idle`, `Crouch_Fwd` | B | El pack A no tiene agachado |
| `jump` | `Jump_Start` | B | Impulso |
| `fall` | `Jump` (en bucle) | B | Es una pose en el aire con variación sutil: no hace falta recortar nada |
| `landing` | `Jump_Land` | B | Absorción del impacto |
| `hit_light` | `Hit_Chest` | B | Gesto corto (0.33 s) que no corta el ritmo |
| `hit_head`, `hit_side`, `hit_heavy`, `stagger` | `Head Hit`, `Rib Hit`, `Big Stomach Hit`, `Big Hit To Head` | A | El pack A es el que tiene el daño bien animado |
| `knockdown`, `ground`, `get_up`, `death` | `Fall Flat`, `Fallen Idle`, `Getting Up`, `Knocked Out` | A | El pack B no tiene ni derribos ni suelo |
| `dodge` | `Roll` | B | Voltereta de combate de cuerpo entero. El `Dodging` del pack A es un *weave* de boxeo (guardia alta y hombros subiendo y bajando 2.23 s) que no tiene nada que ver con el impulso de una esquiva |
| `attack` | `Punch_Cross` | B | Primer golpe del combo |
| `attack_2` | `Punch_Jab` | B | Segundo golpe del combo (0.87 s). Se alterna con el primero |
| `swim_idle`, `swim_up` | `Treading Water` | Agua | Flotar sin desplazarse (el cuerpo se hunde y sube con la ola) |
| `swim_forward`, `swim_down` | `Swimming` | Agua | Brazada hacia delante; hacia abajo se reutiliza la misma, mirando abajo |
| `swim_back` | `Swimming` **invertida** | Agua | No hay brazada hacia atrás: se hornea el clip al revés y se ve natural |
| `enter_water`, `exit_water` | `Swimming To Edge` | Agua | Es el único clip que empieza y acaba **fuera del agua** (con el vértice de la entrada). Se hornea dos veces: al revés para entrar, del derecho para salir, y con `flatten_vertical` para que no dé un salto de altura |
| `ability_1` | `Standing 2H Magic Attack 01` (0.25–2.15 s) | Ataques | Proyectil: se recorta el arranque para que el disparo salga antes |
| `ability_2` | `Standing 2H Magic Attack 04` (0.65–3.00 s) | Ataques | Esfera/AoE: el gesto de lanzar con las dos manos |
| `ability_3` | `Standing 2H Cast Spell 01` (completo) | Ataques | Prisión: conjuro largo, el cuerpo entero participa |
| `ability_4` | `Standing 2H Magic Attack 05` (completo) | Ataques | Oleada: el clip más contundente (3.53 s), para el ataque más fuerte |

Las velocidades de los clips (para atar la zancada/brazada a la velocidad real) **no
se escriben a mano**: las mide `tools/clip_baker.gd` analizando a qué velocidad se
mueve la cadera en el propio clip, y se guardan en `player_animations.tres`. Si
cambias un clip, se remide.


### 2.2. Root motion

**Todos los clips se hornean "en el sitio"**: se quita el desplazamiento
*horizontal* de la cadera. El movimiento del personaje lo lleva SIEMPRE el
`CharacterBody3D`, que es lo correcto con un `move_and_slide()`. El desplazamiento
*vertical* sí se conserva, porque forma parte de la pose (agacharse al aterrizar,
caer al suelo, levantarse).

El generador imprime qué clips traían desplazamiento propio y cuánto (el caso más
claro: `Fall Flat` traía 3.1 m y `Knocked Out` 1.35 m). El único caso donde ese
dato se usa es `walk_back`: los 0.58 m de desplazamiento del original son la
medida buena de su velocidad (0.67 m/s), mejor que la estimada por el pie.

### 2.3. Transiciones (tiempos de crossfade)

| De → A | s | De → A | s |
| --- | --- | --- | --- |
| Locomoción ↔ locomoción | 0.22 | Cualquiera → `jump` | 0.06 |
| Agachado ↔ de pie | 0.30 | `jump` → `fall` / `landing` | 0.14 / 0.10 |
| Con `walk_back` por medio | 0.25 | `fall` → `landing` | 0.08 |
| Volver a la locomoción | 0.18 | `landing` → locomoción | 0.18 |
| Cualquiera → golpe | 0.06 | Cualquiera → `attack` / `attack_2` / `dodge` | 0.10 / 0.10 / 0.08 |
| Combo `attack` ↔ `attack_2` | 0.12 | | |
| Golpe → `recovery` | 0.12 | `knockdown` → `ground` | 0.12 |
| `ground` → `get_up` | 0.15 | `get_up` → locomoción | 0.20 |

Las transiciones de salto son muy cortas para que el salto se sienta inmediato; las
de agacharse son más largas porque el cuerpo recorre mucha distancia y una mezcla
corta se notaría como un tirón.

> **El grafo es casi completo a propósito** (436 transiciones). `travel()` no hace
> nada si no existe la transición, y con 23 estados dejar el grafo a medias es
> pedir que el personaje se quede clavado con el clip anterior (por ejemplo si le
> golpean justo al aterrizar, o si se cae de un borde andando). Las reglas que
> llevan el peso de la sensación se escriben DESPUÉS y sobreescriben los tiempos
> genéricos.

### 2.4. Cómo se elige el estado de locomoción

**Por la velocidad real, no por la tecla.** Según sube o baja la velocidad, el
personaje pasa por `idle → walk → run → sprint` (y al revés al frenar), con
histéresis en los límites para que no parpadee. `Shift` mantenido lleva de `walk`
a `run` y, tras `sprint_delay` (0.6 s) corriendo de verdad, a `sprint`: la
progresión sale de la curva de aceleración, no de un cambio brusco al pulsar.

Si el desplazamiento va hacia atrás respecto a la mirada, usa `walk_back`.

### 2.5. Cadena de daño (sin recuperación instantánea)

```
golpe leve / cabeza / lateral  ->  recovery (aturdido)  ->  moverse
golpe fuerte / tambaleo        ->  stagger -> knockdown -> ground -> get_up -> moverse
cualquier cosa                 ->  death (estado final)
```

* `player.request_damage(tipo, posicion_del_atacante)` es la API para el futuro
  sistema de combate. Tipos: `light`, `head`, `side`, `heavy`, `stagger`,
  `knockdown`, `death`.
* El segundo parámetro es la posición del atacante: el golpe **empuja** al
  personaje en dirección contraria (**knockback**, 1.6–4.4 m/s según el tipo, con
  su propia desaceleración). Mientras el empuje dura, la animación de recuperación
  sigue puesta en vez de saltar a andar.
* Mientras esté aturdido, derribado, levantándose o muerto, el personaje **no
  acepta órdenes** (`is_incapacitated()`), y tampoco gira: el cuerpo lo manda la
  animación.
* Levantarse del suelo es automático tras `ground_time` (1.2 s), o pulsando
  Espacio si activas `get_up_on_input`.

### 2.5.1. Ataque, combo y esquiva

**Ataque.** `player.request_attack()` es la API (la llama el clic izquierdo). El
golpe es una acción de un solo tiro: su duración se lee del clip, así que si
cambias el clip el tiempo se ajusta solo.

**Combo.** Volver a hacer clic mientras golpeas **encadena, no reinicia**:

| Cuándo llega el clic | Qué pasa |
| --- | --- |
| Antes de `combo_window` (45 % del clip) | Se queda **en cola** y entra solo en cuanto se abre la ventana |
| Después de la ventana | Entra **ya**, mezclado con el golpe anterior |
| Justo al terminar el clip | Tampoco se pierde: sale como siguiente golpe |
| Sin clic | El combo termina y el siguiente clic vuelve a empezar por el primero |

Los dos golpes se **alternan** (`attack` = cruzado, `attack_2` = jab), que es lo que
hace que parezca una combinación y no el mismo tiro repetido. Y son dos estados
distintos a propósito: `travel()` solo reinicia un clip si hay una transición de
verdad, y viajar *al mismo* estado no hace nada.

**Esquiva.** `player.request_dodge(direccion)`; sin dirección, esquiva hacia donde
te mueves (y hacia delante si estás parado). Es una **voltereta**: el cuerpo se gira
hacia la dirección de la esquiva (sale solo, porque la orientación sigue la
velocidad real) y el impulso dura `dodge_dash_time` (0.7 s) a `dodge_speed`
(3.2 m/s). La acción se recorta a `dodge_duration` (1.1 s) para no quedarse
esperando al último tramo del clip, que ya no avanza.

### 2.6. Agacharse

`Ctrl` o `C` (`crouch`). La cápsula de colisión se acorta de forma continua hasta
`crouch_height` (0.95 m), y al levantarse vuelve exactamente a la medida original
(se guarda al arrancar, y se trabaja sobre una **copia** de la cápsula: los
sub-recursos de una escena se comparten entre instancias). Si hay algo encima, un
rayo hacia arriba lo detecta y el personaje **no se levanta** hasta que haya sitio.

### 2.7. Pies en el suelo (foot lock)

`PlayerAnimationController` corrige cada frame la altura del modelo midiendo los
tobillos reales: si el pie de apoyo queda flotando, baja el modelo; si se hunde, lo
sube (máximo 7 cm, con suavizado). Es lo que evita que el personaje parezca flotar
o hundirse al caminar **con cualquier modelo**, porque cada rig tiene las piernas
de una longitud distinta.

> **La corrección se FIJA, no se suma.** `model.position.y = base + corrección`.
> Si se sumara, cada frame se acumularía sobre lo corregido el frame anterior y,
> como la medida se hace sobre el modelo *ya desplazado*, se retroalimentaría: el
> personaje se iba hundiendo poco a poco hasta desaparecer bajo el suelo. Hay una
> prueba que lo cubre (`test_caminar_mantiene_los_pies_en_el_suelo`, que mide el
> pie **en el mundo**, no en el espacio del esqueleto: el espacio del esqueleto no
> ve el desplazamiento del nodo del modelo).

### 2.8. Sincronización de los pasos con la velocidad real

Cada clip de locomoción tiene una **velocidad natural medida** (la que se ve en el
clip, sacada del descenso del pie de apoyo relativo a la cadera, muestreada a
240 Hz). `player.gd` reproduce el clip a `velocidad_real / velocidad_del_clip`, así
que los pies no patinan ni al arrancar, ni a velocidad intermedia, ni a tope.

| Clip | Velocidad medida | Velocidad objetivo del personaje |
| --- | --- | --- |
| `walk` (A) | 1.51 m/s | `walk_speed` = 1.8 (×1.19) |
| `run` (B) | 2.36 m/s | `run_speed` = 3.0 (×1.27) |
| `sprint` (B) | 3.46 m/s | `sprint_speed` = 4.0 (×1.16) |
| `walk_back` (A) | 0.67 m/s | — (solo se usa al girar 180°) |
| `crouch_walk` (B) | 0.52 m/s | `crouch_speed` = 0.9 (×1.73) |

Los objetivos van un poco por encima de la velocidad natural del clip (entre un 16 %
y un 27 %), así que el personaje se mueve más ligero sin que los pies patinen: como
la velocidad de reproducción **se deriva** de la velocidad real, el pie sigue
clavado en el suelo aunque el clip vaya algo acelerado. Si cambias un clip,
actualiza su valor en `clip_speeds` (es un `@export`, se puede tocar desde el
inspector).

> Por qué existe la capa `SpeedScale`: `AnimationPlayer.speed_scale` **no** afecta a
> la reproducción cuando el que reproduce es el `AnimationTree` (comprobado con dos
> instancias en paralelo: la pose avanzaba exactamente igual con
> `speed_scale = 1` y `= 3`). La forma nativa de escalar la velocidad con un
> `AnimationTree` es un nodo `TimeScale`.
>
> Consecuencia: al añadir esa capa los parámetros del árbol cambian de ruta: el
> playback está en `parameters/StateMachine/playback` (no en `parameters/playback`)
> y la velocidad en `parameters/SpeedScale/scale`. `PlayerAnimationController` los
> localiza solo (`_find_playback()` y `_find_speed_parameter()`), así que puedes
> reestructurar el árbol sin tocar código.

### 2.9. Cómo se regeneran los clips

```
godot --headless --script res://tools/animation/build_pack_animations.gd
```

Ese único comando hornea los 23 clips desde los dos packs, mide sus velocidades,
escribe `player_animations.tres` y `player_animation_tree.tres`, e imprime el
informe (duración, huesos, velocidad, y qué clips traían root motion).
Los clips que quieras revisar de un vistazo se pueden volcar a una hoja de contactos
con `tools/state_sheet_builder.gd` (`locomocion`, `aire_acciones`, `dano`).

> **No uses `generate_placeholder_character.gd`** después: ese genera los clips
> procedurales de antes y sobreescribiría estos dos ficheros.


### 2.9.1. Postura de pie y de andar (`tools/stance_fixer.gd`)

Los clips horneados conservan **la geometría del reposo del modelo**, y el reposo de
este personaje es una **T de rigging**: los tobillos a **0.52 m** el uno del otro y la
cadera girada 14° respecto a la animación original. Eso no se ve raro en la T, pero al
animar sí: el personaje se queda con las piernas abiertas y la pelvis de lado, que es
justo lo que hace que una postura de parado se lea como una **guardia de combate**.

La culpa no es de los packs, es del retargeting (§ "Cómo se adaptan los clips a un rig
real"): el panadero copia el **delta global** de cada hueso y lo multiplica por el
reposo del hueso de destino, o sea `rotacion_global_destino = delta_origen *
reposo_destino`. Eso es lo que hace que funcione entre esqueletos distintos, pero
también significa que **todo lo que tenga el reposo del modelo se arrastra a los 34
clips**. Arreglarlo en el modelo no vale: los tracks de rotación de `AnimationNodeAnimation`
*reemplazan* la rotación del hueso, así que habría que rehornear los 34 clips y además
tocar el modelo con skin.

Por eso se arregla **en los tres clips donde se nota**, después de hornear:

```
godot --headless --script res://tools/animation/build_stance_fix.gd
```

* **`idle`**: las piernas del clip original son **estáticas** (medido), así que se
  reconstruyen enteras desde el reposo: se cierran 10° hacia el centro (aducción) y se
  sube la cadera lo que haga falta para que los pies queden apoyados justo a la altura
  del reposo (estrechar las piernas **sube** el cuerpo: una postura abierta es más baja).
  Además la cadera se devuelve al reposo en su primera clave, conservando la variación
  que traiga el clip, y encima se le pone un giro de **1.2°**, que es asimetría gratis
  (ver abajo).
* **`walk` y `walk_back`**: se cierran las piernas 8° **encima del movimiento que ya
  trae el clip**. El giro es sobre el eje de la mirada, así que **no cambia la zancada**
  (el recorrido del pie en profundidad se conserva): la velocidad natural del clip
  sigue siendo 1.51 m/s y `clip_speeds` no hay que tocarlo.
* **Transiciones**: `idle -> walk` y `idle -> walk_back` a 0.30 s, `walk -> idle` y
  `walk_back -> idle` a 0.34 s (antes 0.22 y 0.25). Entrar o salir de andar tiene que
  dar tiempo a que el peso se desplace y a que el pie acabe el paso.

Medido, antes y después (en metros, espacio local del jugador):

| | antes | después |
|---|---|---|
| separación de tobillos parado | 0.584 | **0.237** |
| pie de delante/atrás parado (avance) | -0.457 | **-0.018** |
| giro de la cadera parado | 14.4° | **1.2°** (a propósito: asimetría) |
| separación de tobillos andando | 0.478 | **0.27–0.31** |
| tobillo parado, altura | 0.179 / 0.201 | **0.162 / 0.161** (reposo: 0.161) |

#### El "stride": por qué separar las piernas no sirve para subir un pie

La primera versión dejaba una pierna 2° por delante de la otra (el "stride") buscando la
asimetría de una postura real. **Era la causa de que un pie quedara más alto que el
otro**, y no se arregla girando el muslo: en reposo las piernas cuelgan unos 5 cm por
**detrás** de la cadera, así que el tobillo está en el extremo de la pierna, y el stride
**inclina** una y **endereza** la otra. Medido, cada 0.5° de stride separa los tobillos
**3.1 mm** en altura (0° → 1.19 mm, 2° → 7.30 mm).

Y la aducción no puede compensarlo: en una pierna casi vertical, girarla hacia el centro
mueve el tobillo solo **0.23 mm por grado** en vertical (el tobillo está en el punto
extremo, donde girar casi no cambia la altura). Un ajuste por pierna con eso divergía
(el solver se iba a -108°). La solución fue dejar el stride en **0°** (el parámetro se
queda, con el coste medido en el comentario, por si alguien quiere el compromiso) y sacar
la asimetría de donde es **gratis**: un giro de la **cadera sobre la vertical**, que es el
eje de las piernas, así que la inclinación de cada una no cambia y los tobillos quedan
**exactamente a la misma altura** — solo los coloca en arco (uno un poco más adelante y
más abierto).

#### El "deshacer" de la aducción del walk

`_adduct_legs(t)` **gira -t** (el signo va dentro de la función). Deshacer es pasarle el
ángulo **negado**: pasarle el mismo lo aplicaba dos veces. Las metas de la biblioteca se
pierden al rehornear desde cero, pero **no** al reejecutar la herramienta, así que
reejecutarla sobre una biblioteca ya corregida dejaba el `walk` con **16°** en vez de 8° y
las piernas abiertas (medido: pies a **1.14 m**). Lo cazan
`test_el_paso_ni_se_cruza_ni_se_acorta` y `test_caminar_mantiene_los_pies_en_el_suelo`.

Es **idempotente**: guarda en una meta de `player_animations.tres` los parámetros que
aplicó (`adduction_idle`, `adduction_walk`, `idle_stride`, `hips_raise`, `pelvis_yaw`,
`desnivel_mm`, `feet_before_mm`, `feet_after_mm`) y al volver a ejecutarse **deshace lo
anterior** antes de aplicar lo nuevo, así que se puede retocar el ángulo sin acumular
giros. Si se vuelven a hornear los clips (§2.9) hay que volver a lanzarlo.

Lo comprueban `test_postura_de_parado_natural` y `test_el_paso_ni_se_cruza_ni_se_acorta`.

> `walk_back` sí conserva una cadera girada 37°: **está en el clip original** de Pack A
> (`Walking Backwards`), comprobado midiendo la fuente. Es intención del animador, no
> un fallo del retargeting, así que no se toca.


### 2.9.2. Por qué el personaje no patina (y cómo se comprueba)

El panadero mide la velocidad de cada clip de locomoción como **la media** del retroceso
del pie apoyado, y el jugador reproduce el clip a `velocidad_real / velocidad_del_clip`.
Por eso, **de media, el pie apoyado siempre retrocede justo lo que el cuerpo avanza**: no
hay patinaje sistemático. Lo que queda son desviaciones locales dentro del apoyo (el pie
se apoya, se dobla y se despega; ningún clip real tiene el pie a velocidad constante), y
no se ven.

Comprobado midiendo el juego de verdad, con el pie apoyado en su **medio apoyo**:

| | el cuerpo avanza | el pie se mueve | deslizamiento |
|---|---|---|---|
| andando (1.8 m/s) | 0.33 m | 0.04 m | **13%** (0.24 m/s) |
| corriendo | 0.50 m | 0.01 m | **2%** (0.06 m/s) |

Tres trampas al medir esto, por si hay que repetirlo:

* **Unidades.** El espacio del esqueleto está en unidades **locales del modelo**, no en
  metros. Hay que multiplicar por la escala del modelo (**1.7922**) antes de comparar con
  el avance del cuerpo. Mezclar las dos unidades inventa un patinaje del 37% que no existe.
* **El foot lock.** Mueve el nodo del modelo en vertical, así que la altura de un pie **en
  el mundo** deja de decir si está apoyado: un pie en el aire puede quedar a la misma
  altura que el apoyado. Para saber qué pie está apoyado hay que mirar el **esqueleto**
  (el lock no toca los huesos).
* **El final del apoyo no cuenta.** Al despegar, el tobillo sube y avanza mientras la
  puntera sigue clavada: medir el tobillo en esa parte del apoyo da un "deslizamiento" que
  no se ve. Lo justo es medir el **medio apoyo**.

Las tres posturas nuevas las comprueban `test_postura_de_parado_natural`,
`test_el_paso_ni_se_cruza_ni_se_acorta` y `test_el_frenado_en_tierra_no_es_de_golpe`.


### 2.9.3. El reposo: pies, brazos y respiración (`tools/idle_polish.gd`)

Con los pies ya nivelados (§2.9.1) quedaban dos cosas que se veían a simple vista en el
reposo: los brazos caían **pegados al cuerpo**, con las manos por delante de los muslos
(el personaje se leía como en posición de saludo), y la postura era **simétrica y rígida**,
como un maniquí. Y quieto no se movía nada.

`tools/idle_polish.gd` reescribe el clip `idle` entero: coge la **pose base** (la primera
clave del clip ya corregido por §2.9.1, guardada en una meta) y le suma **encima** una capa
procedural. Se lanza **después** de `build_stance_fix.gd`:

```
# OJO (LEGACY): ya NO se usa. Rehace el idle desde la pose del primer fotograma y
# destruye la animacion actual (Breathing Idle). Se conserva solo como respaldo.
godot --headless --script res://tools/legacy/build_idle_polish.gd
```

Qué hace la capa, y por qué cada cosa:

* **Brazos (puntos 2 y 3).** Se separan del cuerpo 7.5° (izquierdo) y 6.2° (derecho) sobre
  el eje de la mirada, y las manos giran 9° sobre su propio eje para que la palma mire al
  muslo en vez de mirar a la otra mano. Medido, la separación entre manos pasa de **0.52 m
  a 0.64 m** (+22%). Las dos cifras son distintas a propósito: una postura real no es
  simétrica.
* **Asimetría (4).** Cadera 1.2°, cabeza 8.5° (el modelo ya traía 11.5° de fábrica y se le
  quitan 3), un hombro 1.2° más bajo que el otro y 1.3° de diferencia entre los dos brazos.
  El eje vertical del esqueleto va **al revés de lo que parece**: un valor negativo en
  `HEAD_YAW` *endereza* la cabeza, porque el ángulo se mide con `atan2(x.z, x.x)` y un giro
  positivo sobre +Y manda +X hacia -Z.
* **Respiración (5).** La columna se echa un pelo **atrás** al inspirar (0.70° + 0.45° +
  0.30° por segmento, con el cuello contrarrestando 0.40° y las clavículas subiendo 1.0°),
  y el pecho se mueve **7.6 mm** en profundidad cada 4.17 s. Se mide en **Z, no en Y**: una
  respiración tranquila mueve el pecho hacia delante y hacia atrás y casi nada en vertical
  (en Y el recorrido era de 0.12 mm, invisible).
* **Variación (6).** Balanceo del peso de **±8 mm** en lateral (traslación de la cadera,
  sin balanceo ni cabeceo: así los pies no cambian de altura) cada 6.25 s, más una deriva
  de ±0.5° en los brazos y ±0.8° en la cabeza cada 12.5 s.
* **Sin rebote vertical.** No se sube y baja la cadera: el "foot lock" del jugador lo
  cancelaría (§2.9.2), así que el pecho sube estirando la columna y las clavículas.

El clip dura **12.5 s** (5 × los 2.5 s originales) a 10 Hz, 126 claves por pista, y **todos
los periodos dividen 12.5 exactos** (4.17 × 3, 6.25 × 2, 12.5 × 1), así que la primera y la
última clave de cada pista son **idénticas** y el bucle no da un tirón: lo comprueba
`test_el_reposo_es_un_bucle_y_esta_torcido` pista por pista.

Las transiciones no se tocan: los cruces de §2.9.1 (0.30/0.34 s) ya reparten el peso y
fundido de entrada y salida de la respiración, que es justo lo que pide el punto 7.

Lo comprueban, además, `test_los_brazos_no_se_pegan_al_cuerpo`,
`test_los_pies_quedan_nivelados_al_pararse` y `test_el_reposo_respira_pero_poquito`.

> El giro de la cabeza se mide contra el **reposo** del hueso, no contra el mundo: el modelo
> lleva un giro de 180° encima (mira a -Z) y la cadera tiene +90° de reposo en el espacio del
> esqueleto. Comparar sin restar el reposo da un giro de 100° que no existe.


### Los clips procedurales (solo como respaldo)

`tools/placeholder_generator.gd` puede **generar** animaciones por código, con todo
el cuerpo coordinado en fases (pasos, brazos en oposición, codo doblándose hacia
delante, balanceo de cadera, contrarrotación del tronco, retardo de la muñeca...).
Hoy **no se usa**: el personaje tiene los 23 clips de los dos packs.

Sigue existiendo por si algún día quieres un personaje sin packs de animación
(`generate_placeholder_character.gd`). Dos detalles de ese generador que merece la
pena conocer, porque explican decisiones de diseño que siguen vigentes:

* El **codo se dobla siempre hacia adelante** (flexión natural). Si se dobla hacia
  atrás, la caminata parece que el personaje *arrastra* los brazos hacia atrás: es
  el detalle que más cambia la sensación de naturalidad (y el bug que se corrigió
  en una pasada anterior).
* El balanceo vertical y lateral del cuerpo se anima en la **posición del nodo
  `Visual`**, no en el hueso `Hips`. Así el balanceo no depende de a qué altura
  tenga la cadera cada modelo y los clips siguen sirviendo para cualquier rig.
  (El foot lock de la §2.7 usa esa misma idea: la altura del cuerpo es un problema
  del *modelo*, no de los clips.)

### Cómo se adaptan los clips a un rig real (retargeting)

Hay **dos** mecanismos, y es importante no confundirlos:

1. **El que se usa hoy: `tools/clip_baker.gd`.** Copia de cada hueso su rotación
   **acumulada** (la del hueso y todos sus padres) y la vuelve a aplicar sobre el
   hueso equivalente del modelo. Así funciona entre esqueletos distintos: uno de 53
   huesos de Blender (pack B) y otro de 65 de Mixamo (pack A) acaban moviendo el
   mismo personaje igual. El mapa de huesos (`tools/rig_baker.gd`, 22 huesos
   estándar con alias y normalización de `.L`/`.R`) empareja hips, columna, brazos,
   piernas y cabeza en los tres casos: personaje, pack A y pack B → **22/22
   emparejados**.
2. **El de los clips procedurales: pose-intents.** Cada hueso recibe unos grados
   (`pitch`, `yaw`, `roll`) sobre los ejes del mundo, partiendo de una postura
   concreta (brazos abajo, piernas rectas, mirando a −Z). Eso funciona tal cual en
   un esqueleto cuyos huesos tienen el *rest* sin rotar (el placeholder), pero un
   rig importado no cumple eso: los huesos tienen el rest rotado (en Mixamo el hueso
   del brazo apunta al lado, porque la postura de reposo es una T-pose), los nombres
   son
propios (`mixamorig_LeftArm`) y el modelo puede estar girado 180°.

`tools/rig_baker.gd` traduce las tres cosas, midiendo del propio esqueleto (nada
escrito a mano):

1. **Mapa de nombres**: `LeftUpperArm` → `mixamorig_LeftArm`, con lista de alias
   (`leftarm`, `leftupperarm`, `l_upperarm`, …). Informa de los que no encuentra.
2. **Corrección de postura de reposo**: gira los brazos desde la T-pose hasta
   colgando (16° separados del cuerpo) y junta las piernas a ~5° de la vertical.
   La corrección solo se aplica si el brazo está realmente en cruz, así que un rig
   que ya viene con los brazos abajo no se toca.
3. **Espacio del modelo**: si el contenido mira a +Z dentro de su nodo, las
   rotaciones se expresan en ese espacio (conjugar por un giro de 180° sobre Y).

La pose que se escribe en cada track se calcula así (esto es lo importante):

```
A[hueso]    = A[padre] * D[hueso]                 rotación acumulada, en el mundo
pose_local  = (A[padre] * rest_global[padre])⁻¹ * A[hueso] * rest_global[hueso]
```

Es decir: cada hueso rota `D` grados respecto a su postura de reposo y esa rotación
la *arrastra* el padre (cinemática directa normal). Con `D = 0` en todos los huesos
la pose queda igual al rest, y con un rest sin rotar la fórmula se reduce a
`pose_local = D` — exactamente lo que hacían las animaciones antes. Por eso el
mismo generador sirve para el placeholder y para un rig de Mixamo.

En los grupos con corrección de rest (brazo, pierna) la **raíz** del grupo aplica
la corrección (`D = D_clip * D_offset`) y los **descendientes** la cancelan en su
eje (`D = D_offset⁻¹ * D_clip * D_offset`), de modo que el codo y la rodilla siguen
doblando en su bisagra natural y la corrección no se aplica dos veces.

### Notas técnicas de Godot 4 (motivo de varios errores durante el desarrollo)

* Un track de hueso se escribe así: `<ruta_al_Skeleton3D>:<NombreDelHueso>`
  y el tipo de track (`ROTATION_3D`, `POSITION_3D`, `SCALE_3D`) indica qué
  componente se anima.
* Esa ruta es **relativa al `root_node` del AnimationMixer**, que por defecto es
  `".."` (el padre del `AnimationPlayer`, o sea el nodo `Player`). Por eso los
  tracks valen `Visual/CharacterModel/Skeleton3D:Hips` y **no**
  `../Visual/...` ni `Skeleton3D:Hips`.
* La *pose* de un hueso en Godot 4 es una transformación local completa (incluye
  el rest): un track de rotación no toca la posición del hueso, y la posición
  (el sube/baja de la cadera) se anima con un track `POSITION_3D` cuyo valor ya
  incluye el rest.
* Los nombres de hueso **no pueden contener `:` ni `/`**. Los importadores de
  glTF sanean esos nombres (Mixamo `mixamorig:Hips` → `mixamorig_Hips`).
* El constructor de cuaterniones es **`Quaternion(x, y, z, w)`** (no `w` primero).
  Escribir el orden mal no da error: da una rotación de 180° en vez de identidad, y
  el personaje aparece tumbado en el aire. Fue el error más caro de la integración
  del modelo real.

---

## 3. Cómo funciona el movimiento

`player.gd` (todo con nodos nativos, sin dependencias externas):

| Ajuste | Valor por defecto |
| --- | --- |
| `walk_speed` / `run_speed` / `sprint_speed` | 1.8 / 3.0 / 4.0 m/s |
| `crouch_speed` | 0.9 m/s |
| `clip_speeds` | velocidad natural medida de cada clip (1.51 / 2.36 / 3.46 m/s…) |
| `sprint_delay` | 0.6 s manteniendo Shift corriendo, para pasar a esprintar |
| `acceleration` / `deceleration` | 20 / 28 m/s² (suavizado con `move_toward`) |
| `land_deceleration` | 9 m/s² (solo en tierra; ver abajo) |
| `air_acceleration` | 7 m/s² (control aéreo reducido) |
| `gravity` / `jump_height` | 22 m/s² / 1.15 m (la velocidad se calcula: `sqrt(2·g·h)`) |
| `coyote_time` / `jump_buffer_time` | 0.12 s / 0.15 s |
| `turn_rate` / `turn_smoothing` | 720 °/s / 16 s⁻¹ (giro progresivo, ver abajo) |
| `attack_move_multiplier` | 0.35 (velocidad mientras se ataca) |
| `combo_window` | 0.45 (fracción del golpe a partir de la cual ya encadena el siguiente) |
| `dodge_speed` / `dodge_dash_time` / `dodge_duration` | 3.2 m/s / 0.7 s / 1.1 s |
| `run_toggle_mode` | `false` = Shift mantenido; `true` = Shift alterna caminar/correr |

* Entrada: `move_forward/back/left/right` (WASD), `jump` (Espacio), `run` (Shift),
  `crouch` (Ctrl/C), `attack` (clic izquierdo), `dodge` (Q).
* **El clic izquierdo encadena el combo.** Si vuelves a hacer clic mientras
  golpeas, el clic no se pierde ni reinicia la animación: si el golpe ya pasó su
  `combo_window` (45 % del clip) el siguiente golpe entra ya, y si todavía es
  pronto queda en cola y sale solo al abrirse la ventana. Los dos golpes se
  alternan (`attack` = cruzado, `attack_2` = jab), así que el combo se ve como una
  combinación y no como el mismo tiro repetido. Si no encolas nada más, el combo
  termina y el siguiente clic vuelve a empezar por el primero.
* El movimiento es **relativo a la cámara**: `PlayerCameraRig.get_movement_direction()`
  proyecta el input sobre el plano XZ usando el yaw del pivote.
* El personaje mira hacia `-Z` (forward de Godot) y gira con `atan2(-dir.x, -dir.z)`.
  El giro usa suavizado exponencial (independiente del framerate) **con tope de
  velocidad angular** (`turn_rate`): es progresivo, pero un cambio de 180° nunca
  se resuelve en un fotograma (tarda ≥ 0.33 s). Mientras se desplaza, la
  orientación sigue la dirección **real** de la velocidad (no la tecla), así que
  el giro acompaña la curva de aceleración en vez de saltar al cambiar de tecla.
* Si el personaje está parado, se orienta hacia la dirección pedida al arrancar.
* Estados: `idle → walk → run`, `jump → fall → landing → idle/walk/run`. El
  aterrizaje solo se activa si estuviste en el aire más de
  `min_air_time_for_landing` (0.12 s), para no disparar el clip al bajar un
  escalón pequeño.
* **Frenar en tierra no es quedarse clavado.** `deceleration` (28 m/s²) se usa en el
  agua y al caminar sobre la superficie, donde sí interesa que el personaje se clave.
  En tierra manda `land_deceleration` (9 m/s²): al soltar los controles un paseo a
  1.8 m/s tarda ~0.2 s en pararse en vez de 0.06 s. Como el estado sigue siendo
  `walk` mientras frena y el clip se reproduce a `velocidad / clip_speed`, la
  animación **se va ralentizando sola** y el pie de apoyo acaba el paso antes de que
  la transición a `idle` (0.34 s) lo lleve a la postura de parado. Lo comprueba
  `test_el_frenado_en_tierra_no_es_de_golpe`.
* Cámara: `Escape` libera el ratón, un clic lo vuelve a capturar.

### Cámara en tercera persona (solo ratón)

| Ajuste | Valor por defecto |
| --- | --- |
| `sensitivity` | 0.22 °/píxel |
| `pitch_min` / `pitch_max` | -50° / 65° |
| `invert_y` | `false` |
| `target_height` | 1.45 m (altura del pivote respecto al personaje) |
| `follow_smoothing` / `vertical_smoothing` | 18 / 6 = la cámara sigue al personaje con un pequeño arrastre |
| `spring_length` (SpringArm3D) | 3.6 m, con `SphereShape3D` de 0.25 m de radio |
| `capture_mouse_on_start` | `true` (Escape libera el ratón, un clic lo vuelve a capturar) |

El `SpringArm3D` acerca la cámara automáticamente cuando hay suelo o pared entre
el pivote y la cámara, así que no la atraviesa. La cámara no inclina ni deforma
al personaje: solo tiene yaw y pitch, y su FOV es fijo.

**Por qué la cámara lleva arrastre:** si el pivote copia la posición del jugador
con retardo cero, el personaje queda clavado en el centro de la pantalla y parece
una pegatina ("imagen flotante"). Con `follow_smoothing` (horizontal) el personaje
se adelanta un poco al moverse y el mundo "pesa"; con `vertical_smoothing` (más
bajo) los saltos no arrastran la cámara y el personaje sube en pantalla. El pivote
sigue siendo `top_level = true`: **la cámara nunca mueve al personaje** y girar con
WASD no la rota.

---

## 4. Cómo cambiar el modelo por otro

### Lo que hay que hacer

1. Importa tu personaje (`personaje.glb` / `.fbx`). Godot crea una escena con
   `Skeleton3D` (+ sus animaciones, si las trae).
2. Crea su escena de personaje con el runner (le pone la raíz `CharacterModel`, lo
   gira a −Z y lo escala a 1.75 m):

   ```
   godot --headless --script res://tools/model/build_model_character.gd
   ```

   (Ajusta `SOURCE_MODEL`, `TARGET_HEIGHT` y `MODEL_HEIGHT_UNITS` dentro del
   fichero; con `MODEL_HEIGHT_UNITS = 0` mide la altura solo.)
3. En `player.tscn`, sustituye el nodo `Visual/CharacterModel` por una instancia de
   tu escena (mismo sitio, mismo nombre).
4. **Vuelve a adaptar las animaciones al rig nuevo:**

   ```
   # OJO: runner LEGACY (tuberia procedural antigua). Sobrescribe la libreria y el
   # arbol actuales: si se ejecuta, hay que volver a hornear despues con
   # tools/animation/build_pack_animations.gd.
   godot --headless --script res://tools/legacy/generate_model_animations.gd
   ```

   (Ajusta `MODEL_SCENE` y `FLIP_MODEL_YAW`; mira `tools/probe_model.tscn` para
   comprobar a ojo hacia dónde mira el modelo.)
5. Rellena `bone_name_map` en el nodo `Visual` si los nombres de hueso son
   distintos (el runner ya escribe los tracks con los nombres reales; el mapa
   sirve además al foot lock y a `adapt_animations_to_model()`).
6. Si tu modelo trae **sus propias animaciones** (idle/walk/run/jump/fall/landing),
   activa `use_model_animation_player = true` en `AnimationController` y el sistema
   usará las suyas, alineando el `root_node` del árbol solo.

### Reemplazo en caliente (desde código)

```gdscript
var nuevo: Node3D = load("res://personajes/mi_personaje.glb").instantiate()
$Player.swap_model(nuevo)   # borra el anterior, detecta el skeleton y reconecta la animación
```

---

## 5. Requisitos que debe cumplir el modelo nuevo

Imprescindibles:

* **Raíz `Node3D`** que se pueda añadir como hijo de `Visual`, de pie sobre el
  origen y mirando hacia **`-Z`**.
* Un **`Skeleton3D`** en algún punto de su jerarquía (el sistema lo busca solo, o
  se lo puedes indicar en `Visual > skeleton_path`).
* Altura aproximada de 1.75 m (si es muy distinto, ajusta el `CollisionShape3D`
  del jugador y/o `Hips`).
* Huesos con nombres sin `:` ni `/`.

Recomendado (hace que todo encaje sin tocar código):

* Huesos con los **nombres del perfil humanoide de Godot**
  (`SkeletonProfileHumanoid`): `Root`, `Hips`, `Spine`, `Chest`, `UpperChest`,
  `Neck`, `Head`, `LeftShoulder`, `LeftUpperArm`, `LeftLowerArm`, `LeftHand`,
  `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`, `LeftToes` y sus equivalentes
  `Right...`. Si no los tiene, `rig_baker.gd` los busca por alias: añade el alias
  que falte a `RigBaker.ALIASES` si es un nombre raro.
* Que el `Skeleton3D` se llame `Skeleton3D` (así las rutas de los tracks
  existentes coinciden sin reescribir nada).

---

## 6. Qué NO debes modificar al cambiar el personaje

* `player.gd`: no contiene ninguna referencia al modelo ni a nombres de hueso.
* `player_animation.gd` y `camera_rig.gd`.
* `CollisionShape3D` del jugador (salvo que la altura del personaje cambie).
* La estructura de `player.tscn` (`Player`, `Visual`, `AnimationPlayer`,
  `AnimationTree`, `AnimationController`, `CameraPivot`).
* `player_animation_tree.tres`: los estados y transiciones siguen valiendo
  mientras las animaciones se llamen igual.

Lo único que cambia es el hijo de `Visual`. Nada más.

---

## 7. Si tu modelo usa otros nombres de hueso (o es de otra altura)

1. Nombres de hueso distintos: añade los alias que falten a
   `RigBaker.ALIASES` (`tools/rig_baker.gd`) y vuelve a lanzar
   `generate_model_animations.gd`. El informe imprime exactamente qué huesos
   reconoció y cuáles no.
2. Otra altura: ajusta `TARGET_HEIGHT` en `tools/build_model_character.gd` y el
   `CollisionShape3D` del jugador. El resto del sistema se adapta solo (el foot
   lock mide los tobillos reales y convierte a metros con la escala del modelo).
3. Rotaciones de rest distintas: es justo lo que resuelve `rig_baker.gd`
   (apartado 2). Ya no hace falta ningún "bake" en tiempo de ejecución.

---

## 8. Si tu modelo trae otro Skeleton3D: qué se adapta y qué no

Nada del movimiento, la cámara, el input, la colisión, el estado ni el árbol de
animación depende del skeleton concreto. Lo único que mira a los huesos es
`PlayerAnimationController.adapt_animations_to_model()` (rutas y nombres en
tiempo de ejecución) y el retargeting previo de `rig_baker.gd` (postura de reposo
y orientación).

| Situación de tu modelo | Qué hay que hacer |
| --- | --- |
| Mismos nombres de hueso (`Root`, `Hips`, `Spine`, …) | nada |
| Nombres distintos (`mixamorig_Hips`, `Bip01 Pelvis`, …) | alias en `RigBaker.ALIASES` + relanzar el runner de animaciones; y rellenar `bone_name_map` en `Visual` |
| El `Skeleton3D` está más adentro o tiene otro nombre | nada: se busca el primer `Skeleton3D` de la jerarquía. Si hay varios, fija `skeleton_path` en `Visual` |
| Rotaciones de rest distintas (T-pose, Blender, Mixamo) | nada: `rig_baker.gd` las mide y las corrige al escribir los clips |
| Trae su propio `AnimationPlayer` con las animaciones | activar `use_model_animation_player = true` en `AnimationController` (nombra los clips idle/walk/run/jump/fall/landing) |
| Otra altura o proporciones | ajustar `TARGET_HEIGHT` y el `CollisionShape3D` del Player (y `target_height` de la cámara) |

Al arrancar (o al llamar a `refresh_after_model_change()`) el controlador imprime
un informe: `N tracks revisados, N huesos remapeados, huesos no encontrados: …`,
que es exactamente la lista de lo que te falta por mapear.

---

## 9. Personaje actual: la armadura futurista (FBX)

### Qué se encontró al inspeccionar los ficheros

La carpeta traía **dos** ficheros con el mismo personaje, y ninguno con
animaciones:

| Fichero | Qué contiene | Decisión |
| --- | --- | --- |
| `tripo_convert_5b346713-….fbx` | `Skeleton3D` con **65 huesos de Mixamo** (`mixamorig_*`), **postura de reposo válida** (T-pose), malla de **20 465 triángulos**, skin con 52 uniones, 4 huesos por vértice, UVs, texturas **PNG** 4096² (albedo) + 2048² (normal) | **es el que se usa** |
| `futuristic armor 3d model.glb` | **la misma malla** (20 465 triángulos) pero 55 huesos y **todas las posturas de reposo a cero** (esqueleto colapsado: solo se renderiza el torso) | descartado (duplicado roto) |

Tampoco traía animaciones el FBX, así que los clips del proyecto (que ya existían
y estaban probados) se **retargetearon** al esqueleto de Mixamo con
`tools/rig_baker.gd`, en vez de escribir animaciones nuevas.

### Cómo está montado

1. `tools/build_model_character.gd` (que solo es el *runner*) llama a
   `tools/model_scene_builder.gd`, que instancia el FBX, renombra la raíz a
   `CharacterModel`, la gira **180°** (el modelo mira a +Z dentro de su nodo; el
   proyecto mira a −Z) y la escala **×1.7922** (0.976 unidades → **1.75 m**), con
   los pies en y = 0.
1.bis. El mismo constructor **repara los pesos de skin que vienen a cero** en el
   FBX (ver "El hilo del modelo", más abajo) y guarda el resultado ya arreglado
   dentro de la escena.
2. `tools/generate_model_animations.gd` (con `rig_baker.gd`) escribe los 9 clips
   sobre el esqueleto real: traduce los nombres a `mixamorig_*`, corrige la
   T-pose (brazos abajo, 16° separados del cuerpo) y junta las piernas a 5° de la
   vertical.
3. El resultado se guarda en `res://personaje/transformaciones/acuatica/models/futuristic_armor_character.tscn`
   y se instancia dentro de `Visual` en `player.tscn`, con el `bone_name_map`
   relleno (22 huesos estándar → `mixamorig_*`).

### Problemas encontrados y cómo se resolvieron

* **El modelo salía tumbado y flotando.** El "espejado" de las rotaciones (para
  pasar del espacio del jugador al del modelo, girado 180°) estaba escrito con el
  orden de componentes equivocado: Godot usa `Quaternion(x, y, z, w)`, no
  `(w, x, y, z)`. El resultado era una rotación de 180° en cada hueso. Se localizó
  midiendo la rotación acumulada del hombro (`A_hombro` daba 179.8° cuando debía
  ser ≈ identidad).
* **Los brazos quedaban en T-pose.** La corrección de postura de reposo se escribe
  como pista propia incluso en los clips que no animan los brazos
  (`RigBaker.forced_bones()`): sin pista, un hueso importado se queda en su rest.
* **La orientación no se puede deducir del esqueleto.** En este rig los huesos de
  los dedos de los pies **no** apuntan hacia donde mira el personaje, así que la
  orientación se pasa explícita (`FLIP_MODEL_YAW`) y se comprueba a ojo con
  `tools/probe_model.tscn`.
* **El foot lock movía el modelo 1.79 veces de más.** Los huesos viven en el
  espacio del modelo (escala 1.79) y el nodo del modelo se mueve en metros: la
  corrección se convierte con la escala vertical real del esqueleto.
* **Los pies quedaban sin apoyar** al mezclar clips escritos para las
  proporciones del placeholder (cadera 0.90 / muslo 0.44 / espinilla 0.42) con las
  del modelo (cadera 0.824 / muslo 0.274 / espinilla 0.383). Por eso `walk`/`run`
  ya no animan la altura del cuerpo: la pone el foot lock midiendo los tobillos
  reales, y vale para cualquier rig.

### El hilo del modelo (vértices sin peso)

El FBX original trae **3 vértices con los cuatro pesos de skin a 0.0** (los índices
14638, 14645 y 14687, todos en el cuello/pecho, en reposo sobre
`(0.0507, 0.7892, 0.0143)`). Un vértice sin pesos no se queda quieto: la matriz de
hueso mezclada sale cero, así que el shader lo manda al **origen del esqueleto**
`(0, 0, 0)`, es decir a los pies. Sus 6 triángulos se estiran desde el cuello hasta
el suelo y eso es el "hilo" vertical que se veía entre las piernas.

No era geometría sobrante (la malla no tiene ningún triángulo fino: la relación de
aspecto máxima es 12 y los lados miden ~0.03 m) ni un problema del retargeting: era
el skin. Por eso **el arreglo está en el generador** (`model_scene_builder.gd` →
`_repair_skin_weights()`), no en tiempo de ejecución: así queda guardado dentro de
la escena, se ve arreglado en el editor y el arreglo es reproducible.

Cómo lo arregla: para cada vértice sin peso busca el vértice **con peso más
cercano** (el donante suele estar a 0.002 unidades) y le copia sus 4 huesos y sus 4
pesos; después reconstruye la superficie con `add_surface_from_arrays()`. El formato
de vértices sale idéntico al original (mismo número de huesos por vértice, misma
compresión) y se conservan material, blend shapes y AABB, así que la malla se ve
exactamente igual. Lo único que no se copia es el LOD automático del importador (un
solo nivel a 1.3 cm): Godot no expone un lector público de LODs y para una malla de
personaje no aporta nada.

El constructor imprime cuántos vértices ha reparado. Si algún día regeneras el
modelo desde otro FBX, mira esa línea: si dice 0, ese modelo ya venía bien.

### Pruebas

`res://tests/test_player_system.gd` comprueba de verdad el resultado (36 pruebas):
estructura de la escena, orientación y escala del modelo, que cada pista de
animación apunte a un hueso existente, que los dos packs estén horneados al MISMO
esqueleto, los estados y las transiciones del árbol, la coherencia de las
velocidades de los clips, la progresión idle→walk→run→sprint, el agachado con la
cápsula, el salto, la cadena de daño (golpe → recuperación y derribo → suelo →
levantarse), el empuje del golpe, **que el combo encadene los dos golpes**, la
esquiva, la postura con el personaje quieto (cabeza a su altura, pies apoyados,
brazos colgando), que al caminar los pies sigan en el suelo, y **el sistema
acuático entero**: que las cuatro habilidades avisen por pista de método en el
fotograma correcto, que nadando se pueda lanzar un hechizo, que el proyectil cree
un objeto de verdad y haga daño al maniquí, y que la prisión lo deje ATRAPADO y lo
suelte sola.

Las 17 pruebas nuevas (además de las 19 anteriores) cubren la locomoción acuática
y su puesta en escena:

| Prueba | Qué defiende |
| --- | --- |
| `test_los_ocho_modos_de_agua` | Que existan y se usen los ocho modos (`NONE`…`CLIMBING`) |
| `test_nadar_en_tres_dimensiones` | Que `Espacio` suba y `Ctrl` baje de verdad, no solo en diagonal |
| `test_al_soltar_ctrl_mantiene_la_profundidad` | Que al soltar `Ctrl` **no** vuelva a flote solo |
| `test_el_balanceo_neutro_no_se_va` | Que el balanceo neutro no acumule deriva |
| `test_caminar_por_el_fondo_de_la_piscina` | Que se pueda andar por el fondo con la gravedad y los pies apoyados |
| `test_despegarse_del_fondo_con_espacio` | Que `Espacio` en el fondo despegue hacia arriba |
| `test_andar_sobre_la_superficie_del_agua` | Que la tecla de superficie lo deje ENCIMA del agua y no se hunda |
| `test_no_se_puede_andar_sobre_agua_somera` | Que en un charco no se pueda (hace falta columna de agua) |
| `test_salir_del_agua_trepando_por_el_borde` | Que `Espacio` junto al borde lo suba a tierra |
| `test_la_camara_se_adapta_al_agua` | Que el brazo de cámara se acorte y el cabeceo se abra |
| `test_la_vista_subacuatica_entra_y_sale` | Que la niebla y el velo entren bajo el agua, salgan fuera, y que el shader del agua conserve la rama de verse DESDE ABAJO |
| `test_las_cuatro_habilidades_funcionan_bajo_el_agua` | Que las cuatro se puedan lanzar sumergido |
| `test_las_habilidades_apuntan_en_tres_dimensiones` | Que bajo el agua apunten a donde mira la cámara (no en horizontal) |
| `test_el_agua_frena_las_habilidades` | Que el agua les quite velocidad (y en el aire no) |
| `test_las_habilidades_reaccionan_al_agua` | Que bajo el agua suelten burbujas y no salpicaduras |
| `test_el_cuerpo_a_cuerpo_funciona_bajo_el_agua` | Que el golpe de mano siga funcionando sumergido |
| `test_el_modo_de_nado_no_parpadea` | Que nadando no salte de modo cada fotograma |


> Todas las pruebas de un fichero comparten el MISMO espacio físico, así que si
> una falla antes de liberar su mundo, deja un maniquí (y un jugador) fantasma en
> el sitio del siguiente. Las pruebas que dependen de golpear a alguien llaman a
> `_aislar_mundo()`, que aparta los cuerpos de otros mundos de prueba.

El fichero **no** es un runner: `extends Node` y se lanza con el ejecutor de
pruebas (o desde el editor), no con `godot --script`.

---

## 10. Runners de regeneración

| Comando | Qué hace | Qué sobrescribe |
| --- | --- | --- |
| `godot --headless --script res://tools/animation/build_pack_animations.gd` | hornea TODOS los clips de los packs, mide sus velocidades y escribe la librería y el árbol | `aquatic_transformation/animations/player_animations.tres` y `…/player_animation_tree.tres` |
| `godot --headless --script res://tools/animation/build_stance_fix.gd` | arregla la postura de pie y de andar (`idle`, `walk`, `walk_back`) y los tiempos de las transiciones (ver §2.9.1) | los mismos `.tres` |
| `res://tools/animation/_run_rebuild.tscn` (se lanza desde el editor) | **runner TODO-EN-UNO**: horneado + postura + separación de brazos (en este entorno el subproceso headless no arranca) | los mismos `.tres` |
| `godot --headless --script res://tools/model/build_model_character.gd` | crea la escena del personaje desde el FBX (orientación, escala y reparación de los vértices sin peso) | `aquatic_transformation/models/futuristic_armor_character.tscn` |
| ~~`tools/legacy/generate_model_animations.gd`~~ | **LEGACY**: adapta los clips al rig del modelo por la tubería procedural antigua | `player_animations.tres`, `player_animation_tree.tres` |
| ~~`tools/legacy/generate_placeholder_character.gd`~~ | **LEGACY**: regenera el modelo placeholder y sus clips | `tools/legacy/placeholder_character.tscn`, los mismos `.tres` |

> **Ojo con el orden:** el runner del placeholder deja las animaciones escritas
> para el esqueleto del placeholder. Si lo ejecutas, vuelve a lanzar después
> `generate_model_animations.gd` para dejarlas adaptadas al modelo actual.

Los datos de huesos, cajas y clips se editan en
`res://tools/legacy/placeholder_generator.gd`, y las reglas de adaptación de rig en
`res://tools/animation/rig_baker.gd` (todo comentado).

---

## 11. El sistema acuático

El personaje no "nada de mentira": hay un lago de verdad, detecta el agua, cambia
de estado al entrar, se mueve en las tres dimensiones dentro del agua y lanza
hechizos que son **objetos reales** de la escena. Todo con herramientas nativas de
Godot: ni un addon, ni un asset externo.

### 11.1 El lago

`res://personaje/transformaciones/acuatica/water/lake.tscn` (instanciado en `player_test.tscn` en `(0, 0, 19)`):

| Nodo | Qué es |
| --- | --- |
| `Agua` (Area3D) | `WaterZone` — un volumen con la capa de física **8** (`WATER_LAYER`). Guarda la altura de la superficie (`-0.30`) y el fondo, y contesta a `surface_height_at(punto)` y `wave_offset_at(punto)` |
| `Superficie` (MeshInstance3D) | La lámina de agua: un plano con `water_surface.gdshader` y **`cast_shadow = 0`** |
| `Fondo` | El lecho del lago (`y = -4`) |
| `Playa` | La rampa de entrada: de `(z=9, y=0)` a `(z=17, y=-4)`, para poder **entrar andando** |

El shader `water_surface.gdshader` es espacial y nativo (`blend_mix`,
`depth_draw_never`, `cull_disabled`, `diffuse_burley`, `specular_schlick_ggx`) y
hace, en este orden:

1. **Olas**: desplaza los vértices con 6 senos sumados, **con la misma fórmula**
   que `WaterZone.wave_offset_at()`. Por eso la superficie que se ve y la altura
   del agua que usa el jugador coinciden.
2. **Refracción**: lee `hint_screen_texture` y desplaza la imagen según la normal.
   Lo que se ve a través del agua se "dobla".
3. **Profundidad**: lee `hint_depth_texture` y lo compara con la profundidad del
   propio agua. La diferencia es el **grosor** de agua que hay hasta el fondo, y de
   ahí salen tres cosas gratis: el color (claro en la orilla, oscuro en el centro),
   la transparencia y el **borde de espuma** (donde el agua es muy fina).
4. **Fresnel**: a ras de agua el agua refleja el cielo (`sky_reflection`). Es lo
   único que cambia al mirar el lago de pie en la orilla.
5. **Espuma y brillo especular**: `ROUGHNESS = 0.06` para que el sol deje un brillo
   duro y móvil encima de las olas.

Dos detalles que costaron sangre y conviene no deshacer:

* **El color del fondo se mezcla POR DEBAJO del tinte del agua**
  (`mix(behind, tint, mix(0.55, 1.0, depth_factor))`). Al revés (tinte encima del
  fondo, con un factor menor que 1) el fondo claro se cuela como gris y el lago
  entero se ve gris y lavado en vez de azul.
* **`ambient_occlusion` bajo (0.55) y un cielo azul de verdad**: el agua se ilumina
  sobre todo con su propio color y con el sol. Con el ambiente entero, un cielo
  claro y plano la deja gris (el agua acaba pareciendo el cielo). Y como el agua
  refleja el cielo, con un cielo gris el lago sale gris: de ahí que el
  `WorldEnvironment` de `player_test.tscn` tenga colores de cielo y de suelo
  elegidos a mano.

### 11.2 Detección del agua (`water_detection.gd`)

`Player/WaterDetection` es un `Area3D` con `collision_mask = 8` (la capa del agua)
y una caja de 0.8 × 1.8 × 0.8 centrada a `y = 0.9`, o sea pegada al cuerpo.

* `_submersion`: fracción del cuerpo (0..1) que queda por debajo de la superficie.
* `get_depth()`: metros de agua **en la vertical del personaje** (superficie menos
  pies, con la ola incluida). Es lo que decide si se nada o se vadea.
* `get_surface_height()`: la altura del agua justo donde está, para flotar y para
  no salirse de la superficie.
* `is_deep_enough_to_swim()`: la sumersión pasa de `swim_threshold` (0.45, o sea
  0.77 m — la cintura).

Con el agua por debajo de la cintura **no se nada**: se **vadea** — se sigue
andando con el clip de andar, pero frenado por `wade_speed_factor` (0.55). Es lo
que pasa en la playa, y evita el salto brusco de "andar" a "nadar" a media orilla.

### 11.3 Entrar, nadar y salir

Estados (todos con su clip de agua, ver §2): `enter_water`, `swim_idle`,
`swim_forward`, `swim_back`, `swim_up`, `swim_down`, `exit_water`.

| Situación | Qué hace |
| --- | --- |
| Agua honda (`depth >= 0.77`) | `_begin_swimming()` → pasa por `enter_water` (1.9 s, con `flatten_vertical` para que no dé un salto de altura) y luego nada |
| Dentro del agua | **Sin gravedad**: empuje `W/S` en horizontal, `Espacio` hacia arriba, `Ctrl` hacia abajo. Con inercia (`swim_acceleration`) y resistencia (`swim_deceleration`) |
| Quieto en el agua | **Flotación**: un muelle amortiguado (`buoyancy_accel`, `buoyancy_damping`) lleva el cuerpo a la altura de flotación de cada estado (`float_depths`) |
| `Espacio` mantenido | Sube, pero **se frena solo** al llegar a la superficie (`swim_surface_margin`): si no, el personaje salía disparado del lago como un tapón |
| `A/D` en el agua | Gira al personaje y nada hacia delante; `S` nada hacia atrás **sin girar** (`_swim_moving_backwards()`) |
| Toca el fondo cerca de la orilla | `is_on_floor()` **y** `depth < swim_depth - margen` → `exit_water` (1.9 s) y a andar/pararse |

El estado vertical lo decide **el input**, no la velocidad (`_swim_vertical`).
Parece un detalle, pero es lo que evita que la flotación suba el cuerpo entre
fotogramas y la animación parpadee a `swim_up` sin que el jugador toque nada.

Y la velocidad de las brazadas está atada a la velocidad real: igual que en tierra,
`playback = velocidad_real / velocidad_del_clip`, con el factor limitado a 2.0 para
que nadando no se convierta en un dibujo animado acelerado.

#### 11.3.1 Los ocho modos del agua (`WaterMode`)

El agua **no** es un estado de animación: es un estado **físico** aparte
(`player.gd`), porque las animaciones de agua se reutilizan entre modos (el fondo y
la superficie comparten `walk`/`idle`). `Player.get_water_mode_name()` devuelve el
nombre, y es lo primero que hay que mirar cuando algo del agua no cuadra.

| Modo | Cuándo | Qué hace la física |
| --- | --- | --- |
| `NONE` | Sin agua | Gravedad y movimiento de tierra |
| `WADING` | Agua por debajo de la cintura | Se anda por el fondo, más lento (`wade_speed_factor`) |
| `ENTERING` | Al entrar en agua honda | Transición de ~1.9 s: la gravedad se va mezclando con la flotación (nada de saltos de altura) |
| `SURFACE` | Flotando | Muelle de flotación a la altura del estado (`float_depths`) |
| `SUBMERGED` | Hundido por debajo de esa altura | Muelle hacia la profundidad que se mantiene (`_hold_depth`) |
| `FLOOR` | Toca el fondo con columna de sobra (`floor_min_depth`) | Gravedad propia del agua, pie en el suelo y velocidad de paseo |
| `SURFACE_WALK` | Con la tecla de superficie pulsada | Muelle vertical contra la superficie (ver 11.3.2) |
| `CLIMBING` | Trepando por el borde | Posición guiada por una curva de dos tramos (ver 11.3.3) |

La profundidad se mide **siempre** contra la superficie real de la zona de agua
(`water_detection`), nunca con `position.y > X`: si mañana mueves el lago, todo
sigue funcionando. El paso de `SURFACE` a `SUBMERGED` se decide por la
**profundidad del cuerpo** respecto de su altura de flotación (con histéresis),
no por dónde esté la cabeza: nadando tumbado la cabeza va a la misma altura que
los pies, así que "cabeza fuera" no sirve como criterio.

#### 11.3.2 Caminar sobre el agua (tecla `F`)

`F` alterna `surface_walk`. Con el modo activo el personaje **no flota**: un muelle
amortiguado (`surface_walk_stiffness`, `surface_walk_damping`) le pone los pies
2 cm por encima de la superficie y lo mantiene ahí, **siguiendo las olas** (la
superficie se lee con `surface_height_at()`, que incluye el oleaje). Anda y corre
con la física de tierra.

Tres detalles que costaron lo suyo:

* No es un colisionador falso flotando: es un muelle contra la altura real del agua.
* El tope de velocidad vertical (`surface_walk_max_speed`) es **bajo** a propósito:
  con un tope alto el muelle sube al personaje de golpe y se pasa de largo por
  encima del agua antes de frenar.
* La comprobación de "¿se puede andar aquí?" **no** exige estar mojado. Encima del
  agua los pies van justo en la superficie y el detector puede decir "seco" estando
  literalmente sobre el lago; lo que manda es que haya columna de agua debajo
  (`surface_walk_min_depth`). Por eso la caja del `WaterDetection` llega 20 cm por
  debajo de los pies.

#### 11.3.3 Salir del agua trepando por el borde (`Espacio`)

`Espacio` con un borde delante lanza la cadena completa
**SUMERGIDO → SUPERFICIE → BORDE → SALIDA → TIERRA** sin depender de una rampa.
`_find_ledge()` busca el borde con cuatro rayos que se adaptan a la altura real del
suelo:

1. un rayo **hacia abajo** desde arriba y un poco por delante, buscando suelo
   transitable (`normal.y >= 0.6`) que esté por encima del agua y a menos de
   `climb_height`;
2. un rayo hacia la pared, a media altura;
3. un rayo hacia arriba por encima del destino (¿hay hueco?);
4. un rayo a la altura de la cabeza ya en el destino.

El destino se recoloca `climb_land_offset` más adentro para no quedarse con medio
cuerpo colgando, y la posición se anima con una curva de dos tramos durante
`climb_time` (no es un teletransporte). `Player.has_ledge_in_front()` sirve para
avisar en pantalla de que se puede subir.

> El primer rayo empieza 0.6 m **por encima** de la altura máxima de trepada a
> propósito: si empezara justo a esa altura, con el cuerpo hundido arrancaría
> pegado a la superficie del borde y el roce haría que no detectara nada.

#### 11.3.4 La cámara y la vista subacuática

* `camera_rig.gd` mezcla el agua: el brazo se acorta (`air_spring_length` 3.6 →
  `water_spring_length` 2.2) y el cabeceo se abre (`water_pitch_min/max`) para poder
  mirar hacia arriba desde el fondo. Lo mezcla `set_underwater(0..1)`, que sube el
  jugador con la profundidad de la **cámara**.
* `vfx/underwater_view.gd` es quien decide si la cámara está bajo el agua (no el
  personaje: se puede estar mojado con la cámara fuera). Con esa profundidad sube
  tres cosas a la vez: el **velo** de pantalla
  (`vfx/underwater_overlay.gdshader`: absorción de color por canal, ondulación y
  viñeta), la **niebla** del `Environment` (que se **duplica** en tiempo de
  ejecución para no ensuciar la escena) y unas **motas** (`GPUParticles3D` colgadas
  de la cámara, en coordenadas locales).
* La superficie del agua tiene su propia rama para verse **desde abajo**
  (`from_below` en `water_surface.gdshader`): reflexión total interna, o sea que
  desde el fondo el lago se ve como un espejo del cielo y no como un cristal
  transparente.

#### 11.3.5 Las habilidades dentro del agua

Bajo el agua cambia el comportamiento, no el sistema:

* Se pueden lanzar las cuatro **sumergido**, nadando y por el fondo. Para lanzar
  solo hace falta estar en el agua **o** pisar algo: en el aire no.
* El apuntado es **en tres dimensiones** desde la cámara (`get_aim_direction()`)
  cuando se está nadando; en tierra sigue siendo horizontal (es lo que espera
  cualquier juego de acción).
* El agua **frena** los efectos: `WaterAbility.underwater_drag` les quita velocidad
  cada fotograma hasta un mínimo (`UNDERWATER_MIN_SPEED`), así que una bola lanzada
  desde el fondo pierde fuerza en vez de atravesar el lago igual que el aire.
* Los efectos de agua cambian de forma: en vez de salpicadura y anillo de espuma
  sueltan **burbujas** que suben y una **corriente**, que es lo que se ve cuando
  algo se mueve dentro del agua. El estallido del proyectil también suelta
  burbujas en vez de espuma.
* La carga previa (`vfx/water_charge.gd`) sigue a las **manos de verdad** (huesos
  del esqueleto, `get_hand_center()`): el agua se junta donde está el personaje,
  mire donde mire. Bajo el agua es más cerrada, más verde-azulada y suelta
  burbujas en vez de gotas.


### 11.4 Las cuatro habilidades

Teclas **1, 2, 3 y 4**. Funcionan **en tierra y en el agua** (es un personaje
acuático). Todo lo decide `WaterAbilityManager` (`Player/AbilityManager`):

| Tecla | Nombre | Clip | Enfría | Qué crea |
| --- | --- | --- | --- | --- |
| 1 | Proyectil de agua | `ability_1` (Magic Attack 01) | **1 s** | Una bola que vuela en línea recta y revienta al chocar (daño 12) |
| 2 | Esfera de agua | `ability_2` (Magic Attack 04) | **3 s** | Una esfera que vuela 0.55 s, explota y deja una **zona** de 3.2 m que hace daño cada 0.4 s durante 2.6 s |
| 3 | Prisión de agua | `ability_3` (Cast Spell 01) | **5 s** | Una burbuja que, al dar a alguien, le llama a su `trap(3 s)`: el objetivo queda **ATRAPADO** de verdad y la burbuja se le queda pegada girando |
| 4 | Oleada de agua | `ability_4` (Magic Attack 05) | **8 s** | Un muro de 5 columnas que arrolla en línea recta y golpea **a todos** los que pilla (45), pero a cada uno una sola vez |

**El efecto no sale al pulsar la tecla: sale cuando lo pide la animación.** Cada
clip de habilidad lleva una **pista de método** (`TYPE_METHOD`) insertada por
`tools/pack_animation_builder.gd` que llama a
`Player.notify_ability_release(estado)` en el fotograma exacto (`ABILITY_RELEASE`:
1.30 / 1.85 / 1.50 / 1.62 s). Así el hechizo sale justo cuando el personaje
termina de cargarlo, aunque cambies el clip.

Como red de seguridad hay un **seguro anti-atasco**: si por lo que sea la pista no
llegara (por ejemplo tras rehacer los clips con otro runner), el gestor suelta el
efecto igualmente 0.35 s después de la hora prevista. La habilidad nunca se queda
sin salir; como mucho, sale un poco tarde.

Las habilidades **no son dibujos dentro del personaje**: son nodos `Node3D` de
verdad que se cuelgan **del mundo** (no del jugador, para que se queden donde se
soltaron), vuelan con física propia, lanzan un rayo contra el escenario
(`world_mask = 1`) y buscan a quién golpear por **grupo + distancia**
(`TARGET_GROUP = "damageable"`), así que pueden golpear a cualquier nodo, no solo a
cuerpos físicos.

**El agua se junta antes de salir.** Al pulsar la tecla el gestor crea una carga
(`vfx/water_charge.gd`) que sigue a las **manos de verdad** (huesos del esqueleto) y
crece durante todo el clip; cuando la pista de método libera el hechizo, esa agua es
la que sale disparada. Así la habilidad se lee como agua **manipulada** y no como un
objeto que aparece de la nada. Si el hechizo se cancela, la carga se borra.

**Y si se lanza bajo el agua, cambia de comportamiento** (no de sistema): apunta en
3D desde la cámara, suelta burbujas y corrientes en vez de salpicaduras y anillos, y
el propio efecto se va frenando (`underwater_drag`). El detalle está en §11.3.5.


### 11.5 Los efectos (`vfx/`)

No hay escenas de efectos ni texturas: **todo se calcula en los shaders**.

| Fichero | Qué dibuja |
| --- | --- |
| `water_particle.gdshader` | Una gota procedural (gradiente radial). Se hace *billboard* a mano en el `vertex()` |
| `water_ring.gdshader` | Un anillo plano que se abre y ondea al alejarse |
| `water_orb.gdshader` | Un orbe/burbuja con fresnel, refracción de pantalla y ondulación |
| `underwater_overlay.gdshader` | El **velo** de pantalla de cuando la cámara está bajo el agua (absorción por canal, ondulación, viñeta) |

`WaterEffects` (`Player/WaterEffects`) es la fábrica: `splash()`, `burst()`,
`ring()`, `foam()`, `wake()`, `flash()`, `make_orb()`, `make_particles()`, y las
versiones "de dentro del agua": `bubbles()` (con gravedad **negativa**: suben),
`current()` (una corriente) y `surface_ripple()`. Además escucha la señal
`Player.water_splash` y va dejando **estela** en el agua mientras el personaje nada,
con un paso y un goteo contextuados por el modo de agua (`WaterMode`): al entrar
salpica, nadando deja estela y ondas, y al salir gotea.


### 11.6 El maniquí de entrenamiento

`res://personaje/transformaciones/acuatica/scenes/training_dummy.gd` + `.tscn` es un `StaticBody3D` del grupo
`damageable` que se construye entero en `_ready()` (tronco, cabeza, colisión y una
`Label3D` que muestra la vida). Sabe recibir daño (`apply_damage()`), quedarse
**ATRAPADO** (`trap()`), avisar de su centro y su radio (`get_hit_center()`,
`get_hit_radius()`), parpadear al recibir un golpe, sacudirse dentro de la prisión
y caer de lado cuando lo derriban. Es a lo que apuntan las pruebas y lo que hay en
`player_test.tscn` (tres, a la izquierda del punto de salida, fuera del camino por
el que andan las pruebas de locomoción).

### 11.7 Tres cosas que hay que saber antes de tocar esto

1. **El `SpeedScale` del `AnimationTree` envuelve a TODA la máquina de estados.**
   Ese `AnimationNodeTimeScale` se puso para atar las zancadas a la velocidad real,
   pero al estar delante de la máquina afecta a todo: un hechizo se reproducía al
   doble de velocidad (y se cortaba a la mitad) solo porque el personaje venía
   esprintando o nadando. Lo arregla `PlayerAnimationController`: al entrar en un
   estado que no está en `TIME_SCALED_STATES` devuelve el factor a 1.0, y
   `get_state_length()` **no** aplica el factor a los estados que no se escalan.
2. **`Superficie.cast_shadow = 0`.** El plano de agua es enorme: si proyecta
   sombra, deja el lecho del lago entero gris oscuro.
3. Los scripts de las habilidades hacen `extends "res://…/water_ability.gd"` (ruta)
   en vez de `extends WaterAbility` (class_name). Un `class_name` recién creado no
   entra en la caché de clases del editor hasta que este reescanea la carpeta, y
   mientras tanto el proyecto no compila.
4. **Los efectos estáticos de agua llevan el anfitrión como PRIMER argumento**
   (`WaterEffects.bubbles(host, punto, …)`, `WaterEffects.burst(host, punto, …)`).
   Si le pasas el punto en su lugar, el motor intenta meter un `Vector3` donde va un
   `Node3D` y revienta en el momento más tonto.
5. **Nada de `position.y > X` para saber si hay agua.** La profundidad se pregunta
   a `water_detection` (que la mide contra la superficie real de la zona), y el
   agua se detecta con un `Area3D` + rayos, no por altura. Es lo que permite mover
   el lago sin tocar una sola línea de física.
6. **La caja del `WaterDetection` llega 20 cm por debajo de los pies** a propósito:
   sin ese margen, caminando por encima del agua (los pies 2 cm sobre la
   superficie) el `Area3D` no solapaba nada y el modo se caía solo.
7. **La vista subacuática la decide la CÁMARA, no el personaje.** Se puede estar
   mojado con la cámara fuera del agua (y al revés): por eso la profundidad se mide
   con la posición de la cámara contra la superficie de la zona
   (`UnderwaterView._camera_depth()`), y el `Environment` se **duplica** al vuelo
   para no dejar la escena sucia.
