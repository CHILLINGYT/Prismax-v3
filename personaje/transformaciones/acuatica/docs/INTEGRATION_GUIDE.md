# INTEGRATION_GUIDE — Cómo integrar el módulo de transformación acuática

Este documento explica **qué es este módulo, qué contiene, de qué depende y cómo
llevarlo al proyecto general del videojuego** sin romper nada.

---

## 1. Qué es este módulo

El **personaje acuático**: un personaje 3D controlable con locomoción terrestre,
vadeo, natación, caminata sobre la superficie del agua, combate cuerpo a cuerpo,
apuntado con un balón de agua y **cuatro habilidades acuáticas**, además de su
cámara en tercera persona y su sistema de detección de agua.

Todo el módulo vive en **una sola carpeta**: `res://personaje/transformaciones/acuatica/`.

---

## 2. Estructura de carpetas

```
res://personaje/transformaciones/acuatica/
├── character/     Escena del jugador + movimiento, cámara, modelo y animación
├── abilities/     Las cuatro habilidades acuáticas + gestor (enfriamientos y avisos)
├── water/         Detección de agua, zona de agua, lago de prueba y shader de superficie
├── vfx/           Efectos de agua, carga en las manos, vista subacuática y sus shaders
├── ui/            Retícula de apuntado
├── models/        Modelo final del personaje (escena Godot ya horneada)
├── animations/    AnimationLibrary + AnimationTree finales
├── scenes/        ESCENA DE PRUEBA/DESARROLLO + maniquí de entrenamiento
└── docs/          Esta guía, el mapa de archivos, el registro de limpieza y la guía técnica
```

Fuera del módulo:

| Carpeta | Qué es | ¿Hace falta para ejecutar? |
| --- | --- | --- |
| `res://source_assets/` | FBX/GLB/OBJ de origen (packs de animación, modelo) | **No** — solo para volver a hornear/reconstruir |
| `res://tools/` | Herramientas de desarrollo (horneado, retargeting, revisión) | **No** |
| `res://tests/` | Pruebas automáticas del sistema | **No** (recomendable llevarlas) |
| `res://addons/ziva_agent/` | Herramienta del asistente usada durante el desarrollo | **No** — se puede excluir al empaquetar |

---

## 3. Archivos esenciales del módulo

Estos son los que **de verdad hacen falta** para tener el personaje funcionando:

| Archivo | Qué aporta |
| --- | --- |
| `character/player.tscn` | **Escena raíz del personaje.** Instancia todo lo demás |
| `character/player.gd` | Movimiento, estados, agua, apuntado, combate y daño |
| `character/player_animation.gd` | Puente estado → `AnimationTree` + adaptación al modelo |
| `character/character_model.gd` | «Slot» del modelo visual (permite cambiar de personaje) |
| `character/camera_rig.gd` | Cámara en tercera persona |
| `animations/player_animations.tres` | Todos los clips del personaje (una `AnimationLibrary`) |
| `animations/player_animation_tree.tres` | Máquina de estados de animación con sus transiciones |
| `models/futuristic_armor_character.tscn` | Modelo final del personaje (malla + esqueleto + material) |
| `abilities/water_ability_manager.gd` | Gestor: enfriamientos, lanzamiento y aviso a la animación |
| `abilities/water_ability.gd` | Base de toda habilidad: vuela, choca, hace daño |
| `abilities/water_projectile.gd` | Habilidad 1: proyectil |
| `abilities/water_burst.gd` | Habilidad 2: esfera/zona de daño |
| `abilities/water_prison.gd` | Habilidad 3: prisión que atrapa |
| `abilities/water_surge.gd` | Habilidad 4: oleada (la más fuerte) |
| `water/water_detection.gd` | Detección de agua del jugador (`Area3D`, capa 8) |
| `water/water_zone.gd` | Volumen de agua: superficie, olas, profundidad e inmersión |
| `water/water_surface.gdshader` | Shader de la superficie del agua |
| `vfx/water_effects.gd` | Fábrica de efectos (salpicaduras, anillos, espuma, burbujas, corriente) |
| `vfx/water_charge.gd` | Agua que se junta en las manos al cargar un hechizo |
| `vfx/underwater_view.gd` | Vista subacuática (niebla + velo + motas) |
| `vfx/*.gdshader` | Shaders de partícula, anillo, orbe y velo subacuático |
| `ui/aim_reticle.gd` | Retícula de apuntado (modo F) |

Escena de prueba: `scenes/player_test.tscn` (**ESCENA DE PRUEBA/DESARROLLO**:
suelo, rampas, plataformas, lago y tres maniquíes). No es contenido de juego.

---

## 4. Qué sistemas son GENERALES y cuáles son ACUÁTICOS

