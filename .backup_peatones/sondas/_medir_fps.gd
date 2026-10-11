extends Node
## Sonda de FPS (temporal): carga el juego real, deja que termine de generar y mide durante unos
## segundos el fotograma medio, el 1% peor y el peor fotograma. Sirve para comprobar que el
## sistema de peatones (y el estabilizador de cabeza que se añadió) no cuesta nada apreciable.

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _t0 := 0
var _contando := false
var _tiempos: Array[float] = []
var _peor := 0.0


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	add_child(_juego)
	_t0 = Time.get_ticks_msec()
	print("[FPS] juego cargado; esperando a que termine de generar...")


func _process(delta: float) -> void:
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		return
	if not _contando:
		if real < 9.0:
			return
		_contando = true
		print("[FPS] midiendo 8 s con %d ciudadanos..." % _dir.peatones.size())
		return
	if delta > 0.0:
		_tiempos.append(delta)
		_peor = maxf(_peor, delta)
	if real > 17.5:
		informe()
		get_tree().quit()


func informe() -> void:
	if _tiempos.is_empty():
		print("[FPS] sin muestras")
		return
	var suma := 0.0
	for d in _tiempos:
		suma += d
	var media := suma / float(_tiempos.size())
	var orden := _tiempos.duplicate()
	orden.sort()
	var i1 := maxi(0, int(orden.size() * 0.99) - 1)
	var p1: float = orden[i1]
	print("[FPS] fotogramas %d | medio %.1f fps | 1%% peor %.1f fps | peor fotograma %.0f ms" % [
			_tiempos.size(), 1.0 / media, 1.0 / p1, _peor * 1000.0])