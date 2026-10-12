class_name WaterEffects
extends Node3D
## =============================================================================
##  EFECTOS DE AGUA  (salpicaduras, gotas, espuma, ondas y esferas)
## =============================================================================
##  Todo lo que se ve cuando el agua se mueve. Se construye ENTERO desde codigo:
##  no hay escenas de efectos ni texturas. Las gotas son un degradado radial
##  calculado en el shader, y las ondas un anillo dibujado por matematicas.
##
##  Va colgado del jugador, asi que:
##    * escucha su señal de salpicadura (entrar/salir del agua),
##    * y mientras nada va soltando estela por detras.
##
##  Las habilidades piden efectos por las funciones estaticas, pasandoles el nodo
##  donde colgarse. Los efectos se borran solos cuando acaban.
##
##  LOS EFECTOS NO DECIDEN NADA
##    Aqui no hay daño, ni enfriamientos, ni estados: solo se dibuja. Quien decide
##    es la habilidad (o el jugador). Asi cambiar el aspecto del agua nunca puede
##    romper el juego.
## =============================================================================

const PARTICLE_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/water_particle.gdshader")
const RING_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/water_ring.gdshader")
const ORB_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/water_orb.gdshader")

## Cada cuanto (s) suelta estela mientras nada por la superficie.
@export var wake_interval := 0.22
## Cuanto mas rapido nada, mas estela.
@export var wake_speed_reference := 1.6
## Cada cuanto (s) suelta una bocanada de burbujas bajo el agua.
@export var bubble_interval := 1.4
## Cada cuanto (s) marca una onda en la superficie al caminar sobre ella.
@export var step_interval := 0.26

var _wake_timer := 0.0
var _bubble_timer := 0.0
var _step_timer := 0.0
var _player: Player = null


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		_player = get_parent().get_parent() as Player
	if _player != null and not _player.water_splash.is_connected(_on_water_splash):
		_player.water_splash.connect(_on_water_splash)


## Los efectos del jugador son CONTEXTUALES: cada uno sale cuando toca, mirando en
## que modo de agua esta. No es un emisor encendido todo el rato.
func _process(delta: float) -> void:
	if _player == null:
		_wake_timer = 0.0
		_bubble_timer = 0.0
		_step_timer = 0.0
		return
	var host := get_tree().current_scene
	if host == null:
		return
	# Modo fisico del agua (Player.WaterMode): tipado explicito con el enum del
	# jugador acuatico para no depender de inferencia.
	var mode: Player.WaterMode = _player.get_water_mode()
	# --- Estela al nadar por la superficie ---
	if mode == Player.WaterMode.SURFACE:
		var speed := _player.move_speed
		_wake_timer -= delta
		if speed >= 0.35 and _wake_timer <= 0.0:
			_wake_timer = wake_interval
			var strength: float = clampf(speed / wake_speed_reference, 0.25, 1.4)
			wake(host, _player.global_position, strength)
	else:
		_wake_timer = 0.0
	# --- Burbujas al estar bajo el agua (respirar, andar por el fondo, nadar) ---
	if _player.is_underwater():
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			# Cuanto mas deprisa se mueve, mas seguido respira.
			var speed := _player.move_speed
			_bubble_timer = bubble_interval * clampf(1.0 - speed * 0.25, 0.35, 1.0)
			var strength: float = clampf(0.4 + speed * 0.35, 0.4, 1.2)
			var mouth := _player.global_position + Vector3.UP * 1.45
			bubbles(host, mouth, int(clampf(9.0 * strength, 4.0, 20.0)), 0.22, strength)
	else:
		_bubble_timer = 0.0
	# --- Ondas al CAMINAR SOBRE la superficie del agua ---
	if mode == Player.WaterMode.SURFACE_WALK:
		_step_timer -= delta
		if _step_timer <= 0.0 and _player.move_speed > 0.15:
			_step_timer = step_interval
			# Los pies van a la superficie: se marca la onda ahi mismo.
			var feet := _player.global_position + Vector3.UP * 0.03
			surface_ripple(host, feet, 0.55 + 0.25 * clampf(_player.move_speed / 3.0, 0.0, 1.6))
	else:
		_step_timer = 0.0


