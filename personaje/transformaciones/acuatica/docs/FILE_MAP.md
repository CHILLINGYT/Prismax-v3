# FILE_MAP — Mapa de archivos del módulo acuático

Qué es cada archivo, a qué sistema pertenece, de qué depende y si **hace falta
copiarlo** al integrar el módulo en el proyecto general.

* **Sistema:** Agua (sistema acuático) · Personaje (base + estados) · Animación ·
  Habilidades · VFX · UI · Pruebas · Herramientas
* **Necesario para integración:** SÍ = el personaje no funciona sin él ·
  NO = útil pero prescindible · SOLO DEV = solo para desarrollar/regenerar

---

## 1. `res://personaje/transformaciones/acuatica/` — EL MÓDULO

### 1.1 `character/` — el personaje

| Archivo | Tipo | Función | Sistema | Depende de | Necesario |
| --- | --- | --- | --- | --- | --- |
| `player.tscn` | Escena | **Escena raíz del personaje**: cuerpo, colisión, modelo, animación, cámara, detección de agua, gestor de habilidades, VFX, retícula | Personaje | Todos los scripts del módulo (ver cabecera de la escena) | **SÍ** |
| `player.gd` | Script | Movimiento, gravedad, saltos, agachado, daño, combo, **estados de agua** (nadar/vadear/fondo/superficie), apuntado y uso de habilidades | Personaje + Agua | `water/water_detection.gd`, `abilities/water_ability_manager.gd`, `vfx/water_charge.gd` | **SÍ** |
| `player_animation.gd` | Script | Puente estado → `AnimationTree` (crossfades), escalado de velocidad, «pies en el suelo» y adaptación al modelo | Animación | `animations/player_animations.tres`, `animations/player_animation_tree.tres` | **SÍ** |
| `character_model.gd` | Script | «Slot» del modelo: encuentra el modelo, su esqueleto y su `AnimationPlayer`; permite cambiar de modelo en caliente | Personaje | `models/futuristic_armor_character.tscn` | **SÍ** |
| `camera_rig.gd` | Script | Cámara en tercera persona (ratón), con *spring arm*, ajustes de agua y de apuntado | Personaje | — | **SÍ** |

### 1.2 `abilities/` — las cuatro habilidades acuáticas

| Archivo | Tipo | Función | Sistema | Depende de | Necesario |
| --- | --- | --- | --- | --- | --- |
| `water_ability.gd` | Script | **Base de toda habilidad**: vuela de verdad, choca (rayo + esfera), hace daño y se borra sola. Define el contrato de objetivo (`grupo "damageable"`) | Habilidades | `vfx/water_effects.gd` | **SÍ** |
| `water_ability_manager.gd` | Script | **Gestor**: enfriamientos, comprobaciones, y crea la habilidad **cuando la animación lo pide** (pista de método + seguro anti-atasco) | Habilidades | los 4 scripts de habilidad, `vfx/water_charge.gd` | **SÍ** |
| `water_projectile.gd` | Script | Habilidad 1 (tecla 1): proyectil que revienta al chocar. Enfriamiento 1 s | Habilidades | `water_ability.gd` | **SÍ** |
| `water_burst.gd` | Script | Habilidad 2 (tecla 2): esfera que explota y deja una zona que dura. Enfriamiento 3 s | Habilidades | `water_ability.gd` | **SÍ** |
| `water_prison.gd` | Script | Habilidad 3 (tecla 3): burbuja que **atrapa** al objetivo (le llama a `trap()`). Enfriamiento 5 s | Habilidades | `water_ability.gd` | **SÍ** |
| `water_surge.gd` | Script | Habilidad 4 (tecla 4): oleada que arrolla y golpea a todos una vez. Enfriamiento 8 s | Habilidades | `water_ability.gd`, `vfx/water_orb.gdshader` | **SÍ** |

### 1.3 `water/` — el sistema de agua

