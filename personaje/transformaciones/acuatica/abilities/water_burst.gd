class_name WaterBurst
extends "res://personaje/transformaciones/acuatica/abilities/water_ability.gd"
## =============================================================================
##  HABILIDAD 2 - ESFERA DE AGUA / EXPLOSION DE AREA
## =============================================================================
##  Una esfera que vuela y, al llegar, REVIENTA en una zona de agua que se queda
##  un rato haciendo daño a todo lo que pille dentro. Tiene dos fases:
##
##    FASE 1 (vuelo): viaja hacia delante [member travel_time] segundos, y si
##      toca algo por el camino explota antes.
##    FASE 2 (zona): se para, crece hasta [member field_radius] y durante
##      [member field_duration] segundos va dando golpes cada
##      [member tick_interval]. Cualquier objetivo que ENTRE en la zona mientras
##      dure tambien recibe: no es un unico golpe instantaneo.
##
##  Todo eso es de verdad: hay un radio, una duracion, daño por golpes, efectos
##  y su propio enfriamiento. La usa el jugador con la tecla 2.
## =============================================================================

@export var field_radius := 3.2
@export var field_duration := 2.6
@export var tick_interval := 0.4
@export var travel_time := 0.55

var _flying := true
var _travel := 0.0
var _field_time := 0.0
var _tick := 0.0


func _build_visual() -> void:
	var orb := WaterEffects.make_orb(
		hit_radius,
		Color(0.08, 0.42, 0.72),
		Color(0.75, 0.96, 1.0))
	add_child(orb)
	_visual = orb
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.85, 1.0)
	light.light_energy = 2.0
	light.omni_range = 7.0
	add_child(light)


func _advance(delta: float) -> void:
	if _flying:
		_travel += delta
		super(delta)
		if not _spent and _flying and _travel >= travel_time:
			_explode(global_position)
		return

	# --- Fase de zona ---
	_field_time += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = tick_interval
	# Un golpe a TODO lo que haya dentro, no solo al primero: es un area.
	for target in find_targets(global_position, field_radius):
		hurt(target, global_position)
	if _field_time >= field_duration:
		_fade_out()


## Al chocar durante el vuelo no desaparece: explota en el sitio del golpe.
func _impact(point: Vector3, target: Node3D) -> void:
	if _spent or not _flying:
		return
	if target != null:
		hurt(target, point)
	_explode(point)


func _explode(point: Vector3) -> void:
	if not _flying:
		return
	_flying = false
	global_position = point
	_tick = 0.0
	_field_time = 0.0
	lifetime = field_duration + 0.5
	_elapsed = 0.0
	if _visual != null:
		# La esfera se hincha hasta el radio del area y se queda ahi.
		var tween := _visual.create_tween()
		tween.tween_property(_visual, "scale", Vector3.ONE * (field_radius / maxf(hit_radius, 0.05)), 0.25)
	var host := get_parent() as Node3D
	water_burst(point, field_radius, 1.0)
	water_ring(point + Vector3.UP * 0.1, field_radius * 2.6, 0.9, 1.0)
	water_foam(point, field_radius * 0.8, field_duration)
	# El area se queda flotando: la esfera se hincha hasta el radio de la zona.
	if host != null and _visual != null:
		var light := OmniLight3D.new()
		light.light_color = Color(0.5, 0.85, 1.0)
		light.light_energy = 1.6
		light.omni_range = field_radius * 2.2
		add_child(light)


func _fade_out() -> void:
	if _spent:
		return
	_spent = true
	_on_expire()
	queue_free()


func _on_expire() -> void:
	water_foam(global_position, field_radius * 0.6, 1.0)
