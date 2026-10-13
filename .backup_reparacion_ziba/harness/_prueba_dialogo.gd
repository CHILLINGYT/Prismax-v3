extends Node

## BANCO DE PRUEBAS del diálogo con Iván. Instancia el JUEGO REAL, se acerca al NPC,
## pulsa E y clic de verdad (eventos inyectados en el sistema de entrada), y comprueba
## paso a paso cada requisito. Escribe su registro a archivo y guarda capturas.

const JUEGO := "res://ziba/escenas/ziba_prototipo.tscn"
const RUTA_LOG := "res://.backup_reparacion_ziba/harness/log_prueba.txt"
const RUTA_CAPTURAS := "res://.backup_reparacion_ziba/harness/capturas"
const GUION_GLOBO := "res://ui/scripts/dialogue_balloon.gd"
const GUION_OBRERO := "res://NPCs/Scripts/npc_estatico_obrero.gd"
const GUION_CIUDAD := "res://generador_ciudad.gd"

const MENSAJES := [
	"Hola, me llamo Iván. Veo que eres nuevo por aquí...",
	"Llegan en un mal momento. La ciudad se ha vuelto muy peligrosa últimamente",
	"hay 20 prófugos de la justicia sueltos por ahí.",
	"Se rumorea que un superhéroe camina entre nosotros para protegernos, pero nadie conoce su verdadera identidad. Ten mucho cuidado.",
]

var _archivo: FileAccess = null
var _fallos: Array[String] = []
var _t0: float = 0.0
var _juego: Node = null
var _ciudad: Node = null
var _obrero: Node3D = null
var _jugador: Node3D = null
var _camara_jugador: Camera3D = null


func _ready() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(RUTA_CAPTURAS)
	_archivo = FileAccess.open(RUTA_LOG, FileAccess.WRITE)
	_log("=== PRUEBA DE DIÁLOGO CON IVÁN ===")
	var guardia := Timer.new()
	guardia.wait_time = 150.0
	guardia.one_shot = true
	guardia.timeout.connect(func() -> void:
		_log("!! TIEMPO AGOTADO: la prueba se detiene")
		get_tree().quit(1))
	add_child(guardia)
	guardia.start()
	_ejecutar()


