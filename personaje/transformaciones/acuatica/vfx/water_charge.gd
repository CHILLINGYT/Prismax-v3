class_name WaterCharge
extends Node3D
## =============================================================================
##  CARGA DE AGUA EN LAS MANOS
## =============================================================================
##  Mientras se prepara una habilidad, el agua se JUNTA en las manos del
##  personaje: una esfera que crece, gotas que se le van sumando y un remolino
##  cada vez mas cerrado. Cuando la animacion libera el efecto, esa agua es la que
##  sale disparada.
##
##  Es lo que hace que la habilidad parezca agua MANIPULADA y no un objeto que
##  aparece de la nada. Sigue a las manos de verdad (huesos del esqueleto), asi
##  que si el personaje gira, salta o nada, la carga va con el.
##
##  Lo manda WaterAbilityManager: lo crea al empezar el hechizo, lo suelta cuando
##  la animacion libera el efecto y lo borra si el hechizo se cancela.
##
##  DEBAJO DEL AGUA la carga es mas cerrada y verde-azulada, suelta burbujas en
##  vez de gotas y no hay salpicadura al liberar: es el mismo sistema, con el
##  aspecto del sitio donde se lanza.
## =============================================================================

const PARTICLE_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/water_particle.gdshader")

## Personaje al que sigue (se le piden las manos cada fotograma).
var player: Node3D = null
## Cuanto (s) tarda en cargarse del todo.
var duration := 1.3
## Radio (m) de la esfera cargada al final.
var radius := 0.45
## true si el hechizo se lanza bajo el agua: cambia color y particulas.
var underwater := false

var _elapsed := 0.0
var _released := false
var _orb: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _light: OmniLight3D = null
var _droplets: GPUParticles3D = null


func _ready() -> void:
	var core := Color(0.06, 0.34, 0.42) if underwater else Color(0.08, 0.42, 0.72)
	var edge := Color(0.62, 0.92, 0.88) if underwater else Color(0.75, 0.96, 1.0)
	_orb = WaterEffects.make_orb(radius, core, edge)
	_mat = _orb.material_override as ShaderMaterial
	if _mat != null:
		_mat.set_shader_parameter("opacity", 0.3)
		_mat.set_shader_parameter("pulse", 0.9)
	_orb.scale = Vector3.ONE * 0.15
	add_child(_orb)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.85, 1.0)
	_light.light_energy = 0.4
	_light.omni_range = 4.5
	add_child(_light)

	_droplets = _make_suction()
	add_child(_droplets)
	_droplets.emitting = true

	# [!] Colocarse en la mano YA, dentro de _ready(), y no esperar al primer
	# _process. Un nodo recien creado esta en el ORIGEN DEL MUNDO, y el gestor de
	# habilidades lee la posicion del agua en el MISMO fotograma en que se crea
	# (justo cuando suelta el hechizo): sin esto, la habilidad nacia en el origen
	# del mundo en vez de en la mano.
	_follow_hands()


## Gotas que llegan desde fuera hacia el centro: la aceleracion radial NEGATIVA
## las trae hacia dentro, que es lo que lee como "el agua se junta".
func _make_suction() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.0, 0.2, 0.0)
	process.radial_accel_min = -9.0
	process.radial_accel_max = -4.0
	process.scale_min = 0.03
	process.scale_max = 0.09
	process.damping_min = 0.4
	process.damping_max = 1.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 2.1
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.09
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("color", Color(0.70, 0.92, 1.0, 0.75))
	var node := GPUParticles3D.new()
	node.amount = 34
	node.lifetime = 0.7
	node.explosiveness = 0.0
	node.local_coords = false
	node.draw_pass_1 = quad
	node.material_override = mat
	node.process_material = process
	node.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _process(delta: float) -> void:
	_elapsed += delta
	_follow_hands()
	var t := clampf(_elapsed / maxf(duration, 0.05), 0.0, 1.0)
	var grow := 0.22 + 0.78 * ease(t, 0.5)
	if _orb != null and not _released:
		_orb.scale = Vector3.ONE * grow
	if _mat != null and not _released:
		# Ni opaca ni deslumbrante: el agua cargada tiene que dejar VER al
		# personaje detras, si no la habilidad tapa a quien la lanza.
		_mat.set_shader_parameter("opacity", lerpf(0.25, 0.6, t))
		_mat.set_shader_parameter("pulse", lerpf(0.9, 1.5, t))
	if _light != null and not _released:
		_light.light_energy = lerpf(0.4, 2.2, t)


## La carga va PEGADA a la MANO que sostiene el agua: el jugador da el sitio
## exacto sacado del hueso de la mano (get_water_ball_position). Antes se usaba el
## punto medio de las dos manos y, con los brazos bajados, ese punto cae en el eje
## del cuerpo: el agua aparecía dentro del pecho. Si el modelo no tuviera
## esqueleto, el jugador devuelve igualmente un punto delante del pecho, así que
## la carga nunca se queda suelta.
func _follow_hands() -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("get_water_ball_position"):
		var at: Vector3 = player.call("get_water_ball_position")
		if at.is_finite():
			global_position = at
			return
	if player.has_method("get_hand_center"):
		var medio: Vector3 = player.call("get_hand_center")
		if medio.is_finite():
			global_position = medio
			return
	global_position = player.global_position + Vector3.UP * 1.3


## Suelta el agua cargada. Se llama en el fotograma exacto en el que la animacion
## libera el hechizo, asi que el efecto principal nace en las manos.
func release() -> void:
	if _released:
		return
	_released = true
	var host := get_parent()
	if host is Node3D:
		if underwater:
			WaterEffects.bubbles(host, global_position, 22, 0.35, 1.1)
			WaterEffects.current(host, global_position, -global_transform.basis.z, 0.6, 0.9)
		else:
			WaterEffects.burst(host, global_position, 0.45, 0.6)
	if _droplets != null:
		_droplets.emitting = false
	if _orb == null:
		queue_free()
		return
	# El agua que estaba junta se abre hacia delante en vez de desaparecer: asi se
	# ve el paso de "cargando" a "lanzado".
	var orb := _orb
	var mat := _mat
	var tween := create_tween()
	tween.set_parallel(true)
	if mat != null:
		tween.tween_method(
			func(v: float) -> void: mat.set_shader_parameter("opacity", v),
			0.9, 0.0, 0.16)
	tween.tween_property(orb, "scale", Vector3.ONE * 2.1, 0.16)
	tween.chain().tween_callback(queue_free)
