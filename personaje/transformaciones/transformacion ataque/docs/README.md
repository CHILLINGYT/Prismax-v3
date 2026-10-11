# Módulo "transformación ataque"

Personaje 3D con combate estilo FreeFlow para **Godot 4.x**, empaquetado para copiarse a
otro proyecto sin reconstruir nada.

---

## A. ¿Qué es este módulo?

Es un personaje jugable completo, con su modelo esquelético, sus animaciones y su sistema
de combate. Se puede instanciar en cualquier escena 3D nueva y funciona solo: si la escena
no tiene un gestor de combate, el personaje crea el suyo.

Incluye:

- **Controlador en tercera persona**: movimiento relativo a la cámara, salto, gravedad.
- **Modelo visual esquelético** animado, con la cápsula de colisión como cuerpo físico real.
- **Sprint**: combo encadenado de cuatro golpes (jab → dos → cros → gancho) con buffer de
  entradas, ventanas de ataque, recuperación cancelable y sincronización del daño con la
  animación.
- **Targeting contextual**: se cambia de enemigo girando la cámara y empujando con WASD,
  sin menús ni bloqueo permanente del objetivo.
- **Reinicio del combo al cambiar de objetivo**, conservando el golpe que ya está en curso.
- **Acciones adicionales**: contraataque, evasión con invulnerabilidad, golpe aturdidor,
  remate, ataque especial y gadget de área.
- **Salud, daño, aturdimiento y muerte** del jugador, con señales para conectar tu propia UI.

Pensado para prototipos y juegos de acción en 3D. **No** incluye enemigos, mapa, HUD ni
menús: esas piezas son tuyas (el apartado H explica cómo conectarlas).

---

## B. Estructura de carpetas

```
transformacion ataque/
├── animations/
│   ├── pose t.fbx              Modelo + esqueleto de 33 huesos (la base visual).
│   ├── pose t.fbx.import       Ajustes de importación del FBX.
│   ├── pose t_0.png            Textura embebida, extraída por Godot al importar.
│   ├── pose t_0.png.import
│   └── player_anim_library.tres  Las 8 animaciones (idle, walk, combat_idle, jump,
│                                 jab, dos, cros, gancho). NO depende de los FBX.
├── docs/
│   └── README.md               Este documento.
├── resources/
│   └── combat_config.tres      Todos los parámetros de combate ajustables.
├── scenes/
│   ├── player.tscn             El personaje (CharacterBody3D). Esto es lo que instancias.
│   └── transformacion_ataque.tscn  Escena independiente: personaje + cámara + suelo.
└── scripts/
    ├── player.gd               Controlador: movimiento, estados, acciones, Sprint.
    ├── player_animator.gd      Reproduce las animaciones según el estado. No decide nada más.
    ├── camera_rig.gd           Cámara en tercera persona (sigue y orbita con el ratón).
    └── combat/
        ├── combat_manager.gd        Registro de enemigos + subsistemas.
        ├── combat_config.gd         Definición del recurso de configuración.
        ├── combat_targeting.gd      Selección de objetivo (dirección, distancia, amenaza).
        ├── attack_data.gd           Datos de un golpe (daño, fases, clip).
        ├── combo_system.gd          Contador de combo + buffer de entradas.
        ├── attack_token_manager.gd  Turnos: limita cuántos enemigos atacan a la vez.
        ├── combat_formation.gd      Anillo de posiciones alrededor del jugador.
        └── threat_system.gd         Avisos de ataque enemigo (para contraatacar).
```

Archivos importantes:

- **`scenes/player.tscn`**: el personaje. Contiene la cápsula, el modelo visual y el
  `AnimationPlayer`.
- **`scripts/player.gd`**: donde está toda la lógica del jugador, incluida la tabla del
  Sprint.
- **`resources/combat_config.tres`**: lo primero que querrás tocar para ajustar el combate.

---

## C. Cómo instalarlo en otro proyecto

1. **Copia la carpeta** `transformacion ataque/` dentro de `res://` del proyecto nuevo.
   La carpeta es autocontenida: todas sus rutas `res://` apuntan dentro de ella, así que no
   arrastra nada del proyecto original.