func _ejecutar() -> void:
	await _frames(3)
	_localizar()
	if _obrero == null:
		_log("FALLO: no se encontró el NPC obrero en la escena del juego")
		_cerrar()
		return

	# 1) Colocación y flecha ---------------------------------------------------
	var listo := false
	for i in 240:
		await _frames(1)
		if bool(_obrero.get("_listo")):
			listo = true
			break
	_log("1) obrero listo: %s | posicion %s | visible %s" % [str(listo), str(_obrero.global_position), str(_obrero.visible)])
	_comprobar(listo, "el obrero se colocó en una plaza")
	var plazas := _buscar_todos(_ciudad, "StaticBody3D", "Parque_")
	_log("   plazas en la ciudad: %d %s" % [plazas.size(), str(plazas.map(func(p: Node) -> String: return String(p.name)))])
	_comprobar(_dentro_de_una_plaza(plazas), "el obrero está dentro de una plaza")
	_medir_flecha()

	# 2) Indicador contextual lejos / cerca ------------------------------------
	var aviso := _obrero.get_node_or_null("IndicadorInteraccion") as CanvasLayer
	_log("2) indicador existe: %s | visible con el jugador lejos: %s" % [str(aviso != null), str(aviso != null and aviso.visible)])
	_comprobar(aviso != null, "el indicador existe")
	_comprobar(aviso == null or not aviso.visible, "lejos del NPC el indicador NO se ve")
	var cerca := _punto_cerca(_obrero, 2.0)
	_jugador.global_position = cerca
	await _fisica(4)
	var dist := _jugador.global_position.distance_to(_obrero.global_position)
	var etiqueta := aviso.find_child("Texto", true, false) as Label if aviso != null else null
	_log("   distancia al NPC: %.2f m | indicador visible: %s | texto: \"%s\"" % [
			dist, str(aviso.visible), str(etiqueta.text) if etiqueta != null else "-"])
	_comprobar(dist <= 3.0, "el jugador quedó a menos de 3 m (%.2f)" % dist)
	_comprobar(aviso.visible, "cerca del NPC el indicador SÍ se ve")
	_comprobar(etiqueta != null and etiqueta.text == "E — Hablar con Iván", "el texto del indicador es el pedido")
	await _capturar("01_indicador")

	# 3) Pulsar E: sólo el primer mensaje --------------------------------------
	_log("    antes de pulsar E: distancia %.2f m | indicador %s | diálogo cargado en el NPC %s" % [
			_jugador.global_position.distance_to(_obrero.global_position),
			str(aviso.visible if aviso != null else false), str(_obrero.get("_dialogo") != null)])
	await _pulsar("interactuar")
	var globo := _buscar_globo()
	if globo == null:
		_log("    (el primer E no abrió nada; se reintenta, como haría el jugador)")
		await _pulsar("interactuar")
		globo = _buscar_globo()
		_log("    tras reintentar: globo %s | _globo del NPC %s | diálogo cargado %s | DM %s" % [
				str(globo != null), str(_obrero.get("_globo")),
				str(_obrero.get("_dialogo") != null), str(Engine.has_singleton("DialogueManager"))])
	_log("3) globo abierto: %s | número de globos: %d" % [str(globo != null), _globos().size()])
	_comprobar(globo != null and _globos().size() == 1, "se abrió UN solo globo de diálogo")
	_comprobar(_jugador.get("_dialogo_abierto") == true, "el jugador tiene bloqueados los ataques durante el diálogo")
	_log("   modo de ratón: %d (VISIBLE=%d) | mensaje mostrado: \"%s\"" % [
			Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, _texto(globo)])
	_comprobar(_texto(globo) == MENSAJES[0], "se muestra sólo el MENSAJE 1")
	_comprobar(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "el ratón queda visible para poder pulsar")
	_comprobar(not _boton(globo).visible, "el botón «Entendido» no aparece todavía")
	_medir_panel(globo, "mensaje 1")
	_log("    (texto antes de la captura: %s)" % _texto(globo))
	await _capturar("02_mensaje1")
	_log("    (texto después de la captura: %s)" % _texto(globo))

	# 4) Clic izquierdo: orden exacto de los cuatro mensajes -------------------
	for i in [1, 2, 3]:
		await _clic_panel(globo)
		var t := _texto(globo)
		_log("4) tras clic %d -> \"%s\"" % [i, t])
		_comprobar(t == MENSAJES[i], "el mensaje %d es el esperado (en orden)" % (i + 1))
		if i < 3:
			_comprobar(not _boton(globo).visible, "todavía no hay botón (mensaje %d)" % (i + 1))
		await _frames(1)
	_comprobar(_boton(globo).visible and _boton(globo).text == "Entendido", "el ÚLTIMO mensaje muestra el botón «Entendido»")
	_medir_panel(globo, "último mensaje, el más largo")
	await _capturar("03_mensaje4")

	# 5) El clic en el último mensaje NO cierra --------------------------------
	await _clic_en(_panel_borde(globo))
	_log("5a) clic en el PANEL del último mensaje -> globos: %d | mensaje: \"%s\"" % [_globos().size(), _resumen(globo)])
	_comprobar(_globos().size() == 1, "el clic en el panel del último mensaje NO cierra el diálogo")
	await _clic_en(_texto_centro(globo))
	_log("5b) clic en el TEXTO del último mensaje -> globos: %d | mensaje: \"%s\"" % [_globos().size(), _resumen(globo)])
	_comprobar(_globos().size() == 1, "el clic en el texto del último mensaje NO cierra el diálogo")
	_comprobar(_texto(globo) == MENSAJES[3], "sigue en el último mensaje")

	# 6) Mantener E pulsada no duplica la conversación ------------------------
	Input.action_press("interactuar")
	await _frames(40)
	Input.action_release("interactuar")
	await _frames(2)
	_log("6) con E mantenida 0.7 s -> globos: %d" % _globos().size())
	_comprobar(_globos().size() == 1, "mantener E pulsada no abre una segunda conversación")

	# 7) El clic durante el diálogo NO ataca ----------------------------------
	var estado_antes: Variant = _jugador.get("estado")
	Input.action_press("atacar")
	# Las lecturas van en el MISMO fotograma de la pulsación: `just_pressed` sólo dura uno.
	var justo := Input.is_action_just_pressed("atacar")
	var puede: bool = bool(_jugador.call("_clic_ataca"))
	var ataque_activo: bool = bool(_jugador.get("_ataque_activo"))
	await _frames(2)
	Input.action_release("atacar")
	await _frames(2)
	_log("7) con el diálogo abierto: clic detectado=%s | _clic_ataca()=%s | _ataque_activo=%s" % [
			str(justo), str(puede), str(ataque_activo)])
	_comprobar(justo, "el clic izquierdo se está detectando como «atacar»")
	_comprobar(not puede, "con el diálogo abierto el clic NO puede atacar")
	_comprobar(not ataque_activo, "no arrancó ningún ataque")
	_comprobar(_jugador.get("estado") == estado_antes, "el estado del jugador no cambió")

	# 8) Botón «Entendido»: cierra y devuelve el control ----------------------
	await _clic_boton_rapido(globo)
	var sigue_bloqueado: bool = _jugador.get("_dialogo_abierto") == true
	await _frames(6)
	_log("8) tras pulsar «Entendido»: globos %d | bloqueo inmediato=%s | bloqueo después=%s | ratón %d (CAPTURED=%d)" % [
			_globos().size(), str(sigue_bloqueado), str(_jugador.get("_dialogo_abierto")),
			Input.mouse_mode, Input.MOUSE_MODE_CAPTURED])
	_comprobar(_globos().size() == 0, "pulsar «Entendido» cierra la conversación")
	_comprobar(sigue_bloqueado, "el clic del botón sigue bloqueado en su propio fotograma (no ataca)")
	_comprobar(_jugador.get("_dialogo_abierto") == false, "el jugador recupera el control de los ataques")
	_comprobar(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "el ratón vuelve a su modo anterior")
	_comprobar(_obrero.get("_globo") == null, "el NPC queda libre para otra conversación")
	if aviso != null:
		_comprobar(aviso.visible, "al cerrar, el indicador vuelve a verse (sigue cerca)")

	# 9) Se puede repetir: vuelve a empezar por el mensaje 1 ------------------
	await _pulsar("interactuar")
	var g2 := _buscar_globo()
	_log("9) segunda conversación: %s | mensaje: \"%s\"" % [str(g2 != null), _texto(g2)])
	_comprobar(g2 != null and _texto(g2) == MENSAJES[0], "la conversación se repite desde el MENSAJE 1")
	_comprobar(_globos().size() == 1, "no se duplica el diálogo al repetir")

	# 10) Alejarse durante el diálogo no lo cierra ---------------------------
	_jugador.global_position = _obrero.global_position + Vector3(25.0, 0.0, 0.0)
	await _fisica(6)
	_log("10) jugador a %.1f m mientras habla -> globos %d | mensaje: \"%s\" | indicador %s" % [
			_jugador.global_position.distance_to(_obrero.global_position), _globos().size(),
			_resumen(g2), str(aviso.visible)])
	_comprobar(_globos().size() == 1, "alejarse NO cierra la conversación")
	_comprobar(not aviso.visible, "lejos, el indicador desaparece")
	# Y estando lejos se puede seguir avanzando hasta el final y cerrar con el botón.
	for i in [1, 2, 3]:
		await _clic_panel(g2)
		_comprobar(_texto(g2) == MENSAJES[i], "lejos, el clic sigue avanzando al mensaje %d" % (i + 1))
	_comprobar(_boton(g2).visible, "lejos, el último mensaje también muestra el botón")
	await _clic_boton(g2)
	await _frames(8)
	_comprobar(_globos().size() == 0, "la conversación se cierra con el botón aunque esté lejos")

	# 11) Regeneración de la ciudad ------------------------------------------
	_log("11) regenerando la ciudad…")
	_ciudad.call("generar_ciudad")
	for i in 300:
		await _frames(1)
		if _buscar_todos(_ciudad, "StaticBody3D", "Parque_").size() > 0:
			break
	# El obrero revisa cada 0.5 s si su plaza sigue existiendo: se le da ese margen.
	await _frames(90)
	var plazas2 := _buscar_todos(_ciudad, "StaticBody3D", "Parque_")
	_log("   obrero en %s | plazas nuevas: %d | dentro de una plaza: %s" % [
			str(_obrero.global_position), plazas2.size(), str(_dentro_de_una_plaza(plazas2))])
	_comprobar(_obrero.visible and _dentro_de_una_plaza(plazas2), "tras regenerar, Iván vuelve a una plaza")
	_jugador.global_position = _punto_cerca(_obrero, 1.8)
	await _fisica(6)
	await _frames(3)
	_comprobar(aviso.visible, "tras regenerar, el indicador sigue apareciendo cerca")
	await _pulsar("interactuar")
	var g3 := _buscar_globo()
	_log("   tras regenerar, diálogo: %s | mensaje: \"%s\"" % [str(g3 != null), _texto(g3)])
	_comprobar(g3 != null and _texto(g3) == MENSAJES[0], "tras regenerar, la conversación funciona y empieza por el mensaje 1")
	await _capturar("04_tras_regenerar")
	# El botón sólo existe en el último mensaje: se avanza primero hasta él.
	for i in [1, 2, 3]:
		await _clic_panel(g3)
	await _clic_boton(g3)
	await _frames(8)

	# 12) Sin ataques al cerrar y estado final ------------------------------
	Input.action_press("atacar")
	# Mismo fotograma: `just_pressed` sólo dura uno.
	var puede_fuera: bool = bool(_jugador.call("_clic_ataca"))
	var justo_fuera := Input.is_action_just_pressed("atacar")
	await _frames(2)
	Input.action_release("atacar")
	await _frames(2)
	_log("12) fuera del diálogo: clic detectado=%s | _clic_ataca() = %s" % [str(justo_fuera), str(puede_fuera)])
	_comprobar(puede_fuera, "fuera del diálogo el clic vuelve a servir para atacar")
	_comprobar(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "el ratón sigue capturado al final")
	await _capturas_de_lejos()
	_cerrar()


