extends Node
## Auditoría de APARICIÓN (temporal): comprueba que al repartir la gente no haya nadie sobre el
## asfalto, nadie fuera de la red, nadie amontonado y nadie dentro del radio del inicio del
## jugador. Mide el instante de creación (primer fotograma tras repartir).

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _listo := false


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	_run.call_deferred()


func _run() -> void:
	while _dir == null:
		await get_tree().process_frame
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	# Se deja pasar un par de segundos de juego: el director recoloca a quien haya quedado
	# dentro del entorno del inicio del jugador en cuanto lo localiza.
	var hasta := float(Time.get_ticks_msec()) + 1500.0
	while float(Time.get_ticks_msec()) < hasta:
		await get_tree().process_frame
	_auditar()
	get_tree().quit()


func _auditar() -> void:
	var jugador: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if jugador == null:
		jugador = _juego.get_node_or_null("Jugador") as Node3D
	if jugador == null:
		for n in _juego.find_children("*", "CharacterBody3D", true, false):
			if String(n.name).to_lower().contains("jugador") or String(n.name).to_lower().contains("player"):
				jugador = n
				break
	if jugador != null:
		print("[Auditoria] jugador localizado en %s (%s)" % [jugador.name, str(jugador.global_position)])
	var p_jug := jugador.global_position if jugador != null else Vector3.ZERO
	var red: Object = _dir.red
	var asfalto := 0
	var fuera := 0
	var juntos := 0
	var cerca_jugador := 0
	var dist_min_jugador := 9999.0
	var dist_min_par := 9999.0
	var posiciones: Array[Vector3] = []
	var capas := 0
	for c in _dir.peatones:
		var p: Vector3 = c.global_position
		posiciones.append(p)
		if c.collision_layer == 0 and c.collision_mask == 0:
			capas += 1
		if red != null:
			var t: Array = c.tramo_red()
			var es_cruce := t.size() >= 3 and String(t[2]) == "cruce"
			if not es_cruce and red.es_calzada(p):
				asfalto += 1
			var idx: int = red.nodo_mas_cercano(p)
			if idx >= 0:
				var n: Vector3 = red.pos(idx)
				if Vector2(p.x - n.x, p.z - n.z).length() > 3.0:
					fuera += 1
		if jugador != null:
			var d := Vector2(p.x - p_jug.x, p.z - p_jug.z).length()
			dist_min_jugador = minf(dist_min_jugador, d)
			if d < 28.0:
				cerca_jugador += 1
	for i in posiciones.size():
		for j in range(i + 1, posiciones.size()):
			var d := Vector2(posiciones[i].x - posiciones[j].x, posiciones[i].z - posiciones[j].z).length()
			if d < dist_min_par:
				dist_min_par = d
			if d < 1.0:
				juntos += 1
	print("[Auditoria] ciudadanos: %d" % posiciones.size())
	print("[Auditoria] sobre el asfalto al aparecer: %d" % asfalto)
	print("[Auditoria] a más de 3 m de la red: %d" % fuera)
	print("[Auditoria] amontonados (a menos de 1 m de otro): %d" % juntos)
	print("[Auditoria] separación mínima entre dos: %.2f m" % dist_min_par)
	print("[Auditoria] dentro de 28 m del inicio del jugador: %d (mínimo %.1f m)" % [cerca_jugador, dist_min_jugador])
	print("[Auditoria] sin capa de colisión (correcto: no usan física): %d de %d" % [capas, posiciones.size()])