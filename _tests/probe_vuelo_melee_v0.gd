extends Node3D
## SONDA EN VIVO del daño de los golpes básicos del VUELO.
##
## Reproduce el camino REAL: el jugador verdadero (leo_jugador.tscn) se
## transforma a VUELO frente a un enemigo verdadero (enemigo_prueba.tscn) y los
## golpes se disparan con EVENTOS de entrada reales (melee_light), no llamando
## funciones internas. Después de cada golpe imprime:
##   * la vida real del enemigo (vida_actual()),
##   * el estado del cuerpo activo (en_suelo, velocidad, distancia),
##   * y una RÉPLICA EXACTA de la consulta espacial del módulo
##     (esfera 1.4 en adelante*1.2 + up*0.9, máscara 1|16) para distinguir
##     "geometría/capas" de "lógica".

const ENEMIGO_ESPERA := 0.25

var _r: Node = null
var _enemigo: Node = null
var _t: float = 0.0
var _paso: int = 0
var _soltar: Array[StringName] = []
var _vida0: float = -1.0


func _ready() -> void:
	_r = get_node_or_null("Jugador")
	_enemigo = get_node_or_null("Enemigo")
	print("[PROBE] jugador=", _r, " enemigo=", _enemigo)
	if _enemigo != null and _enemigo.has_method("vida_actual"):
		_vida0 = float(_enemigo.call("vida_actual"))
	print("[PROBE] vida inicial del enemigo: ", _vida0)
	print("[PROBE] enemigos en grupo damageable: ", get_tree().get_nodes_in_group("damageable").size())


func _physics_process(delta: float) -> void:
	# Suelta lo pulsado en el fotograma anterior (para que el próximo pulso
	# vuelva a ser un "just_pressed" de verdad).
	for n in _soltar:
		Input.action_release(n)
	_soltar.clear()

	_t += delta
	match _paso:
		0:
			if _t >= ENEMIGO_ESPERA:
				_paso = 1
				print("[PROBE] forma inicial=", _r.get("forma"), " (0=humano)")
				_r.call("_on_transformacion_elegida", &"aguila")
		1:
			if _t >= 1.8:
				_paso = 2
				_informe("tras transformar")
				_sondear()
				_pulsar(&"melee_light")
		2:
			if _t >= 2.15:
				_paso = 3
				_informe("tras golpe 1")
				_pulsar(&"melee_light")
		3:
			if _t >= 2.5:
				_paso = 4
				_informe("tras golpe 2")
				_pulsar(&"melee_light")
		4:
			if _t >= 3.0:
				_paso = 5
				_informe("tras golpe 3 (ventana de impacto)")
		5:
			if _t >= 4.4:
				_paso = 6
				_informe("FINAL")
				_sondear()
				var vida := _vida_enemigo()
				print("[PROBE] DAÑO TOTAL=", _vida0 - vida, " (esperado 8+12+16=36 si los 3 conectan)")
				print("[PROBE] FIN")


func _pulsar(nombre: StringName) -> void:
	Input.action_press(nombre)
	_soltar.append(nombre)
	print("[PROBE] pulso ", nombre)


func _vida_enemigo() -> float:
	if _enemigo != null and _enemigo.has_method("vida_actual"):
		return float(_enemigo.call("vida_actual"))
	return -1.0


func _cuerpo_activo() -> CharacterBody3D:
	if _r != null and _r.has_method("cuerpo_activo"):
		return _r.call("cuerpo_activo") as CharacterBody3D
	return null


func _informe(etiqueta: String) -> void:
	var cuerpo := _cuerpo_activo()
	var en_suelo := false
	var vel := Vector3.ZERO
	var dist := -1.0
	var pos := Vector3.ZERO
	if cuerpo != null:
		en_suelo = cuerpo.is_on_floor()
		vel = cuerpo.velocity
		pos = cuerpo.global_position
		if _enemigo is Node3D:
			dist = (pos - (_enemigo as Node3D).global_position).length()
	print("[PROBE] %s → forma=%s vida=%.1f cuerpo=%s en_suelo=%s vel=(%.2f, %.2f, %.2f) dist=%.2f pos=(%.2f, %.2f, %.2f)" % [
		etiqueta, str(_r.get("forma")), _vida_enemigo(), str(cuerpo), str(en_suelo),
		vel.x, vel.y, vel.z, dist, pos.x, pos.y, pos.z,
	])


## Réplica EXACTA de la consulta de _impacto_melee: si acá aparece el enemigo y
## el módulo no daña, el problema es de lógica, no de geometría ni de capas.
func _sondear() -> void:
	var cuerpo := _cuerpo_activo()
	if cuerpo == null:
		print("[PROBE] réplica: sin cuerpo activo")
		return
	var espacio := cuerpo.get_world_3d().direct_space_state
	var esfera := SphereShape3D.new()
	esfera.radius = 1.4
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = esfera
	var visual := cuerpo.get_node_or_null("VisualRoot") as Node3D
	var adelante := Vector3.FORWARD
	if visual != null:
		adelante = -visual.global_transform.basis.z
	consulta.transform = Transform3D(Basis.IDENTITY, cuerpo.global_position + adelante * 1.2 + Vector3.UP * 0.9)
	consulta.collide_with_bodies = true
	consulta.collision_mask = 1 | 16
	consulta.exclude = [cuerpo.get_rid()]
	var golpes := espacio.intersect_shape(consulta, 6)
	print("[PROBE] réplica: %d colisiones; visual=%s adelante=(%.2f, %.2f, %.2f)" % [
		golpes.size(), str(visual), adelante.x, adelante.y, adelante.z,
	])
	for res in golpes:
		var nodo := res["collider"] as Node
		if nodo == null:
			continue
		print("[PROBE]   · %s (%s) capa=%d damageable=%s maniqui=%s" % [
			nodo.name, nodo.get_class(), (nodo as CollisionObject3D).collision_layer,
			str(nodo.is_in_group("damageable")), str(nodo.is_in_group("maniqui")),
		])