## Capturas con cámara propia para juzgar el tamaño real de la flecha de cerca y de
## lejos, midiendo además cuántos píxeles ocupa en pantalla a cada distancia.
func _capturas_de_lejos() -> void:
	_log("13) capturas con cámara propia (tamaño real y visibilidad por distancia)")
	await _capturar_flecha(4.0, 1.8, "05_flecha_cerca")
	await _capturar_flecha(30.0, 6.0, "06_flecha_30m")
	await _capturar_flecha(100.0, 55.0, "07_flecha_100m")


func _capturar_flecha(dist: float, alto: float, nombre: String) -> void:
	var punta := _obrero.get_node("IndicadorAmarillo/Flecha/Punta") as MeshInstance3D
	var vastago := _obrero.get_node("IndicadorAmarillo/Flecha/Vastago") as MeshInstance3D
	var ap := (punta.global_transform * punta.mesh.get_aabb()) as AABB
	var av := (vastago.global_transform * vastago.mesh.get_aabb()) as AABB
	var cam := Camera3D.new()
	cam.top_level = true
	add_child(cam)
	var dir := Vector3(1.0, 0.0, 1.0).normalized()
	cam.global_position = _obrero.global_position + dir * dist + Vector3.UP * alto
	cam.look_at(_obrero.global_position + Vector3.UP * 3.0, Vector3.UP)
	cam.current = true
	await _frames(4)
	var abajo := cam.unproject_position(Vector3(ap.get_center().x, ap.position.y, ap.get_center().z))
	var arriba := cam.unproject_position(Vector3(av.get_center().x, av.end.y, av.get_center().z))
	var px := arriba.distance_to(abajo)
	var lienzo := get_viewport().get_visible_rect().size
	var factor := float(DisplayServer.window_get_size().y) / lienzo.y
	var medio := (abajo + arriba) * 0.5
	var dentro := medio.x >= 0.0 and medio.y >= 0.0 and medio.x <= lienzo.x and medio.y <= lienzo.y
	var visible := not cam.is_position_behind(av.get_center())
	_log("    a %.0f m (%.0f m de altitud): la flecha ocupa %.0f px de alto en el lienzo = %.0f px en una ventana de 1920x1080 | en encuadre: %s | delante: %s" % [
			dist, alto, px, px * factor, str(dentro), str(visible)])
	await _capturar(nombre)
	cam.queue_free()
	if _camara_jugador != null and is_instance_valid(_camara_jugador):
		_camara_jugador.current = true
	await _frames(2)


