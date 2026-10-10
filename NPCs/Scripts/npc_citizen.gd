class_name NPCCitizen
extends CharacterBody3D

## Ciudadano autónomo.
##
## Máquina de estados con variaciones aleatorias propias de cada ciudadano:
##
##   IDLE --(espera)--> DECIDE --(destino válido)--> WALK --> ARRIVE --> IDLE
##                        |                          |
##                        |                          +--> PAUSE (se detiene y sigue)
##                        +--(nada que hacer)             TURN  (gira en el sitio y sigue)
##
## Ningún ciudadano va en sincronía con otro: cada uno sortea su tempo, su velocidad
## (escala de animación incluida, para que los pies no patinen) y sus clips, así que no
## se ven clones haciendo lo mismo al mismo tiempo.
##
## Escalabilidad: el NPCSpawner asigna un nivel de actividad según la distancia al jugador
## (cerca = todo activo, media = sin evitación, lejos = congelado), de modo que se pueden
## tener cientos de ciudadanos en la ciudad pagando sólo por los que se ven de cerca.

enum State { IDLE, DECIDE, WALK, PAUSE, TURN, ARRIVE, NOTICE, REACT }

## Nivel de actividad (LOD de comportamiento). Lo asigna el NPCSpawner.
enum Activity { NEAR, MID, FAR }

## Tipos de reacción al jugador; cada ciudadano sortea uno con estos pesos.
## (Se descartó "saludar con la mano": el único clip de saludo de los packs, UAL2 "Yes", al pasarlo
## a estos rigs queda con pose de caminar. En su lugar está REACT_GREET, que se para y hace un gesto
## de los que YA están horneados y medidos: asentir, negar, señalar o recoger algo.)
const REACT_LOOK := 0   ## sigue a lo suyo y sólo gira la cabeza de reojo
const REACT_STOP := 1   ## se para y lo mira
const REACT_TURN := 2   ## se para y se gira de cuerpo entero hacia él
const REACT_GREET := 3  ## se para y le dedica un gesto breve
const REACT_WEIGHTS := [0.40, 0.24, 0.20, 0.16]

## Huecos de idle de la máquina de estados compartida. Cada ciudadano recibe en ellos CUATRO clips
## distintos y va pasando de uno a otro: quieto nunca se ve dos veces la misma postura.
const IDLE_SLOTS := ["idle", "idle_b", "idle_c", "idle_d"]

## Librería de animaciones del rig Mixamo (los modelos PSX de siempre).
const SHARED_LIBRARY := "res://NPCs/Animations/Citizen_Animations.res"
## Librería del rig Auto-Rig Pro (City Folks / Urban Man). Se hornea con el mismo horneador a
## partir de los MISMOS clips ya validados, más la carrera y los giros del pack RPG.
const SHARED_LIBRARY_ARP := "res://NPCs/Animations/Citizen_Animations_ARP.res"
const LOCOMOTION_TREE := "res://NPCs/Animations/Citizen_Locomotion.tres"

const LAYER_WORLD := 1  # capa 1: terreno/edificios
const LAYER_NPC := 2    # capa 2: ciudadanos

## Clips disponibles por tipo de cuerpo y uso; cada ciudadano elige los suyos al azar.
##
## OJO: sólo entran caminatas e idles CIVILES. Se midió cada clip del pack y se descartaron
## tres que no lo eran (daban el aspecto de "llevar algo en las manos" o de estar de brazos
## cruzados): UAL "Walk_Carry" (brazos adelantados 0,19 m y codo 57°), "Walk_Formal" (los
## brazos apenas se mueven) e "Idle_FoldArms" (codo 103°). Tampoco se usa "Sprint", que con
## el paso de trote deja una zancada exagerada: para ir con prisa ya están "Jog_Fwd" y "Run".
const CLIP_POOLS := {
	## Ciudadanos del rig nuevo (City Folks / Urban Man): tienen a mano los 23 clips horneados
	## para ese rig, mezclando los dos sexos de origen y los giros y las carreras del pack RPG.
	"poly": {
		"idle": ["idle_m1", "idle_m2", "idle_u1", "idle_u3", "idle_f1", "idle_f2"],
		"walk": ["walk_m1", "walk_f1", "walk_u1"],
		"jog": ["jog_u1", "run_m1", "run_f1", "run_fwd_rpg"],
		"turn_l": ["turn_m1_l", "turn_f1_l", "turn90_l_rpg"],
		"turn_r": ["turn_m1_r", "turn_f1_r", "turn90_r_rpg"],
	},
	"male": {
		"idle": ["idle_m1", "idle_m2", "idle_u1", "idle_u3"],
		"walk": ["walk_m1", "walk_u1"],
		"jog": ["jog_u1", "run_m1"],
		"turn_l": ["turn_m1_l"],
		"turn_r": ["turn_m1_r"],
	},
	"female": {
		"idle": ["idle_f1", "idle_f2", "idle_u1", "idle_u3"],
		"walk": ["walk_f1", "walk_u1"],
		"jog": ["jog_u1", "run_f1"],
		"turn_l": ["turn_f1_l"],
		"turn_r": ["turn_f1_r"],
	},
}

