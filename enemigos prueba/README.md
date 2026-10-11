# enemigos prueba

Carpeta **autocontenida** con los enemigos cuerpo a cuerpo del prototipo FreeFlow.
Se puede copiar a otro proyecto de **Godot 4.7.2** y usar los enemigos sin llevarse el
resto del juego.

Todo lo que hay aquí dentro funciona sin el mapa principal, sin el personaje principal y
sin los scripts del sandbox. Está verificado: cargar `scenes/test_enemies.tscn` arranca
un combate completo con seis enemigos y un muñeco de pruebas.

---

## 1. Qué contiene la carpeta

```
enemigos prueba/
├── README.md                        este archivo
├── scenes/
│   ├── enemy.tscn                   LA ESCENA DEL ENEMIGO (esto es lo que instancias)
│   └── test_enemies.tscn            escena de prueba: arena + 6 enemigos + muñeco
├── scripts/
│   ├── enemy.gd                     comportamiento e IA (máquina de estados)
│   ├── test_enemy_spawner.gd        activa/desactiva oleadas en la partida (tecla G, ver §5.5)
│   └── combat/                      el "kit de encuentro" que el enemigo necesita
│       ├── combat_manager.gd        registro de enemigos y coordinación del encuentro
│       ├── combat_config.gd         todos los valores ajustables (Resource)
│       ├── attack_token_manager.gd  turnos de ataque (máx. atacantes a la vez)
│       ├── combat_formation.gd      reparto de posiciones del anillo alrededor del objetivo
│       ├── threat_system.gd         avisos de ataque inminente (telegrafiado)
│       └── combo_system.gd          combo e input buffer (lo usa el gestor, no el enemigo)
├── materials/
│   └── enemy.tres                   material rojo del cuerpo
├── resources/
│   └── combat_config.tres           configuración ajustada (la que usa la escena de prueba)
└── test/
    ├── test_player.gd               muñeco de pruebas (NO es parte reutilizable, ver §7)
    └── prueba_spawner.gd            prueba headless del spawner (6, reposición, desactivación)
```

**No hay animaciones ni `AnimationTree` para los enemigos**: no existen en el proyecto
original y no se han inventado. El enemigo es una cápsula con material, y su
"animación" es procedural, con `Tween`: se inclina hacia delante al preparar el golpe,
embiste al golpear y se cae de lado al morir. Lo que sí tiene es barra de vida,
parpadeo al recibir daño y cambio de color como aviso de ataque.

Los 6 scripts de `scripts/combat/` son **copias** de los del sistema de combate del
proyecto original (mismos archivos, solo con las rutas `preload` reescritas para que
apunten dentro de esta carpeta). Están aquí porque sin ellos el enemigo no ataca:
sin gestor, los enemigos rodean al objetivo pero nunca le pegan. Ver §6.3 si tu proyecto
ya tiene los suyos.

---

## 2. Qué escena abrir para probar

**`res://enemigos prueba/scenes/test_enemies.tscn`**

Ábrela y dale a ejecutar (F6). Verás una arena cerrada, seis enemigos rojos y un muñeco
azul de pruebas. Los enemigos lo detectan, se reparten alrededor, esperan turno y le van
quitando vida. La etiqueta sobre el muñeco muestra su vida en directo.

- **WASD** mueve al muñeco (ejes del mundo) para ver cómo los enemigos lo persiguen.
- **Espacio** salta, **R** lo revive.
- Los enemigos no usan ninguna tecla: su IA es autónoma.

La escena no necesita nada del juego original: tiene su propio gestor, su propia
configuración, su suelo y su luz.

---

## 3. Cómo copiar la carpeta a otro proyecto

1. Copia entera la carpeta `enemigos prueba/` dentro de la carpeta de tu proyecto Godot 4.7.2.
2. En Godot, *Proyecto → Recargar proyecto actual* (o cierra y abre el editor) para que
   importe los recursos y genere los `.uid` que falten.
3. Abre `res://enemigos prueba/scenes/test_enemies.tscn` y comprueba que se ejecuta.
4. Si funciona ahí, ya puedes instanciar `scenes/enemy.tscn` en tus propias escenas (§4).

