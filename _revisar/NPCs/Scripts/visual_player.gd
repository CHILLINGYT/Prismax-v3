class_name VisualTestPlayer
extends CharacterBody3D

## JUGADOR DE PRUEBA de la escena visual (`NPC_Visual_Test.tscn`).
##
## Está APARTE del jugador de la Etapa 3 (`TestPlayer`) y del personaje definitivo del juego
## (`res://node_3d.tscn`, que no se toca): existe sólo para poder recorrer la escena nueva y
## comparar a los ciudadanos nuevos mientras caminan a su lado.
##
## Habla el mismo idioma que esos ciudadanos: modelo de los paquetes PolyMate (City Folks /
## Urban Man, rig de Auto-Rig Pro) y su librería de animaciones horneada, así que se mueve con los
## MISMOS clips que ellos (andar, trote, giros) y con la velocidad del propio clip, de modo que
## los pies no patinan.
##
##   WASD  -> mueve AL PERSONAJE, en la dirección en la que mira la cámara (W = adelante).
##   Ratón -> gira LA CÁMARA alrededor del personaje, y nada más.
##
## CamPivot y Camera3D son hijos del personaje: la cámara lo sigue siempre y lo deja centrado,
## con suavizado y acercándose sólo si algo se interpone.

const SHARED_LIBRARY := "res://NPCs/Animations/Citizen_Animations_ARP.res"
const LOCOMOTION_TREE := "res://NPCs/Animations/Citizen_Locomotion.tres"

@export_group("Control")
@export var mouse_sensitivity := 0.0025
@export var min_pitch_deg := -55.0
@export var max_pitch_deg := 30.0
## Escala de velocidad: acelera por igual el avance y la animación (sin patinar). A 1,0 el paso es
## el del propio clip (unos 1,6 m/s), que es el ritmo real de una persona caminando.
@export_range(0.5, 2.0) var speed_scale := 1.0
## Velocidad de giro del cuerpo hacia donde avanza (rad/s). Bajo a propósito: si el cuerpo gira de
## golpe, el personaje parece un muñeco patinando sobre los talones en vez de una persona.
@export var turn_rate := 7.0
## Tiempo que tarda el personaje en alcanzar su velocidad de crucero o en frenar del todo.
@export var accel_time := 0.3

@export_group("Cámara (tercera persona)")
## Distancia del rig de cámara al punto del personaje al que mira (constante).
@export var camera_distance := 3.8
## Altura del punto del personaje que la cámara mantiene centrado (pecho/cabeza).
@export var camera_height := 1.5
## Suavizado del seguimiento (1/s): más alto = más pegado al personaje.
@export var follow_smoothing := 14.0
## Recentrado automático suave detrás del personaje al avanzar (rad/s); 0 = desactivado.
@export_range(0.0, 3.0) var auto_align_rate := 0.8
## Capas contra las que choca la cámara (1 = mundo): si algo se interpone, se acerca.
@export_flags_3d_physics var camera_collision_mask := 1

@export_group("Apariencia")
## Modelo del paquete PolyMate usado como avatar del jugador de prueba.
@export var model_scene: PackedScene

@onready var _rig: Node3D = $CameraRig
@onready var _pitch_node: Node3D = $CameraRig/CameraPitch
@onready var _camera: Camera3D = $CameraRig/CameraPitch/Camera3D
@onready var _player: AnimationPlayer = $AnimationPlayer
@onready var _tree: AnimationTree = $AnimationTree
@onready var _stats: Label = $HUD/Stats

## Clips de la librería horneada para el rig nuevo, por estado del árbol de animación. Se sortean
## entre los disponibles (y entre los dos sexos de origen) para que el jugador no sea idéntico a
## ningún ciudadano en el ritmo del paso.
const CLIP_POOLS := {
	"idle": ["idle_m1", "idle_u1"],
	"idle_b": ["idle_m2", "idle_u3"],
	"walk": ["walk_m1", "walk_u1"],
	"jog": ["jog_u1", "run_fwd_rpg"],
	"turn_l": ["turn_m1_l", "turn90_l_rpg"],
	"turn_r": ["turn_m1_r", "turn90_r_rpg"],
}

