class_name PlayerAnimationController
extends Node
## =============================================================================
##  CONTROLADOR DE ANIMACION DEL JUGADOR
## =============================================================================
##  Une la LOGICA del jugador con el AnimationTree:
##
##    * El jugador solo llama a play_state("walk"), play_state("jump")...
##    * Este nodo hace el travel() en la maquina de estados, que se encarga de
##      los crossfades (transiciones suaves) entre animaciones.
##    * Sabe cuanto dura cada clip (para el estado "landing").
##    * Adapta las animaciones al skeleton del modelo actual: reescribe la ruta
##      del nodo de los tracks y remapea nombres de hueso. Esto es lo que hace
##      que puedas cambiar el modelo sin rehacer las animaciones ni el codigo.
##
##  Estados (== nombres de las animaciones y de los estados del AnimationTree):
##      Locomocion:  idle, walk, run, walk_back
##      Agachado:    crouch_idle, crouch_walk
##      Aire:        jump, fall, landing
##      Acciones:    attack, attack_2, dodge, recovery
##      Daño:        hit_light, hit_head, hit_side, hit_heavy, stagger,
##                   knockdown, ground, get_up, death
##      Agua:        swim_idle, swim_forward, swim_back, swim_up, swim_down,
##                   enter_water, exit_water
##      Habilidades: ability_1 (proyectil), ability_2 (esfera), ability_3
##                   (prision), ability_4 (ataque fuerte)
##  Los clips los genera tools/pack_animation_builder.gd a partir de los packs de
##  animacion, con estos mismos nombres.
## =============================================================================

## Se emite cuando el AnimationTree cambia realmente de estado.
signal state_changed(state: StringName)

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_RUN := &"run"
## OJO: no hay estado "sprint" a proposito. Esprintar es ir mas rapido con el
## MISMO clip de correr: el factor de velocidad lo acelera solo. Un clip de
## sprint aparte provocaba dos animaciones de carrera consecutivas al mantener
## Shift.
const STATE_WALK_BACK := &"walk_back"
const STATE_CROUCH_IDLE := &"crouch_idle"
const STATE_CROUCH_WALK := &"crouch_walk"
const STATE_JUMP := &"jump"
const STATE_FALL := &"fall"
const STATE_LANDING := &"landing"
const STATE_HIT_LIGHT := &"hit_light"
const STATE_HIT_HEAD := &"hit_head"
const STATE_HIT_SIDE := &"hit_side"
const STATE_HIT_HEAVY := &"hit_heavy"
const STATE_STAGGER := &"stagger"
const STATE_KNOCKDOWN := &"knockdown"
const STATE_GROUND := &"ground"
const STATE_GET_UP := &"get_up"
const STATE_DEATH := &"death"
const STATE_DODGE := &"dodge"
const STATE_ATTACK := &"attack"
## Segundo golpe del combo (ver Player.request_attack).
const STATE_ATTACK_2 := &"attack_2"
const STATE_RECOVERY := &"recovery"

## --- Sistema acuatico -------------------------------------------------------
## Estados de natacion. Los elige Player segun la velocidad y la direccion REAL
## (vertical incluida), igual que la locomocion de tierra.
const STATE_SWIM_IDLE := &"swim_idle"
const STATE_SWIM_FORWARD := &"swim_forward"
const STATE_SWIM_BACK := &"swim_back"
const STATE_SWIM_UP := &"swim_up"
const STATE_SWIM_DOWN := &"swim_down"
## Estados de transicion de entrada/salida del agua: evitan el salto brusco de
## "andar" a "nadar" (y al reves).
const STATE_ENTER_WATER := &"enter_water"
const STATE_EXIT_WATER := &"exit_water"

## Las cuatro habilidades acuaticas.
const STATE_ABILITY_1 := &"ability_1"
const STATE_ABILITY_2 := &"ability_2"
const STATE_ABILITY_3 := &"ability_3"
const STATE_ABILITY_4 := &"ability_4"

## Todos los estados de natacion, para consultarlos desde fuera.
const SWIM_STATES: Array[StringName] = [
	STATE_SWIM_IDLE, STATE_SWIM_FORWARD, STATE_SWIM_BACK, STATE_SWIM_UP,
	STATE_SWIM_DOWN,
]