No hace falta copiar ninguna entrada del mapa de acciones (los enemigos no leen teclado),
ni autoloads, ni ajustes de proyecto. La carpeta no contiene ninguna ruta `res://` que
salga de ella misma, y ninguno de sus scripts declara `class_name`, así que no puede
chocar con clases globales que ya tengas.

---

## 4. Cómo instanciar un enemigo en una escena

### 4.1 Desde el editor

1. Arrastra `scenes/enemy.tscn` a tu escena 3D. Aparece como `Enemy`.
2. Colócalo sobre el suelo: el nodo raíz está a la altura de **los pies**, la cápsula
   ocupa de `y=0` a `y=2`. Se apoya solo en el suelo con la gravedad.
3. Repite para tantos enemigos como quieras. Se reparten solos alrededor del objetivo.
4. Añade un `CombatManager` si no lo tienes (§6.3) o deja que cada enemigo use el suyo.

### 4.2 Por código

```gdscript
const ENEMIGO := preload("res://enemigos prueba/scenes/enemy.tscn")

func _spawn() -> void:
	var e: CharacterBody3D = ENEMIGO.instantiate()
	e.global_position = Vector3(4.0, 0.0, 0.0)
	add_child(e)
```

### 4.3 Requisitos físicos

| Ajuste | Valor | Por qué |
|---|---|---|
| `collision_layer` del enemigo | `4` | el jugador lo golpea por capa |
| `collision_mask` del enemigo | `7` | choca con suelo (1), jugador (2) y otros enemigos (4) |
| Suelo | capa `1` | es lo que usa el proyecto original |

Si tu juego usa otras capas, edita `collision_layer` / `collision_mask` en el nodo raíz
de cada enemigo. Si el suelo no está en la máscara del enemigo, se cae al vacío.

### 4.4 Nodos internos que el script espera por nombre

No renombres estos nodos, el script los busca por nombre y, si no están, pierde funciones
en silencio (no da error):

| Nodo | Para qué |
|---|---|
| `Body` (`MeshInstance3D`) | cuerpo visible, parpadeo de daño y aviso de ataque |
| `HealthBar` (`Node3D`) | barra de vida flotante (se orienta hacia la cámara sola) |
| `HealthBar/Fill` (`MeshInstance3D`) | relleno de la barra; su ancho se escala con la vida |

---

## 5. Cómo conectar el enemigo con el jugador

El enemigo no depende del personaje del proyecto: se conecta a **cualquier cosa** que
cumpla una interfaz mínima. Tiene dos formas de encontrarla.

### 5.1 Automática (grupo `player`)

Cualquier nodo que se meta en el grupo `player` se convierte en el objetivo:

```gdscript
extends CharacterBody3D

var health: float = 100.0

func _ready() -> void:
	add_to_group("player")        # así lo encuentran los enemigos

func is_alive() -> bool:          # el enemigo deja de atacarlo si devuelve false
	return health > 0.0

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
```

Con eso ya lo persiguen, lo rodean y le hacen daño. El personaje principal del proyecto
original cumple esta interfaz tal cual (`is_alive()` y `take_damage(amount)`).

### 5.2 Explícita (inspector)

Si no quieres usar grupos, rellena en el inspector del enemigo:

- **Wiring → Target Path**: ruta al nodo objetivo (por ejemplo `../Player`).
- **Wiring → Combat Manager Path**: ruta al gestor del encuentro (por ejemplo `../CombatManager`).

La ruta explícita tiene prioridad; si está vacía, se usa el grupo.

### 5.3 Si el objetivo desaparece

Cuando `is_alive()` devuelve `false` o el nodo se libera, el enemigo vuelve a `IDLE` y
espera. Si no hay ningún objetivo, se queda quieto sin dar errores.

### 5.4 Cambiar el muñeco de pruebas por tu personaje

En `scenes/test_enemies.tscn`, borra el nodo `TestPlayer` y pon el tuyo (o instancia el
personaje de tu juego) dejándolo en el grupo `player` o apuntando el `target_path` de los
enemigos a él. Puedes borrar entonces la carpeta `test/` completa: no la usa nada más.

