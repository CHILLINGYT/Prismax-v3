# Leo — módulo portable del personaje

Esta carpeta contiene **todo lo que es específico del personaje Leo** (un `CharacterBody3D`)
y sus recursos. Está pensada para poder **copiarse entera a otro proyecto de Godot** sin
mezclarse ni sobrescribir los archivos de ese proyecto.

---

## 1. Qué contiene

```
res://personaje/transformaciones/humano/
├── leo.tscn                         <- ESCENA PRINCIPAL del personaje (CharacterBody3D)
├── scripts/
│   ├── leo.gd                       <- movimiento, salto, agacharse, baile y animaciones
│   └── camara_tercera_persona.gd    <- cámara en 3.ª persona (la usa el nodo "pivote")
├── models/
│   └── Standing W_Briefcase Idle.fbx  <- malla/modelo del personaje (Mixamo) + su textura
├── animations/
│   ├── leo_animations.tres          <- AnimationLibrary con TODOS los clips que usa Leo
│   └── *.fbx                        <- clips originales de Mixamo (Walking, Fast Run, …)
│                                      usados para (re)generar la librería
└── previews/
    ├── t_pose.tscn / walking.tscn / leooo.tscn   <- escenas de previsualización de clips
```

La **escena principal** es `res://personaje/transformaciones/humano/leo.tscn`. Su nodo raíz se llama `leo`.

### Cómo está montada la escena `leo.tscn`
```
leo (CharacterBody3D)            <- script: scripts/leo.gd
├── CollisionShape3D  (CapsuleShape3D)
├── Modelo            <- instancia de models/Standing W_Briefcase Idle.fbx
├── Animador          (AnimationPlayer, librería: animations/leo_animations.tres)
└── pivote            (Node3D, script: scripts/camara_tercera_persona.gd)
    └── SpringArm3D
        └── Camera3D
```
Todas las rutas internas del personaje son **relativas a su propia escena** (`$pivote`,
`$Animador`, `Modelo/Skeleton3D:…`), por lo que no dependen de ninguna ruta absoluta
del proyecto que la hospeda.

---

## 2. Dependencias internas (van dentro de Leo)

- `leo.tscn` → `scripts/leo.gd`, `scripts/camara_tercera_persona.gd`,
  `models/Standing W_Briefcase Idle.fbx`, `animations/leo_animations.tres`.
- `scripts/leo.gd` → no carga ningún recurso por ruta (solo nodos hijos y la librería
  asignada al `AnimationPlayer`).
- `camara_tercera_persona.gd` → no depende de nada externo.
- `models/Standing W_Briefcase Idle.fbx` → su textura extraída
  `Standing W_Briefcase Idle_0.png` (misma carpeta).

Todo esto se mueve y funciona junto.

---

## 3. Dependencias EXTERNAS (lo que NO está en Leo y hay que tener en cuenta)

Leo es prácticamente autónomo. Solo necesita lo siguiente del proyecto destino:

| Dependencia | ¿Dónde está? | ¿Hay que hacer algo? |
|---|---|---|
| Acción **`ui_accept`** (salto) | Es una acción *incorporada* de Godot | Nada: existe en todo proyecto por defecto. Leo la usa con `Input.is_action_just_pressed("ui_accept")`. |
| Gravedad **`physics/3d/default_gravity`** | Ajuste de proyecto | Nada: tiene valor por defecto. |
| Motor de física (`Jolt Physics` / `Godot Physics`) | Ajuste de proyecto | Opcional. Leo funciona con cualquiera. |
| `class_name` **`CamaraTerceraPersona`** | Script `scripts/camara_tercera_persona.gd` | **Revisar**: es un identificador *global* de GDScript. Si el proyecto destino ya tuviera otra clase con ese nombre, habría conflicto. Ver §5. |
| Una escena que **instancie** `leo.tscn` | (tu nivel/mapa) | Añadir el personaje a tu mundo: instanciá `res://personaje/transformaciones/humano/leo.tscn`. |

**Importante:** Leo **no** usa ninguna de las acciones personalizadas del proyecto
(`adelante`, `izquierda`, `atras`, `derecha`). El movimiento se lee con teclas físicas
directas (`KEY_W/S/A/D`, `KEY_SHIFT`, `KEY_CTRL`, `KEY_R`) y el ratón. Por eso **no hay
que copiar ninguna Input Action**: solo la acción incorporada `ui_accept`.

Leo **no** usa autoloads, managers, sistemas de guardado ni singletons. Tampoco depende
de ninguna escena del mundo.

---

## 4. Inputs que usa el personaje

| Tecla / entrada | Función | Cómo se lee |
|---|---|---|
| `W` `A` `S` `D` | Moverse | `Input.is_key_pressed(KEY_…)` (teclas físicas) |
| `Shift` | Correr | `Input.is_key_pressed(KEY_SHIFT)` |
| `Ctrl` | Agacharse | `Input.is_key_pressed(KEY_CTRL)` |
| `Espacio` | Saltar | acción `ui_accept` |
| `R` | Baile (alternar) | `InputEventKey` / `KEY_R` |
| ratón | Girar a Leo | `InputEventMouseMotion` |
| **clic derecho** | Orbitar la cámara | `MOUSE_BUTTON_RIGHT` (cámara) |

---

## 5. Cómo integrar Leo en otro proyecto

1. Copiá la carpeta completa **`res://personaje/transformaciones/humano/`** dentro del proyecto destino.
   La carpeta se llama `Leo`, así que **no pisa** ninguna carpeta existente.
2. En tu escena de nivel, instanciá `res://personaje/transformaciones/humano/leo.tscn` (botón *Instanciar escena hija*)
   y colocalo donde quieras que aparezca el personaje.
3. Comprobá que exista la acción `ui_accept` (por defecto sí está).
4. **Revisá colisiones de `class_name`**: abrí `Leo/scripts/camara_tercera_persona.gd`.
   Si el proyecto destino ya define una clase `CamaraTerceraPersona`, renombrala aquí y
   actualizá la referencia en `Leo/scripts/leo.gd`
   (`@onready var cam: CamaraTerceraPersona = $pivote`).
5. Listo. Leo no necesita nada más del proyecto anfitrión.

### Qué revisar DESPUÉS de copiar
- Que `Leo/leo.tscn` abra sin “recursos faltantes”.
- Que el modelo se vea con su textura.
- Que `ui_accept` salte y que WASD mueva.

---

## 6. Notas de portabilidad

- **No depende de rutas absolutas** a otros nodos del proyecto.
- Los **nombres internos** de nodos se mantienen (`Modelo`, `pivote`, `Animador`, …) porque
  están referenciados por el script y por las pistas de animación (`Modelo/Skeleton3D:…`).
  Al instanciar la escena, el proyecto anfitrión puede renombrar el nodo instanciado sin
  problema: las rutas internas son relativas.
- Los `.import` de los `.fbx` apuntan a la caché de `res://.godot/imported/`. Godot los
  reimporta automáticamente al abrir el proyecto destino; no hay que copiar `.godot/`.
- Las **animaciones ya están embebidas** en `leo_animations.tres`, así que el personaje
  funciona sin necesidad de los `.fbx` de `animations/` (esos sirven solo para regenerar
  la librería).