## Todos los estados de habilidad.
const ABILITY_STATES: Array[StringName] = [
	STATE_ABILITY_1, STATE_ABILITY_2, STATE_ABILITY_3, STATE_ABILITY_4,
]

## Estados cuya velocidad de reproduccion SI se ajusta a la velocidad real del
## personaje, para que los pasos (o las brazadas) no patinen. El resto de estados
## --hechizos, golpes, daño, salto-- van siempre a 1x.
const TIME_SCALED_STATES: Array[StringName] = [
	STATE_IDLE, STATE_WALK, STATE_RUN, STATE_WALK_BACK,
	STATE_CROUCH_IDLE, STATE_CROUCH_WALK,
	STATE_SWIM_IDLE, STATE_SWIM_FORWARD, STATE_SWIM_BACK,
	STATE_SWIM_UP, STATE_SWIM_DOWN,
	# Locomocion con la bola en la mano (Water Aim). Tambien se escala: el paso de
	# estos clips tiene que quedar clavado en el suelo a la velocidad de apuntado,
	# que es mas lenta que andar normal.
	&"aim_walk_back", &"aim_walk_forward", &"aim_walk_right",
	&"aim_run_forward", &"aim_run_back", &"aim_run_left", &"aim_run_right",
	&"aim_crouch_forward", &"aim_crouch_back",
]

## Estados en los que el personaje esta FLOTANDO: el modelo se puede descolgar
## un poco para que el cuerpo quede a la altura del agua en vez de "de pie" sobre
## una superficie invisible.
const FLOATING_STATES: Array[StringName] = [
	STATE_SWIM_IDLE, STATE_SWIM_FORWARD, STATE_SWIM_BACK, STATE_SWIM_UP,
	STATE_SWIM_DOWN, STATE_ENTER_WATER, STATE_EXIT_WATER,
]

## Estados SIN los cuales el personaje no se puede mover bien. Si falta alguno se
## avisa por consola, pero el juego sigue (el estado se queda en el clip anterior).
const REQUIRED_STATES: Array[StringName] = [
	STATE_IDLE, STATE_WALK, STATE_RUN, STATE_JUMP, STATE_FALL, STATE_LANDING,
]

@export_group("Referencias")
@export var animation_player: AnimationPlayer
@export var animation_tree: AnimationTree
@export var model: CharacterModel
## Estado con el que arranca el personaje.
@export var initial_state: StringName = STATE_IDLE

@export_group("Adaptación al modelo")
## Reescribe las rutas de los tracks de animacion hacia el skeleton del modelo
## actual y remapea los nombres de hueso usando CharacterModel.bone_name_map.
@export var adapt_animation_paths := true
## Si el modelo importado trae su propio AnimationPlayer con animaciones
## llamadas idle/walk/run/jump/fall/landing, se usa ESE en lugar del del jugador
## (asi conservas tus animaciones y el mismo AnimationTree).
@export var use_model_animation_player := false
# NOTA: las animaciones ya vienen "horneadas" al esqueleto del modelo (nombres de
# hueso, postura de reposo y orientacion incluidos) por tools/rig_baker.gd, asi
# que aqui no hay que corregir rotaciones de rest en tiempo de ejecucion.

@export_group("Sincronización de velocidad")
## Limites del factor de velocidad de la animacion de locomocion. Con 0.4 la
## animacion puede ir un 60% mas lenta al arrancar/frenar, y con 2.0 el doble de
## rapida. Evita que los pies "patinen" respecto al suelo.
@export var min_speed_factor := 0.4
@export var max_speed_factor := 2.0

@export_group("Pies en el suelo")
## Corrige la altura del modelo para que el pie de apoyo toque el suelo: evita
## que el personaje flote o se hunda cuando la animacion no encaja exactamente
## con la longitud de las piernas del modelo. Funciona con CUALQUIER rig, porque
## mide el pie real en cada frame.
@export var foot_lock_enabled := true
## Correccion maxima (m): evita que una pose extrana hunda o levante el personaje.
@export var foot_lock_max_correction := 0.07
## Velocidad de la correccion (1/s). Alta = el pie se clava antes (menos rebote).
@export var foot_lock_speed := 45.0