### 5.5 Spawner de prueba para la partida (tecla G)

`scripts/test_enemy_spawner.gd` es un nodo opcional que activa y desactiva seis enemigos
alrededor del jugador **en cualquier momento de la partida**, sin recargar la escena:

- **G** (acción `enemigos_prueba`) alterna: genera 6 enemigos en un anillo de 4,5–8 m
  alrededor de la posición ACTUAL del jugador (grupo `player`), o retira sólo los suyos.
- Cada aparición se valida con física real: suelo con pendiente razonable, al nivel del
  jugador (nada de tejados ni cornisas), hueco de cápsula libre (sin edificios, muros,
  props, el jugador ni otros enemigos) y separación mínima entre apariciones. Si un punto
  está ocupado se prueban ángulos y radios alternativos; si no se encuentran seis sitios
  válidos, lo informa por consola con `push_warning` y genera los que pueda.
- Si un enemigo generado desaparece (muere), el sistema **repone** hasta mantener seis,
  pero nunca duplica: activar dos veces cuenta lo existente antes de generar, y mantener
  la tecla pulsada no hace nada extra (sólo actúa al pulsarla).
- Al desactivar retira SOLO los enemigos que generó él; no toca a nadie más.

Para usarlo en una escena: añade un nodo con el script y un gestor del encuentro
(`scripts/combat/combat_manager.gd` con su `resources/combat_config.tres`) en la misma
escena, para que los enemigos además ataquen coordinados. En este proyecto está instalado
en la partida (`res://ziba/escenas/ziba_prototipo.tscn`, nodos `EnemigosPrueba` y
`GestionEnemigosPrueba`) y el jugador cumple la interfaz de §5.1.

Interfaz pública: `alternar()`, `activar()`, `desactivar()`, `esta_activo()`, `contar()`.

Prueba automatizada: `godot --headless -s "res://enemigos prueba/test/prueba_spawner.gd"`.

---

## 6. Cómo configurar vida, daño y comportamiento

### 6.1 Vida (por enemigo, en el inspector)

- **Stats → Max Health** (`max_health`, por defecto `100`). Es la vida de esa instancia.
  El campo `enemy_max_health` de la configuración existe pero el script del enemigo no lo
  lee: la vida se pone por instancia.

### 6.2 Movimiento (por enemigo, en el inspector)

- **Movement → Acceleration** (`14`), **Gravity** (`22`), **Turn Speed** (`10`).

### 6.3 Comportamiento (compartido, en `resources/combat_config.tres`)

Todos los enemigos leen los mismos valores desde un `Resource` (`scripts/combat/combat_config.gd`).
Los que usa el enemigo:

| Campo | Por defecto en el `.tres` | Qué hace |
|---|---|---|
| `enemy_detection_range` | `12.0` | distancia a la que pasa de `IDLE` a `ALERT` |
| `enemy_move_speed` | `3.5` | velocidad al acercarse |
| `enemy_attack_range` | `1.8` | distancia a la que decide atacar |
| `enemy_windup` | `0.5` | segundos de aviso antes del golpe (se pone naranja) |
| `enemy_active` | `0.15` | ventana en la que el golpe hace daño |
| `enemy_recovery` | `0.8` | recuperación tras golpear (aquí suelta el turno) |
| `enemy_damage` | `10.0` | daño por golpe |
| `enemy_hit_stun` | `0.25` | aturdimiento al recibir un golpe (y duración del parpadeo) |
| `enemy_death_linger` | `0.5` | cuánto tarda el cuerpo en desaparecer |
| `formation_radius` | `2.5` | radio del anillo alrededor del objetivo |
| `formation_min_separation` | `1.3` | separación mínima entre enemigos |
| `wait_patience` | `1.2` | segundos esperando turno antes de buscar otro ángulo |
| `stall_time` | `0.4` | segundos atascado antes de rodear al que le bloquea |
| `sidestep_time` | `0.55` | duración del rodeo lateral |
| `max_attackers` | `2` | cuántos enemigos pueden atacar a la vez |