## Clips que están horneados pero NO se usan, con el motivo medido. Están apuntados aquí para que no
## vuelvan a colarse solos al añadir animaciones nuevas a la librería (el sorteo se hace por
## categorías, no por listas a mano: ver POOL_OF_KIND).
const CLIPS_NOT_USED := {
	"idle_m3": "dura 0,67 s: es la transición entre dos idles, en bucle parece un tic",
	"run_u1": "es el Sprint de UAL1: 3,28 m/s de zancada, exagerada para un peatón",
	"sprint_rpg": "1,89 alturas de paso: carrera de atleta, no de transeúnte",
}

## Qué pool le toca a cada categoría ("kind" es el metadato con el que el horneador clasifica cada
## clip). Los clips se leen de la librería y se reparten con esta tabla, así que añadir animaciones
## nuevas al pack es hornearlas y ya entran solas en el sorteo, sin tocar este archivo.
const POOL_OF_KIND := {
	"idle": "idle", "social": "idle", "walk": "walk", "jog": "jog", "run": "jog",
	"turn": "turn", "react": "react",
}

@export_group("Modelo")
## Escena del modelo (los FBX de NPCs/Characters/PSX). Se instancia como hijo "Model".
@export var model_scene: PackedScene
@export_enum("male", "female") var body_type: String = "male"
## Sortea las piezas del cuerpo (cabeza, torso, manos, piernas y pies) para que no haya dos
## ciudadanos iguales. Se apaga para ver un modelo tal cual viene del paquete.
@export var vary_model_parts := true
## Monta la capa de decisión con planificador por objetivos (addon GdPlanningAI): el ciudadano
## decide pasear, descansar o acercarse a curiosear al jugador valorando coste y recompensa.
## El planificador por agente cuesta CPU, así que conviene activarlo sólo en los del nivel NEAR.
@export var use_goap := false

@export_group("Comportamiento")
## Zona (en coordenadas de mundo, XZ) por la que puede deambular.
@export var wander_area := Rect2(-28.0, -28.0, 56.0, 56.0)
## Tiempo quieto antes de elegir un nuevo destino.
@export var idle_time := Vector2(1.5, 6.0)
## Radio a partir del cual se considera que llegó al destino.
@export var arrival_distance := 0.7
## Viaje mínimo y máximo (metros) de cada trayecto.
@export var trip_distance := Vector2(6.0, 22.0)

@export_group("Personalidad")
## Si está activo, cada ciudadano sortea su propia personalidad al aparecer (no hay dos iguales).
@export var randomize_personality := true
## Multiplicador de velocidad; afecta al movimiento Y a la animación (los pies no patinan).
@export_range(0.6, 1.4) var move_scale := 1.0
## Probabilidad de ir con el paso acelerado (trote) en un trayecto.
@export_range(0.0, 1.0) var hurry_chance := 0.15
## Probabilidad de detenerse un momento a mitad de camino.
@export_range(0.0, 1.0) var pause_chance := 0.2
## Probabilidad de girar en el sitio (con su clip de giro) antes de retomar el paso.
@export_range(0.0, 1.0) var turn_chance := 0.15
## Probabilidad de mirar alrededor mientras espera.
@export_range(0.0, 1.0) var look_chance := 0.3
## Probabilidad de decidir quedarse quieto en vez de caminar (Idle -> Idle -> Walk).
@export_range(0.0, 1.0) var stay_chance := 0.15

@export_group("Reacciones al jugador")
## Distancia (metros) a la que un ciudadano se da cuenta del jugador.
@export var notice_distance := 9.0
## Por debajo de esta distancia se fijan en él aunque ya estuvieran dentro del radio.
@export var close_distance := 3.0
## Probabilidad de reaccionar al notarlo: el resto sigue a lo suyo (nada de reaccionar en masa).
@export_range(0.0, 1.0) var reaction_chance := 0.6
## Espera mínima y máxima (segundos) antes de poder volver a reaccionar.
@export var reaction_cooldown := Vector2(12.0, 28.0)
## Máximo que gira la cabeza sin mover el cuerpo (grados).
@export_range(15.0, 90.0) var head_yaw_limit := 60.0
## Máximo que sube o baja la mirada (grados).
@export_range(5.0, 45.0) var head_pitch_limit := 25.0
## Altura del jugador a la que miran (cara/pecho).
@export var look_at_height := 1.5

@export_group("Movimiento")
## Giro máximo (radianes por segundo) al cambiar de dirección; evita giros bruscos.
@export_range(0.5, 12.0) var turn_rate := 3.5
## Distancia a la que empieza a frenar al llegar.
@export var brake_distance := 0.9
## Tiempo sin avanzar que dispara el recálculo de ruta (anti-atasco).
@export var stuck_timeout := 2.0

@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _player: AnimationPlayer = $AnimationPlayer
@onready var _tree: AnimationTree = $AnimationTree

