class_name WaterPrison
extends "res://personaje/transformaciones/acuatica/abilities/water_ability.gd"
## =============================================================================
##  HABILIDAD 3 - PRISION DE AGUA
## =============================================================================
##  Una burbuja que vuela y, al dar a un objetivo, lo ENCIERRA. Pero no es un
##  dibujo: el objetivo queda de verdad ATRAPADO. La habilidad le llama a su
##  trap(duracion), y el objetivo (el maniqui) entra en un estado del que no
##  puede salir hasta que se acaba el tiempo. Mientras tanto la burbuja se queda
##  PEGADA a el, girando y apretandose.
##
##  Si la burbuja choca con una pared o se le acaba el tiempo sin dar a nadie,
##  simplemente se deshace.
##
##  La usa el jugador con la tecla 3.
## =============================================================================

@export var trap_duration := 3.0
@export var orb_radius := 1.35

var _caught: Node3D = null
var _hold := 0.0
var _spin := 0.0


func _build_visual() -> void:
	var orb := WaterEffects.make_orb(
		orb_radius,
		Color(0.10, 0.50, 0.80),
		Color(0.78, 0.97, 1.0))
	add_child(orb)
	_visual = orb
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.88, 1.0)
	light.light_energy = 2.2
	light.omni_range = 6.5
	add_child(light)


func _physics_process(delta: float) -> void:
	# --- Fase de presion: pegada al objetivo atrapado ---
	if _caught != null:
		_hold += delta
		if is_instance_valid(_caught) and _caught.is_inside_tree():
			global_position = _center_of(_caught)
		if _visual != null:
			# La burbuja gira y se aprieta poco a poco: se esta cerrando.
			var squeeze := clampf(1.0 - _hold / maxf(trap_duration, 0.1) * 0.3, 0.45, 1.0)
			_spin += delta * 1.6
			# Se gira desde cero cada vez para que la ondulacion no se acumule.
			_visual.rotation = Vector3(_spin * 0.35, _spin, _spin * 0.2)
			_visual.scale = Vector3.ONE * squeeze
		if _hold >= trap_duration:
			_release()
		return
	super(delta)


## En vez de reventar y desaparecer, atrapa a quien pille.
func _impact(point: Vector3, target: Node3D) -> void:
	if _spent or _caught != null:
		return
	if target != null and trap(target, trap_duration):
		# La prision tambien hace daño: encierra Y golpea. Si no, gastar la
		# habilidad no quitaba ni un punto de vida, que no tiene sentido.
		hurt(target, point)
		_caught = target
		_hold = 0.0
		global_position = _center_of(target)
		water_ring(point + Vector3.UP * 0.1, orb_radius * 3.0, 0.7, 0.8)
		water_foam(point, orb_radius * 0.9, trap_duration * 0.6)
		return
	# Sin objetivo: se deshace como un golpe normal.
	super(point, target)


func _release() -> void:
	if _spent:
		return
	_spent = true
	water_burst(global_position, orb_radius * 1.6, 0.65)
	queue_free()


func _on_expire() -> void:
	water_burst(global_position, orb_radius * 1.2, 0.5)