## Nodo donde se cuelgan los efectos: el MUNDO (el padre del jugador), no el
## jugador. Asi los efectos se quedan en el sitio donde han pasado y no viajan
## pegados al personaje.
func _host() -> Node3D:
	var player := get_parent()
	if player != null and player.get_parent() is Node3D:
		return player.get_parent() as Node3D
	return get_tree().current_scene as Node3D


## Salpicadura al entrar o salir del agua: la pide el propio jugador.
func _on_water_splash(spot: Vector3, strength: float) -> void:
	splash(_host(), spot, clampf(strength / 4.0, 0.35, 2.0))


# -----------------------------------------------------------------------------
#  Efectos (funciones estaticas: se pueden llamar desde cualquier sitio)
# -----------------------------------------------------------------------------
## Salpicadura de entrar o salir del agua: corona de gotas + onda en la superficie.
## [param strength] 0.5 = un chapuzon pequeño, 2.0 = una bomba.
static func splash(host: Node3D, at: Vector3, strength := 1.0) -> void:
	if not _valid(host):
		return
	_droplets(host, at + Vector3.UP * 0.1, {
		"amount": int(clampf(26.0 * strength, 10.0, 140.0)),
		"speed": 2.6 * strength,
		"size": 0.075 + 0.03 * strength,
		"life": 0.85,
		"up": 1.0,
		"spread": 38.0,
		"radius": 0.18,
	})
	ring(host, at, 1.5 + 1.6 * strength, 0.85, 0.9)
	# Espuma que se queda flotando un momento donde ha roto el agua.
	foam(host, at, 0.7 + 0.5 * strength, 1.4)


## Golpe de un proyectil o explosion: gotas hacia todos lados + onda del tamaño
## del radio de la habilidad.
static func burst(host: Node3D, at: Vector3, radius: float, strength := 1.0) -> void:
	if not _valid(host):
		return
	_droplets(host, at, {
		"amount": int(clampf(90.0 * strength, 30.0, 260.0)),
		"speed": 5.0 * strength,
		"size": 0.09 + 0.05 * strength,
		"life": 1.1,
		"up": 0.35,
		"spread": 180.0,
		"radius": radius * 0.35,
	})
	# Vaho/nube de gotitas finas que se queda flotando: da volumen a la explosion.
	# Ojo con el tamaño: son muchas gotas juntas, asi que si cada una es grande la
	# explosion se lee como UNA esfera gigante en vez de como agua que salta.
	_droplets(host, at, {
		"amount": int(clampf(50.0 * strength, 20.0, 120.0)),
		"speed": 1.1 * strength,
		"size": radius * 0.3,
		"life": 1.8,
		"up": 0.8,
		"spread": 180.0,
		"radius": radius * 0.5,
		"opacity": 0.24,
		"gravity": 1.5,
	})
	ring(host, at, radius * 2.3, 0.7, 1.0)
	flash(host, at, radius * 0.5, 0.45)


## Onda circular plana en el suelo o en el agua.
static func ring(host: Node3D, at: Vector3, diameter: float, duration: float, strength := 1.0) -> void:
	if not _valid(host):
		return
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(diameter, diameter)
	mesh.subdivide_width = 0
	mesh.subdivide_depth = 0
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("strength", clampf(strength, 0.0, 1.5))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(node)
	node.global_position = at
	var tween := node.create_tween()
	tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("progress", v),
		0.0, 1.0, maxf(duration, 0.1))
	tween.finished.connect(node.queue_free)