@export_group("Flotación")
## Desplazamiento (m) que se le da al modelo en los estados de agua. Los clips de
## natacion colocan el cuerpo a distinta altura respecto al origen del jugador
## que los de tierra (al nadar boca abajo el cuerpo queda tumbado a media altura),
## asi que hay que descolgarlo un poco para que el agua le pase por donde toca.
@export var swim_model_offset := 0.0
## Velocidad (1/s) con la que el modelo pasa de la altura de tierra a la de agua.
## Baja a proposito: el cambio de postura se ve como si el cuerpo se acomodara
## flotando, no como un salto.
@export var swim_offset_speed := 4.0

## Lo pone el jugador: true solo en los estados en los que el personaje esta
## apoyado (idle/walk/run), para no tocar saltos ni golpes.
var foot_lock_active := false

var _playback: AnimationNodeStateMachinePlayback
var _current_state: StringName = &""
var _speed_parameter := ""  # ruta del parametro del nodo TimeScale del arbol
var _foot_lock := 0.0
## Desplazamiento actual de flotacion (m). Se interpola hacia swim_model_offset
## solo en los estados de agua, y hacia 0 al salir.
var _float_offset := 0.0
## Altura original del nodo del modelo: la correccion de los pies se aplica
## SIEMPRE sobre esta base, nunca acumulando sobre el valor del frame anterior.
var _base_y := 0.0
var _base_captured := false


func _ready() -> void:
	_resolve_references()
	_setup_playback()
	if adapt_animation_paths:
		var report := adapt_animations_to_model()
		if int(report["remapped_bones"]) > 0 or not (report["missing_bones"] as PackedStringArray).is_empty():
			print("PlayerAnimationController: %s" % _format_report(report))
	play_state(initial_state, true)


## Cambia de estado de animacion (hace travel con crossfade).
func play_state(state: StringName, force: bool = false) -> void:
	if _playback == null:
		_current_state = state
		return
	if state == _current_state and not force:
		return
	# El nodo TimeScale del arbol envuelve a TODA la maquina de estados, asi que
	# el factor de velocidad de la locomocion tambien afectaria a un hechizo, a un
	# golpe o a una reaccion de daño: un ataque saldria al doble de velocidad solo
	# porque el personaje venia esprintando (o nadando, que es peor). Al entrar en
	# un estado que no es de locomocion se devuelve a 1x.
	# Los golpes son la excepcion: se reproducen a la velocidad de golpe (un poco
	# mas rapida que el clip horneado) para que el combate responda, y con esa
	# misma velocidad se calcula su duracion de accion.
	if ACTION_SPEED_STATES.has(state):
		set_locomotion_speed_factor(action_speed)
	elif not TIME_SCALED_STATES.has(state):
		set_locomotion_speed_factor(1.0)
	_current_state = state
	_playback.travel(state)
	state_changed.emit(state)


## Estado actual segun la maquina de estados.
func get_current_state() -> StringName:
	if _playback == null:
		return _current_state
	return StringName(_playback.get_current_node())


## Duracion (en segundos) de la animacion de un estado. 0.0 si no existe.
func get_state_length(state: StringName) -> float:
	var player := get_active_animation_player()
	if player == null:
		return 0.0
	var animation := _find_animation(player, state)
	if animation == null:
		return 0.0
	# Si la animacion se reproduce mas rapida/lenta, dura menos/mas. Pero solo las
	# de locomocion se aceleran: un hechizo dura siempre lo que dura su clip, y si
	# aqui se aplicara el factor de la carrera duraria la mitad y se cortaria.
	# Los golpes usan SU propia velocidad (la que se acaba de fijar al arrancarlos);
	# la locomocion, la que lleva el arbol segun lo rapido que vaya el personaje.
	var factor := 1.0
	if ACTION_SPEED_STATES.has(state):
		factor = action_speed
	elif TIME_SCALED_STATES.has(state):
		factor = get_locomotion_speed_factor()
	return animation.length / (factor if factor > 0.0 else 1.0)