| Archivo | Tipo | Función | Sistema | Depende de | Necesario |
| --- | --- | --- | --- | --- | --- |
| `water_detection.gd` | Script (`Area3D`) | Detección de agua del jugador: ¿estoy dentro?, ¿cuánta agua tengo encima?, ¿es bastante honda para nadar? | Agua | `water_zone.gd` (preload por ruta) | **SÍ** |
| `water_zone.gd` | Script (`Area3D`) | Volumen de agua: altura de la superficie **con olas**, profundidad, inmersión y pertenencia. Capa de física **8** | Agua | — (su fórmula de olas debe coincidir con el shader) | **SÍ** |
| `lake.tscn` | Escena | Lago de prueba: `WaterZone` + superficie con shader + cuenca (fondo, playa, muros) | Agua | `water_zone.gd`, `water_surface.gdshader` | **SÍ** (para probar; el juego puede tener su propio lago con `WaterZone`) |
| `water_surface.gdshader` | Shader | Superficie del agua: olas, refracción, espuma y reflejo. Sus números de ola son **los mismos** que los de `water_zone.gd` | Agua | — | **SÍ** |

### 1.4 `vfx/` — efectos

| Archivo | Tipo | Función | Sistema | Depende de | Necesario |
| --- | --- | --- | --- | --- | --- |
| `water_effects.gd` | Script | **Fábrica de efectos** (estáticos): salpicadura, gotas, espuma, ondas, burbujas, corriente, orbe. Los efectos no deciden nada: solo dibujan | VFX | `water_particle.gdshader`, `water_ring.gdshader`, `water_orb.gdshader` | **SÍ** |
| `water_charge.gd` | Script | Agua que se junta en las manos mientras se carga un hechizo (sigue el hueso de la mano) | VFX | `water_particle.gdshader` | **SÍ** |
| `underwater_view.gd` | Script | Vista subacuática: niebla, velo de pantalla y motas (según la profundidad de la **cámara**) | VFX | `underwater_overlay.gdshader`, `water_particle.gdshader` | **SÍ** |
| `water_particle.gdshader` | Shader | Gota de agua procedural (degradado radial) | VFX | — | **SÍ** |
| `water_ring.gdshader` | Shader | Anillo/onda que se abre sobre el agua | VFX | — | **SÍ** |
| `water_orb.gdshader` | Shader | Orbe/burbuja de agua (con refracción) | VFX | — | **SÍ** |
| `underwater_overlay.gdshader` | Shader | Velo de pantalla bajo el agua (tinte + ondulación + viñeta) | VFX | — | **SÍ** |

### 1.5 `ui/`, `models/` y `animations/`

| Archivo | Tipo | Función | Sistema | Depende de | Necesario |
| --- | --- | --- | --- | --- | --- |
| `ui/aim_reticle.gd` | Script (`CanvasLayer`) | Retícula en el centro de la pantalla mientras se apunta (azul sin objetivo, naranja con objetivo) | UI | `player.gd` (`is_aiming()`, `get_aim_phase()`, `get_aim_target()`) | **SÍ** |
| `models/futuristic_armor_character.tscn` | Escena | **Modelo final**: malla skinned (52 uniones), esqueleto de 65 huesos Mixamo y material PBR. Reparado (vértices sin peso) | Personaje | Texturas propias en `models/textures/` | **SÍ** |
| `models/textures/tripo_…_2.png` | Textura | **Albedo** del modelo (4096×4096, VRAM/S3TC) — la copia que viaja DENTRO del módulo | Personaje | — | **SÍ** |
| `models/textures/tripo_…_3.png` | Textura | **Normal map** del modelo (2048×2048) — la copia que viaja DENTRO del módulo | Personaje | — | **SÍ** |
| `animations/player_animations.tres` | `AnimationLibrary` | **Todos los clips** del personaje (locomoción, aire, daño, combo, agua, habilidades) | Animación | — (se regenera con `tools/animation/`) | **SÍ** |
| `animations/player_animation_tree.tres` | `AnimationNodeBlendTree` | `TimeScale` → máquina de estados con todas las transiciones y sus tiempos de mezcla | Animación | `player_animations.tres` (los clips por **nombre**) | **SÍ** |