# ------------------------------------------------------------------ mediciones

func _medir_flecha() -> void:
	var flecha := _obrero.get_node_or_null("IndicadorAmarillo/Flecha") as Node3D
	var punta := _obrero.get_node_or_null("IndicadorAmarillo/Flecha/Punta") as MeshInstance3D
	var vastago := _obrero.get_node_or_null("IndicadorAmarillo/Flecha/Vastago") as MeshInstance3D
	if flecha == null or punta == null or vastago == null:
		_comprobar(false, "la flecha existe")
		return
	var ap := (punta.global_transform * punta.mesh.get_aabb()) as AABB
	var av := (vastago.global_transform * vastago.mesh.get_aabb()) as AABB
	var cajas := _caja_del_modelo()
	var mp := punta.mesh as CylinderMesh
	var mv := vastago.mesh as CylinderMesh
	_log("    diseño de las MALLAS: punta r %.3f alto %.3f | vástago r %.3f alto %.3f | escala del nodo Flecha %s" % [
			mp.top_radius, mp.height, mv.top_radius, mv.height, str(flecha.scale)])
	_log("    flecha: punta ancho %.3f alto %.3f (y %.3f..%.3f) | vastago ancho %.3f alto %.3f (y %.3f..%.3f)" % [
			ap.size.x, ap.size.y, ap.position.y, ap.position.y + ap.size.y,
			av.size.x, av.size.y, av.position.y, av.position.y + av.size.y])
	var alto := av.end.y - ap.position.y
	var ancho := maxf(ap.size.x, av.size.x)
	_log("    TOTAL: alto %.3f m | ancho %.3f m | respecto de la flecha anterior (0.972 x 0.542): alto x%.2f ancho x%.2f" % [
			alto, ancho, alto / 0.972, ancho / 0.542])
	_log("    modelo (cajas de su malla): y %.3f..%.3f | alto %.3f" % [cajas.position.y, cajas.end.y, cajas.size.y])
	var hueco := ap.position.y - cajas.end.y
	var cf := Vector2(ap.get_center().x, ap.get_center().z)
	var cm := Vector2(cajas.get_center().x, cajas.get_center().z)
	var desvio := cf.distance_to(cm)
	_log("    hueco punta -> coronilla: %.3f m | centrado: desvío %.3f m (flecha %s vs modelo %s)" % [
			hueco, desvio, str(cf), str(cm)])
	_log("    visibilidad: visible %s | en árbol %s | layers %d | rango %.1f..%.1f | cámara del jugador far %.0f" % [
			str(punta.visible), str(punta.is_visible_in_tree()), punta.layers,
			punta.visibility_range_begin, punta.visibility_range_end,
			_camara_jugador.far if _camara_jugador != null else -1.0])
	_comprobar(alto / 0.972 > 3.5, "la flecha es ~4x más alta que la anterior (x%.2f)" % (alto / 0.972))
	_comprobar(ancho / 0.542 > 2.6, "la flecha es ~3x más ancha que la anterior (x%.2f)" % (ancho / 0.542))
	_comprobar(absf(alto / ancho - 3.0) < 1.2, "proporción de flecha alargada (alto/ancho = %.2f)" % (alto / ancho))
	_comprobar(hueco > 0.05, "la flecha no atraviesa la cabeza: hueco de %.3f m" % hueco)
	_comprobar(desvio < 0.25, "la flecha está centrada sobre Iván (desvío %.3f m)" % desvio)
	_comprobar(mp.bottom_radius == 0.0, "la punta sigue apuntando hacia abajo (radio inferior 0)")
	_comprobar(punta.is_visible_in_tree() and punta.visibility_range_end == 0.0, "la flecha no tiene rango de visibilidad que la oculte")


