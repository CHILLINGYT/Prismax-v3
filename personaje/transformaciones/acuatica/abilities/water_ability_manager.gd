class_name WaterAbilityManager
extends Node
## =============================================================================
##  GESTOR DE HABILIDADES DE AGUA
## =============================================================================
##  Es el que manda: decide si una habilidad se puede usar, lleva los
##  ENFRIAMIENTOS y crea el objeto de la habilidad EN EL MOMENTO EXACTO en que la
##  animacion lo pide.
##
##  POR QUE NO SE CREA AL PULSAR LA TECLA
##    Porque la animacion tiene un ataque previo: el personaje junta las manos,
##    carga y solo despues empuja. Si el proyectil saliera al pulsar, se veria
##    salir de la nada antes de que el personaje lo lance. Por eso hay dos pasos:
##
##      1. PULSAR (try_cast): se comprueba el enfriamiento y arranca la animacion.
##      2. LIBERAR (release): lo pide la propia animacion por una PISTA DE METODO
##         del AnimationTree, que llama a Player.notify_ability_release(). Justo
##         ahi nace el proyectil, en la mano, cuando la animacion lo suelta.
##
##    Asi el efecto y la animacion van clavados aunque cambies el clip.
##
##  SEGURO ANTI-ATASCO: si por lo que sea la pista de metodo no llegara (por
##  ejemplo si alguien cambia el clip por otro sin la pista), hay un temporizador
##  de reserva que libera igual. Una habilidad NUNCA se queda sin salir.
##
##  Se cuelga del jugador como hijo: Player/AbilityManager.
## =============================================================================

signal ability_cast_started(index: int, ability_name: String)
signal ability_released(index: int, ability_name: String)
signal ability_blocked(index: int, reason: String)

const ABILITY_PROJECTILE := preload("res://personaje/transformaciones/acuatica/abilities/water_projectile.gd")
const ABILITY_BURST := preload("res://personaje/transformaciones/acuatica/abilities/water_burst.gd")
const ABILITY_PRISON := preload("res://personaje/transformaciones/acuatica/abilities/water_prison.gd")
const ABILITY_SURGE := preload("res://personaje/transformaciones/acuatica/abilities/water_surge.gd")

## Las cuatro habilidades, en orden. Cada una dice:
##   state     estado de animacion que la representa (lo pone el constructor de
##             animaciones; aqui solo se usa)
##   name      nombre para mostrar
##   script    que objeto crea al liberarse
##   cooldown  segundos de enfriamiento (1 / 3 / 5 / 8 pedidos)
##   release   segundo del clip en el que sale el efecto (el mismo que usa la
##             pista de metodo; aqui solo es el seguro anti-atasco)
##   damage / hit_radius / speed / lifetime / knockback  como se comporta
##   kind      tipo de daño que recibe el objetivo
const ABILITIES := [
	{
		"state": &"ability_1",
		"name": "Proyectil de agua",
		"script": ABILITY_PROJECTILE,
		"cooldown": 1.0,
		"release": 1.3,
		"damage": 12.0,
		"hit_radius": 0.55,
		"speed": 18.0,
		"lifetime": 2.5,
		"knockback": 3.0,
		"kind": &"light",
	},
	{
		"state": &"ability_2",
		"name": "Esfera de agua",
		"script": ABILITY_BURST,
		"cooldown": 3.0,
		"release": 1.85,
		"damage": 8.0,
		"hit_radius": 0.7,
		"speed": 12.0,
		"lifetime": 4.0,
		"knockback": 5.0,
		"kind": &"heavy",
		"field_radius": 3.2,
		"field_duration": 2.6,
	},
	{
		"state": &"ability_3",
		"name": "Prision de agua",
		"script": ABILITY_PRISON,
		"cooldown": 5.0,
		"release": 1.5,
		"damage": 10.0,
		"hit_radius": 0.9,
		"speed": 14.0,
		"lifetime": 3.0,
		"knockback": 0.0,
		"kind": &"light",
		"trap_duration": 3.0,
	},
	{
		"state": &"ability_4",
		"name": "Oleada de agua",
		"script": ABILITY_SURGE,
		"cooldown": 8.0,
		"release": 1.62,
		"damage": 45.0,
		"hit_radius": 2.4,
		"speed": 7.0,
		"lifetime": 2.6,
		"knockback": 9.0,
		"kind": &"heavy",
	},
]

## Altura (m) sobre los pies a la que nace la habilidad, de pie y nadando.
@export var spawn_height := 1.25
@export var spawn_swim_height := 0.6
## Distancia (m) por delante del personaje a la que nace.
@export var spawn_forward := 0.65

## Enfriamiento restante de cada habilidad (segundos), indexado por su numero.
var _cooldowns := {}
## Habilidad armada esperando su liberacion (0 = ninguna).
var _pending := 0
var _pending_time := 0.0
## Margen (s) extra sobre el tiempo de liberacion para el seguro anti-atasco.
@export var fallback_margin := 0.35