2. **Abre el proyecto en Godot** y deja que importe. Godot generará los `.uid`, importará el
   FBX y volverá a extraer la textura embebida (`pose t_0.png`) si falta.
3. **Abre la escena independiente** `res://transformacion ataque/scenes/transformacion_ataque.tscn`
   y ejecútala. Deberías ver al personaje sobre un suelo, con la cámara detrás.
4. **Configura las acciones de entrada** (ver la lista completa en el apartado I). Sin ellas
   el personaje avisa por consola indicando exactamente cuáles faltan.
5. **Configura la cámara**. La escena `player.tscn` trae la propiedad
   `camera_rig_path` con el valor por defecto `../CameraRig`. Si instancias el personaje en
   una escena con la cámara colocada como hermana, ya funciona. Si tu cámara está en otro
   sitio, escribe su ruta en esa propiedad, o deja la propiedad vacía y pon la cámara en el
   grupo `camera_rig`. Si no hay cámara, el personaje se mueve con los ejes del mundo.
6. **Instancia al personaje** en tu escena nueva: arrastra `scenes/player.tscn` o usa
   `preload("res://transformacion ataque/scenes/player.tscn").instantiate()`.
7. **Configura el suelo**: el personaje es un `CharacterBody3D` con `collision_mask = 5`
   (capas 1 y 3). Tu suelo debe estar en la capa 1. Hay un ejemplo mínimo en
   `transformacion_ataque.tscn`.
8. **Conecta los enemigos**: deben cumplir la interfaz del apartado H y registrarse con el
   `CombatManager`. Si no pones ninguno, el personaje igual se mueve, se anima y ejecuta el
   Sprint (golpeando al aire).
9. **Comprueba que funciona sin el proyecto original**: ejecuta solo tu escena nueva. No hace
   falta `main.tscn`, ni el mapa, ni los seis enemigos.

> Nota honesta: copiar la carpeta **sí** es suficiente para el código y los recursos (se
> verificó que no queda ninguna referencia fuera de ella), pero el proyecto de destino
> **debe** tener las acciones de entrada del apartado I. Sin ellas el personaje no responde.

---

## D. Cómo funciona el movimiento

Todo el movimiento vive en `scripts/player.gd` (`_physics_process` y el estado `FREE`).

- **Dirección relativa a la cámara**: `_input_dir()` lee `move_left/move_right` y
  `move_forward/move_back` con `Input.get_axis`, y las proyecta sobre los ejes de la cámara
  (`_camera_rig.global_transform.basis`), aplanando la componente vertical. Si no hay cámara
  asignada, usa los ejes del mundo.
- **Aceleración y frenado**: la velocidad horizontal se interpola con `acceleration`
  (moviéndose) o `deceleration` (parado) mediante `move_toward`.
- **Orientación**: `_face_dir()` gira el cuerpo suavemente hacia la dirección de avance, con
  `turn_speed`. Durante un ataque, `_turn_towards()` gira con un límite angular en rad/s
  (`player_turn_speed` del recurso de configuración) para no producir giros instantáneos.
- **Salto y gravedad**: la gravedad se aplica cuando el cuerpo no está en el suelo. Al pulsar
  salto estando en el suelo se aplica `jump_velocity`. La física la controla siempre el
  `CharacterBody3D`; **ninguna animación mueve al personaje**.
- **Máquina de estados**: `FREE`, `APPROACH`, `WINDUP`, `ACTIVE`, `RECOVERY`, `COUNTER`,
  `EVADE`, `HIT`, `DEAD`. Cada estado decide su propia velocidad; el movimiento libre solo
  ocurre en `FREE`.

---

## E. Cómo funcionan las animaciones

Las gestiona `scripts/player_animator.gd`, que **solo elige qué clip suena y a qué
velocidad**. No decide objetivos, no aplica daño y no bloquea la entrada: el movimiento y el
combate siguen siendo responsabilidad de `player.gd`.