## Mide el panel del diálogo: tamaño real sobre la pantalla, líneas y recorte del texto.
func _medir_panel(globo: Node, etiqueta: String) -> void:
	if globo == null or not is_instance_valid(globo):
		return
	var marco := globo.get_node("Catcher/PanelInferior/Marco") as Control
	var texto := globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Texto") as RichTextLabel
	var vista := get_viewport().get_visible_rect().size
	var r := marco.get_global_rect()
	var pc_ancho := r.size.x / vista.x * 100.0
	var pc_alto := r.size.y / vista.y * 100.0
	var visibles := texto.visible_characters
	var total := texto.get_total_character_count()
	_log("    PANEL (%s): %.0f x %.0f px | %.1f%% del ancho y %.1f%% del alto de la pantalla | ventana %s | lienzo %s" % [
			etiqueta, r.size.x, r.size.y, pc_ancho, pc_alto,
			str(DisplayServer.window_get_size()), str(vista)])
	_log("    texto: %d línea(s) | alto de contenido %.0f px | alto del nodo %.0f px | caracteres %d de %d" % [
			texto.get_line_count(), texto.get_content_height(), texto.size.y, visibles, total])
	_comprobar(pc_ancho <= 45.0, "el panel ocupa como máximo el 45%% del ancho (%.1f%%)" % pc_ancho)
	_comprobar(pc_alto <= 30.0, "el panel es bajo (%.1f%% del alto)" % pc_alto)
	_comprobar(visibles < 0 or visibles >= total, "el mensaje se muestra entero (sin recorte)")
	_comprobar(texto.get_content_height() <= texto.size.y + 1.0, "el texto cabe en su caja (sin desbordar)")