var state: State = State.IDLE
var activity: Activity = Activity.NEAR
var walk_speed := 1.2
var jog_speed := 2.5
var _idle_timer := 0.0
var _pause_timer := 0.0
var _arrive_timer := 0.0
var _turn_timer := 0.0
var _turn_duration := 0.5
var _turn_yaw := 0.0
var _variant_pending := false
var _variant_at := 0.0
var _face_yaw := 0.0
var _stuck_timer := 0.0
var _last_position := Vector3.ZERO
var _trip_start := Vector3.ZERO
var _trip_length := 1.0
var _pause_at := -1.0
var _turn_at := -1.0
var _hurrying := false
var _looking := false
var _look_yaw := 0.0
var _pending_freeze := false
var _freeze_timer := 0.0
var _playback: AnimationNodeStateMachinePlayback
var _active_clip := ""
var _idle_slot := ""   # hueco de idle en el que está ahora ("idle", "idle_b", "idle_c" o "idle_d")
# --- reacciones al jugador (Etapa 3)
var _player_node: Node3D
var _look_target: Node3D
var _look: NPCLookAt
var _watch := 0.0           # fundido de la mirada: 0 = no mira, 1 = mira al máximo
var _watching := false
var _notice_timer := 0.0    # comprobación escalonada y enfriamiento entre reacciones
var _noticed_inside := false
var _notice_hold := 0.0
var _react_timer := 0.0
var _react_kind := REACT_LOOK
var _was_walking := false
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _is_arp := false                 # el modelo es del rig nuevo (City Folks / Urban Man)
var _goap: NPCGoapBrain = null       # capa de decisión opcional (GdPlanningAI)
var _goap_seek := false              # el planificador le mandó ir a ver al jugador


func _ready() -> void:
	_rng.randomize()
	collision_layer = LAYER_NPC
	collision_mask = LAYER_WORLD
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if randomize_personality:
		_randomize_personality()

	_spawn_model()
	_setup_animation()
	_setup_agent()
	_setup_goap()
	_enter_idle(true)


# ------------------------------------------------------------------ preparación

func _spawn_model() -> void:
	if model_scene == null:
		push_warning("NPCCitizen sin model_scene (nodo: %s)" % name)
		return
	var model := model_scene.instantiate()
	# El nombre debe ser exactamente "Model": las pistas de animación son "Model/Skeleton3D:hueso".
	model.name = "Model"
	add_child(model)
	# Los packs nuevos (City Folks / Urban Man) cuelgan el esqueleto de un nodo intermedio y traen
	# las mallas separadas por pieza: se reestructura la jerarquía y se sortean las piezas para
	# que no haya dos ciudadanos iguales.
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_is_arp = NPCCitizenModel.is_arp_rig(skeleton)
	if _is_arp:
		# El color de la ropa se sortea aparte del cuerpo: así se combinan libremente (cualquier
		# cuerpo con cualquier ropa) y de ahí sale la variedad de aspecto.
		var plan := NPCCitizenModel.plan_variants(_rng) if vary_model_parts else {}
		NPCCitizenModel.prepare(model, _rng, vary_model_parts, NPCCitizenModel.PARTS, plan)
	# Acabado común a los dos rigs: brillo suave y perfilado (rim) para que el cuerpo se lea como
	# un volumen y no como una calcomanía plana. Se hace sobre copias, el pack queda intacto.
	NPCCitizenModel.polish_materials(model)
	_face_yaw = _detect_face_yaw(model)
	_setup_look(model)


## Prepara la mirada: busca el hueso de la cabeza y le cuelga el modificador que la gira.
## Si el modelo no tiene esqueleto ni cabeza (modelo raro), simplemente no mira y ya está.
func _setup_look(model: Node) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var head := -1
	for i in skeleton.get_bone_count():
		var bone_lower := String(skeleton.get_bone_name(i)).to_lower()
		# Rigs Mixamo: "mixamorig_Head". Rigs Auto-Rig Pro: "head.x".
		if bone_lower.ends_with("head") or bone_lower.begins_with("head"):
			head = i
			break
	if head < 0:
		return
	# Punto al que mira: se coloca en la cara del jugador cada vez que lo mira.
	_look_target = Node3D.new()
	_look_target.name = "LookTarget"
	_look_target.position = Vector3(0.0, look_at_height, 1.5)
	add_child(_look_target)
	_look = NPCLookAt.new()
	_look.name = "LookAt"
	_look.setup(String(skeleton.get_bone_name(head)), _look_target, head_yaw_limit, head_pitch_limit)
	skeleton.add_child(_look)


## Los tres rigs miran hacia +Z; se mide igualmente para que agregar modelos no rompa el giro.
func _detect_face_yaw(model: Node) -> float:
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return 0.0
	var left := _find_bone(skeleton, ["mixamorig_LeftArm", "arm_stretch.l", "B_L_UpperArm"])
	var right := _find_bone(skeleton, ["mixamorig_RightArm", "arm_stretch.r", "B_R_UpperArm"])
	if left < 0 or right < 0:
		return 0.0
	var axis := skeleton.get_bone_global_rest(left).origin - skeleton.get_bone_global_rest(right).origin
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		return 0.0
	var forward := axis.normalized().cross(Vector3.UP)
	return atan2(forward.x, forward.z)


func _setup_animation() -> void:
	var library_path := SHARED_LIBRARY_ARP if _is_arp else SHARED_LIBRARY
	var shared: AnimationLibrary = load(library_path)
	if shared == null:
		push_error("NPCCitizen: falta %s" % library_path)
		return
	var wanted: Dictionary = _select_clips(shared)
	var library := AnimationLibrary.new()
	for slot: String in wanted:
		if String(wanted[slot]) == "":
			continue
		var anim: Animation = shared.get_animation(wanted[slot])
		if anim == null:
			push_warning("NPCCitizen: falta el clip %s" % wanted[slot])
			continue
		library.add_animation(slot, anim)
	# La librería por defecto ("") es la que resuelve el AnimationTree al pedir "idle"/"walk".
	_player.add_animation_library("", library)
	_tree.tree_root = load(LOCOMOTION_TREE)
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	# La velocidad de avance sale de la animación -> pies sincronizados con el movimiento.
	walk_speed = float((shared.get_animation(wanted["walk"]) as Animation).get_meta("speed", 1.2))
	jog_speed = float((shared.get_animation(wanted["jog"]) as Animation).get_meta("speed", 2.5))
	# La escala personal afecta por igual al avance y a la animación: nunca patina.
	_player.speed_scale = move_scale
	_active_clip = String(wanted["walk"])