## Script del agua que se junta en las manos mientras se carga. Se preloadea
## (igual que las habilidades) para no depender de la cache de class_name.
const ChargeScript := preload("res://personaje/transformaciones/acuatica/vfx/water_charge.gd")

var _player: Player = null
## Agua cargandose en las manos ahora mismo (o null).
var _charge: Node3D = null
## true cuando la carga "prestada" es el balón de apuntado del jugador, no una
## creada por el gestor. Entonces no se libera/borra aquí: la suelta el jugador.
var _charge_is_aim_ball := false


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		_player = get_parent().get_parent() as Player
	for i in ABILITIES.size():
		_cooldowns[i + 1] = 0.0


func _process(delta: float) -> void:
	for key in _cooldowns.keys():
		if _cooldowns[key] > 0.0:
			_cooldowns[key] = maxf(_cooldowns[key] - delta, 0.0)
	# Seguro anti-atasco: la animacion nunca ha pedido liberar y ya deberia haberlo
	# hecho. Se libera igual, para que la habilidad no se pierda.
	if _pending > 0:
		_pending_time += delta
		if _pending_time > _release_time(_pending) + fallback_margin:
			_do_release(_pending)


# -----------------------------------------------------------------------------
#  API
# -----------------------------------------------------------------------------
## Intenta lanzar la habilidad [param index] (1..4). Devuelve true si ha
## arrancado (entonces la animacion ya esta puesta y el efecto saldra solo).
## Si devuelve false, la razon se emite en ability_blocked.
func try_cast(index: int) -> bool:
	if _player == null:
		return false
	if index < 1 or index > ABILITIES.size():
		return false
	if _player.is_dead or _player.is_incapacitated():
		return _blocked(index, "no puedes actuar")
	if _pending > 0:
		return _blocked(index, "ya estas lanzando otra")
	if _cooldowns.get(index, 0.0) > 0.0:
		return _blocked(index, "enfriando")
	# Otra accion en curso (golpe, esquiva, otro ataque): primero se acaba.
	var state: StringName = ABILITIES[index - 1]["state"]
	if _player.is_acting() and _player.get_state() != state:
		return _blocked(index, "ocupado")
	# Hacer pie solo es obligatorio en TIERRA. En el agua (nadando, por el fondo o
	# encima de la superficie) se puede lanzar sin tocar nada.
	if not _player.is_in_water_physics() and not _player.is_on_floor():
		return _blocked(index, "en el aire")
	_pending = index
	_pending_time = 0.0
	_start_charge(index)
	_player.start_action(state)
	ability_cast_started.emit(index, ability_name(index))
	return true


## La animacion pide liberar. La llama Player.notify_ability_release() desde una
## pista de metodo, asi que el efecto nace en el fotograma exacto del clip.
func release_for_state(state: StringName) -> void:
	var index := index_of_state(state)
	if index > 0 and _pending == index:
		_do_release(index)


## Cancela un lanzamiento armado sin crear nada (por ejemplo si el personaje cae).
func cancel_pending() -> void:
	_pending = 0
	_pending_time = 0.0
	_cancel_charge()


func is_ready(index: int) -> bool:
	if index < 1 or index > ABILITIES.size():
		return false
	return _cooldowns.get(index, 0.0) <= 0.0


func cooldown_left(index: int) -> float:
	return float(_cooldowns.get(index, 0.0))


## 0 = listo, 1 = recien usado. Para una barra de enfriamiento.
func cooldown_ratio(index: int) -> float:
	var total := float(ABILITIES[index - 1]["cooldown"]) if index >= 1 and index <= ABILITIES.size() else 1.0
	if total <= 0.0:
		return 0.0
	return clampf(cooldown_left(index) / total, 0.0, 1.0)


func ability_name(index: int) -> String:
	if index < 1 or index > ABILITIES.size():
		return ""
	return String(ABILITIES[index - 1]["name"])


func ability_count() -> int:
	return ABILITIES.size()


## Numero de habilidad (1..4) del estado de animacion, o 0 si no es una habilidad.
func index_of_state(state: StringName) -> int:
	for i in ABILITIES.size():
		if ABILITIES[i]["state"] == state:
			return i + 1
	return 0


## true si el estado es el de alguna habilidad.
func is_ability_state(state: StringName) -> bool:
	return index_of_state(state) > 0


# -----------------------------------------------------------------------------
#  Interno
# -----------------------------------------------------------------------------
func _do_release(index: int) -> void:
	if index < 1 or index > ABILITIES.size():
		_pending = 0
		_cancel_charge()
		return
	_pending = 0
	_pending_time = 0.0
	_cooldowns[index] = float(ABILITIES[index - 1]["cooldown"])
	_release_charge()
	_spawn(index)
	ability_released.emit(index, ability_name(index))