## Espuma: burbujas lentas que suben y un disco translucido que se desvanece.
static func foam(host: Node3D, at: Vector3, radius: float, duration: float) -> void:
	if not _valid(host):
		return
	_droplets(host, at + Vector3.UP * 0.05, {
		"amount": int(clampf(radius * 40.0, 12.0, 90.0)),
		"speed": 0.5,
		"size": 0.09,
		"life": duration,
		"up": 1.0,
		"spread": 70.0,
		"radius": radius,
		"opacity": 0.5,
		"gravity": -0.4,
	})
	# Disco de espuma: una esfera achatada con el material del agua translucida.
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 0.4
	sphere.radial_segments = 24
	sphere.rings = 8
	var mat := ShaderMaterial.new()
	mat.shader = ORB_SHADER
	mat.set_shader_parameter("opacity", 0.45)
	mat.set_shader_parameter("refraction_strength", 0.0)
	mat.set_shader_parameter("core_color", Color(0.75, 0.90, 0.98))
	mat.set_shader_parameter("edge_color", Color(0.95, 1.0, 1.0))
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(node)
	node.global_position = at + Vector3.UP * 0.04
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("opacity", v * 0.45),
		1.0, 0.0, maxf(duration, 0.1))
	tween.tween_property(node, "scale", Vector3(1.25, 1.0, 1.25), maxf(duration, 0.1))
	tween.chain().tween_callback(node.queue_free)


## Estela de la natacion: gotitas pequeñas que salen hacia atras.
static func wake(host: Node3D, at: Vector3, strength := 1.0) -> void:
	if not _valid(host):
		return
	_droplets(host, at + Vector3.UP * 0.35, {
		"amount": int(clampf(9.0 * strength, 4.0, 24.0)),
		"speed": 1.1 * strength,
		"size": 0.06,
		"life": 0.6,
		"up": 0.9,
		"spread": 55.0,
		"radius": 0.22,
		"opacity": 0.7,
	})
	ring(host, at + Vector3.UP * 0.32, 0.9 + 0.5 * strength, 0.75, 0.5)


## Burbujas que SUBEN: la firma visual de estar bajo el agua. Se usan para
## respirar, para la estela de un golpe sumergido y para lo que rompe el agua
## desde abajo. Suben y se deshacen solas.
## [param strength] 0.4 = una bocanada pequeña, 1.5 = un golpe fuerte.
static func bubbles(host: Node3D, at: Vector3, amount := 10, radius := 0.25, strength := 1.0) -> void:
	if not _valid(host):
		return
	_droplets(host, at, {
		"amount": int(clampf(float(amount) * strength, 3.0, 90.0)),
		"speed": 0.5 + 0.5 * strength,
		"size": 0.045 + 0.03 * strength,
		"life": 1.1 + 0.5 * strength,
		"up": 1.0,
		"spread": 75.0,
		"radius": radius,
		"opacity": 0.55,
		# Gravedad NEGATIVA: en vez de caer, suben.
		"gravity": -1.7,
	})


## Corriente/remolino: la estela turbulenta que deja algo que se mueve bajo el
## agua (una oleada, una explosion sumergida). Va EN DIRECCION del movimiento, no
## hacia arriba: por eso no reutiliza make_particles.
static func current(host: Node3D, at: Vector3, dir: Vector3, radius := 1.0, strength := 1.0) -> void:
	if not _valid(host):
		return
	var forward := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var process := ParticleProcessMaterial.new()
	process.direction = forward
	process.spread = 42.0
	process.initial_velocity_min = 0.8 * strength
	process.initial_velocity_max = 2.6 * strength
	process.gravity = Vector3.ZERO
	process.scale_min = 0.05
	process.scale_max = 0.16
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	process.damping_min = 1.2
	process.damping_max = 2.4
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(radius, 0.05)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("color", Color(0.70, 0.90, 1.0, 0.5))
	var node := GPUParticles3D.new()
	node.amount = int(clampf(40.0 * strength, 12.0, 120.0))
	node.lifetime = 0.9
	node.one_shot = true
	node.explosiveness = 0.35
	node.local_coords = false
	node.draw_pass_1 = quad
	node.material_override = mat
	node.process_material = process
	node.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(node)
	node.global_position = at
	node.emitting = true
	node.finished.connect(node.queue_free)