## Sortea el repertorio de clips de este ciudadano: qué clip le toca a cada nombre que pide la
## máquina de estados compartida. Se separa del montaje porque es la parte que interesa comprobar.
func _select_clips(shared: AnimationLibrary) -> Dictionary:
	var pool: Dictionary = _pools_from_library(shared)
	if not _is_arp:
		# Los modelos PSX de siempre tienen menos clips: se quedan con sus repertorios civiles por
		# sexo, ya medidos, y de la librería sólo toman las categorías nuevas (los gestos).
		var gender: Dictionary = CLIP_POOLS.get(body_type, CLIP_POOLS["male"])
		for key: String in ["idle", "walk", "jog", "turn_l", "turn_r"]:
			pool[key] = gender[key]
	var walk_clip: String = _pick_clip(pool["walk"])
	var jog_clip: String = _pick_clip(pool["jog"])
	if jog_clip == "":
		jog_clip = walk_clip
	# Cuatro huecos de idle DISTINTOS por ciudadano (la máquina de estados va pasando de uno a otro).
	var idles: Array = _pick_clips(pool["idle"], IDLE_SLOTS.size())
	while idles.size() < IDLE_SLOTS.size():
		idles.append(walk_clip)
	# Cada ciudadano entrega SUS clips a los mismos nombres: un solo recurso de máquina de estados
	# sirve para todos y aun así ninguno se mueve igual que otro.
	return {
		"idle": idles[0],
		"idle_b": idles[1],
		"idle_c": idles[2],
		"idle_d": idles[3],
		"walk": walk_clip,
		"jog": jog_clip,
		"turn_l": _pick_clip(pool["turn_l"]),
		"turn_r": _pick_clip(pool["turn_r"]),
		"react": _pick_clip(pool["react"]),
	}


func _pick_clip(options: Array, avoid := "") -> String:
	if options.is_empty():
		return ""
	if avoid != "" and options.size() > 1:
		var filtered: Array = []
		for option in options:
			if String(option) != avoid:
				filtered.append(option)
		if not filtered.is_empty():
			options = filtered
	return String(options[_rng.randi() % options.size()])


## Saca varios clips DISTINTOS (sin repetir) para los huecos de idle.
func _pick_clips(options: Array, count: int) -> Array:
	var result: Array = []
	var bag: Array = options.duplicate()
	while result.size() < count:
		if bag.is_empty():
			bag = options.duplicate()
			if bag.is_empty():
				return result
		var index := _rng.randi() % bag.size()
		result.append(String(bag[index]))
		bag.remove_at(index)
	return result


## Reparte los clips de la librería por categorías usando el metadato "kind" con el que se
## hornearon. Los clips sin categoría conocida y los de la lista de descartados se quedan fuera.
func _pools_from_library(shared: AnimationLibrary) -> Dictionary:
	var pools := {"idle": [], "walk": [], "jog": [], "turn_l": [], "turn_r": [], "react": []}
	for clip: String in shared.get_animation_list():
		if CLIPS_NOT_USED.has(clip):
			continue
		var anim: Animation = shared.get_animation(clip)
		var pool := String(POOL_OF_KIND.get(String(anim.get_meta("kind", "")), ""))
		if pool == "":
			continue
		if pool == "turn":
			# El lado del giro va en el nombre del clip ("_l" izquierda, "_r" derecha).
			pools["turn_l" if clip.contains("_l") else "turn_r"].append(clip)
		else:
			pools[pool].append(clip)
	return pools


## Pasa a otro hueco de idle, nunca el mismo que el de la vez anterior: un ciudadano que se para
## muchas veces no repite siempre la misma postura.
func _goto_idle_slot(avoid := "") -> void:
	if _playback == null:
		return
	var slot := _pick_clip(IDLE_SLOTS, avoid)
	if slot == "":
		return
	_idle_slot = slot
	_playback.travel(slot)


## Cada ciudadano sortea su propio carácter para que no se comporten como clones.
func _randomize_personality() -> void:
	move_scale = _rng.randf_range(0.85, 1.15)
	hurry_chance = _rng.randf_range(0.05, 0.3)
	pause_chance = _rng.randf_range(0.1, 0.35)
	turn_chance = _rng.randf_range(0.05, 0.3)
	look_chance = _rng.randf_range(0.15, 0.5)
	stay_chance = _rng.randf_range(0.05, 0.25)
	# Quieto: unos descansan un momento y otros se quedan un buen rato, cada uno con su medida.
	idle_time = Vector2(_rng.randf_range(1.0, 3.5), _rng.randf_range(4.0, 9.0))
	# Reacciones: unos son muy sociables y otros pasan del jugador; también varía cuánto
	# pueden girar la cabeza, así que no todos reaccionan igual ni miran igual.
	reaction_chance = _rng.randf_range(0.35, 0.85)
	head_yaw_limit = _rng.randf_range(45.0, 75.0)
	head_pitch_limit = _rng.randf_range(15.0, 30.0)
	reaction_cooldown = Vector2(_rng.randf_range(10.0, 14.0), _rng.randf_range(22.0, 32.0))


