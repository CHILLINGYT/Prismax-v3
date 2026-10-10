class_name WaterSurge
extends "res://personaje/transformaciones/acuatica/abilities/water_ability.gd"
## =============================================================================
##  HABILIDAD 4 - LA MAS FUERTE: OLEADA DE AGUA
## =============================================================================
##  Un muro de agua que avanza arrollando. Es la habilidad mas potente y por eso
##  es la que mas tarda en cargarse (la animacion tiene un ataque previo largo) y
##  la que mas enfriamiento tiene.
##
##  En que se nota que es la fuerte:
##    * RADIO enorme (varios metros): no hay que apuntar, barre.
##    * NO se gasta al primer golpe: sigue avanzando y va golpeando a todos los
##      que pilla por delante, cada uno una sola vez.
##    * Empuje: los que aguanta el golpe salen despedidos.
##    * Efectos a escala: ola, espuma, vaho y ondas mucho mas grandes.
##
##  La usa el jugador con la tecla 4.
## =============================================================================

@export var wave_height := 3.0
@export var wave_width := 5.0

var _hit_ids := {}


func _build_visual() -> void:
	# El muro de agua se arma con varias esferas translucidas solapadas: leidas
	# de frente parece una pared de agua y no hace falta ninguna malla nueva.
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://personaje/transformaciones/acuatica/vfx/water_orb.gdshader")
	mat.set_shader_parameter("core_color", Color(0.04, 0.30, 0.58))
	mat.set_shader_parameter("edge_color", Color(0.78, 0.96, 1.0))
	mat.set_shader_parameter("opacity", 0.38)
	mat.set_shader_parameter("refraction_strength", 0.07)
	mat.set_shader_parameter("ripple_scale", 3.5)
	var columns := 5
	var center := int(float(columns) / 2.0)
	for i in columns:
		var t := float(i) / float(columns - 1) - 0.5
		var mesh := SphereMesh.new()
		mesh.radius = wave_width / float(columns) * 0.85
		mesh.height = wave_height
		mesh.radial_segments = 20
		mesh.rings = 10
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Repartidas a lo ancho y un poco mas bajas por los lados: forma de ola.
		node.position = Vector3(t * wave_width, -absf(t) * wave_height * 0.25 + wave_height * 0.3, 0.0)
		add_child(node)
		if i == center:
			_visual = node
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.85, 1.0)
	light.light_energy = 3.0
	light.omni_range = wave_width * 2.0
	add_child(light)
	var spray := WaterEffects.make_particles({
		"amount": 55,
		"speed": 1.4,
		"size": 0.2,
		"life": 0.85,
		"up": 0.9,
		"spread": 120.0,
		"radius": wave_width * 0.35,
		"opacity": 0.4,
		"gravity": 3.0,
	})
	add_child(spray)
	spray.emitting = true


## Golpea a TODOS los que pilla, pero a cada uno una sola vez: si no, un muro que
## dura varios segundos haria daño en cada fotograma.
func _check_hits() -> void:
	for target in find_targets(global_position, hit_radius):
		var id := target.get_instance_id()
		if _hit_ids.has(id):
			continue
		_hit_ids[id] = true
		hurt(target, global_position)


## La oleada NO se para con los enemigos: los atraviesa y sigue. Si se parara en
## el primero, dejaria de ser una oleada (y ademas el rayo la frenaria justo
## encima, repitiendo el daño por los dos caminos).
func _stops_on_target() -> bool:
	return false


func _advance(delta: float) -> void:
	# Avanza girando un poco: una ola no viaja recta y tiesa.
	rotate_y(delta * 0.25)
	super(delta)


func _on_impact(point: Vector3, _target: Node3D) -> void:
	water_burst(point, wave_width * 0.6, 1.1)
	water_ring(point + Vector3.UP * 0.1, wave_width * 1.8, 0.9, 1.0)
	water_foam(point, wave_width * 0.5, 1.4)


func _on_expire() -> void:
	water_foam(global_position, wave_width * 0.5, 1.2)
