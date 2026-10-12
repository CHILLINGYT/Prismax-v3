class_name WaterProjectile
extends "res://personaje/transformaciones/acuatica/abilities/water_ability.gd"
## =============================================================================
##  HABILIDAD 1 - PROYECTIL DE AGUA  (la mas rapida, el enfriamiento mas corto)
## =============================================================================
##  Una bola de agua comprimida que SALE DISPARADA en linea recta. Es un objeto
##  de verdad: viaja por el mundo a [member speed] m/s, deja estela, choca contra
##  paredes y contra los objetivos, y al chocar revienta y hace daño.
##
##  Lo que la hace sentir como un proyectil y no como un dibujo:
##    * estela de gotas que se queda donde ha pasado (local_coords = false),
##    * luz propia, para verla venir aunque sea de noche,
##    * la explosion del impacto es proporcionada a su radio.
##
##  La usa el jugador con la tecla 1.
## =============================================================================

@export var orb_radius := 0.3
@export var trail_amount := 44


func _build_visual() -> void:
	var orb := WaterEffects.make_orb(
		orb_radius,
		Color(0.06, 0.38, 0.66),
		Color(0.72, 0.95, 1.0))
	add_child(orb)
	_visual = orb

	# Luz propia: un proyectil de agua tiene que verse venir.
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.82, 1.0)
	light.light_energy = 2.6
	light.omni_range = 6.0
	add_child(light)

	# Estela. local_coords = false hace que las gotas se queden EN EL SITIO donde
	# se sueltan: por eso queda una estela detras en vez de una nube pegada.
	# DEBAJO DEL AGUA la estela no son gotas: son burbujas que suben.
	var trail := WaterEffects.make_particles({
		"amount": trail_amount,
		"speed": 0.5,
		"size": 0.07 if underwater else 0.11,
		"life": 0.9 if underwater else 0.5,
		"up": 0.4,
		"spread": 75.0,
		"radius": orb_radius * 0.7,
		"opacity": 0.6 if underwater else 0.75,
		"gravity": -1.6 if underwater else 0.6,
	})
	add_child(trail)
	trail.emitting = true


func _physics_process(delta: float) -> void:
	super(delta)
	# El agua gira sobre si misma: una esfera perfecta e inmovil se ve muerta.
	if _spent or _visual == null:
		return
	_visual.rotate_y(delta * 2.2)
	_visual.rotate_x(delta * 1.1)
	# Y se deforma un poco al volar: el agua no viaja como una canica rigida.
	var pulse := 1.0 + sin(_elapsed * 24.0) * 0.07
	_visual.scale = Vector3(pulse, 1.0, pulse)


func _on_impact(point: Vector3, _target: Node3D) -> void:
	water_burst(point, hit_radius * 1.7, 0.65)
	WaterEffects.flash(get_parent() as Node3D, point, hit_radius * 0.6, 0.28)
	# El agua se aplasta contra lo que golpea, en vez de desaparecer redonda.
	if _visual != null and is_instance_valid(_visual):
		var tween := _visual.create_tween()
		tween.tween_property(_visual, "scale", Vector3(1.5, 0.6, 1.5), 0.12)