func _setup_agent() -> void:
	_agent.radius = 0.4
	_agent.height = 1.7
	_agent.path_desired_distance = 0.4
	_agent.target_desired_distance = arrival_distance
	_agent.path_max_distance = 3.0
	_agent.avoidance_enabled = activity == Activity.NEAR
	_agent.neighbor_distance = 6.0
	_agent.max_neighbors = 6
	_agent.max_speed = _move_speed()
	_agent.velocity_computed.connect(_on_velocity_computed)
	_last_position = global_position
	_trip_start = global_position


# ------------------------------------------- API para el planificador (GdPlanningAI)

## Busca el primer hueso que exista de una lista de candidatos (cada rig usa sus nombres).
func _find_bone(skeleton: Skeleton3D, candidates: Array) -> int:
	for candidate: String in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1


## Monta la capa de decisión (addon GdPlanningAI) si este ciudadano la tiene activada.
## El planificador necesita un GdPAIWorldNode en la escena; si no lo hay se avisa y se sigue
## con la máquina de estados de siempre.
func _setup_goap() -> void:
	if not use_goap:
		return
	var world: GdPAIWorldNode = GdPAIUTILS.get_child_of_type(get_tree().root, GdPAIWorldNode) as GdPAIWorldNode
	if world == null:
		push_warning("NPCCitizen (%s): use_goap activado pero no hay GdPAIWorldNode" % name)
		return
	_goap = NPCGoapBrain.new()
	_goap.setup(self)
	add_child(_goap)


## ¿Está en condiciones de que el planificador le mande ir a ver al jugador?
func goap_can_seek() -> bool:
	return activity == Activity.NEAR and is_watching() and state != State.NOTICE and state != State.REACT


## ¿Va andando ahora mismo?
func goap_is_walking() -> bool:
	return state == State.WALK or state == State.PAUSE or state == State.TURN


## ¿Se quedó quieto esperando a alguien (o descansando)?
func goap_is_resting() -> bool:
	return state == State.IDLE or state == State.DECIDE


## ¿El planificador le mandó ir a ver al jugador?
func goap_is_seeking() -> bool:
	return _goap_seek


## Orden del planificador: pasear a un destino nuevo.
func wander_to_new_destination() -> bool:
	_goap_seek = false
	if state == State.NOTICE or state == State.REACT:
		return false
	if not _pick_destination():
		_enter_idle()
		return false
	_enter_walk()
	return true


## Orden del planificador: quedarse quieto un rato.
func rest_for(seconds: float) -> void:
	_goap_seek = false
	_enter_idle()
	_idle_timer = maxf(seconds, 0.5)


## ¿Hay jugador en la escena?
func has_player() -> bool:
	return _look_target != null


## Posición del jugador (la usa el planificador para valorar si merece la pena acercarse).
func player_position() -> Vector3:
	return _look_target.global_position if _look_target != null else Vector3.ZERO


## Orden del planificador: acercarse al jugador hasta quedarse a `stop_distance`.
## Devuelve false si ya estaba lo bastante cerca (entonces sólo se queda mirándolo).
func approach_player(stop_distance := 2.6) -> bool:
	if _look_target == null or _agent == null:
		return false
	var to_player := _look_target.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= stop_distance + 0.5:
		_goap_seek = true
		return false
	_agent.target_position = _look_target.global_position - to_player.normalized() * stop_distance
	if not _agent.is_target_reachable():
		return false
	_goap_seek = true
	_enter_walk()
	return true


# ------------------------------------------------------------------ estados

func _enter_idle(first := false) -> void:
	state = State.IDLE
	_looking = false
	_idle_timer = _rng.randf_range(0.6, 2.0) if first else _rng.randf_range(idle_time.x, idle_time.y)
	# En esperas largas se sortea una variación de idle (una sola vez por espera):
	# el ciudadano pasa a otro clip de idle y vuelve, así no se ve congelado.
	_variant_pending = _idle_timer > 3.0
	_variant_at = _idle_timer * 0.45
	if _rng.randf() < look_chance:
		_looking = true
		_look_yaw = rotation.y + _rng.randf_range(-1.1, 1.1)
	_goto_idle_slot(_idle_slot)


## Se queda quieto un momento (en mitad de un trayecto) y luego retoma el paso.
func _enter_pause(min_time := 1.0, max_time := 3.0) -> void:
	state = State.PAUSE
	_pause_timer = _rng.randf_range(min_time, max_time)
	_goto_idle_slot(_idle_slot)


## Estado de un solo fotograma: aquí se decide qué hacer después.
func _enter_decide() -> void:
	state = State.DECIDE


func _decide() -> void:
	# Con planificador de objetivos: aquí no se sortea nada, se espera su próxima orden
	# (mientras tanto se queda quieto, que es justo lo que hace _enter_idle).
	if _goap != null:
		_enter_idle()
		return
	# A veces decide no moverse todavía (Idle -> Idle -> Walk).
	if _rng.randf() < stay_chance:
		_enter_idle()
		return
	if not _pick_destination():
		_enter_idle()
		return
	_enter_walk()