## Estados de ACCION cuya velocidad de reproduccion se ajusta aparte: los golpes
## del combo. No son locomocion, asi que su velocidad NO depende de lo rapido que
## se mueva el personaje, sino de que el golpe responda al clic.
const ACTION_SPEED_STATES: Array[StringName] = [&"attack", &"attack_2"]

## Velocidad de reproduccion que se aplica a los golpes del combo (1.0 = la del
## clip horneado). La fija el jugador; aqui solo se guarda.
var action_speed := 1.0


## Fija la velocidad de reproduccion de los golpes del combo.
func set_action_speed(factor: float) -> void:
	action_speed = clampf(factor, min_speed_factor, max_speed_factor)


## Ajusta la velocidad de reproduccion de la animacion de locomocion para que
## los pasos coincidan con la velocidad real del personaje (evita el "patinaje"
## de pies al arrancar y al frenar).
## [param factor] = velocidad_actual / velocidad_de_referencia_del_estado.
func set_locomotion_speed_factor(factor: float) -> void:
	if _speed_parameter.is_empty() or animation_tree == null:
		return
	animation_tree.set(_speed_parameter, clampf(factor, min_speed_factor, max_speed_factor))


## Factor de velocidad que se esta aplicando ahora mismo (1.0 = normal).
func get_locomotion_speed_factor() -> float:
	if _speed_parameter.is_empty() or animation_tree == null:
		return 1.0
	var value: Variant = animation_tree.get(_speed_parameter)
	return float(value) if value != null else 1.0


## true si hay una animacion disponible para ese estado.
func has_state(state: StringName) -> bool:
	var player := get_active_animation_player()
	return player != null and _find_animation(player, state) != null


## Devuelve el AnimationPlayer que se esta usando realmente (el del modelo si
## use_model_animation_player esta activado y el modelo lo trae).
func get_active_animation_player() -> AnimationPlayer:
	if animation_tree != null and animation_tree.anim_player != NodePath():
		var node := animation_tree.get_node_or_null(animation_tree.anim_player)
		var player := node as AnimationPlayer
		if player != null:
			return player
	return animation_player


func has_all_required_states(player: AnimationPlayer = null) -> bool:
	var target := player if player != null else get_active_animation_player()
	if target == null:
		return false
	for state in REQUIRED_STATES:
		if _find_animation(target, state) == null:
			return false
	return true


## Nodo base al que el AnimationMixer resuelve los paths de los tracks.
## Es el root_node del mixer (".." por defecto = el padre del AnimationPlayer).
func get_track_base_node() -> Node:
	for candidate in [animation_tree, animation_player]:
		var mixer := candidate as AnimationMixer
		if mixer == null:
			continue
		var base := mixer.get_node_or_null(mixer.root_node)
		if base != null:
			return base
		var parent := mixer.get_parent()
		if parent != null:
			return parent
	return null


## Adapta las animaciones al skeleton del modelo actual.
## Devuelve un informe: { "tracks", "remapped_bones", "missing_bones" }.
##
## OJO con las rutas: un track de hueso es "<ruta_al_Skeleton3D>:<Hueso>" y esa
## ruta es relativa al root_node del AnimationMixer (por defecto "..", o sea el
## padre del AnimationPlayer), NO relativa al AnimationPlayer. Por eso aqui se
## calcula la ruta desde get_track_base_node().
func adapt_animations_to_model() -> Dictionary:
	var report := {
		"tracks": 0,
		"remapped_bones": 0,
		"missing_bones": PackedStringArray(),
	}
	var skeleton := model.get_skeleton() if model != null else null
	var player := get_active_animation_player()
	if skeleton == null or player == null:
		return report

	var base := get_track_base_node()
	if base == null:
		return report
	var skeleton_path := String(model.get_skeleton_path_from(base))
	if skeleton_path.is_empty():
		return report

	var missing := PackedStringArray()
	for library_name: StringName in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for animation_name: StringName in library.get_animation_list():
			var animation := library.get_animation(animation_name)
			for track in animation.get_track_count():
				var track_type := animation.track_get_type(track)
				if track_type != Animation.TYPE_POSITION_3D \
						and track_type != Animation.TYPE_ROTATION_3D \
						and track_type != Animation.TYPE_SCALE_3D:
					continue
				var path := animation.track_get_path(track)
				var bone: String = String(path.get_concatenated_subnames())
				if bone.is_empty():
					continue
				report["tracks"] = int(report["tracks"]) + 1

				# 1) El nombre del hueso: igual, o traducido por bone_name_map.
				var target_bone := bone
				if skeleton.find_bone(target_bone) < 0:
					target_bone = String(model.resolve_bone_name(StringName(bone)))
					if skeleton.find_bone(target_bone) >= 0:
						report["remapped_bones"] = int(report["remapped_bones"]) + 1
				if skeleton.find_bone(target_bone) < 0:
					if not missing.has(bone):
						missing.append(bone)
					continue

				# 2) La ruta del nodo: apuntar siempre al skeleton del modelo actual.
				var new_path := NodePath("%s:%s" % [skeleton_path, target_bone])
				if new_path != path:
					animation.track_set_path(track, new_path)

	report["missing_bones"] = missing
	return report