### 1.6 `scenes/` — prueba y desarrollo

| Archivo | Tipo | Función | Sistema | Depende de | Necesario |
| --- | --- | --- | --- | --- | --- |
| `player_test.tscn` | Escena | **ESCENA DE PRUEBA/DESARROLLO**: suelo, plataformas, rampa, el lago y tres maniquíes. Es la escena principal del proyecto | Pruebas | `character/player.tscn`, `water/lake.tscn`, `scenes/training_dummy.tscn` | NO (recomendable para probar) |
| `training_dummy.tscn` + `.gd` | Escena + Script | Maniquí de entrenamiento: vida, daño, atrapado y derribo. Implementa el contrato de objetivo | Pruebas | `vfx/water_effects.gd` | NO |
| `README.md` (en `aquatic_transformation/`) | Doc | Puerta de entrada al módulo | — | — | NO |

### 1.7 `docs/`

| Archivo | Función |
| --- | --- |
| `INTEGRATION_GUIDE.md` | Cómo integrar el módulo en otro proyecto (qué copiar y qué comprobar) |
| `FILE_MAP.md` | Este documento |
| `CLEANUP_LOG.md` | Qué se eliminó en la limpieza y qué se conservó |
| `guia_personaje_3d.md` | Guía técnica completa del sistema (diseño, animación, agua, habilidades) |

---

## 2. Fuera del módulo

| Ruta | Tipo | Función | Sistema | Necesario |
| --- | --- | --- | --- | --- |
| `tests/test_player_system.gd` | Script de pruebas | Batería de pruebas del personaje (estructura, huesos, animación, agua, habilidades, combo) | Pruebas | NO (recomendable) |
| `tools/animation/` | Herramientas | Horneado de clips, retargeting, postura, hojas de revisión | Herramientas | **SOLO DEV** |
| `tools/model/` | Herramientas | Reconstrucción de la escena del modelo desde el FBX | Herramientas | **SOLO DEV** |
| `tools/review/` | Escenas | Hojas de revisión (regenerables) | Herramientas | **SOLO DEV** |
| `tools/legacy/` | Herramientas | Tuberías antiguas (placeholder procedural, personaje OBJ) | Herramientas | **SOLO DEV** (no ejecutar: dos de ellas sobrescriben recursos actuales) |
| `source_assets/movements_update/` | FBX | PACK M: respiración, caminata, carrera y golpes | Assets de origen | NO (solo para rehornear) |
| `source_assets/attacks_update/` | FBX | PACK A2: apuntado con la bola (caminar/correr/strafe/agachado) y magia | Assets de origen | NO |
| `source_assets/aura_pack/` | FBX | PACK A: daño, derribos, suelo, caminar atrás (34 clips) | Assets de origen | NO |
| `source_assets/standard_library/` | GLB/FBX | PACK B: `Animation Library[Standard]` (idle, jog, sprint, agachado, salto, esquiva) | Assets de origen | NO |
| `source_assets/swim_clips/` | FBX | PACK W: natación (`Treading Water`, `Swimming`, `Swimming To Edge`) | Assets de origen | NO |
| `source_assets/ability_clips/` | FBX | PACK H: los cuatro ataques mágicos de dos manos | Assets de origen | NO |
| `source_assets/character_model_fbx/` | FBX + PNG | Modelo de origen del personaje (el que usa `tools/model/`) | Assets de origen | NO |
| `source_assets/legacy_armor_obj/` | OBJ + JPG/PNG | Modelo antiguo construido desde el OBJ (LEGACY) | Assets de origen | NO |
| `source_assets/unreferenced_textures/` | JPG/PNG | Texturas sueltas que estaban en la raíz, **sin referencia** (se conservan) | Assets de origen | NO |
| `addons/ziva_agent/` | Addon | Herramienta del asistente usada en el desarrollo | — | NO (excluir al empaquetar) |
| `.godot/` | Caché | Caché e importación del editor | — | NO (se regenera) |