func _enter_walk() -> void:
	state = State.WALK
	_stuck_timer = 0.0
	_last_position = global_position
	_trip_start = global_position
	_trip_length = maxf(global_position.distance_to(_agent.target_position), 0.5)
	_hurrying = _rng.randf() < hurry_chance
	# Sucesos del trayecto (como mucho uno de cada tipo), en un punto intermedio del camino.
	_pause_at = _rng.randf_range(0.3, 0.7) if _rng.randf() < pause_chance else -1.0
	_turn_at = _rng.randf_range(0.2, 0.6) if _rng.randf() < turn_chance else -1.0
	_set_locomotion()
	_agent.max_speed = _move_speed()


func _resume_walk() -> void:
	state = State.WALK
	_set_locomotion()


func _enter_arrive() -> void:
	state = State.ARRIVE
	_arrive_timer = _rng.randf_range(0.2, 0.8)
	_goto_idle_slot(_idle_slot)


## Giro en el sitio con su propio clip (Caminar -> Girar -> Caminar) antes de retomar el paso.
func _enter_turn() -> void:
	var next := _agent.get_next_path_position()
	var offset := next - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		_resume_walk()
		return
	state = State.TURN
	_turn_timer = 0.0
	_turn_yaw = atan2(offset.x, offset.z) - _face_yaw
	var yaw_step := wrapf(_turn_yaw - rotation.y, -PI, PI)
	_turn_duration = clampf(absf(yaw_step) / 3.0, 0.35, 0.9)
	if _playback:
		# El signo se midió sobre el clip: "turn_l" es el que acaba el cuerpo girado a la izquierda,
		# y girar hacia la izquierda es restar al ángulo (rotación.y positiva gira a la derecha).
		_playback.travel("turn_r" if yaw_step > 0.0 else "turn_l")


func _set_locomotion() -> void:
	if _playback:
		_playback.travel("jog" if _hurrying else "walk")


## Busca un destino alcanzable dentro de wander_area y comprueba que se pueda llegar andando.
func _pick_destination() -> bool:
	var map := _agent.get_navigation_map()
	for attempt in 14:
		var point := Vector3(
			_rng.randf_range(wander_area.position.x, wander_area.end.x),
			0.0,
			_rng.randf_range(wander_area.position.y, wander_area.end.y)
		)
		# 1) el punto debe caer sobre la malla de navegación (no en un tejado ni en el vacío)
		var closest := NavigationServer3D.map_get_closest_point(map, point)
		if point.distance_to(closest) > 2.0:
			continue
		# 2) longitud de viaje razonable (ni dos pasos ni cruzar toda la ciudad)
		var distance := closest.distance_to(global_position)
		if distance < trip_distance.x or distance > trip_distance.y:
			continue
		# 3) debe existir camino hasta él (si está en una isla inalcanzable, se descarta)
		if not _is_reachable(map, closest):
			continue
		_agent.target_position = closest
		return true
	return false


func _is_reachable(map: RID, target: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, global_position, target, true)
	if path.size() < 2:
		return false
	return (path[path.size() - 1] as Vector3).distance_to(target) < 1.5


func _move_speed() -> float:
	var base := jog_speed if _hurrying else walk_speed
	return base * move_scale


# ------------------------------------------------------------------ física

func _physics_process(delta: float) -> void:
	# Congelado (nivel lejano): se deja terminar el fundido hacia idle y se apaga la animación.
	if _pending_freeze:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_pending_freeze = false
			_player.process_mode = Node.PROCESS_MODE_DISABLED
			set_physics_process(false)
			return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	# Reacciones sociales (mirar al jugador): fundido de la mirada y, si toca, cambio de estado.
	_update_reactions(delta)

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			_update_looking(delta)
			_idle_timer -= delta
			if _variant_pending and _idle_timer <= _variant_at:
				_variant_pending = false
				# Cambia de postura a mitad de la espera (y nunca a la misma): quieto se le ve
				# moverse sin llegar a caminar.
				_goto_idle_slot(_idle_slot)
			if _idle_timer <= 0.0:
				_enter_decide()
		State.DECIDE:
			_decide()
		State.WALK:
			desired = _walk_desired_velocity(delta)
			if state != State.WALK:
				desired = Vector3.ZERO
		State.PAUSE:
			_pause_timer -= delta
			if _pause_timer <= 0.0:
				_resume_walk()
		State.TURN:
			desired = _turn_desired_velocity(delta)
		State.ARRIVE:
			_arrive_timer -= delta
			if _arrive_timer <= 0.0:
				_enter_idle()
		State.NOTICE:
			# Se ha dado cuenta del jugador: si iba andando sigue andando (mirando de reojo),
			# y al cabo de un instante decide qué hacer.
			if _was_walking:
				desired = _walk_desired_velocity(delta)
				if state != State.NOTICE:
					desired = Vector3.ZERO
			_notice_hold -= delta
			if _notice_hold <= 0.0 and state == State.NOTICE:
				_enter_react()
		State.REACT:
			if _react_kind == REACT_LOOK and _was_walking:
				# Sólo mira de reojo: sigue su camino sin pararse.
				desired = _walk_desired_velocity(delta)
				if state != State.REACT:
					desired = Vector3.ZERO
			else:
				desired = _react_desired_velocity(delta)

	if _agent.avoidance_enabled:
		# La velocidad segura llega por _on_velocity_computed (evita chocar con otros NPCs).
		_agent.set_velocity(desired)
	else:
		_apply_horizontal(desired)
		move_and_slide()

	if state != State.TURN:
		_update_facing(delta, desired)