## Empieza a juntar agua en las manos. Es lo que hace que la habilidad parezca
## agua manipulada: el agua lleva cargandose desde que se pulsa la tecla.
func _start_charge(index: int) -> void:
	_cancel_charge()
	if _player == null or not _player.is_inside_tree():
		return
	if _player.is_aiming():
		# Apuntando ya hay un balón de agua cargándose entre las manos: ESE es la
		# carga del hechizo. No se crea otro (se verían dos aguas) y al liberar se
		# suelta el de las manos.
		_charge_is_aim_ball = true
		return
	_charge_is_aim_ball = false
	var host := _player.get_parent()
	if host == null:
		return
	var node := ChargeScript.new() as Node3D
	if node == null:
		return
	node.set("player", _player)
	node.set("duration", _release_time(index))
	node.set("underwater", _player.is_underwater())
	# El agua que se junta tiene el tamaño de la habilidad: la oleada final es la
	# mas grande con diferencia, y la prision se carga cerrada y comprimida.
	var radius := 0.34
	if index == 2:
		radius = 0.42
	elif index == 3:
		radius = 0.3
	elif index == 4:
		radius = 0.55
	node.set("radius", radius)
	host.add_child(node)
	_charge = node


## El hechizo sale: el agua que estaba cargada se abre y desaparece.
func _release_charge() -> void:
	if _charge_is_aim_ball:
		# La carga era el balón de las manos: lo suelta el jugador (y lo rearma).
		_charge_is_aim_ball = false
		if _player != null:
			_player.release_aim_ball()
		return
	if _charge == null:
		return
	if is_instance_valid(_charge):
		_charge.call("release")
	_charge = null


## El hechizo se cancela: el agua cargada se va sin mas.
func _cancel_charge() -> void:
	if _charge_is_aim_ball:
		# El balón de apuntado es del jugador: no se toca aquí.
		_charge_is_aim_ball = false
		return
	if _charge == null:
		return
	if is_instance_valid(_charge):
		_charge.queue_free()
	_charge = null


func _spawn(index: int) -> void:
	if _player == null or not _player.is_inside_tree():
		return
	var def: Dictionary = ABILITIES[index - 1]
	var scene: GDScript = def["script"]
	var ability: Node3D = scene.new() as Node3D
	if ability == null:
		return

	# DIREECCION: en tierra (y caminando sobre el agua) hacia donde mira el
	# personaje, en horizontal. DENTRO DEL AGUA se apunta con la CAMARA en 3D:
	# sumergido se puede lanzar hacia arriba, hacia abajo o en diagonal, no solo
	# hacia delante.
	var forward := -_player.global_transform.basis.z
	if _player.is_aiming():
		# Apuntando: la habilidad sale DE LA MANO y va HACIA el punto que marca la
		# reticula (direccion = objetivo - mano). El origen lo da el hueso de la
		# mano, no el nodo del agua: leer el nodo recien creado devolvia el origen
		# del mundo y la habilidad nacia en el suelo.
		forward = _player.get_aim_shot_direction()
	elif _player.is_in_water_physics() and _player.get_water_mode() != Player.WaterMode.SURFACE_WALK:
		forward = _player.get_aim_direction()
	else:
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var underwater: bool = _player.is_underwater()
	var height := spawn_swim_height if _player.is_swimming() else spawn_height
	var origin := _player.global_position + Vector3.UP * height + forward * spawn_forward
	if _player.is_aiming():
		# Nace EN LA MANO que sostiene el agua (el hueso), no del aire ni del suelo.
		origin = _player.get_aim_origin()

	# Valores de la habilidad. Se ponen ANTES de añadirla al arbol para que
	# _ready() (que construye el aspecto) ya los encuentre puestos.
	ability.damage = float(def["damage"])
	ability.hit_radius = float(def["hit_radius"])
	ability.speed = float(def["speed"])
	ability.lifetime = float(def["lifetime"])
	ability.knockback = float(def["knockback"])
	ability.damage_kind = def["kind"]
	# Lanzada bajo el agua: el proyectil se frena con la resistencia del agua y su
	# aspecto es de remolino y burbujas, no de salpicadura de superficie.
	ability.underwater = underwater
	if def.has("field_radius"):
		ability.set("field_radius", float(def["field_radius"]))
	if def.has("field_duration"):
		ability.set("field_duration", float(def["field_duration"]))
	if def.has("trap_duration"):
		ability.set("trap_duration", float(def["trap_duration"]))

	# Se cuelga del mundo (no del jugador): la habilidad tiene que quedarse donde
	# se suelta, no seguir al personaje.
	var world := _player.get_parent()
	if world == null:
		world = _player
	world.add_child(ability)
	ability.setup(_player, origin, forward)


func _release_time(index: int) -> float:
	if index < 1 or index > ABILITIES.size():
		return 0.0
	return float(ABILITIES[index - 1]["release"])


func _blocked(index: int, reason: String) -> bool:
	ability_blocked.emit(index, reason)
	return false