func _caja_del_modelo() -> AABB:
	var modelo := _obrero.find_child("Model", true, false)
	var caja := AABB()
	var primera := true
	if modelo == null:
		return caja
	for n in modelo.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		var c := (m.global_transform * m.mesh.get_aabb()) as AABB
		if primera:
			caja = c
			primera = false
		else:
			caja = caja.merge(c)
	return caja


# ------------------------------------------------------------------ localización

func _localizar() -> void:
	_juego = get_node_or_null("Juego")
	if _juego == null:
		return
	_ciudad = _buscar_por_script(_juego, GUION_CIUDAD)
	_obrero = _buscar_por_script(_juego, GUION_OBRERO) as Node3D
	_jugador = get_tree().get_first_node_in_group("player") as Node3D
	_camara_jugador = get_viewport().get_camera_3d()
	_log("localizado: juego %s | ciudad %s | obrero %s | jugador %s" % [
			str(_juego != null), str(_ciudad != null), str(_obrero != null), str(_jugador != null)])

func _buscar_por_script(raiz: Node, ruta: String) -> Node:
	if raiz == null:
		return null
	var s: Script = raiz.get_script() as Script
	if s != null and s.resource_path == ruta:
		return raiz
	for h in raiz.get_children():
		var r := _buscar_por_script(h, ruta)
		if r != null:
			return r
	return null

func _buscar_todos(raiz: Node, tipo: String, prefijo: String) -> Array:
	var salida: Array = []
	if raiz == null:
		return salida
	for n in raiz.find_children(prefijo + "*", tipo, true, false):
		salida.append(n)
	return salida

func _dentro_de_una_plaza(plazas: Array) -> bool:
	for p in plazas:
		var n := p as Node3D
		var d := n.global_position - _obrero.global_position
		if absf(d.x) <= 12.0 and absf(d.z) <= 12.0:
			return true
	return false

func _punto_cerca(npc: Node3D, dist: float) -> Vector3:
	# Hacia el cruce de la plaza (la zona que el generador mantiene despejada).
	var plazas := _buscar_todos(_ciudad, "StaticBody3D", "Parque_")
	var centro := npc.global_position + Vector3(1.0, 0.0, 0.0)
	for p in plazas:
		var n := p as Node3D
		if absf(n.global_position.x - npc.global_position.x) <= 12.0 and absf(n.global_position.z - npc.global_position.z) <= 12.0:
			centro = n.global_position
			break
	var dir := centro - npc.global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = Vector3(1, 0, 0)
	return npc.global_position + dir.normalized() * dist


# ------------------------------------------------------------------ globo y UI

func _globos() -> Array:
	var salida: Array = []
	var escena := get_tree().current_scene
	if escena == null:
		return salida
	for n in escena.get_children():
		var s: Script = n.get_script() as Script
		if s != null and s.resource_path == GUION_GLOBO:
			salida.append(n)
	return salida

func _buscar_globo() -> Node:
	var g := _globos()
	return g[0] if g.size() > 0 else null

func _texto(globo: Node) -> String:
	if globo == null or not is_instance_valid(globo):
		return ""
	var l := globo.get_node_or_null("Catcher/PanelInferior/Marco/Margen/Columna/Texto") as RichTextLabel
	return l.text if l != null else ""

func _nombre(globo: Node) -> String:
	if globo == null or not is_instance_valid(globo):
		return ""
	var l := globo.get_node_or_null("Catcher/PanelInferior/Marco/Margen/Columna/Nombre") as RichTextLabel
	return l.text if l != null else ""

func _boton(globo: Node) -> Button:
	if globo == null or not is_instance_valid(globo):
		return Button.new()
	return globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Pie/Entendido") as Button