## Gira despacio hacia el lado que le tocó mirar mientras espera.
func _update_looking(delta: float) -> void:
	if not _looking:
		return
	rotation.y = lerp_angle(rotation.y, _look_yaw, 1.0 - exp(-1.2 * delta))
	if absf(wrapf(_look_yaw - rotation.y, -PI, PI)) < 0.05:
		_looking = false


func _turn_desired_velocity(delta: float) -> Vector3:
	_turn_timer += delta
	rotation.y = lerp_angle(rotation.y, _turn_yaw, 1.0 - exp(-8.0 * delta))
	if _turn_timer >= _turn_duration:
		_resume_walk()
	return Vector3.ZERO


func _walk_desired_velocity(delta: float) -> Vector3:
	var target := _agent.get_next_path_position()
	var offset := target - global_position
	offset.y = 0.0
	var remaining := global_position.distance_to(_agent.target_position)
	if _agent.is_navigation_finished() or remaining <= arrival_distance:
		_enter_arrive()
		return Vector3.ZERO
	# Sucesos de mitad de trayecto: pararse un momento o girar en el sitio (Idle/Walk -> Turn).
	var progress := clampf(1.0 - remaining / _trip_length, 0.0, 1.0)
	if _pause_at > 0.0 and progress >= _pause_at:
		_pause_at = -1.0
		_enter_pause(1.0, 3.0)
		return Vector3.ZERO
	if _turn_at > 0.0 and progress >= _turn_at and activity == Activity.NEAR:
		_turn_at = -1.0
		_enter_turn()
		return Vector3.ZERO
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	var direction := offset.normalized()
	# Frena sólo en el último tramo; el resto del recorrido va a la velocidad de la animación.
	var speed := _move_speed()
	if remaining < brake_distance:
		speed *= maxf(remaining / brake_distance, 0.35)
	# Al elegir un destino, el NPC gira suavemente: mientras no mire hacia donde avanza
	# reduce la velocidad, así nunca se desplaza de espaldas ni en diagonal forzada.
	var facing := Vector3(sin(rotation.y + _face_yaw), 0.0, cos(rotation.y + _face_yaw))
	speed *= clampf(facing.dot(direction), 0.0, 1.0)
	_check_stuck(delta)
	return direction * speed


## Si avanza menos de lo esperado durante `stuck_timeout`, busca otro destino.
func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < stuck_timeout:
		return
	_stuck_timer = 0.0
	if global_position.distance_to(_last_position) < 0.3:
		if not _pick_destination():
			_enter_idle()
		else:
			_trip_length = maxf(global_position.distance_to(_agent.target_position), 0.5)
			_pause_at = -1.0
			_turn_at = -1.0
	_last_position = global_position


func _update_facing(delta: float, desired: Vector3) -> void:
	if desired.length_squared() < 0.0001:
		return
	var target_yaw := atan2(desired.x, desired.z) - _face_yaw
	# Suavizado exponencial: independiente del framerate y sin giros bruscos.
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_rate * delta))


func _apply_horizontal(desired: Vector3) -> void:
	velocity.x = desired.x
	velocity.z = desired.z


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


# ------------------------------------------------------------------ reacciones al jugador

## Comprueba, de vez en cuando, si el jugador anda cerca y si este ciudadano le hace caso.
## Sólo en el nivel NEAR: los que están lejos no gastan nada en mirar a nadie.
func _update_reactions(delta: float) -> void:
	_update_watch(delta)
	if activity != Activity.NEAR or state == State.NOTICE or state == State.REACT:
		return
	_notice_timer -= delta
	if _notice_timer > 0.0:
		return
	# Cada ciudadano comprueba cada 0,25-0,5 s (desfasados): no todos miran al jugador a la vez.
	_notice_timer = _rng.randf_range(0.25, 0.5)
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node3D
		if _player_node == null:
			return
	var to_player := _player_node.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > notice_distance:
		_noticed_inside = false
		return
	var entered := not _noticed_inside
	_noticed_inside = true
	# Si le pasa muy cerca y además se mueve, se fijan en él aunque ya estuvieran dentro.
	var insist := distance <= close_distance and _player_speed() > 0.6
	if not entered and not insist:
		return
	if _rng.randf() > reaction_chance:
		_notice_timer = _rng.randf_range(1.0, 2.0)  # éste pasa del jugador (volverá a mirar luego)
		return
	_enter_notice()


func _player_speed() -> float:
	if _player_node is CharacterBody3D:
		return (_player_node as CharacterBody3D).velocity.length()
	return 0.0


## Fase 1: se ha dado cuenta del jugador y empieza a mirarlo de reojo. Dura un instante
## distinto en cada ciudadano, para que no reaccionen todos a la vez.
func _enter_notice() -> void:
	_was_walking = state == State.WALK or state == State.PAUSE or state == State.TURN
	state = State.NOTICE
	_notice_hold = _rng.randf_range(0.35, 0.9)
	_watching = true