## Vuelve a conectar el AnimationTree tras cambiar el modelo en caliente.
func refresh_after_model_change() -> void:
	adapt_animations_to_model()
	_clear_mixer_caches(animation_tree)
	_clear_mixer_caches(animation_player)
	# El modelo nuevo puede estar a otra altura: se vuelve a tomar la base para no
	# arrastrar la correccion del anterior.
	_base_captured = false
	_foot_lock = 0.0
	_float_offset = 0.0
	play_state(_current_state, true)


## Fuerza al mixer a reconstruir su cache de nodos/huesos. Es necesario despues
## de reescribir los paths de los tracks de las animaciones.
func _clear_mixer_caches(mixer: AnimationMixer) -> void:
	if mixer == null:
		return
	if mixer.has_method("clear_caches"):
		mixer.clear_caches()
	elif mixer is AnimationTree:
		var tree_root := (mixer as AnimationTree).tree_root
		(mixer as AnimationTree).tree_root = null
		(mixer as AnimationTree).tree_root = tree_root


# -----------------------------------------------------------------------------
#  Pie en el suelo (foot lock)
# -----------------------------------------------------------------------------
## Se ejecuta DESPUES de que el AnimationTree escriba la pose (este nodo va
## despues del arbol en el arbol de escena).
##
## Mide la altura real de los tobillos respecto a su altura de reposo y desplaza
## el modelo lo necesario para que el pie de apoyo quede en el suelo. Es lo que
## evita que el personaje parezca flotar o hundirse al caminar.
##
## OJO: la correccion se FIJA (model.position.y = base + correccion), no se suma.
## Si se sumara, cada frame se acumularia sobre lo corregido el frame anterior,
## y como la medida se hace sobre el modelo YA desplazado, el personaje se iria
## hundiendo poco a poco hasta desaparecer bajo el suelo.
func _physics_process(delta: float) -> void:
	if model == null:
		return
	if not _base_captured:
		_base_y = model.position.y
		_base_captured = true
	var skeleton := model.get_skeleton()
	if skeleton == null:
		return
	var wanted := 0.0
	if foot_lock_enabled and foot_lock_active:
		var lowest := INF
		var rest := INF
		# Los nombres estandar se traducen con el mapa del modelo, asi que esto
		# funciona con cualquier rig (mixamorig_LeftFoot, foot_L, ...).
		for standard in [&"LeftFoot", &"RightFoot"]:
			var bone := skeleton.find_bone(model.resolve_bone_name(standard))
			if bone >= 0:
				lowest = minf(lowest, skeleton.get_bone_global_pose(bone).origin.y)
				rest = minf(rest, skeleton.get_bone_global_rest(bone).origin.y)
		if lowest < INF and rest < INF:
			# Los huesos viven en el espacio del modelo, que puede estar escalado
			# (este modelo mide 1.75 m con escala 1.79): se pasa a metros, que es
			# la unidad en la que se mueve el nodo del modelo.
			var units_to_meters := skeleton.global_transform.basis.y.length()
			wanted = clampf((rest - lowest) * units_to_meters, -foot_lock_max_correction, foot_lock_max_correction)
	_foot_lock = lerpf(_foot_lock, wanted, 1.0 - exp(-foot_lock_speed * delta))
	var float_target := swim_model_offset if FLOATING_STATES.has(_current_state) else 0.0
	_float_offset = lerpf(_float_offset, float_target, 1.0 - exp(-swim_offset_speed * delta))
	model.position.y = _base_y + _foot_lock + _float_offset