Los clips se cargan desde `animations/player_anim_library.tres` y se registran en el
`AnimationPlayer` del personaje al arrancar.

| Situación del jugador | Clip |
|---|---|
| Quieto, sin combate reciente | `idle` |
| Quieto, después de atacar | `combat_idle` |
| Desplazándose | `walk` (velocidad de reproducción escalada con la velocidad real) |
| Saltando | `jump` |
| Golpe del Sprint 1..4 | `jab`, `dos`, `cros`, `gancho` |

- La locomoción solo se actualiza en los estados `FREE` y `APPROACH`. Durante un ataque, la
  evasión o el contraataque, el clip de la acción manda y no se pisa.
- **Caminar**: la velocidad del ciclo se escala con la velocidad horizontal real
  (`walk_reference_speed` = 3.47 m/s, medido del propio clip; los límites son 0.8–1.8). Así
  los pies no patinan cuando el personaje corre a 6 m/s.
- **Salto**: el clip se lanza al saltar y se mantiene mientras el personaje está en el aire
  reproduciendo ese mismo clip. Al aterrizar se vuelve automáticamente a caminar o al reposo.
- **Temporizador de idle de combate (10 s)**: se cuenta **desde el último INICIO de ataque**,
  no desde que apareció la pose de combate. Cada vez que arranca un golpe
  (`_start_windup()` llama a `notify_attack_started()`) el contador vuelve a cero. Mientras
  queden menos de 10 segundos, estar quieto reproduce `combat_idle`; pasados los 10 segundos,
  vuelve a `idle`. Si el jugador camina, se reproduce `walk` aunque esté en combate; y si se
  detiene antes de los 10 segundos, vuelve a `combat_idle`.

---

## F. Cómo funciona Sprint

La secuencia está en la constante `SPRINT` de `scripts/player.gd`:

| # | Golpe | Clip | Duración del clip | Instante de impacto | Brazo |
|---|---|---|---|---|---|
| 1 | jab | `jap-inicio}.fbx` | 0.467 s | 0.233 s | izquierdo |
| 2 | dos | `dos.fbx` | 0.600 s | 0.135 s | derecho |
| 3 | cros | `cros.fbx` | 0.733 s | 0.147 s | izquierdo (cruza el cuerpo) |
| 4 | gancho | `gancho.fbx` | 0.633 s | 0.327 s | derecho (gancho) |

**Fases.** Para cada golpe, `windup = impacto medido`, `active = 0.10 s` (ventana en la que se
resuelve el impacto) y `recovery = resto del clip`. El tiempo total de la acción es
exactamente la duración del clip, así que el golpe visual termina cuando termina el estado de
recuperación.

**El daño lo aplican los temporizadores, no la animación.** Es la única vía de daño, y
`_hit_done` garantiza que un golpe solo pueda impactar una vez. No hay eventos de animación
aplicando daño, así que no existe doble contabilización posible.

**Entrada y buffer.** Cada clic válido avanza un golpe. `combo_system.gd` guarda la pulsación
durante `input_buffer_time` (0.2 s) y `player.gd` la consume en cuanto el estado lo permite
(`_try_consume_buffered()`). La recuperación es cancelable: si hay una acción válida en el
buffer, el siguiente golpe arranca de inmediato en vez de esperar al final de la
recuperación. Las pulsaciones caducan, así que no se ejecutan ataques viejos.

**Reinicio de la secuencia.** Si el jugador deja cerrar el combo (sin pulsar dentro de la
ventana), la secuencia vuelve a empezar en `jab`. Después del cuarto golpe también vuelve a
`jab`.

---

## G. Cómo funciona el targeting

Está en `scripts/combat/combat_targeting.gd`. La selección ocurre **al iniciar cada acción**,
nunca a mitad de un golpe.

1. Se construye una **intención** direccional mezclando tres señales con pesos:
   dirección de movimiento (`weight_move_direction` = 4.0), dirección de la cámara
   (`weight_camera` = 2.5) y orientación actual del cuerpo (`weight_facing` = 1.0). Girar la
   cámara y empujar hacia un enemigo expresa "quiero golpear a ese" y cambia el objetivo al
   instante.