### Del personaje base (lo que el módulo *usa*, no lo que añade)

* `CharacterBody3D` y el movimiento base (andar, correr, saltar, agacharse, esquivar).
* La cámara en tercera persona.
* El sistema general de animación (`AnimationPlayer` + `AnimationTree` + controlador).
* El sistema general de daño y reacciones del personaje (`request_damage()`).
* El input (WASD, ratón, Espacio, Shift, Ctrl/C, Q, clic).
* El «slot» de modelo (`CharacterModel`), que permite cambiar el modelo sin tocar código.
* El contrato de objetivos (`grupo "damageable"` + `apply_damage()`): lo usan tanto el
  combate general como las habilidades acuáticas.

### Específicamente ACUÁTICO (lo que añade este módulo)

* Estados y física del agua del personaje: vadear, nadar, fondo, caminar sobre la
  superficie, entradas y salidas del agua.
* `water_detection.gd` + `water_zone.gd` + `water_surface.gdshader` (el agua como sistema).
* Las cuatro habilidades acuáticas, su gestor de enfriamientos y sus VFX.
* El apuntado con el balón de agua (`F`) y su retícula.
* La vista subacuática y los efectos de agua.
* Los clips de animación de natación y de las cuatro habilidades.

---

## 5. De qué depende el módulo (comprobado)

* **Motor:** Godot **4.7** (probado en 4.7.2). Renderer **Forward+**.
* **Física:** el proyecto usa **Jolt Physics** (`physics/3d/physics_engine`). El módulo
  no llama a APIs específicas de Jolt, pero se ha probado con él: si tu proyecto usa
  otro motor de física, pruébalo (sobre todo el deslizamiento por rampas y el agua).
* **Autoloads:** **ninguno**. El módulo no necesita ningún singleton global.
* **Capa de física 8 (`WaterZone.WATER_LAYER`):** el agua vive en esa capa; el
  `WaterDetection` del jugador la busca con su máscara. **Si tu proyecto usa la capa 8
  para otra cosa, cámbiala en los tres sitios:** `water/water_zone.gd`
  (`WATER_LAYER`), `character/player.tscn` (máscara del nodo `WaterDetection`) y
  `water/lake.tscn` (`collision_layer` del nodo `WaterZone`).
* **`class_name` globales:** el módulo registra nombres genéricos —
  `Player`, `CharacterModel`, `WaterZone`, `WaterAbility`, `WaterEffects`,
  `WaterCharge`, `UnderwaterView`, `AimReticle`, `PlayerAnimationController`,
  `PlayerCameraRig`, `TrainingDummy`, `WaterAbilityManager`, `WaterProjectile`,
  `WaterBurst`, `WaterPrison`, `WaterSurge`.
  **Si el proyecto general ya tiene una clase con el mismo nombre, Godot dará un
  conflicto:** renombra aquí (en el `.gd` y en la escena que lo usa).
* **Input:** el módulo usa las acciones que están en `project.godot` (ver §6).

---

## 6. Acciones de entrada que hay que fusionar

Si integras en un proyecto existente, añade al mapa de entrada estas acciones
(si ya existen, respeta las del proyecto general):

| Acción | Tecla/botón | Para qué |
| --- | --- | --- |
| `move_forward`, `move_back`, `move_left`, `move_right` | W A S D | Movimiento |
| `jump` | Espacio | Saltar / subir en el agua |
| `run` | Shift | Correr y esprintar |
| `crouch` | Ctrl o C | Agacharse / hundirse |
| `attack` | Clic izquierdo | Ataque y combo |
| `attack_right` | Clic derecho | Golpe cruzado |
| `dodge` | Q | Esquivar |
| `ability_1` … `ability_4` | 1 2 3 4 | Las cuatro habilidades acuáticas |
| `aim` | F | Apuntar con el balón de agua |
| `surface_walk` | E | Caminar sobre la superficie del agua |
| `debug_hit`, `debug_side`, `debug_heavy`, `debug_head`, `debug_knockdown`, `debug_death` | H G J U K L | Solo pruebas de daño (se pueden omitir) |

> Las acciones `debug_*` existen para probar el sistema de daño sin combate; el
> propio `player.gd` explica cómo quitarlas.

---

## 7. Cómo integrar el módulo (3 escenarios)

### A. «Quiero el proyecto entero» (lo más simple)

Copia el proyecto completo. Solamente revisa:

1. `project.godot` → la escena principal (`run/main_scene`) apunta a
   `res://personaje/transformaciones/acuatica/scenes/player_test.tscn`.
2. Puedes excluir `addons/ziva_agent/` y `.godot/` (ver §9).

### B. «Quiero el personaje dentro de mi juego ya existente»

