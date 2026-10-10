class_name UnderwaterView
extends Node3D
## =============================================================================
##  VISTA SUBACUATICA
## =============================================================================
##  Lo que cambia cuando la CAMARA se mete debajo del agua. Se mira la posicion de
##  la camara, no la del personaje: si la camara esta fuera, la imagen es normal
##  aunque el personaje este nadando.
##
##  Cambia tres cosas, todas nativas de Godot:
##    1. NIEBLA del entorno (Environment.fog_*): la luz se absorbe con la distancia
##       y con la profundidad. Se duplica el entorno de la escena para no tocar el
##       original (si no, el editor marcaria la escena como modificada).
##    2. VELO de pantalla (CanvasLayer + ColorRect + shader): tiñe la imagen, la
##       ondula un poco y cierra la vista con una viñeta.
##    3. MOTAS suspendidas: partículas colgadas de la CAMARA, asi que se quedan
##       flotando alrededor mientras te mueves.
##
##  Todo se controla con `amount` (0 = camara fuera, 1 = bien dentro), que sube y
##  baja suave: entrar y salir del agua nunca da un salto visual.
##
##  Es SOLO aspecto: no toca el movimiento, ni el daño, ni los estados.
## =============================================================================

const OVERLAY_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/underwater_overlay.gdshader")
const PARTICLE_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/water_particle.gdshader")

## Profundidad (m) de camara a la que el efecto esta a tope. Tres metros: en esta
## piscina (3.7 m en el fondo) el efecto tiene que llegar a tope, no quedarse a
## medias porque el lago sea poco profundo.
@export var max_depth := 3.0
## Curva del efecto con la profundidad: < 1 = aparece pronto y satura despacio.
@export var depth_curve := 0.45
## Rapidez (1/s) con la que el efecto entra y sale. Que no sea instantaneo es lo
## que hace que salir del agua se sienta como salir del agua.
@export var fade_speed := 2.5
## Densidad de niebla a tope.
@export var fog_density_max := 0.32
## Distancia (m) a la que empieza y acaba la niebla.
@export var fog_begin := 0.5
@export var fog_end := 55.0
## Cuanto tiñe el velo a tope.
@export var tint_strength_max := 0.6
## Color del agua y de la niebla, respectivamente.
@export var deep_color := Color(0.05, 0.28, 0.40)
@export var fog_color := Color(0.04, 0.20, 0.30)
@export var motes_amount := 70
@export var motes_volume := 9.0

var _player: Node3D = null
var _camera: Camera3D = null
var _world_env: WorldEnvironment = null
var _env: Environment = null
var _overlay: ColorRect = null
var _mat: ShaderMaterial = null
var _motes: GPUParticles3D = null
var _underwater := 0.0


func _ready() -> void:
	_player = get_parent() as Node3D
	_camera = _find_camera(_player)
	_setup_overlay()
	_setup_environment()
	_setup_motes()
	_apply()


func _process(delta: float) -> void:
	var raw := clampf(_camera_depth() / maxf(max_depth, 0.1), 0.0, 1.0)
	var target := pow(raw, depth_curve)
	_underwater = move_toward(_underwater, target, fade_speed * delta)
	if absf(_underwater - target) > 0.0005 or _underwater > 0.0005:
		_apply()
	elif _overlay != null and _overlay.visible:
		_apply()


# -----------------------------------------------------------------------------
#  API (por si otro sistema quiere saber si la camara esta bajo el agua)
# -----------------------------------------------------------------------------
## 0 = camara fuera del agua, 1 = bien dentro. Ya suavizado.
func get_underwater_amount() -> float:
	return _underwater


func is_camera_underwater() -> bool:
	return _underwater > 0.35


