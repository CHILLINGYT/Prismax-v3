# CLEANUP_LOG — Registro de la limpieza

Registro de **todo lo que se eliminó** durante la reorganización del módulo
acuático, con el motivo y la comprobación que se hizo antes de borrarlo.

Regla aplicada: **no se eliminó nada por el simple hecho de no estar
referenciado**. Cada archivo de esta lista es:

* temporal o de diagnóstico **auto-declarado** en su propio encabezado, o
* un render/artefacto de inspección **sin ninguna referencia**, o
* un **duplicado verificado byte a byte** (MD5) y sin referencias por ruta **ni
  por UID**.

---

## 1. Sondas y scripts temporales

| Archivo | Tipo | Motivo | Comprobación |
| --- | --- | --- | --- |
| `res://tools/_t1.gd` | Script | Su encabezado dice literalmente «sonda temporal de diagnostico; ya no se usa» y define `const NOTA := "sin uso"` | Sin referencias en el proyecto |
| `res://tools/_t2.gd` | Script | ídem | Sin referencias |
| `res://tools/_t3.gd` | Script | ídem | Sin referencias |
| `res://tools/_diag_idle_pose.gd` | Script de diagnóstico | «Diagnóstico temporal»: medía la pose del idle y escribía en `.godot/idle_pose_diag.txt` | Sin referencias; su salida vivía en la caché del editor |
| `res://tools/_method_track_probe.gd` + `.tscn` | Sonda | «Sonda temporal… se puede borrar después»: comprobó que el `AnimationTree` dispara las pistas de método (el sistema de habilidades ya depende de ellas, así que cumplió su función) | Sin referencias |
| `res://worlds/_probe_idle.gd` + `.tscn` | Sonda | «SONDA DE POSTURA (temporal)… No forma parte del juego» | Sin referencias |
| `res://worlds/_probe_camara_abajo.gd` | Sonda | «Sonda TEMPORAL: cámara metida en el agua…» | Sin referencias |
| `res://worlds/_probe_subacuatica.tscn` | Escena de sonda | Envolvía la sonda de cámara subacuática | Sin referencias |

## 2. Renders y artefactos de inspección

| Archivo | Tipo | Motivo |
| --- | --- | --- |
| `res://tools/_probe_bottom.png`, `_probe_front.png`, `_probe_side.png`, `_probe_top.png` (+ `.import`) | Renders | Vistas ortográficas del modelo en T-pose, generadas solo para inspección. Verificado visualmente antes de borrar |
| `res://tools/_render_abajo_frente.png`, `_render_abajo_lado.png`, `_render_frente.png`, `_render_lado.png`, `_render_trescuartos.png` (+ `.import`) | Renders | Renders del modelo para revisión visual. Verificado visualmente antes de borrar |
| `res://tools/_grid_a.tscn`, `_grid_b.tscn`, `_grid_swim.tscn`, `_grid_attacks.tscn` | Escenas generadas **huérfanas** | Hojas de contactos de clips antiguas: **no hay ninguna herramienta en el proyecto que las genere** (las hojas actuales las producen `tools/animation/clip_probe_builder.gd` → `tools/review/probe_clips.tscn` y `state_sheet_builder.gd` → `tools/review/hoja_*.tscn`). Se pueden rehacer con esas herramientas |

> Los `.import` de los PNG **no se pudieron borrar con la herramienta** (rutas
> protegidas). Godot los limpia solo al detectar que su archivo fuente ya no
> existe; no afectan al proyecto.

## 3. Archivo accidental

| Archivo | Tipo | Motivo |
| --- | --- | --- |
| `res://node_3d.tscn` | Escena vacía | Escena por defecto de un único `Node3D` creada en la raíz por accidente. Sin uso y sin referencias |

## 4. Duplicados verificados

Comprobación hecha **antes** de eliminar, para cada carpeta: (1) mismos archivos
y mismos tamaños; (2) **mismo MD5 byte a byte** del contenido (los `.fbx`, `.glb`,
`.png`, `License.txt` eran idénticos; solo diferían los `.import`, que Godot
regenera porque codifican la ruta); (3) ninguna referencia a la ruta desde el
resto del proyecto; (4) **ninguna referencia a sus UID** desde el resto del
proyecto (se escanearon los 51 UID que registraban: cero coincidencias).