`resources/combat_config.tres` es una copia de la configuración ajustada del proyecto
original. Si no asignas ninguna configuración al gestor, se usan los valores por defecto
del script (que difieren en `formation_radius`: `2.2` en vez de `2.5`).

Editar el `.tres` afecta a todos los enemigos que usen ese gestor. Para dos
comportamientos distintos, crea dos `.tres` y usa dos gestores en escenas separadas.

### 6.4 Máquina de estados (lo que ya está implementado)

`IDLE → ALERT → APPROACH ⇄ WAIT → WINDUP → ACTIVE → RECOVERY → APPROACH`,
más `HIT` y `STUN` al recibir daño y `DEAD` al morir.

- **WAIT** no es estar parado: espera un turno de ataque, se coloca en su hueco del anillo
  y, si se aburre (`wait_patience`), se desplaza lateralmente buscando ángulo.
- **WINDUP** es el aviso: se pone naranja (`_set_tell`). Un jugador puede reaccionar ahí.
- **RECOVERY** es la ventana de castigo: suelta el turno y otro compañero puede entrar.
- Ataques simultáneos limitados por `max_attackers` (cola FIFO justa, no por cercanía).

---

## 7. Interfaz pública del enemigo (para tu propio jugador o IA)

```gdscript
# --- Lo que el enemigo necesita DE TI (objetivo) ---
is_alive() -> bool                 # opcional: si no existe, se le supone vivo
take_damage(amount: float)         # opcional: si no existe, el golpe no hace nada
global_position                    # obligatorio (es un Node3D)

# --- Lo que TÚ puedes llamar en el enemigo ---
is_alive() -> bool
is_stunned() -> bool
get_state_name() -> String         # "IDLE", "APPROACH", "WINDUP", ...
take_hit(amount: float, hit_dir: Vector3, knockback: float, stun_time: float) -> bool
take_damage(amount: float)         # atajo: sin dirección ni aturdimiento
stun(duration: float)
on_countered(counter_stun: float)  # cuando el jugador contrarresta su ataque
execute()                          # remate: derrota al instante a un enemigo aturdido

# --- Señal ---
died(enemy: Node3D)
```

### Ejemplos reales

```gdscript
# Golpe del jugador (esto es exactamente lo que hace scripts/player.gd del proyecto)
if enemigo.is_alive() and enemigo.has_method("take_hit"):
	enemigo.take_hit(daño, direccion, empuje, 0.0)

# Contraataque: si el enemigo avisa (WINDUP) y lo contrarrestas, queda aturdido
if enemigo.is_stunned():
	pass

# Remate estilo FreeFlow
if enemigo is Node3D and enemigo.is_stunned():
	enemigo.execute()

# Saber cuándo muere
enemigo.died.connect(func(e: Node3D) -> void: print("ha muerto ", e.name))
```

### Qué necesita del exterior

| Necesita | ¿Obligatorio? | Cómo se conecta |
|---|---|---|
| Un objetivo con `take_damage` / `is_alive` | sí, para que ataque | grupo `player` o `target_path` |
| Un gestor de encuentro | sí, para que ataque | grupo `combat_manager` o `combat_manager_path` incluye uno en `scripts/combat/` |
| Una cámara 3D | no | solo para orientar la barra de vida |
| Acciones de entrada | **ninguna** | los enemigos no leen teclado |
| Grupos | se registra en `enemies` | de ahí saca la separación entre compañeros |

Grupos que el enemigo **lee**: `enemies` (separación y rodeo), `player` (objetivo),
`combat_manager` (gestor). El único que **escribe** es `enemies`.

### Interfaz que debe cumplir un gestor propio (si no usas el incluido)

```gdscript
# Propiedades
config                              # Resource con los campos de §6.3
tokens                              # request(e) / has_token(e) / release(e) / cancel(e)
formation                           # has_slot(e) / get_slot(e) -> Vector3
threats                             # register(e, tipo, duración, ¿bloquea?) / clear_for(e)

# Métodos
register_enemy(enemy) -> void
notify_enemy_died(enemy) -> void
```

El enemigo comprueba `has_method("register_enemy")` y `has_method("notify_enemy_died")`
antes de aceptar un gestor, así que no está atado a un archivo concreto: si tu proyecto
ya tiene un gestor de combate con esa interfaz, apunta el `combat_manager_path` a él y
borra `scripts/combat/` de esta carpeta.

