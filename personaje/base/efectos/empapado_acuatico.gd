class_name EmpapadoAcuatico
extends Node3D
## =============================================================================
##  ENEMIGO EMPAPADO (defensa debilitada) — de la Marea Quebradefensas
## =============================================================================
##  Estado temporal que se le cuelga a un ENEMIGO ya golpeado por el combo
##  acuático: lo deja mojado y con la defensa debilitada. Mientras dura, los
##  ataques acuáticos le hacen `MULT` (1,05) de daño: lo consulta el controlador
##  acuático con `activo_en()`; NINGUNA otra forma lo consulta, así que el
##  personaje de Combate y las demás transformaciones no se benefician de él.
##
##    * Se aplica SÓLO con impactos reales (lo llama el controlador al cerrar la
##      Marea Quebradefensas) y a UN SOLO objetivo: el del tercer golpe.
##    * Si el enemigo ya está empapado, `aplicar_a()` RENUEVA la duración sin
##      acumular: el factor sigue siendo 1,05 (nunca 1,05²), no hay dobles
##      bonificaciones ni estados duplicados.
##    * El efecto visual es INDEPENDIENTE del enemigo: no toca sus materiales ni
##      sus texturas (no hay conflictos con sus shaders). Es una capa de agua
##      translúcida con el material de agua del proyecto + gotas que resbalan,
##      creadas como HIJOS de este nodo; la figura del enemigo sigue viéndose.
##    * Vive colgado del enemigo, así que lo acompaña si se mueve y se libera
##      con él. Se apaga solo: fundido final y `queue_free()`. Nunca queda nada
##      encendido ni un modificador activo.
##
##  La escena del enemigo NO se toca: funciona con cualquier nodo del grupo
##  "damageable" (el mismo contrato que usan las habilidades de agua).
## =============================================================================

const WaterEffectsScript := preload("res://personaje/transformaciones/acuatica/vfx/water_effects.gd")
const PARTICLE_SHADER := preload("res://personaje/transformaciones/acuatica/vfx/water_particle.gdshader")

## Nombre fijo del nodo: `activo_en()` lo busca por nombre en el objetivo.
const NOMBRE := &"EmpapadoAcuatico"
## Segundos de fundido final antes de desaparecer (la opacidad baja con él).
const FUNDIDO := 0.9
## Opacidad base de la capa de agua (baja: no debe tapar al enemigo).
const OPACIDAD := 0.30
## Radio (m) por defecto si el objetivo no declara `get_hit_radius()`.
const RADIO_DEFECTO := 0.55
## Altura (m) por defecto del centro del efecto si no declara `get_hit_center()`.
const ALTURA_DEFECTO := 1.0

var duracion := 5.0
var _restante := 0.0
var _radio := RADIO_DEFECTO
var _mat_orb: ShaderMaterial = null
var _gotas: GPUParticles3D = null


## ¿Está el objetivo empapado AHORA MISMO? Es lo que consulta el daño acuático
## para aplicar el +5 %. Falso si el nodo no existe o ya expiró.
static func activo_en(objetivo: Node) -> bool:
	if objetivo == null or not is_instance_valid(objetivo):
		return false
	return objetivo.get_node_or_null(NodePath(String(NOMBRE))) != null


## Aplica (o RENUEVA, sin acumular) el estado sobre el objetivo. Devuelve la
## instancia viva, o null si el objetivo no es válido.
static func aplicar_a(objetivo: Node3D, segundos: float) -> EmpapadoAcuatico:
	if objetivo == null or not is_instance_valid(objetivo) or not objetivo.is_inside_tree():
		return null
	var existente := objetivo.get_node_or_null(NodePath(String(NOMBRE))) as EmpapadoAcuatico
	if existente != null:
		existente.renovar(segundos)
		return existente
	var estado := EmpapadoAcuatico.new()
	estado.name = String(NOMBRE)
	estado.duracion = maxf(segundos, 0.1)
	estado._restante = estado.duracion
	objetivo.add_child(estado)
	return estado


func _ready() -> void:
	var objetivo := get_parent() as Node3D
	if objetivo != null:
		if objetivo.has_method("get_hit_radius"):
			_radio = maxf(float(objetivo.call("get_hit_radius")), 0.2)
		var centro: Vector3 = objetivo.global_position + Vector3.UP * ALTURA_DEFECTO
		if objetivo.has_method("get_hit_center"):
			centro = objetivo.call("get_hit_center")
		position = objetivo.to_local(centro)
	_restante = maxf(_restante, 0.1)
	_montar()


## Renueva la duración. NO toca la intensidad: sigue siendo un único +5 %.
func renovar(segundos: float) -> void:
	duracion = maxf(segundos, 0.1)
	_restante = duracion
	if _gotas != null and is_instance_valid(_gotas):
		_gotas.emitting = true


func _process(delta: float) -> void:
	_restante = maxf(_restante - delta, 0.0)
	if _mat_orb != null:
		var vivo: float = clampf(_restante / FUNDIDO, 0.0, 1.0)
		_mat_orb.set_shader_parameter("opacity", OPACIDAD * vivo)
	if _gotas != null and is_instance_valid(_gotas) and _restante <= FUNDIDO * 0.5:
		_gotas.emitting = false
	if _restante <= 0.0:
		queue_free()


func _montar() -> void:
	# Capa de agua: la esfera translúcida del proyecto, con poca opacidad para
	# que el enemigo siga viéndose por debajo.
	var orb: MeshInstance3D = WaterEffectsScript.make_orb(_radio * 1.15,
			Color(0.10, 0.45, 0.72), Color(0.72, 0.95, 1.0))
	_mat_orb = orb.material_override as ShaderMaterial
	if _mat_orb != null:
		_mat_orb.set_shader_parameter("opacity", OPACIDAD)
		_mat_orb.set_shader_parameter("refraction_strength", 0.0)
	orb.name = "CapaAgua"
	add_child(orb)
	# Gotas que resbalan: emisor continuo pequeño, en coordenadas LOCALES (así
	# acompaña al enemigo si se mueve) y con gravedad normal: caen.
	var proceso := ParticleProcessMaterial.new()
	proceso.direction = Vector3.DOWN
	proceso.spread = 55.0
	proceso.initial_velocity_min = 0.15
	proceso.initial_velocity_max = 0.5
	proceso.gravity = Vector3(0.0, -2.2, 0.0)
	proceso.scale_min = 0.35
	proceso.scale_max = 1.1
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proceso.emission_sphere_radius = _radio * 0.85
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("color", Color(0.66, 0.88, 1.0, 0.55))
	_gotas = GPUParticles3D.new()
	_gotas.name = "GotasEmpapado"
	_gotas.amount = 24
	_gotas.lifetime = 1.1
	_gotas.draw_pass_1 = quad
	_gotas.material_override = mat
	_gotas.process_material = proceso
	_gotas.visibility_aabb = AABB(Vector3.ONE * -3.0, Vector3.ONE * 6.0)
	_gotas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gotas)