# -----------------------------------------------------------------------------
#  Interno
# -----------------------------------------------------------------------------
## Profundidad (m) de la CAMARA bajo la superficie del agua, o 0 si esta fuera.
## Se comprueba que los nodos sigan vivos: al liberar la escena, el ultimo
## fotograma de proceso puede pillar al jugador o a la camara ya borrados.
func _camera_depth() -> float:
	if _camera == null or _player == null:
		return 0.0
	if not is_instance_valid(_camera) or not is_instance_valid(_player):
		return 0.0
	if not _camera.is_inside_tree() or not _player.is_inside_tree():
		return 0.0
	var detection := _player.get("water_detection") as Node
	if detection == null or not is_instance_valid(detection):
		return 0.0
	if not detection.has_method("get_zone"):
		return 0.0
	# Se comprueba que la zona siga viva ANTES de convertirla: convertir un objeto
	# ya liberado es un error, y al cerrar la escena hay un fotograma en el que eso
	# puede pasar.
	var raw_zone: Variant = detection.call("get_zone")
	if raw_zone == null or not is_instance_valid(raw_zone):
		return 0.0
	var zone := raw_zone as Node
	if not zone.is_inside_tree():
		return 0.0
	var at := _camera.global_position
	if not bool(zone.call("contains_horizontal", at, 0.0)):
		return 0.0
	var surface := float(zone.call("surface_height_at", at))
	return maxf(surface - at.y, 0.0)


func _apply() -> void:
	var a := _underwater
	if _mat != null:
		_mat.set_shader_parameter("amount", a)
		_mat.set_shader_parameter("tint", Vector3(deep_color.r, deep_color.g, deep_color.b))
		_mat.set_shader_parameter("tint_strength", tint_strength_max)
		_mat.set_shader_parameter("wobble", 1.0)
		_mat.set_shader_parameter("vignette", 1.0)
	if _overlay != null:
		_overlay.visible = a > 0.004
	if _env != null:
		# La niebla se hace mas densa con la profundidad: en la superficie casi no
		# se nota y en el fondo no se ve el otro lado de la piscina.
		_env.fog_enabled = a > 0.004
		_env.fog_light_color = fog_color
		_env.fog_light_energy = 1.0
		_env.fog_density = fog_density_max * a
		_env.fog_sky_affect = 0.0
		_env.fog_mode = Environment.FOG_MODE_DEPTH
		_env.fog_depth_begin = fog_begin
		_env.fog_depth_end = lerpf(8.0, fog_end, a)
	if _motes != null:
		_motes.emitting = a > 0.25
		_motes.amount_ratio = clampf(a * 1.2, 0.0, 1.0)


func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UnderwaterLayer"
	layer.layer = 1
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.name = "Velo"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY_SHADER
	_overlay.material = _mat
	_overlay.visible = false
	layer.add_child(_overlay)


## Duplica el entorno de la escena. Es a proposito: si se escribiera en el de la
## escena, el editor la marcaria como modificada al ejecutar y la niebla se
## quedaria guardada en el mapa para siempre.
func _setup_environment() -> void:
	# Se busca el entorno del NIVEL (el hermano del jugador y lo que hay por alli),
	# no el de "la escena actual": asi funciona igual jugando que dentro de una
	# prueba, donde el nivel esta montado a mano.
	var scene := get_tree().current_scene
	var host: Node = null
	if _player != null and is_instance_valid(_player):
		host = _player.get_parent()
	_world_env = _find_environment(host)
	if _world_env == null:
		_world_env = _find_environment(scene)
	if _world_env == null or _world_env.environment == null:
		return
	_env = _world_env.environment.duplicate() as Environment
	if _env == null:
		return
	_world_env.environment = _env


## Motas suspendidas: cuelgan de la CAMARA, asi que se quedan alrededor mientras
## el personaje se mueve (es lo que hace que el agua se sienta con volumen).
func _setup_motes() -> void:
	if _camera == null:
		return
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.14
	process.gravity = Vector3(0.0, -0.02, 0.0)
	process.scale_min = 0.012
	process.scale_max = 0.05
	process.damping_min = 0.0
	process.damping_max = 0.3
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(motes_volume * 0.5, motes_volume * 0.35, motes_volume * 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.05
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("color", Color(0.78, 0.94, 1.0, 0.45))
	var node := GPUParticles3D.new()
	node.name = "Motas"
	node.amount = maxi(motes_amount, 8)
	node.lifetime = 6.0
	node.local_coords = true
	node.draw_pass_1 = quad
	node.material_override = mat
	node.process_material = process
	node.visibility_aabb = AABB(
		Vector3.ONE * -motes_volume, Vector3.ONE * motes_volume * 2.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.emitting = false
	_camera.add_child(node)
	_motes = node


func _find_camera(node: Node) -> Camera3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is Camera3D:
			return child as Camera3D
		var deep := _find_camera(child)
		if deep != null:
			return deep
	return null


func _find_environment(node: Node) -> WorldEnvironment:
	if node == null:
		return null
	for child in node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		var deep := _find_environment(child)
		if deep != null:
			return deep
	return null