| Duplicado eliminado | Copia de referencia que se conserva | Tamaño liberado |
| --- | --- | --- |
| `res://characters/Universal_Animation_LibraryStandard/Animation Library[Standard]/` | `res://source_assets/standard_library/` | ~55,2 MB |
| `res://tests/Universal_Animation_LibraryStandard/Animation Library[Standard]/` | ídem | ~55,2 MB |
| `res://addons/Universal_Animation_LibraryStandard/Animation Library[Standard]/` | ídem | ~55,2 MB |
| `res://docs/Animation Library[Standard]/` | ídem | ~55,2 MB |
| `res://Animaciones con aura/Animation Library[Standard]/` (anidada en el PACK A) | ídem | ~55,2 MB |
| `res://characters/animaciones personaje acuatico/` | `res://source_assets/swim_clips/` | ~6,3 MB |
| `res://addons/animaciones personaje acuatico/` | ídem | ~6,3 MB |
| `res://futuristic armor 3d model 2/animaciones personaje acuatico/` | ídem | ~6,3 MB |
| `res://characters/ataques personaje acuatico/` | `res://source_assets/ability_clips/` | ~8,3 MB |
| `res://docs/ataques personaje acuatico/` | ídem | ~8,3 MB |
| `res://Animation Library[Standard]/ataques personaje acuatico/` (anidada) | ídem | ~8,3 MB |

**Total liberado: ≈ 319 MB.**

## 5. Carpetas vacías

Tras mover sus archivos al módulo, se eliminaron las carpetas que quedaron
vacías: `res://characters/`, `res://worlds/`, `res://docs/` y `res://addons/`
(esta última, además, tras borrar sus copias duplicadas).

Aviso: el script que retiraba carpetas vacías recorrió también
`res://addons/ziva_agent/` y retiró **solo carpetas vacías** de plataformas no
usadas (`bin/linux_*`, `bin/macos`, `bin/windows_arm64`, `zivacode/…`,
`bin-deps/…`). **No se borró ningún archivo**: los binarios reales del asistente
(Windows x64) siguen intactos.

---

## 6. CONSERVADOS a propósito (aunque parezcan prescindibles)

| Archivo | Por qué se conserva |
| --- | --- |
| `res://tools/animation/_run_rebuild.gd` + `.tscn` | Aunque su encabezado dice «runner temporal», es **el único camino que funciona aquí para rehornear las animaciones**: en este entorno el subproceso `--headless` no arranca, así que este runner (que se lanza desde el editor) es la herramienta real de reconstrucción |
| `res://tools/review/hoja_*.tscn`, `probe_clips.tscn`, `probe_phases.tscn`, `probe_model.tscn`, `probe_models.tscn` | Hojas de revisión **regenerables** por las herramientas actuales; se conservan como documentación visual del resultado |
| `res://tools/review/check_model_mesh.tscn` (antes `_check_hilito.tscn`) | Comprueba que la malla no tiene vértices sin peso (el «hilo» del cuello). Útil si se vuelve a importar el modelo |
| `res://source_assets/unreferenced_textures/` (3 texturas) | Estaban sueltas en la raíz **sin ninguna referencia**. Se conservan (renombradas de carpeta) por ser texturas de origen, no porque estén en uso |
| `res://source_assets/aura_pack/` (34 FBX) | El juego usa 8 de esos clips; el resto **se conserva** por si se cambia la asignación de estados |
| `res://source_assets/standard_library/Unity|Unreal Engine/` | Variantes del mismo pack para otros motores: forman parte del pack original |
| `res://tools/legacy/` | Tuberías antiguas (placeholder procedural, personaje OBJ) conservadas como respaldo, **documentadas como peligrosas** de ejecutar |
| `res://addons/ziva_agent/` | Herramienta del asistente usada en el desarrollo: **no forma parte del módulo**, pero no se elimina. Se puede excluir al empaquetar el proyecto para entregarlo |
| `res://.godot/` | Caché del editor: **no se toca** (el proyecto está en uso). En la máquina del compañero se regenera sola al abrir el proyecto |