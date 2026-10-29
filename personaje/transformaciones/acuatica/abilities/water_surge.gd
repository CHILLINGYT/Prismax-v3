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

## Sonido del IMPACTO de la ola: el MISMO chapoteo de impacto que las demás
## habilidades acuáticas (golpe agua 2.wav). La ACTIVACIÓN de la oleada es otro
## momento y otro archivo (efecto habilidades.wav, lo dispara el controlador). Suena
## UNA vez por cada objetivo alcanzado de verdad y nunca al crear la ola ni cuando no
## toca a nadie: el marcador _hit_ids garantiza que un mismo objetivo no vuelva a
## sonar en toda la ejecución de la habilidad.
const AUD_OLA_IMPACTO := preload("res://audio/personaje/transformacion/Animaciones acuaticas/golpe agua 2.wav")

## Reproductores en rueda: varios impactos seguidos (o dos a la vez) no se cortan
## entre sí y NUNCA se crean nodos nuevos mientras dura la habilidad.
const VOCES_IMPACTO := 5
## Volumen de cada impacto: por debajo del golpe del puño, para que una ola que barre
## a varios enemigos no sature.
const AUD_OLA_DB := -6.0
## CHOQUE contra el escenario (pared, suelo, un objeto) y FINAL por tiempo sin haber
## tocado nada: los dos suenan con el mismo chapoteo de la ola, pero más bajos y (el
## final) más grave, para distinguirse de sus impactos contra enemigos.
const AUD_OLA_CHOQUE_DB := -9.0
const AUD_OLA_FIN_DB := -13.0
const AUD_OLA_FIN_PITCH := 0.8

var _hit_ids := {}
var _voces: Array[AudioStreamPlayer3D] = []
var _voz := 0
## El choque contra el escenario y el final por tiempo ya sonaron (una vez cada uno).
var _ola_choque_sonado := false
var _ola_fin_sonado := false


func _build_visual() -> void:
	# La oleada conserva SU reproductor de impacto (5 voces y más alcance, para un
	# muro que barre a varios): se desactiva el genérico de la clase base para que
	# cada impacto suene UNA sola vez, no dos.
	sonido_impacto_propio = true
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
	# Voces del sonido de impacto, listas desde el primer fotograma: 3D (se oye venir
	# del agua, no del jugador) y reutilizadas, para no crear nodos por impacto. Viven
	# en un GRUPO COMPARTIDO colgado del host: la oleada se libera al acabarse y, si
	# fueran hijas suyas, el último chapoteo se cortaría a media reproducción.
	var pool := _pool_sonidos(POOL_IMPACTO_OLA)
	if pool.get_child_count() == 0:
		for i in VOCES_IMPACTO:
			var voz := AudioStreamPlayer3D.new()
			voz.name = "SonidoOla%d" % (i + 1)
			voz.stream = AUD_OLA_IMPACTO
			voz.volume_db = AUD_OLA_DB
			voz.max_distance = 45.0
			pool.add_child(voz)
	_voces.clear()
	for hijo in pool.get_children():
		if hijo is AudioStreamPlayer3D:
			_voces.append(hijo as AudioStreamPlayer3D)


## Golpea a TODOS los que pilla, pero a cada uno una sola vez: si no, un muro que
## dura varios segundos haria daño en cada fotograma.
func _check_hits() -> void:
	for target in find_targets(global_position, hit_radius):
		var id := target.get_instance_id()
		if _hit_ids.has(id):
			continue
		_hit_ids[id] = true
		hurt(target, global_position)
		# IMPACTO CONFIRMADO de la ola: suena aquí, una vez por objetivo alcanzado.
		_sonar_impacto()


## Un impacto de la ola: una voz libre reproduce el efecto en la posición de la ola
## (el choque) y, si están sonando todas, la rueda. Las voces viven en el host, así
## que hay que colocar cada una en el sitio del impacto (no heredan la posición).
## El volumen y el tono se fijan SIEMPRE: una voz que acaba de sonar como final (más
## grave) no puede contagiar ese tono al siguiente impacto.
func _sonar_impacto() -> void:
	if _voces.is_empty():
		return
	var voz := _tomar_voz(_voces, _voz)
	if voz.playing:
		_voz = (_voz + 1) % _voces.size()
	voz.global_position = global_position
	voz.volume_db = AUD_OLA_DB
	voz.pitch_scale = 1.0
	voz.play()


## CHOQUE de la ola contra el ESCENARIO (pared, suelo, un objeto): también suena,
## una sola vez (la ola se gasta en ese choque).
func _sonar_choque() -> void:
	if _ola_choque_sonado:
		return
	_ola_choque_sonado = true
	_sonar_voz(_voces, global_position, AUD_OLA_CHOQUE_DB, 1.0)


## FINAL por tiempo: la ola se apagó sin llegar a tocar nada. Suena más bajo y más
## grave, como cierre, y nunca como un impacto contra un enemigo que no golpeó.
func _sonar_fin_ola() -> void:
	if _ola_fin_sonado:
		return
	_ola_fin_sonado = true
	_sonar_voz(_voces, global_position, AUD_OLA_FIN_DB, AUD_OLA_FIN_PITCH)


## La oleada NO se para con los enemigos: los atraviesa y sigue. Si se parara en
## el primero, dejaria de ser una oleada (y ademas el rayo la frenaria justo
## encima, repitiendo el daño por los dos caminos).
func _stops_on_target() -> bool:
	return false


func _advance(delta: float) -> void:
	# Avanza girando un poco: una ola no viaja recta y tiesa.
	rotate_y(delta * 0.25)
	super(delta)


func _on_impact(point: Vector3, target: Node3D) -> void:
	# La oleada solo llega aquí al topar con el ESCENARIO (nunca se para con los
	# enemigos): es un choque real y suena.
	if target == null:
		_sonar_choque()
	water_burst(point, wave_width * 0.6, 1.1)
	water_ring(point + Vector3.UP * 0.1, wave_width * 1.8, 0.9, 1.0)
	water_foam(point, wave_width * 0.5, 1.4)


func _on_expire() -> void:
	# Se le acabó el tiempo a la ola: FINAL (después de los impactos que sí haya dado).
	_sonar_fin_ola()
	water_foam(global_position, wave_width * 0.5, 1.2)