var walk_speed := 1.6
var run_speed := 2.6
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _pitch := 0.0
var _cam_yaw := 0.0
var _face_yaw := 0.0
var _playback: AnimationNodeStateMachinePlayback
var _state := ""                # vacío a propósito: el primer _play("idle") tiene que hacer travel()
var _move_dir := Vector3.ZERO   # última dirección de avance (permite frenar sin girar)
var _speed_current := 0.0       # velocidad real de avance (m/s), con rampa de arranque/frenada
var _base_walk := 1.6           # velocidad propia del clip de caminar (sin escala)
var _base_run := 2.6            # velocidad propia del clip de trote (sin escala)
var _mouse_idle := 0.0          # segundos desde el último movimiento del ratón
var _move_speed_display := 0.0
var _model: Node3D = null       # modelo instanciado (se le inclina el cuerpo al girar)
var _angular := 0.0             # velocidad de giro actual del cuerpo (rad/s), con inercia
var _turn_timer := 0.0          # mientras dura, se está reproduciendo el clip de giro
var _idle_timer := 8.0          # cuenta atrás para cambiar de postura de espera
var _idle_alt := false          # alterna las dos posturas de espera
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("player")
	_rng.randomize()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# La cámara vive en un rig independiente del cuerpo: sigue su POSICIÓN (con suavizado) pero
	# no hereda sus giros, así que el ratón la orbita alrededor del personaje sin arrastrarlo.
	_cam_yaw = _rig.rotation.y
	_pitch = _pitch_node.rotation.x
	_camera.position = Vector3(0.0, 0.0, camera_distance)
	_rig.global_position = global_position + Vector3.UP * camera_height
	# Empieza mirando hacia donde mira la cámara, es decir, de espaldas a ella.
	rotation.y = _cam_yaw + PI
	_spawn_avatar()
	_setup_animation()


## Monta el avatar: modelo PolyMate completo (sin sortear piezas, para que sea siempre el mismo
## personaje) con el acabado común de materiales y la jerarquía "Model/Skeleton3D" que esperan
## las pistas de animación.
func _spawn_avatar() -> void:
	if model_scene == null:
		push_warning("VisualTestPlayer sin model_scene")
		return
	var model := model_scene.instantiate()
	# El nombre debe ser exactamente "Model": las pistas de animación son "Model/Skeleton3D:hueso".
	model.name = "Model"
	add_child(model)
	_model = model
	# El rig nuevo cuelga el esqueleto de un nodo intermedio: prepare() lo deja colgando del modelo
	# y, como no se le pide variedad, conserva sus piezas tal cual vienen del paquete.
	NPCCitizenModel.prepare(model, _rng, false)
	_face_yaw = _detect_face_yaw(model)
	# Mismo acabado que los ciudadanos: brillo suave y perfilado, para que el personaje se lea como
	# un volumen y no como una calcomanía plana. Se aplica sobre copias del material.
	NPCCitizenModel.polish_materials(model)


## Los rigs del proyecto miran hacia +Z; se mide igualmente para que cambiar de modelo no rompa el
## giro (el rig nuevo nombra los brazos "arm_stretch.l/.r").
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


func _find_bone(skeleton: Skeleton3D, candidates: Array) -> int:
	for candidate: String in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1


func _setup_animation() -> void:
	var shared: AnimationLibrary = load(SHARED_LIBRARY)
	if shared == null:
		push_error("VisualTestPlayer: falta %s" % SHARED_LIBRARY)
		return
	# Los nombres de la izquierda son los ESTADOS del árbol de animación; los de la derecha, los
	# clips de la librería horneada para este rig.
	var library := AnimationLibrary.new()
	for slot: String in CLIP_POOLS:
		var clip := _pick_clip(CLIP_POOLS[slot])
		var anim: Animation = shared.get_animation(clip)
		if anim == null:
			push_warning("VisualTestPlayer: falta el clip %s" % clip)
			continue
		library.add_animation(slot, anim)
	_player.add_animation_library("", library)
	_tree.tree_root = load(LOCOMOTION_TREE)
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	# La velocidad de avance es la del propio clip por la escala: animación y paso van juntos.
	_base_walk = float((library.get_animation("walk") as Animation).get_meta("speed", 1.6))
	_base_run = float((library.get_animation("jog") as Animation).get_meta("speed", 2.6))
	walk_speed = _base_walk * speed_scale
	run_speed = _base_run * speed_scale
	_player.speed_scale = speed_scale
	_play("idle")


func _pick_clip(options: Array) -> String:
	return String(options[_rng.randi() % options.size()])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# El ratón SÓLO orienta la cámara: orbita alrededor del personaje, nada más.
		_mouse_idle = 0.0
		_cam_yaw -= event.relative.x * mouse_sensitivity
		_rig.rotation.y = _cam_yaw
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		_pitch_node.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	_mouse_idle += delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	# --- El PERSONAJE se mueve con WASD leyendo la orientación horizontal de la cámara:
	# W = hacia donde mira la cámara, S = al revés, A/D = a los lados.
	var input := Input.get_vector("test_move_left", "test_move_right", "test_move_forward", "test_move_back")
	var cam_forward := -_rig.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := _rig.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var direction := cam_right * input.x + cam_forward * -input.y
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var moving := direction.length_squared() > 0.01
	var turn_angle := 0.0
	if moving:
		_move_dir = direction.normalized()
		# Cuánto le falta al cuerpo para mirar hacia donde avanza (positivo = girar a la derecha).
		turn_angle = wrapf(atan2(_move_dir.x, _move_dir.z) - _face_yaw - rotation.y, -PI, PI)
	_steer(turn_angle, delta)

	var running := Input.is_action_pressed("test_run")
	var wanted := (run_speed if running else walk_speed) if moving else 0.0
	# Rampa de arranque y frenada: el desplazamiento y la animación cambian a la vez.
	var ramp := maxf(walk_speed, run_speed) / maxf(accel_time, 0.02) * delta
	_speed_current = move_toward(_speed_current, wanted, ramp)

	if _speed_current > 0.12:
		var base := _base_run if running else _base_walk
		velocity.x = _move_dir.x * _speed_current
		velocity.z = _move_dir.z * _speed_current
		# La animación se reproduce a la velocidad real de avance: ni patina ni se acelera de más.
		_player.speed_scale = clampf(_speed_current / base, 0.45, 1.6)
		_set_gait(turn_angle, running, delta)
		_move_speed_display = _speed_current
	else:
		_speed_current = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		_move_speed_display = 0.0
		_set_idle(delta)

	move_and_slide()
	_update_camera(delta)


