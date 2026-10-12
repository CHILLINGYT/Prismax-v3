class_name TrainingDummy
extends StaticBody3D
## =============================================================================
##  MANIQUI DE ENTRENAMIENTO
## =============================================================================
##  Un objetivo para probar las habilidades: tiene vida, recibe daño, se puede
##  quedar ATRAPADO y al final cae. No ataca ni se mueve: solo aguanta.
##
##  Cumple el contrato que piden las habilidades (ver water_ability.gd):
##    * esta en el grupo "damageable",
##    * tiene apply_damage(), get_hit_center(), get_hit_radius(),
##    * tiene trap() e is_defeated().
##  Por eso las habilidades le dan sin saber que es un maniqui: el mismo codigo
##  valdria para un enemigo de verdad.
##
##  Se construye solo en _ready(): malla, colision, etiqueta de vida y el efecto
##  de estar atrapado. Asi la escena solo tiene que tener el nodo raiz.
## =============================================================================

const TARGET_GROUP := &"damageable"
const WaterEffectsScript := preload("res://personaje/transformaciones/acuatica/vfx/water_effects.gd")

@export var max_health := 100.0
## Radio (m) con el que las habilidades le aciertan.
@export var hit_radius := 0.55
## Cuanto se hunde (m) la etiqueta de vida por encima de la cabeza.
@export var label_height := 2.15

var health := 0.0
var _trapped := 0.0
var _flash := 0.0
var _defeated := false
var _material: StandardMaterial3D = null
var _label: Label3D = null
var _body: Node3D = null
var _shake_seed := 0.0
## De donde vino el ultimo golpe (por si un dia el maniqui devuelve el golpe).
var _last_hit_from := Vector3.INF
## Burbuja de agua que se le pone encima mientras esta atrapado.
var _trap_visual: Node3D = null


func _ready() -> void:
	add_to_group(TARGET_GROUP)
	health = max_health
	_shake_seed = float(get_instance_id() % 1000) * 0.01
	_build()


## Construye el maniqui entero desde codigo. Se hace asi para que la escena sea
## un unico nodo y no haya que mantener a mano malla, colision y etiqueta.
func _build() -> void:
	_body = Node3D.new()
	_body.name = "Cuerpo"
	add_child(_body)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.62, 0.66, 0.72)
	_material.roughness = 0.7
	_material.emission_enabled = true
	_material.emission = Color(0.35, 0.75, 1.0)
	_material.emission_energy_multiplier = 0.0

	var trunk := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	trunk.mesh = capsule
	trunk.material_override = _material
	trunk.position = Vector3(0.0, 0.75, 0.0)
	_body.add_child(trunk)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	head.mesh = sphere
	head.material_override = _material
	head.position = Vector3(0.0, 1.72, 0.0)
	_body.add_child(head)

	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.35
	capsule_shape.height = 1.5
	shape.shape = capsule_shape
	shape.position = Vector3(0.0, 0.75, 0.0)
	add_child(shape)

	# Etiqueta con la vida. billboard activado: si no, al mirarla desde detras
	# (la camara del proyecto mira hacia -Z) se veria del reves.
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.pixel_size = 0.0032
	_label.outline_size = 18
	_label.modulate = Color(1, 1, 1)
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.position = Vector3(0.0, label_height, 0.0)
	add_child(_label)
	_update_label()


func _process(delta: float) -> void:
	# Latido de daño: el maniqui se ilumina un instante al recibir un golpe.
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		if _material != null:
			_material.emission_energy_multiplier = _flash * 2.5
	# Atrapado: tiembla y se le ve el agua encima.
	if _trapped > 0.0:
		_trapped = maxf(_trapped - delta, 0.0)
		if _body != null:
			var t := float(Time.get_ticks_msec()) * 0.02 + _shake_seed
			_body.position = Vector3(sin(t * 7.0), 0.0, cos(t * 6.3)) * 0.04
		if _trapped <= 0.0:
			_release_visual()
			_update_label()


# -----------------------------------------------------------------------------
#  Contrato de objetivo (lo que llaman las habilidades)
# -----------------------------------------------------------------------------
func apply_damage(amount: float, from_position: Vector3, _kind: StringName = &"light") -> void:
	if _defeated or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_flash = 1.0
	_update_label(amount)
	if health <= 0.0:
		_defeat()
	# El empuje no mueve a un maniqui clavado en el suelo, pero se deja anotado
	# que el golpe venia de ahi: es lo que usaria un enemigo de verdad.
	if from_position.is_finite():
		_last_hit_from = from_position


func get_hit_center() -> Vector3:
	return global_position + Vector3.UP * 0.95


func get_hit_radius() -> float:
	return hit_radius


func is_defeated() -> bool:
	return _defeated


## Quedar atrapado: durante [param duration] segundos no puede hacer nada y se le
## ve envuelto en agua. Es un ESTADO de verdad, no un efecto de quita y pon.
func trap(duration: float) -> void:
	if _defeated or duration <= 0.0:
		return
	_trapped = maxf(_trapped, duration)
	_show_trapped_visual()
	_update_label()


func is_trapped() -> bool:
	return _trapped > 0.0


func get_trap_left() -> float:
	return _trapped


func get_health_ratio() -> float:
	return health / maxf(max_health, 0.001)


## Devuelve el maniqui a su sitio (util en pruebas).
func reset() -> void:
	_defeated = false
	health = max_health
	_trapped = 0.0
	_flash = 0.0
	_release_visual()
	if _body != null:
		_body.position = Vector3.ZERO
		_body.rotation = Vector3.ZERO
	if _material != null:
		_material.emission_energy_multiplier = 0.0
		_material.albedo_color = Color(0.62, 0.66, 0.72)
	_update_label()


# -----------------------------------------------------------------------------
#  Interno
# -----------------------------------------------------------------------------
func _defeat() -> void:
	_defeated = true
	if _body != null:
		# Cae de lado: basta con tumbarlo, no hace falta una animacion.
		_body.rotation = Vector3(0.0, 0.0, deg_to_rad(84.0))
		_body.position = Vector3(0.0, 0.15, 0.0)
	if _material != null:
		_material.albedo_color = Color(0.35, 0.38, 0.42)
	# Al caer se le quita el agua de encima: la prision se rompe.
	_release_visual()
	_trapped = 0.0
	_update_label()


func _show_trapped_visual() -> void:
	if _trap_visual != null:
		return
	var orb: MeshInstance3D = WaterEffectsScript.make_orb(hit_radius * 2.0)
	add_child(orb)
	orb.position = Vector3(0.0, 0.95, 0.0)
	_trap_visual = orb


func _release_visual() -> void:
	if _trap_visual != null and is_instance_valid(_trap_visual):
		_trap_visual.queue_free()
	_trap_visual = null


func _update_label(just_took := 0.0) -> void:
	if _label == null:
		return
	if _defeated:
		_label.text = "DERRIBADO"
		_label.modulate = Color(1.0, 0.45, 0.4)
		return
	var line := "VIDA %d / %d" % [int(round(health)), int(round(max_health))]
	if just_took > 0.0:
		line += "   -%d" % int(round(just_took))
	if _trapped > 0.0:
		line += "\nATRAPADO %.1fs" % _trapped
		_label.modulate = Color(0.55, 0.85, 1.0)
	else:
		_label.modulate = Color(1, 1, 1)
	_label.text = line
