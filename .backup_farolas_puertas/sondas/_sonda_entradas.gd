extends Node

## Sonda de entradas en casas (Task 11, 5ª pasada):
##  - el tope de gente entrando a la vez se respeta (_entrando <= entrar_max)
##  - no hay puertas/sillas marcadas como ocupadas sin dueño (fuga de reservas)
##  - _entrando coincide con las reservas reales de tipo "entrada"
##  - las entradas no se atascan: siguen ocurriendo con los valores naturales
## Mide con el reloj de juego del propio director (_t_ahora).

var _dir: Node = null
var _fase := "colocacion"
var _t_ini := 0.0
var _t_muestra := 0.0
var _entradas_ini := 0
var _max_entrando := 0
var _huerfanos_max := 0
var _muestras := 0
var _fallos := 0


func _ready() -> void:
	Engine.time_scale = 6.0
	var escena: PackedScene = load("res://ziba/escenas/ziba_prototipo.tscn")
	var mundo := escena.instantiate()
	add_child(mundo)
	var reloj := get_tree().create_timer(270.0)
	reloj.timeout.connect(func() -> void:
		print("[Sonda] FAILSAFE: se acabó el tiempo")
		get_tree().quit())


func _process(delta: float) -> void:
	if _dir == null:
		_dir = _buscar(get_tree().root, "res://NPCs/Scripts/director_peatones.gd")
		return
	var t := float(_dir.get("_t_ahora"))
	if _fase == "colocacion":
		if t < 25.0:
			return
		# Fase forzada: todas las peticiones intentan entrar (para estresar el sistema).
		_dir.set("entrar_prob", 1.0)
		_dir.set("entrar_prob_tarde", 1.0)
		_t_ini = t
		_t_muestra = t
		_entradas_ini = int(_dir.get("_entradas"))
		_fase = "forzada"
		print("[Sonda] fase FORZADA desde t=%.0f s | ciudadanos=%d puertas usables=%d" % [
				t, _cuenta(), (_dir.get("_portales") as Array).size()])
	if _fase == "forzada":
		if t - _t_muestra >= 5.0:
			_muestra(t)
			_t_muestra = t
		if t - _t_ini >= 60.0:
			var n := int(_dir.get("_entradas")) - _entradas_ini
			print("[Sonda] fase forzada: %d entradas en 60 s de juego (%.1f/min) con tope %d" % [
					n, float(n), int(_dir.get("entrar_max"))])
			if n <= 0:
				_fallos += 1
				print("[Sonda] FALLO: nadie entró con probabilidad 1,0")
			_dir.set("entrar_prob", 0.012)
			_dir.set("entrar_prob_tarde", 0.022)
			_t_ini = t
			_t_muestra = t
			_entradas_ini = int(_dir.get("_entradas"))
			_fase = "natural"
			print("[Sonda] fase NATURAL (prob 0,012) desde t=%.0f s" % t)
	# natural
	if t - _t_muestra >= 10.0:
		_muestra(t)
		_t_muestra = t
	if t - _t_ini >= 120.0:
		var n2 := int(_dir.get("_entradas")) - _entradas_ini
		print("[Sonda] fase natural: %d entradas en 120 s (%.1f/min) con %d ciudadanos" % [
				n2, float(n2) / 2.0, _cuenta()])
		print("[Sonda] RESUMEN: muestras=%d max_entrando=%d huerfanos_max=%d fallos=%d" % [
				_muestras, _max_entrando, _huerfanos_max, _fallos])
		print("[Sonda] contadores del director: %s" % str(_dir.call("resumen")))
		print("[Sonda] fin")
		get_tree().quit()


func _muestra(t: float) -> void:
	_muestras += 1
	var entrando := int(_dir.get("_entrando"))
	var tope := int(_dir.get("entrar_max"))
	var reservas: Dictionary = _dir.get("_reservas")
	var reales := 0
	var refp := {}
	var refa := {}
	var refr := {}
	for c in reservas.keys():
		var r: Dictionary = reservas[c]
		match String(r.get("tipo", "")):
			"entrada":
				reales += 1
				refp[int(r.get("indice", -1))] = true
			"banco":
				refa[int(r.get("indice", -1))] = true
			"reposera":
				refr[int(r.get("indice", -1))] = true
	var huerfanos := 0
	var portales: Array = _dir.get("_portales")
	var asientos: Array = _dir.get("_asientos")
	var reposeras: Array = _dir.get("_reposeras")
	for i in portales.size():
		if not bool(portales[i]["libre"]) and not refp.has(i):
			huerfanos += 1
	for i2 in asientos.size():
		if not bool(asientos[i2]["libre"]) and not refa.has(i2):
			huerfanos += 1
	for i3 in reposeras.size():
		if not bool(reposeras[i3]["libre"]) and not refr.has(i3):
			huerfanos += 1
	_max_entrando = maxi(_max_entrando, entrando)
	_huerfanos_max = maxi(_huerfanos_max, huerfanos)
	if entrando > tope or entrando != reales or huerfanos > 0:
		_fallos += 1
	print("[Sonda] t=%6.1f s ciudadanos=%2d entrando=%d (reales=%d, tope=%d) huerfanos=%d entradas=%d nacimientos=%d sentados=%d tumbados=%d" % [
			t, _cuenta(), entrando, reales, tope, huerfanos,
			int(_dir.get("_entradas")), int(_dir.get("_nacimientos")),
			int(_dir.call("resumen")["sentados"]), int(_dir.call("resumen")["tumbados"])])


func _cuenta() -> int:
	return (_dir.get("peatones") as Array).size()


func _buscar(n: Node, ruta: String) -> Node:
	if n.get_script() != null and (n.get_script() as Script).resource_path == ruta:
		return n
	for h in n.get_children():
		var r := _buscar(h, ruta)
		if r != null:
			return r
	return null