## Fase 2: sortea QUÉ reacción tiene (mirar de reojo, pararse o girarse entero).
func _enter_react() -> void:
	_was_walking = _was_walking or state == State.WALK
	state = State.REACT
	_react_kind = _pick_reaction()
	# Cada reacción dura lo suyo, y lo sortea cada ciudadano: no reaccionan como un coro.
	match _react_kind:
		REACT_GREET:
			# Le dedica un gesto breve en vez de quedarse quieto mirándolo.
			_react_timer = _rng.randf_range(1.4, 2.8)
			if _playback:
				_playback.travel("react")
			return
		REACT_TURN:
			_react_timer = _rng.randf_range(1.6, 3.4)
		_:
			_react_timer = _rng.randf_range(0.9, 2.6)
	# El que sólo mira de reojo mientras camina NO cambia de clip: si no, las piernas patinarían
	# (el cuerpo avanzaría con la animación de quieto).
	var keeps_walking: bool = _was_walking and _react_kind == REACT_LOOK
	if _playback and not keeps_walking and not IDLE_SLOTS.has(_playback.get_current_node()):
		_goto_idle_slot(_idle_slot)


func _pick_reaction() -> int:
	var total := 0.0
	for weight in REACT_WEIGHTS:
		total += float(weight)
	var roll := _rng.randf() * total
	for i in REACT_WEIGHTS.size():
		roll -= float(REACT_WEIGHTS[i])
		if roll <= 0.0:
			return i
	return REACT_LOOK


## Estado REACT cuando el ciudadano se ha parado: mantiene la mirada (y el cuerpo girado si
## le tocó girarse) hasta que se le acaba el tiempo, y luego vuelve a lo que estaba haciendo.
func _react_desired_velocity(delta: float) -> Vector3:
	_react_timer -= delta
	if _react_kind == REACT_TURN and _player_node != null:
		var to_player := _player_node.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.0001:
			# Se gira de cuerpo entero, pero despacio: nunca de golpe.
			var target_yaw := atan2(to_player.x, to_player.z) - _face_yaw
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-2.2 * delta))
	if _react_timer <= 0.0:
		_finish_reaction()
	return Vector3.ZERO


## Se acaba la reacción: deja de mirar, espera un rato antes de volver a fijarse y retoma lo
## que estaba haciendo (seguir su trayecto o quedarse quieto donde estaba).
func _finish_reaction() -> void:
	_watching = false
	_noticed_inside = true
	_notice_timer = _rng.randf_range(reaction_cooldown.x, reaction_cooldown.y)
	if _was_walking:
		_resume_walk()
	else:
		_enter_idle()


## Fundido de la mirada: la cabeza se gira poco a poco y también vuelve poco a poco (nunca de
## golpe). Es independiente del framerate y se apaga solo si el jugador se aleja.
func _update_watch(delta: float) -> void:
	if _look == null:
		return
	if _watching and _player_node != null and is_instance_valid(_player_node):
		var distance := global_position.distance_to(_player_node.global_position)
		if distance > notice_distance * 1.8:
			_watching = false
		else:
			_look_target.global_position = _player_node.global_position + Vector3.UP * look_at_height
	_watch = move_toward(_watch, 1.0 if _watching else 0.0, delta * 3.0)
	_look.watch = _watch


# ------------------------------------------------------------------ niveles de actividad (LOD)

## Ajusta cuánto trabajo hace este ciudadano según lo lejos que esté del jugador.
##
##   NEAR  -> navegación completa + animación + evitación entre ciudadanos
##   MID   -> navegación y animación normales, sin evitación (la evitación es lo caro)
##   FAR   -> se queda quieto y su animación se apaga (no navega ni anima)
##
## El reparto lo hace el NPCSpawner por turnos, así que subir o bajar de nivel no provoca
## picos de trabajo en un solo fotograma.
func set_activity(tier: Activity) -> void:
	if tier == activity:
		return
	activity = tier
	match activity:
		Activity.NEAR:
			_pending_freeze = false
			_player.process_mode = Node.PROCESS_MODE_INHERIT
			_agent.avoidance_enabled = true
			set_physics_process(true)
		Activity.MID:
			_pending_freeze = false
			_player.process_mode = Node.PROCESS_MODE_INHERIT
			_agent.avoidance_enabled = false
			_watching = false
			set_physics_process(true)
		Activity.FAR:
			_agent.avoidance_enabled = false
			_watching = false
			# Se deja terminar el fundido hacia Idle antes de congelar la animación.
			_enter_idle()
			_pending_freeze = true
			_freeze_timer = 0.6


func is_frozen() -> bool:
	return _player.process_mode == Node.PROCESS_MODE_DISABLED


# ------------------------------------------------------------------ API para la Etapa 3

## Detiene al ciudadano y lo deja en Idle durante `seconds` (útil para reacciones futuras).
func hold_still(seconds: float) -> void:
	_enter_idle()
	_idle_timer = maxf(_idle_timer, seconds)


func current_clip() -> String:
	return _active_clip


## ¿Está mirando al jugador ahora mismo? (lo usan las reacciones y las pruebas)
func is_watching() -> bool:
	return _watching


## Cuánto mira (0 = nada, 1 = todo lo que le permiten sus límites).
func watch_amount() -> float:
	return _watch


func is_walking() -> bool:
	return state == State.WALK or state == State.PAUSE or state == State.TURN


## Velocidad real de avance (m/s), sin contar el frenado.
func move_speed() -> float:
	return _move_speed()