2. Se descartan los enemigos que no cumplen las condiciones:
   - deben estar **vivos** (`is_alive()`),
   - dentro de `target_radius` (9 m),
   - dentro del cono de `target_max_angle_deg` (140°) alrededor de la intención.
3. Los candidatos se puntúan por **alineación con la intención** (`weight_alignment` = 3.0,
   dominante), **distancia** (`weight_distance` = 1.0, complementaria, nunca decisiva),
   **amenaza activa** (`weight_threat`) y un pequeño bono por ser el objetivo actual
   (`current_target_bonus` = 0.3).
4. **Histéresis**: se mantiene el objetivo actual salvo que otro lo supere por
   `target_switch_threshold` (0.25). Eso evita el parpadeo entre candidatos parecidos, pero
   un giro claro de cámara gana de inmediato. **No existe bloqueo permanente del objetivo.**

No se elige "el más cercano": la distancia solo desempata.

**Cambio de objetivo durante un golpe**: el objetivo del golpe en curso queda fijado al
iniciarlo. Si al empezar la siguiente acción el targeting devuelve un enemigo distinto, el
Sprint se reinicia (`_chain_index = 0`), de modo que el siguiente golpe contra el nuevo
objetivo es siempre `jab`. El golpe anterior no se cancela, termina su fase, y su daño se
resolvió contra su propio objetivo.

---

## H. Cómo conectar nuevos enemigos

Un enemigo es **cualquier `Node3D`** que exponga estos métodos (se comprueban con
`has_method`, así que no necesitas heredar de ninguna clase del módulo):

| Método | Firma | Para qué |
|---|---|---|
| `is_alive()` | `-> bool` | El personaje ignora a los enemigos muertos al elegir objetivo. |
| `take_hit(amount, dir, knockback, stun)` | `(float, Vector3, float, float) -> bool` | Aplica el daño del golpe, el empuje y el aturdimiento. |
| `is_stunned()` | `-> bool` | Marca al enemigo como rematable. |
| `execute()` | `-> void` | Remate: el enemigo debe morir inmediatamente. |

Además debe **registrarse en el `CombatManager`** para que el targeting lo vea:

```gdscript
# Desde el propio enemigo, en _ready() o en el primer frame:
var mgr := get_tree().get_first_node_in_group("combat_manager")
if mgr != null and mgr.has_method("register_enemy"):
    mgr.register_enemy(self)

# Y al morir:
if mgr != null and mgr.has_method("unregister_enemy"):
    mgr.unregister_enemy(self)
```

Es importante usar `has_method` en vez de un cast al tipo del manager: si tu proyecto tiene su
propio gestor de combate, un cast fallaría porque el script es otro archivo.

**Opcionales** (solo si quieres que el personaje pueda contraatacarlos): registrar la amenaza
en el `ThreatSystem` durante la preparación del ataque, igual que hace el enemigo del sandbox:

```gdscript
mgr.threats.register(self, "melee", duracion_del_windup, true)
# y al terminar o ser interrumpido:
mgr.threats.clear_for(self)
```

El `CombatManager` que trae el módulo también ofrece `attack_token_manager` y
`combat_formation` para que varios enemigos se coordinen (limitar atacantes simultáneos y
repartirse alrededor del jugador), pero **el personaje no los necesita** para funcionar.

---

## I. Cómo modificar el comportamiento

