extends Node3D
## SONDA EN VIVO del daño de los golpes básicos del VUELO + integración FreeFlow.
##
## Reproduce el camino REAL: el jugador verdadero (leo_jugador.tscn) transformado
## a VUELO frente a un enemigo verdadero, con EVENTOS de entrada reales
## (melee_light). Cadena de 5 golpes: los 3 primeros clavado en el lugar (como la
## primera observación del problema) y los 2 últimos AVANZANDO, que es como pelea
## un jugador: con el objetivo del FreeFlow y el acercamiento, los golpes siguen
## conectando aunque el empuje lo aleje.

var _r: Node = null
var _enemigo: Node = null
var _gc: Node = null
var _t: float = 0.0
var _paso: int = 0
var _soltar: Array[StringName] = []
var _mantenidas: Array[StringName] = []
var _vida0: float = -1.0

func _ready() -> void:
	_r = get_node_or_null("Jugador")
	_enemigo = get_node_or_null("Enemigo")
	_gc = _r.get_node_or_null("Vuelo/GroundCombat") if _r != null else null
	print("[PROBE] jugador=", _r, " enemigo=", _enemigo, " ground_combat=", _gc)
	if _enemigo != null and _enemigo.has_method("vida_actual"):
		_vida0 = float(_enemigo.call("vida_actual"))
	print("[PROBE] vida inicial del enemigo: ", _vida0)
	print("[PROBE] usar_objetivo_freeflow=", _gc.get("usar_objetivo_freeflow") if _gc != null else "?")

func _physics_process(delta: float) -> void:
	for n in _soltar:
		Input.action_release(n)
	_soltar.clear()
	_t += delta
	match _paso:
		0:
			if _t >= 0.2:
				_paso = 1
				_r.call("_on_transformacion_elegida", &"aguila")
		1:
			if _t >= 1.8:
				_paso = 2
				_informe("tras transformar")
				_pulsar(&"melee_light")
		2:
			if _t >= 2.15:
				_paso = 3
				_informe("tras golpe 1 (parado)")
				_pulsar(&"melee_light")
		3:
			if _t >= 2.5:
				_paso = 4
				_informe("tras golpe 2 (parado)")
				_pulsar(&"melee_light")
		4:
			if _t >= 2.85:
				_paso = 5
				_informe("tras golpe 3 (parado)")
				_mantener(&"mover_adelante")
				_pulsar(&"melee_light")
		5:
			if _t >= 3.2:
				_paso = 6
				_informe("tras golpe 4 (avanzando)")
				_pulsar(&"melee_light")
		6:
			if _t >= 4.3:
				_paso = 7
				_mantener(&"mover_adelante")
		7:
			if _t >= 5.2:
				_paso = 8
				_informe("FINAL (golpe 5 con persecución)")
				_soltar_accion(&"mover_adelante")
				_replica()
				var vida := _vida_enemigo()
				print("[PROBE] DAÑO TOTAL=%.0f (cadena 8/12/16/20/8=64 si conectan los 5)" % [_vida0 - vida])
				print("[PROBE] FIN")

func _pulsar(nombre: StringName) -> void:
	Input.action_press(nombre)
	_soltar.append(nombre)
	print("[PROBE] pulso ", nombre)

func _mantener(nombre: StringName) -> void:
	Input.action_press(nombre)
	if not _mantenidas.has(nombre):
		_mantenidas.append(nombre)

func _soltar_accion(nombre: StringName) -> void:
	Input.action_release(nombre)
	_mantenidas.erase(nombre)

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
	if cuerpo == null:
		print("[PROBE] %s → SIN cuerpo activo" % etiqueta)
		return
	var dist := -1.0
	if _enemigo is Node3D:
		dist = cuerpo.global_position.distance_to((_enemigo as Node3D).global_position)
	var nombre_objetivo := "—"
	if _gc != null and _gc.get("_objetivo") != null:
		nombre_objetivo = String((_gc.get("_objetivo") as Node).name)
	print("[PROBE] %s → forma=%s en_suelo=%s dist=%.2f objetivo=%s vida=%.1f" % [
		etiqueta, str(_r.get("forma")), str(cuerpo.is_on_floor()), dist, nombre_objetivo, _vida_enemigo(),
	])

## Réplica EXACTA de la consulta espacial del respaldo (esfera 1.4 a 1.2 delante,
## máscara 1|16): muestra qué cuerpos ve realmente el golpe.
func _replica() -> void:
	var cuerpo := _cuerpo_activo()
	if cuerpo == null:
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
	print("[PROBE] réplica espacial: %d colisiones" % golpes.size())
	for res in golpes:
		var nodo := res["collider"] as Node
		if nodo == null:
			continue
		print("[PROBE]   · %s damageable=%s" % [nodo.name, str(nodo.is_in_group("damageable"))])