## Gira el cuerpo hacia donde avanza, pero con INERCIA: arranca despacio, coge velocidad y vuelve a
## frenar al llegar. Eso es lo que quita el "giro de muñeco" y lo que hace que el cuerpo no vaya por
## delante de los pies. Mientras gira, el cuerpo se inclina un poco hacia dentro de la curva.
func _steer(turn_angle: float, delta: float) -> void:
	var wanted_angular := clampf(turn_angle * 6.0, -turn_rate, turn_rate)
	_angular = move_toward(_angular, wanted_angular, turn_rate * 2.0 * delta)
	rotation.y = wrapf(rotation.y + _angular * delta, -PI, PI)
	if _model != null:
		# La inclinación se hace sobre el MODELO, no sobre el cuerpo: así la cápsula de colisión no
		# se tuerce y el personaje sigue pisando el suelo igual.
		_model.rotation.z = lerp(_model.rotation.z, -_angular * 0.03, 1.0 - exp(-8.0 * delta))


## Elige el clip del paso. Media vuelta casi parado se hace con el clip de giro en el sitio, que
## NO trae el giro en el hueso (se midió: la cadera apenas se mueve, unos 7°), así que el cuerpo lo
## giramos nosotros y el clip sólo aporta el apoyo del pie. Durante medio segundo no se toma otra
## decisión, para que el clip se vea entero en lugar de reiniciarse todo el rato.
func _set_gait(turn_angle: float, running: bool, delta: float) -> void:
	if _turn_timer > 0.0:
		_turn_timer -= delta
		return
	if absf(turn_angle) > 0.9 and _speed_current < walk_speed * 0.5:
		_play("turn_r" if turn_angle > 0.0 else "turn_l")
		_turn_timer = 0.5
		return
	_play("jog" if running else "walk")


## Parado, el personaje no es una estatua: cada 5-12 segundos pasa a la otra postura de espera
## (respiración y reparto de peso distintos), con el cruce lento que ya trae el árbol.
func _set_idle(delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_alt = not _idle_alt
		_idle_timer = _rng.randf_range(5.0, 12.0)
		_play("idle_b" if _idle_alt else "idle")
	elif _state != "idle" and _state != "idle_b":
		_play("idle")


## Cámara de tercera persona: el rig sigue al personaje con suavizado, mantiene SIEMPRE la misma
## distancia y lo deja centrado. Se acerca sólo si algo se interpone entre ella y el personaje.
func _update_camera(delta: float) -> void:
	var focus := global_position + Vector3.UP * camera_height
	_rig.global_position = _rig.global_position.lerp(focus, 1.0 - exp(-follow_smoothing * delta))
	# Recentrado suave detrás del personaje cuando avanza y el ratón lleva un rato quieto.
	if auto_align_rate > 0.0 and _speed_current > 0.15 and _mouse_idle > 0.6:
		_cam_yaw = lerp_angle(
			_cam_yaw, rotation.y + _face_yaw + PI, 1.0 - exp(-auto_align_rate * delta)
		)
		_rig.rotation.y = _cam_yaw
	var wanted := camera_distance
	var space := get_world_3d().direct_space_state
	if space != null and camera_collision_mask != 0:
		var origin := _pitch_node.global_position
		var backwards := _pitch_node.global_transform.basis.z.normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + backwards * (camera_distance + 0.2))
		query.collision_mask = camera_collision_mask
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			wanted = clampf(origin.distance_to(hit["position"]) - 0.2, 0.5, camera_distance)
	_camera.position = _camera.position.lerp(Vector3(0.0, 0.0, wanted), 1.0 - exp(-10.0 * delta))


func _process(_delta: float) -> void:
	if _stats != null:
		_stats.text = "velocidad %.2f m/s  ·  animación: %s  ·  %d FPS" % [
			_move_speed_display, _state, Engine.get_frames_per_second()
		]


func _play(state_name: String) -> void:
	if _state == state_name:
		return
	_state = state_name
	if _playback != null:
		_playback.travel(state_name)