| Qué quieres cambiar | Dónde |
|---|---|
| Velocidad, aceleración, frenado, salto, gravedad, giro libre | `scripts/player.gd`, grupo **Movement** del inspector |
| Nombres de las acciones de entrada | `scripts/player.gd`, grupo **Input actions** (ver abajo) |
| Cámara y gestor de combate | `scripts/player.gd`, grupo **Wiring** |
| Radio y ángulo de targeting, pesos, histéresis | `resources/combat_config.tres`, grupo **Targeting** |
| Daño base, alcance, distancia ideal, empuje, ventana de cancelación | `resources/combat_config.tres`, grupo **Player attack** |
| Nº máximo de enemigos atacando a la vez | `resources/combat_config.tres`, **max_attackers** |
| Anillo de enemigos y separación mínima | `resources/combat_config.tres`, grupo **Formation** |
| Duración del combo y del buffer de entradas | `resources/combat_config.tres`, grupo **Combo & input buffer** |
| Comportamiento enemigo (velocidad, daño, tiempos) | `resources/combat_config.tres`, grupo **Enemy** |
| Contraataque, evasión, aturdidor, remate, especial, gadget | `resources/combat_config.tres`, grupos **Counter**, **Evade**, **Stun / takedown**, **Special / gadget** |
| Giro del personaje hacia el objetivo, paciencia enemiga, sidestep | `resources/combat_config.tres`, grupo **Fluidity** |
| **Duración y daño de cada golpe del Sprint** | `scripts/player.gd`, constante `SPRINT` (y `HIT_WINDOW`) |
| Escalado de la animación de caminar, velocidad de las transiciones, 10 s del idle de combate | `scripts/player_animator.gd` (propiedades exportadas) |

**Acciones de entrada que necesita el módulo.** Ponlas en tu proyecto con estos nombres, o
renombra las propiedades del grupo *Input actions* para que apunten a las tuyas (el módulo
**no** modifica tu mapa de entrada):

| Propiedad | Nombre por defecto | Uso |
|---|---|---|
| `action_move_forward/back/left/right` | `move_forward`, `move_back`, `move_left`, `move_right` | Movimiento |
| `action_jump` | `jump` | Salto |
| `action_attack` | `combat_attack` | Golpe del Sprint |
| `action_counter` | `combat_counter` | Contraataque |
| `action_evade` | `combat_evade` | Evasión |
| `action_stun` | `combat_stun` | Golpe aturdidor |
| `action_special` | `combat_special` | Ataque especial |
| `action_takedown` | `combat_takedown` | Remate |
| `action_gadget` | `combat_gadget` | Gadget de área |

Si falta alguna, el personaje lo indica una vez por consola con la lista exacta.

---

## J. Limitaciones conocidas

**Implementado y verificado**

- Movimiento relativo a la cámara, salto, gravedad, colisiones.
- Sprint de cuatro golpes con buffer, cancelación de recuperación, sincronización del daño y
  protección contra impactos duplicados.
- Targeting contextual con cambio rápido y reinicio del Sprint al cambiar de objetivo.
- Idle, caminar, idle de combate (con temporizador de 10 s), salto y los cuatro golpes.
- Contraataque, evasión con invulnerabilidad, aturdidor, remate, especial y gadget (lógica).
- Autonomía: el personaje funciona en una escena vacía, sin gestor y sin enemigos.

**Limitaciones y cosas a saber**

1. **No hay animaciones para todo.** El paquete original solo trae idle, caminar, idle de
   combate, salto y los cuatro golpes. Los estados de **recibir impacto, aturdimiento, muerte,
   evasión, contraataque, aturdidor, especial, remate y gadget** no tienen clip propio: el
   personaje mantiene la animación anterior. No se inventaron sustituciones.
2. **El clip `cros` usa el brazo izquierdo**, no el derecho (medido: el brazo derecho barre
   solo 5° mientras el izquierdo barre 50° y cruza el cuerpo). Se integró tal cual porque así
   se pidió; el combo queda alternando izquierda/derecha.
3. **No incluye UI.** No hay barra de vida, contador de combo ni panel de derrota. El
   personaje expone las señales `health_changed(current, max_health)`, `died` y
   `combo_changed(count)` para que conectes la tuya. Los datos de objetivo y combo se pueden
   leer con `get_target()`, `get_state_name()` y `manager.combo.count`.
4. **Gestor propio vs. gestor del proyecto.** Si tu proyecto ya tiene un `CombatManager`
   propio (con otro script), el personaje no puede usarlo: crea el suyo. Es una limitación
   real de la comprobación de tipos de GDScript. Para compartir un único gestor, usa el que
   trae el módulo (`scripts/combat/combat_manager.gd`) como gestor del encuentro.
