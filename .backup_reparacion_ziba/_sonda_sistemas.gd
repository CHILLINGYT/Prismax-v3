extends Node

## SONDA DE SISTEMAS — comprobación tras la reparación de ziba_prototipo.tscn.
##
## Instancia el JUEGO REAL como hijo (igual que el arnés del diálogo), espera a que
## la ciudad procedural termine de generarse y comprueba que están presentes y vivos:
## el jugador, la ciudad, el NPC de Iván, el director de eventos y el gestor de
## streaming. Guarda capturas y un registro, y termina el proceso por sí sola.

const RUTA_LOG := "res://.backup_reparacion_ziba/log_sistemas.txt"
const RUTA_CAPTURAS := "res://.backup_reparacion_ziba/capturas"

var _registro: FileAccess = null
var _fallos: Array[String] = []
var _juego: Node = null
var _t0: float = 0.0


func _ready() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(RUTA_CAPTURAS)
	_registro = FileAccess.open(RUTA_LOG, FileAccess.WRITE)
	_log("=== SONDA DE SISTEMAS (post-reparación) ===")
	var guardia := Timer.new()
	guardia.wait_time = 150.0
	guardia.one_shot = true
	guardia.timeout.connect(func() -> void:
		_log("!! TIEMPO AGOTADO")
		_cerrar())
	add_child(guardia)
	guardia.start()
	_ejecutar()