# -----------------------------------------------------------------------------
#  Interno
# -----------------------------------------------------------------------------
func _resolve_references() -> void:
	var owner_node := get_parent()
	if owner_node == null:
		return
	if model == null:
		model = owner_node.get_node_or_null("Visual") as CharacterModel
	if animation_player == null:
		animation_player = owner_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_tree == null:
		animation_tree = owner_node.get_node_or_null("AnimationTree") as AnimationTree


func _setup_playback() -> void:
	if animation_tree == null:
		push_warning("PlayerAnimationController: falta el AnimationTree; no habra animaciones.")
		return

	# ¿El modelo trae sus propias animaciones? Entonces usamos las suyas.
	if use_model_animation_player and model != null:
		var model_player := model.get_animation_player()
		if model_player != null and has_all_required_states(model_player):
			animation_tree.anim_player = animation_tree.get_path_to(model_player)
			# El AnimationTree resuelve los paths de las animaciones relativos a
			# SU root_node, asi que hay que alinearlo con el del AnimationPlayer
			# del modelo, o no encontrara sus tracks.
			var model_root := model_player.get_node_or_null(model_player.root_node)
			if model_root == null:
				model_root = model_player.get_parent()
			if model_root != null:
				animation_tree.root_node = animation_tree.get_path_to(model_root)
			print("PlayerAnimationController: usando el AnimationPlayer del modelo (%s)" % model_player.name)

	var player := get_active_animation_player()
	for state in REQUIRED_STATES:
		if player == null or _find_animation(player, state) == null:
			push_warning("PlayerAnimationController: falta la animacion '%s'. El estado quedara en la animacion anterior." % state)

	animation_tree.active = true
	_playback = _find_playback()
	if _playback == null:
		push_warning("PlayerAnimationController: no se encontro la maquina de estados dentro del AnimationTree.")
	_speed_parameter = _find_speed_parameter()


## Busca el nodo de velocidad de reproduccion (AnimationNodeTimeScale) dentro
## del arbol. En esta escena esta en "parameters/SpeedScale/scale".
func _find_speed_parameter() -> String:
	var properties := animation_tree.get_property_list()
	for property in properties:
		var property_name := String(property["name"])
		if property_name == "parameters/SpeedScale/scale":
			return property_name
	for property in properties:
		var property_name := String(property["name"])
		if property_name.begins_with("parameters/") and property_name.ends_with("/scale"):
			return property_name
	return ""


## Busca el playback de la maquina de estados, este donde este dentro del arbol
## (si la raiz es la propia maquina, esta en "parameters/playback"; si hay capas
## encima, en "parameters/<Nombre>/playback").
func _find_playback() -> AnimationNodeStateMachinePlayback:
	var direct: Variant = animation_tree.get("parameters/playback")
	if direct is AnimationNodeStateMachinePlayback:
		return direct as AnimationNodeStateMachinePlayback
	for property in animation_tree.get_property_list():
		var property_name := String(property["name"])
		if property_name.begins_with("parameters/") and property_name.ends_with("/playback"):
			var found: Variant = animation_tree.get(property_name)
			if found is AnimationNodeStateMachinePlayback:
				return found as AnimationNodeStateMachinePlayback
	return null


func _find_animation(player: AnimationPlayer, state: StringName) -> Animation:
	for library_name: StringName in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		if library != null and library.has_animation(state):
			return library.get_animation(state)
	return null


func _format_report(report: Dictionary) -> String:
	var missing := report["missing_bones"] as PackedStringArray
	var text := "%d tracks revisados, %d huesos remapeados por bone_name_map" % [int(report["tracks"]), int(report["remapped_bones"])]
	if not missing.is_empty():
		text += ". Huesos no encontrados en el modelo: %s" % ", ".join(missing)
	return text