func _resumen(globo: Node) -> String:
	if globo == null or not is_instance_valid(globo):
		return "(sin globo)"
	return "%s | botón=%s" % [_texto(globo), str(_boton(globo).visible)]

func _panel_centro(globo: Node) -> Vector2:
	var marco := globo.get_node("Catcher/PanelInferior/Marco") as Control
	return marco.get_global_rect().get_center()

## Punto del panel que NO está sobre el texto (esquina superior izquierda, dentro del
## margen del marco): sirve para probar que el panel en sí también avanza.
func _panel_borde(globo: Node) -> Vector2:
	var marco := globo.get_node("Catcher/PanelInferior/Marco") as Control
	return marco.get_global_rect().position + Vector2(14, 14)

func _texto_centro(globo: Node) -> Vector2:
	var l := globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Texto") as Control
	return l.get_global_rect().get_center()

func _clic_panel(globo: Node) -> void:
	await _clic_en(_panel_centro(globo))

func _clic_boton(globo: Node) -> void:
	var b := _boton(globo)
	if not b.visible:
		_log("    AVISO: el botón «Entendido» no está visible en este mensaje")
	var rect := b.get_global_rect()
	var disparos := [0]
	b.pressed.connect(func() -> void: disparos[0] += 1)
	_log("    botón «%s» rect %s -> clic en %s" % [b.text, str(rect), str(rect.get_center())])
	await _clic_en(rect.get_center())
	_log("    señal `pressed` del botón: %s" % str(disparos[0] > 0))

## Igual que `_clic_boton`, pero vuelve en el mismo fotograma de la suelta: así se puede
## muestrear el bloqueo de ataques inmediatamente después.
func _clic_boton_rapido(globo: Node) -> void:
	var b := _boton(globo)
	var rect := b.get_global_rect()
	var disparos := [0]
	b.pressed.connect(func() -> void: disparos[0] += 1)
	_log("    botón «%s» rect %s -> clic en %s" % [b.text, str(rect), str(rect.get_center())])
	var pr := InputEventMouseButton.new()
	pr.button_index = MOUSE_BUTTON_LEFT
	pr.button_mask = MOUSE_BUTTON_MASK_LEFT
	pr.pressed = true
	pr.position = rect.get_center()
	pr.global_position = rect.get_center()
	get_viewport().push_input(pr, true)
	await _frames(2)
	var su := InputEventMouseButton.new()
	su.button_index = MOUSE_BUTTON_LEFT
	su.button_mask = 0
	su.pressed = false
	su.position = rect.get_center()
	su.global_position = rect.get_center()
	get_viewport().push_input(su, true)
	_log("    señal `pressed` del botón: %s" % str(disparos[0] > 0))

## Clic izquierdo REAL: se inyecta en coordenadas LOCALES del viewport (las mismas que
## devuelve `get_global_rect()`), que es como llega un clic de verdad a la interfaz. El
## estado de la acción "atacar" se marca aparte con `Input.action_press` (un clic real
## hace las dos cosas).
func _clic_en(pos: Vector2) -> void:
	for pulsado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pulsado else 0
		ev.pressed = pulsado
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(2)


func _pulsar(accion: String) -> void:
	Input.action_press(accion)
	await _frames(2)
	Input.action_release(accion)
	await _frames(3)


# ------------------------------------------------------------------ utilidades

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _fisica(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := "%s/%s.png" % [RUTA_CAPTURAS, nombre]
	var err := img.save_png(ruta)
	_log("    captura %s -> %s" % [ruta, error_string(err)])

func _comprobar(ok: bool, texto: String) -> void:
	if not ok:
		_fallos.append(texto)
	_log("   %s %s" % ["OK  " if ok else "FALLO", texto])

func _log(texto: String) -> void:
	var t := Time.get_ticks_msec() / 1000.0 - _t0
	var linea := "[%6.2f] %s" % [t, texto]
	print(linea)
	if _archivo != null:
		_archivo.store_line(linea)
		_archivo.flush()

func _cerrar() -> void:
	_log("=== %s ===" % ("TODO OK: %d comprobaciones sin fallos" % 0 if _fallos.is_empty() else "FALLOS: %d -> %s" % [_fallos.size(), str(_fallos)]))
	if _archivo != null:
		_archivo.close()
	get_tree().quit(0 if _fallos.is_empty() else 1)