---

## 3. Apéndice: rutas anteriores → rutas actuales

Para quien tenga apuntes, capturas o ramas antiguas con las rutas viejas:

| Antes | Ahora |
| --- | --- |
| `res://characters/player/*` | `res://personaje/transformaciones/acuatica/character/*` |
| `res://characters/player/abilities/*` | `res://personaje/transformaciones/acuatica/abilities/*` |
| `res://characters/player/vfx/*` | `res://personaje/transformaciones/acuatica/vfx/*` |
| `res://characters/player/ui/*` | `res://personaje/transformaciones/acuatica/ui/*` |
| `res://characters/player/player_animations.tres` | `res://personaje/transformaciones/acuatica/animations/player_animations.tres` |
| `res://characters/player/player_animation_tree.tres` | `res://personaje/transformaciones/acuatica/animations/player_animation_tree.tres` |
| `res://characters/player/water_detection.gd` | `res://personaje/transformaciones/acuatica/water/water_detection.gd` |
| `res://characters/models/*` | `res://personaje/transformaciones/acuatica/models/*` |
| `res://worlds/water/*` | `res://personaje/transformaciones/acuatica/water/*` |
| `res://worlds/player_test.tscn` | `res://personaje/transformaciones/acuatica/scenes/player_test.tscn` |
| `res://worlds/training_dummy.*` | `res://personaje/transformaciones/acuatica/scenes/training_dummy.*` |
| `res://worlds/armor_preview.tscn` | `res://tools/legacy/armor_preview.tscn` |
| `res://characters/armor/futuristic_armor_character.tscn` | `res://tools/legacy/armor_character_legacy.tscn` |
| `res://characters/placeholder/placeholder_character.tscn` | `res://tools/legacy/placeholder_character.tscn` |
| `res://docs/guia_personaje_3d.md` | `res://personaje/transformaciones/acuatica/docs/guia_personaje_3d.md` |
| `res://Actualizacion movimientos/` | `res://source_assets/movements_update/` |
| `res://Actualizacion ataques/` | `res://source_assets/attacks_update/` |
| `res://Animaciones con aura/` | `res://source_assets/aura_pack/` |
| `res://Animation Library[Standard]/` | `res://source_assets/standard_library/` |
| `res://animaciones personaje acuatico/` | `res://source_assets/swim_clips/` |
| `res://ataques personaje acuatico/` | `res://source_assets/ability_clips/` |
| `res://futuristic+armor+3d+model/` | `res://source_assets/character_model_fbx/` |
| `res://futuristic armor 3d model 2/` | `res://source_assets/legacy_armor_obj/` |
| `res://tools/pack_animation_builder.gd` | `res://tools/animation/pack_animation_builder.gd` |
| `res://tools/clip_baker.gd`, `rig_baker.gd`, `stance_fixer.gd`, `idle_arms.gd`, `clip_probe_column.gd`, `state_sheet_builder.gd`, `clip_probe_builder.gd` | `res://tools/animation/…` |
| `res://tools/build_pack_animations.gd`, `build_stance_fix.gd`, `build_clip_probe.gd`, `_run_rebuild.*` | `res://tools/animation/…` |
| `res://tools/model_scene_builder.gd`, `build_model_character.gd` | `res://tools/model/…` |
| `res://tools/hoja_*.tscn`, `probe_*.tscn`, `_check_hilito.tscn` | `res://tools/review/…` (el último ahora es `check_model_mesh.tscn`) |
| `res://tools/armor_rig_builder.gd`, `build_armor_character.gd`, `placeholder_generator.gd`, `generate_placeholder_character.gd`, `generate_model_animations.gd`, `idle_polish.gd`, `build_idle_polish.gd` | `res://tools/legacy/…` |