## Onda + espuma en la SUPERFICIE al pisarla (caminar sobre el agua) o al rozarla
## algo. Se queda unos segundos expandiendose y desvaneciendose.
static func surface_ripple(host: Node3D, at: Vector3, radius := 0.6) -> void:
	if not _valid(host):
		return
	ring(host, at, radius * 3.0, 0.9, 0.45)
	foam(host, at, radius * 0.8, 0.8)


## Latigazo de luz: una esfera del material de agua que se hincha y se apaga.
## Es el "flash" que hace que una explosion se lea aunque sea de noche.
static func flash(host: Node3D, at: Vector3, radius: float, duration: float) -> void:
	if not _valid(host):
		return
	var node := make_orb(radius)
	node.material_override.set_shader_parameter("pulse", 1.0)
	node.material_override.set_shader_parameter("opacity", 0.55)
	host.add_child(node)
	node.global_position = at
	var mat := node.material_override as ShaderMaterial
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_method(
		func(v: float) -> void:
			mat.set_shader_parameter("pulse", v)
			mat.set_shader_parameter("opacity", v * 0.55),
		1.0, 0.0, maxf(duration, 0.1))
	tween.tween_property(node, "scale", Vector3.ONE * 1.8, maxf(duration, 0.1))
	tween.chain().tween_callback(node.queue_free)


## Esfera de agua translucida (proyectil, area de la explosion, prision).
static func make_orb(radius: float, core := Color(0.10, 0.45, 0.72), edge := Color(0.70, 0.94, 1.0)) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var mat := ShaderMaterial.new()
	mat.shader = ORB_SHADER
	mat.set_shader_parameter("core_color", core)
	mat.set_shader_parameter("edge_color", edge)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# -----------------------------------------------------------------------------
#  Fontaneria
# -----------------------------------------------------------------------------
## Sistema de particulas de gotas. El diccionario son los ajustes: asi una sola
## funcion sirve para una salpicadura, una explosion o una estela sin repetir
## cuarenta propiedades en cada llamada.
static func _droplets(host: Node3D, at: Vector3, cfg: Dictionary) -> GPUParticles3D:
	var node := make_particles(cfg)
	host.add_child(node)
	node.global_position = at
	node.emitting = true
	node.finished.connect(node.queue_free)
	return node


## Crea (sin colgar ni emitir) un sistema de particulas de gotas. Lo usan las
## habilidades que necesitan una ESTELA pegada a algo que se mueve: se le añade
## como hijo con local_coords = false y va soltando gotas por donde pasa.
##
## Ajustes del diccionario: amount, speed, size, life, up, spread, radius,
## opacity, gravity.
static func make_particles(cfg: Dictionary) -> GPUParticles3D:
	var amount := int(cfg.get("amount", 20))
	var life := float(cfg.get("life", 0.8))
	var radius := float(cfg.get("radius", 0.2))
	var spread := float(cfg.get("spread", 45.0))
	var speed := float(cfg.get("speed", 2.0))
	var size := float(cfg.get("size", 0.08))
	var opacity := float(cfg.get("opacity", 0.9))
	var gravity := float(cfg.get("gravity", 9.8))

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = spread
	process.initial_velocity_min = speed * 0.55
	process.initial_velocity_max = speed * 1.45
	process.gravity = Vector3(0.0, -gravity, 0.0)
	process.scale_min = size * 0.6
	process.scale_max = size * 1.5
	process.angular_velocity_min = -180.0
	process.angular_velocity_max = 180.0
	process.damping_min = 0.6
	process.damping_max = 1.6
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(radius, 0.01)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * maxf(size, 0.02) * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("color", Color(0.66, 0.88, 1.0, opacity))
	var node := GPUParticles3D.new()
	node.amount = maxi(amount, 1)
	node.lifetime = life
	node.one_shot = true
	node.explosiveness = 1.0
	node.local_coords = false
	node.draw_pass_1 = quad
	node.material_override = mat
	node.process_material = process
	# Sin esto las particulas desaparecen al mirar de lado: Godot las descarta
	# por el AABB del emisor, que en una explosion es mucho mas pequeño que el
	# recorrido real de las gotas.
	node.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _valid(host: Node3D) -> bool:
	return host != null and host.is_inside_tree()