---

## 8. Qué hacer si algo no se encuentra después de copiar

| Síntoma | Causa y solución |
|---|---|
| Al abrir el editor: `Failed to load resource` sobre un `.gd` o `.tres` | La carpeta se copió a medias o con otra ruta. Debe estar exactamente en `res://enemigos prueba/`, porque las rutas internas son absolutas a esa carpeta. Si quieres otro nombre, renómbrala y busca-y-reemplaza `res://enemigos prueba/` en los 6 scripts y en los 2 `.tres`. |
| Faltan `.uid` | Normal: Godot los genera al importar. Recarga el proyecto. No son necesarios para que funcione. |
| La escena carga pero los enemigos **no atacan** (solo caminan y esperan) | No encuentran gestor. Comprueba que hay un nodo con `combat_manager.gd` en la escena, o rellena **Combat Manager Path**. Sin gestor no hay turnos de ataque. |
| Los enemigos **no se mueven** | No encuentran objetivo: no hay ningún nodo en el grupo `player` ni `Target Path` asignado. Se quedan en `IDLE` sin dar error. |
| Los enemigos se **caen al vacío** | El `collision_mask` del enemigo (`7`) no incluye la capa de tu suelo. Ajusta las capas (§4.3). |
| Los enemigos **no reciben daño** | Tu ataque llama a un método distinto. Usa `take_hit(amount, hit_dir, knockback, stun_time)` o `take_damage(amount)`. |
| El enemigo recibe daño pero **no puedes rematarlo** | `execute()` solo tiene sentido con el enemigo en `STUN`: usa `stun(...)` u `on_countered(...)` antes, o comprueba `is_stunned()`. |
| La **barra de vida** no aparece o no baja | Se renombraron los nodos `HealthBar` / `HealthBar/Fill` / `Body` (§4.4). |
| Error de valores extraños en el comportamiento | El gestor de tu proyecto entrega un `config` que no tiene los campos de §6.3. El enemigo lee ese `Resource` dinámicamente: necesita esos nombres exactos. |
| Dos gestores en la misma escena | Los enemigos usan el **primero** que encuentra en el grupo `combat_manager`, así que se reparten de forma impredecible. Deja solo uno, o usa `combat_manager_path`. |

---

## 9. Comprobado / no comprobado

Probado de verdad en el proyecto (Godot 4.7.2, Forward+):

- La carpeta no tiene ninguna ruta `res://` que salga de ella.
- `scenes/enemy.tscn` y `scenes/test_enemies.tscn` se abren y se instancian.
- **Escena de prueba en vivo**: 6 enemigos se registran, rodean al muñeco
  (anillo medido de 1,3 a 3,8 m), esperan turno y le hacen daño (40–60 de daño en 7 s).
  Estados observados: `WAIT`, `APPROACH`, `RECOVERY`. Nadie se cae del suelo.
- **El mapa original sigue funcionando** con los enemigos ya movidos: el enemigo se
  engancha al gestor del mapa (`res://scripts/combat/combat_manager.gd`, otro archivo
  distinto al suyo) y la vida del personaje baja igual que antes (100 → 40 en 7 s), con la
  barra del HUD coincidiendo.
- Los 12 recursos de la carpeta cargan; ningún script declara `class_name`.
- **Spawner (tecla G)**: `test/prueba_spawner.gd` (arena de prueba con edificio) y
  `res://ziba/test/prueba_partida.gd` (la partida completa, con la ciudad) pasan: 6/6 en
  anillo válido, sin solapes ni apariciones sobre tejados, no duplica al reactivar,
  repone al que desaparece, desactiva sólo los suyos y avisa cuando no hay sitio válido.
  En vivo (partida real) se comprobó el activado con G y el combate resultante.

No comprobado (no se puede desde aquí): copiar la carpeta a un proyecto **físicamente
distinto**. La independencia se ha verificado por tres vías: cero rutas externas,
ejecución sin el mapa principal y combate completo con enemigos que solo usan los
recursos de esta carpeta.