func _ejecutar() -> void:
	await _frames(3)
	_juego = get_node_or_null("Juego")
	_log("escena del juego instanciada: %s" % str(_juego != null))
	if _juego == null:
		_fallo("no se pudo instanciar el juego")
		_cerrar()
		return

	# --- Nodos clave de la ESCENA (deben existir nada más cargar) ---
	var jugador := _juego.get_node_or_null("Jugador") as Node3D
	var ciudad := _juego.get_node_or_null("Ciudad")
	var obrero := _juego.get_node_or_null("NPC_Estatico_Obrero") as Node3D
	var director := _juego.get_node_or_null("DirectorEventos")
	var streaming := _juego.get_node_or_null("StreamingMundo")
	_log("--- nodos de la escena ---")
	_log("  Jugador            : %s (hijos %d)" % [str(jugador != null), jugador.get_child_count() if jugador != null else -1])
	_log("  Ciudad (generador) : %s" % str(ciudad != null))
	_log("  NPC_Estatico_Obrero: %s" % str(obrero != null))
	_log("  DirectorEventos    : %s | en árbol: %s | script: %s" % [
			str(director != null), str(director.is_inside_tree()) if director != null else "-",
			String(director.get_script().resource_path) if director != null and director.get_script() != null else "-"])
	_log("  StreamingMundo     : %s | en árbol: %s | activo=%s | modo_diagnostico=%s" % [
			str(streaming != null), str(streaming.is_inside_tree()) if streaming != null else "-",
			str(streaming.get("activo")) if streaming != null else "-",
			str(streaming.get("modo_diagnostico")) if streaming != null else "-"])
	_comprobar(jugador != null, "el jugador está presente")
	_comprobar(ciudad != null, "el generador de ciudad está presente")
	_comprobar(obrero != null, "el NPC de Iván está presente")
	_comprobar(director != null and director.is_inside_tree(), "DirectorEventos está presente y vivo")
	_comprobar(streaming != null and streaming.is_inside_tree(), "StreamingMundo está presente y vivo")
	_comprobar(streaming != null and streaming.get("activo") == false, "StreamingMundo.activo sigue en false")
	_comprobar(streaming != null and streaming.get("modo_diagnostico") == false, "StreamingMundo.modo_diagnostico sigue en false")

	# --- Esperar a la generación de la ciudad ---
	_log("--- esperando la generación de la ciudad ---")
	var t_ini := Time.get_ticks_msec() / 1000.0
	var generada: Node = null
	var peatones_nodo: Node = null
	while Time.get_ticks_msec() / 1000.0 - t_ini < 120.0:
		await _frames(1)
		generada = _buscar_nodo_por_nombre(_juego, "CiudadGenerada")
		peatones_nodo = _buscar_nodo_por_nombre(_juego, "Peatones")
		if peatones_nodo != null and peatones_nodo.get_child_count() > 20:
			break
	var t_gen := Time.get_ticks_msec() / 1000.0 - t_ini
	var vivas := _nodos_vivos(_juego)
	_log("  generación: %.1f s | CiudadGenerada: %s (hijos %d) | nodos vivos totales: %d" % [
			t_gen, str(generada != null), generada.get_child_count() if generada != null else -1, vivas])
	_comprobar(generada != null and generada.get_child_count() > 5, "la ciudad procedural se generó (CiudadGenerada con %d hijos)" % (generada.get_child_count() if generada != null else -1))
	_comprobar(vivas > 2000, "el mundo tiene contenido real (%d nodos vivos)" % vivas)

	# --- Contenido esperado de la ciudad ---
	var plazas := _contar_por_nombre(generada, "Parque_")
	var n_peatones := peatones_nodo.get_child_count() if peatones_nodo != null else -1
	_log("  plazas (Parque_*): %d | nodo Peatones: %s | peatones vivos: %d" % [
			plazas, str(peatones_nodo != null), n_peatones])
	_comprobar(plazas > 0, "hay plazas en la ciudad (%d)" % plazas)
	_comprobar(peatones_nodo != null and n_peatones > 20, "los peatones se generaron (%d)" % n_peatones)

	# --- Iván quedó colocado y el jugador está en el mundo ---
	var listo := false
	for i in 900:
		await _frames(1)
		if obrero != null and bool(obrero.get("_listo")):
			listo = true
			break
	_log("--- NPC de Iván ---")
	_log("  colocado: %s | posición: %s" % [str(listo), str(obrero.global_position) if obrero != null else "-"])
	_comprobar(listo, "el NPC se colocó en una plaza")
	_log("--- jugador ---")
	_log("  posición: %s | dentro del árbol: %s" % [
			str(jugador.global_position) if jugador != null else "-",
			str(jugador.is_inside_tree()) if jugador != null else "-"])
	if obrero != null and jugador != null:
		_log("  distancia jugador<->Iván: %.2f m" % jugador.global_position.distance_to(obrero.global_position))

	# --- Capturas: vista del jugador y vista aérea ---
	await _capturar("sistemas_01_jugador")
	var aerea := _juego.get_node_or_null("CamaraAerea") as Camera3D
	if aerea != null:
		aerea.global_position = Vector3(0, 260, 0)
		aerea.look_at(Vector3.ZERO, Vector3.FORWARD)
		aerea.current = true
		await _frames(8)
		await _capturar("sistemas_02_aerea")

	_log("=== RESULTADO: %d fallos ===" % _fallos.size())
	for f in _fallos:
		_log("  FALLO: " + f)
	_log("tiempo total: %.1f s" % (Time.get_ticks_msec() / 1000.0 - _t0))
	_cerrar()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _nodos_vivos(raiz: Node) -> int:
	if raiz == null:
		return 0
	var c := 1
	for h in raiz.get_children():
		c += _nodos_vivos(h)
	return c


func _contar_por_nombre(raiz: Node, prefijo: String) -> int:
	if raiz == null:
		return 0
	var c := 0
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if String(n.name).begins_with(prefijo):
			c += 1
		for h in n.get_children():
			pila.append(h)
	return c


func _buscar_nodo_por_nombre(raiz: Node, nombre: String) -> Node:
	if raiz == null:
		return null
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if String(n.name) == nombre:
			return n
		for h in n.get_children():
			pila.append(h)
	return null


func _capturar(nombre: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ok := img.save_png(RUTA_CAPTURAS + "/" + nombre + ".png") == OK
	_log("  captura %s: %s (%dx%d)" % [nombre, str(ok), img.get_width(), img.get_height()])


func _comprobar(cond: bool, texto: String) -> void:
	if not cond:
		_fallos.append(texto)
	_log("  %s %s" % ["OK  " if cond else "FALLO", texto])


func _fallo(texto: String) -> void:
	_fallos.append(texto)
	_log("  FALLO " + texto)


func _log(texto: String) -> void:
	print(texto)
	if _registro != null:
		_registro.store_line(texto)
		_registro.flush()


func _cerrar() -> void:
	_log("=== FIN ===")
	if _registro != null:
		_registro.close()
	get_tree().quit(0 if _fallos.is_empty() else 1)