1. Copia la carpeta `res://personaje/transformaciones/acuatica/` completa. **Basta con eso**: el
   módulo es autocontenido (incluye ya las texturas del modelo en `models/textures/`,
   así que el personaje se ve completo y a color; no queda blanco).
2. Copia `res://source_assets/` **solo si** vas a rehornear animaciones o reconstruir
   el modelo (si no, no hace falta).
3. Fusiona las acciones de entrada de §6.
4. Decide qué capa de física usa el agua (§5).
5. Sustituye/instancia `player.tscn` en tu nivel (o reasigna el modelo del personaje
   con el «slot» `CharacterModel`, que existe justo para eso).
6. Si tu juego ya tiene su propia cámara o su propio controlador de jugador, tienes
   dos caminos:
   * **usar el personaje completo** (`player.tscn`), que incluye cámara y animación, o
   * **llevarte solo el agua y las habilidades**: copia `water/`, `vfx/`, `abilities/`
     y añade al `player.gd` de tu proyecto las llamadas de `WaterDetection`,
     `WaterAbilityManager` y el apuntado (busca en `player.gd` las funciones
     `_physics_process` → sección de agua, `request_ability()` e `is_aiming()`).

### C. «Solo quiero el sistema de agua»

Copia `water/` + `vfx/` + `abilities/`. Necesitarás:

* una escena de nivel con un nodo `WaterZone` (o copia `water/lake.tscn`) sobre la
  superficie del agua;
* un `Area3D` de detección en tu personaje con la máscara de la capa del agua
  (copia `water/water_detection.gd`);
* llamar a `refresh()` una vez por fotograma de física y consultar
  `is_in_water()`, `get_submersion()` y `is_deep_enough_to_swim()`.

---

## 8. Comprobaciones después de integrar

1. Abre el proyecto: **no debe haber errores** en el panel de Salida (ni recursos
   sin cargar). Si aparecen «Missing» en alguna escena, revisa las rutas del §5.
2. Ejecuta `aquatic_transformation/scenes/player_test.tscn` y comprueba:
   * el personaje aparece con su modelo y su cámara;
   * WASD mueve, ratón gira la cámara, Espacio salta;
   * al entrar al lago: salpicadura, vadeo y, al fondo, natación;
   * `E` camina sobre la superficie del agua;
   * `1`–`4` lanzan las cuatro habilidades (con su enfriamiento);
   * `F` apunta con el balón de agua (retícula en el centro);
   * clic izquierdo encadena el combo de 4 golpes;
   * bajo el agua, la cámara cambia (niebla y velo subacuático).
3. Ejecuta las pruebas (`tests/test_player_system.gd`) si las copiaste.

---

## 9. Qué NO hace falta copiar

| Qué | Por qué |
| --- | --- |
| `res://tools/` | Herramientas de desarrollo. Solo se necesitan para **rehornear** animaciones o reconstruir el modelo |
| `res://source_assets/` | FBX/GLB/OBJ de origen (≈ 300 MB). Las animaciones ya están horneadas en los `.tres` y el modelo (con sus texturas, en `models/textures/`) ya está en su `.tscn` |
| `res://tools/legacy/` | Tuberías antiguas (placeholder procedural y personaje OBJ). **Dos de sus scripts sobrescriben los recursos actuales si se ejecutan** |
| `res://tools/review/` | Hojas de revisión regenerables |
| `.godot/` | Caché del editor: **se regenera sola** en la máquina del compañero al abrir el proyecto |
| `addons/ziva_agent/` | Herramienta del asistente usada en el desarrollo (binarios grandes). No es parte del juego |

---

## 10. Dependencias externas y limitaciones conocidas

* **DEPENDENCIA EXTERNA — puntos de integración con el proyecto general:** el módulo
  está preparado para convivir con un «personaje base», pero el emparejamiento real
  (quién manda en el input, dónde vive la vida/salud general, qué capa de física se
  usa para el agua, si el proyecto general tiene su propia cámara) **solo puede
  resolverse al integrarlo de verdad**: no se puede verificar desde este proyecto.
* **Ni el módulo ni sus pruebas dependen de nada que no esté dentro del proyecto**
  (no hay autoloads, ni plugins, ni servicios externos).
* El **maniquí de entrenamiento** (`scenes/training_dummy.gd`) es un objetivo de
  pruebas: implementa el mismo contrato (`grupo "damageable"` + `apply_damage()`,
  `trap()`, `is_defeated()`) que puede implementar cualquier enemigo del juego.
* El módulo **no incluye IA** ni enemigos móviles.
* Si se cambia cualquier clip de animación, hay que **volver a hornear** con las
  herramientas de `tools/animation/` (ver `tools/README.md`).