5. **La cámara no colisiona con los enemigos**: el `SpringArm3D` solo tiene máscara de capa 1
   (suelo). Los enemigos pueden tapar la vista. Es el comportamiento que ya tenía el
   proyecto original.
6. **El modelo y las animaciones vienen de un mismo FBX de estilo Mixamo**, con esqueleto de
   33 huesos. Las animaciones están horneadas en `player_anim_library.tres` con rutas de
   pista del tipo `Skeleton3D:mixamorig_*`, así que **solo funcionan con este modelo** (o con
   uno cuyo esqueleto use los mismos nombres de hueso). No hay retargeting.
7. **El personaje y sus copias del sandbox son divergentes.** El proyecto original conserva
   sus propios `scripts/player.gd` y compañía; este módulo es una copia adaptada (sin
   `class_name`, con acciones configurables y sin dependencias externas). Cambiar uno no
   cambia el otro.
8. **Sin red ni multijugador.** Nada del módulo está pensado para sincronización en red.

---

## K. Solución de problemas

**No se ven las animaciones / el personaje queda en pose de T**
- Comprueba que `animations/player_anim_library.tres` existe y que `scripts/player_animator.gd`
  apunta a esa ruta.
- Si el personaje aparece en T y quieto, es que el `AnimationPlayer` no tiene clips: mira la
  consola al arrancar.
- Si el FBX no se importó, selecciona `animations/pose t.fbx` en el editor y pulsa
  *Reimportar*. Godot volverá a extraer la textura embebida.

**El modelo no aparece (personaje invisible)**
- El nodo `Visual` debe ser hijo del `CharacterBody3D` y estar visible.
- Si ves la cápsula azul en lugar del personaje, es que has vuelto a hacer visible el nodo
  `Body`; el módulo lo oculta a propósito.
- Comprueba que `Visual` conserva su escala (184.5) y su giro de 180° en Y. El modelo original
  mide ~0.0098 unidades y mira hacia +Z; sin ese ajuste se ve diminuto y de espaldas.

**La cámara no sigue al personaje o no gira**
- `camera_rig_path` debe apuntar a un `Node3D` que tenga el script `camera_rig.gd` y su
  `target_path` apuntando al personaje. Si lo dejas vacío, se busca en el grupo `camera_rig`.
- Si no hay cámara, el movimiento funciona pero con los ejes del mundo.
- Para girar hay que hacer clic en la ventana: el script captura el ratón al arrancar (Escape
  lo libera y vuelve a capturarlo).

**"faltan acciones de entrada -> ..." en la consola**
- Crea esas acciones en *Proyecto → Mapa de entrada*, o cambia los nombres de las propiedades
  del grupo *Input actions* del personaje para que coincidan con las tuyas.

**El personaje ataca pero no hace daño**
- El enemigo no está registrado: llama a `manager.register_enemy(enemigo)`.
- Al enemigo le falta `is_alive()` o `take_hit(...)` con la firma correcta.
- El enemigo está fuera de `target_radius` (9 m) o fuera del cono de 140°: el personaje
  golpea al aire en vez de girarse solo.
- Está demasiado lejos para el golpe: el personaje se acerca solo (`APPROACH`), pero si el
  objetivo se aleja más rápido puede fallar el golpe.

**Los enemigos no se coordinan (todos atacan a la vez)**
- Deben pedir turno con `manager.tokens.request(self)` y soltarlo con `release(self)`; el
  nº máximo de atacantes simultáneos es `max_attackers` en `combat_config.tres`.

**El combo no avanza más allá de `jab`**
- La secuencia avanza solo si la siguiente pulsación llega **dentro de la ventana** (durante
  la recuperación). Si dejas que el combo se cierre, vuelve a `jab`. Aumenta
  `input_buffer_time` en `combat_config.tres` si quieres más margen.

**Errores al abrir el proyecto tras copiarlo**
- Si Godot avisa de un UID duplicado, cierra y vuelve a abrir el proyecto: es la reimportación
  inicial generando los `.uid` y el `.godot/imported` del FBX.