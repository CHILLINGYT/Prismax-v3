extends Node
## PRUEBA (temporal) del sistema de pisadas acuáticas. NO se empaqueta.
## Instancia leo_jugador.tscn, fuerza la forma acuática y mide cuántas pisadas
## emite PasosJugador por clip, contra las fases MEDIDAS de la TABLA.

var _jug: Node
var _ap: AnimationPlayer
var _pasos: Node
var _pisadas: Array = []
var _fallos := 0

func _ready() -> void:
	_jug = (load("res://personaje/base/escenas/leo_jugador.tscn") as PackedScene).instantiate()
	add_child(_jug)
	await get_tree().process_frame
	_jug.set_physics_process(false)
	_jug.set_process(false)
	_ap = _jug.get_node_or_null("Acuatico/AnimadorAcuatico") as AnimationPlayer
	_pasos = _jug.get_node_or_null("Pasos")
	print("[test] ap=", _ap != null, " pasos=", _pasos != null)
	if _ap == null or _pasos == null:
		get_tree().quit(); return
	_pasos.pisada.connect(_on_pisada)
	if _jug.has_method("_entrar_acuatico"):
		_jug.call("_entrar_acuatico")
	await get_tree().process_frame

	# (clip, duración de la fase, mínimo esperado, máximo esperado)
	await _fase("walk", 1.4333333 * 3.0, "walk", 4, 8)
	await _fase("run", 0.7 * 3.0, "run", 4, 8)
	await _fase("idle_stand", 1.5, "quieto", 0, 0)
	await _fase("swim_forward", 2.0, "nadar", 0, 0)
	await _fase("jump", 1.0, "salto", 0, 0)
	await _fase("fall", 1.0, "caída", 0, 0)
	await _fase_permiso("walk", 1.5, "walk sin apoyo", 0, 0)
	print("[test] FALLOS = ", _fallos)
	print("[test] FIN")
	get_tree().quit()

func _on_pisada(forma: String, clip: String, pie: String, _u: float, _v: int) -> void:
	_pisadas.append({"f": forma, "c": clip, "pie": pie})

func _fase(clip: String, dur: float, etiqueta: String, mn: int, mx: int) -> void:
	await _correr(clip, dur, true, etiqueta, mn, mx)

func _fase_permiso(clip: String, dur: float, etiqueta: String, mn: int, mx: int) -> void:
	await _correr(clip, dur, false, etiqueta, mn, mx)

func _correr(clip: String, dur: float, permitido: bool, etiqueta: String, mn: int, mx: int) -> void:
	_pisadas.clear()
	if not _ap.has_animation(clip):
		print("[test] clip AUSENTE: ", clip); _fallos += 1; return
	_ap.speed_scale = 1.0
	_ap.play(clip)
	var t := 0.0
	while t < dur:
		var dt := get_process_delta_time()
		_pasos.call("actualizar", "acuatico", _ap, permitido, dt)
		t += dt
		await get_tree().process_frame
	var n := _pisadas.size()
	var pies := {}
	for p in _pisadas:
		pies[p["pie"]] = int(pies.get(p["pie"], 0)) + 1
	var ok := n >= mn and n <= mx
	if not ok:
		_fallos += 1
	print("[test] %-16s n=%2d pies=%s -> %s" % [etiqueta, n, str(pies), ("OK" if ok else "REVISAR (esperado %d..%d)" % [mn, mx])])