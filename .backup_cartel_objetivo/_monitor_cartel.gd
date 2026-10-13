extends Node

## MONITOR DE LA PRUEBA DEL CARTEL DE OBJETIVO «habla con el hombre en la plaza».
##
## Cuelga de la raíz del árbol (sobrevive al cambio de escena), espera a que el mundo
## entre por el flujo real de la pantalla de carga y comprueba, con medidas reales y
## capturas: aparición, texto exacto, posición (referencia: arriba al centro), estilo,
## que acercarse o pulsar E fuera de rango NO lo oculta, que la conversación con Iván
## SÍ lo oculta, que cerrar y reabrir el diálogo no lo hace reaparecer y que regenerar
## la ciudad tampoco. Escribe su registro y termina el proceso por sí sola.

const RUTA_LOG := "res://.backup_cartel_objetivo/log_prueba_cartel.txt"
const RUTA_CAPTURAS := "res://.backup_cartel_objetivo/capturas"
const ESCENA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const TEXTO_ESPERADO := "habla con el hombre en la plaza"
const GUION_GLOBO := "res://ui/scripts/dialogue_balloon.gd"
const GUION_OBRERO := "res://NPCs/Scripts/npc_estatico_obrero.gd"
const GUION_CARTEL := "res://ui/scripts/cartel_objetivo.gd"

var _f: FileAccess = null
var _fallos: Array[String] = []
var _t0 := 0.0
var _mundo: Node = null
var _cartel: CanvasLayer = null
var _panel: PanelContainer = null
var _label: Label = null
var _ciudad: Node = null
var _obrero: Node3D = null
var _jugador: Node3D = null
var _visto_en_carga := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(RUTA_CAPTURAS)
	_f = FileAccess.open(RUTA_LOG, FileAccess.WRITE)
	_log("=== PRUEBA DEL CARTEL DE OBJETIVO ===")
	var guardia := Timer.new()
	guardia.wait_time = 200.0
	guardia.one_shot = true
	guardia.timeout.connect(func() -> void:
		_log("!! TIEMPO AGOTADO")
		_cerrar())
	add_child(guardia)
	guardia.start()
	_ejecutar()


func _ejecutar() -> void:
	# --- 0) Entrar al mundo por el flujo real, vigilando que el cartel no se vea antes.
	# El ORDEN importa: primero se mira si el mundo YA es la escena en curso y sólo
	# después la visibilidad, porque el cartel se hace visible justo al entrar al mundo.
	var espera := 0.0
	var fotogramas := 0
	var frame_entrada := -1
	var frame_visible := -1
	while espera < 150.0:
		await _frames(1)
		fotogramas += 1
		var actual := get_tree().current_scene
		var ya_en_mundo: bool = actual != null and actual.scene_file_path == ESCENA_MUNDO
		if ya_en_mundo and frame_entrada < 0:
			frame_entrada = fotogramas
		var c := _buscar_por_script(get_tree().root, GUION_CARTEL)
		var visible_ahora: bool = c != null and (c as CanvasLayer).visible
		if visible_ahora and frame_visible < 0:
			frame_visible = fotogramas
		if visible_ahora and not ya_en_mundo:
			_visto_en_carga += 1
		if ya_en_mundo:
			break
		espera += get_process_delta_time()
	var esc := get_tree().current_scene
	var en_mundo: bool = esc != null and esc.scene_file_path == ESCENA_MUNDO
	_comprobar(en_mundo, "se entró al mundo por el flujo normal (pantalla de carga)")
	_log("  fotograma en que el mundo pasa a ser la escena en curso: %d | primer fotograma con el cartel visible: %d" % [frame_entrada, frame_visible])
	_log("  fotogramas con el cartel visible MIENTRAS el mundo NO era la escena en curso: %d" % _visto_en_carga)
	_comprobar(_visto_en_carga == 0, "el cartel NO se ve durante la pantalla de carga")
	_comprobar(frame_visible < 0 or frame_entrada < 0 or frame_visible >= frame_entrada, "el cartel sólo aparece cuando el mundo ya es la escena en curso (visible en el fotograma %d, entrada en el %d)" % [frame_visible, frame_entrada])
	if not en_mundo:
		_cerrar()
		return
	_mundo = esc
	await _frames(5)

	# --- 1) El cartel existe y aparece al entrar al mundo.
	_cartel = _mundo.get_node_or_null("CartelObjetivo") as CanvasLayer
	_panel = _mundo.get_node_or_null("CartelObjetivo/Margen/Cartel") as PanelContainer
	_label = _mundo.get_node_or_null("CartelObjetivo/Margen/Cartel/Texto") as Label
	_ciudad = _mundo.get_node_or_null("Ciudad")
	_log("--- 1) aparición ---")
	_log("  cartel: %s | panel: %s | texto: %s | capa (layer): %s | visible: %s" % [
			str(_cartel != null), str(_panel != null), str(_label != null),
			str(_cartel.layer) if _cartel != null else "-", str(_cartel.visible) if _cartel != null else "-"])
	_comprobar(_cartel != null and _panel != null and _label != null, "el cartel existe en el mundo")
	_comprobar(_cartel != null and _cartel.visible, "el cartel está VISIBLE al entrar al mundo (sin pulsar nada)")
	_comprobar(_cartel is CanvasLayer and _panel is Control, "el cartel es interfaz 2D (CanvasLayer + Control), no un objeto 3D")
	_comprobar(_cartel != null and _cartel.layer == 70, "el cartel vive en su propia capa de interfaz (layer 70)")

	# --- 2) Texto exacto.
	var t := "" if _label == null else _label.text
	_log("--- 2) texto ---")
	_log("  texto mostrado: \"%s\" (%d caracteres)" % [t, t.length()])
	_comprobar(t == TEXTO_ESPERADO, "el texto es exactamente «%s»" % TEXTO_ESPERADO)

	# --- 3) Posición y tamaño (referencia: arriba al centro).
	var lienzo := get_viewport().get_visible_rect().size
	var ventana := Vector2(DisplayServer.window_get_size())
	var r := Rect2()
	if _panel != null:
		r = _panel.get_global_rect()
	var escala := ventana.x / lienzo.x if lienzo.x > 0.0 else 1.0
	_log("--- 3) posición y tamaño ---")
	_log("  lienzo %s | ventana %s | escala %.2f" % [str(lienzo), str(ventana), escala])
	_log("  rect del cartel: pos %s tam %s" % [str(r.position), str(r.size)])
	_log("  en la ventana real: %.0f x %.0f px | centro x %.0f (mitad %.0f, desvío %.1f) | borde superior a %.0f px (%.1f%% del alto)" % [
			r.size.x * escala, r.size.y * escala, r.get_center().x * escala, lienzo.x * 0.5 * escala,
			absf(r.get_center().x - lienzo.x * 0.5) * escala, r.position.y * escala, r.position.y / lienzo.y * 100.0])
	_log("  tamaño relativo: %.1f%% del ancho y %.1f%% del alto de la pantalla" % [
			r.size.x / lienzo.x * 100.0, r.size.y / lienzo.y * 100.0])
	_comprobar(_panel != null and absf(r.get_center().x - lienzo.x * 0.5) <= 2.0, "el cartel está centrado horizontalmente (desvío %.1f px)" % (absf(r.get_center().x - lienzo.x * 0.5) * escala))
	_comprobar(_panel != null and r.position.y > 0.0 and r.position.y <= lienzo.y * 0.08, "el cartel va pegado al borde superior (%.1f px del lienzo)" % r.position.y)
	_comprobar(_panel != null and r.size.x <= lienzo.x * 0.40 and r.size.y <= lienzo.y * 0.12, "el cartel es compacto (%.1f%% x %.1f%% de la pantalla)" % [r.size.x / lienzo.x * 100.0, r.size.y / lienzo.y * 100.0])
	_comprobar(_panel != null and r.position.x >= 0.0 and r.end.x <= lienzo.x, "el cartel no queda cortado por los lados")
	if _label != null:
		var min_t := _label.get_minimum_size()
		var rt := _label.get_global_rect()
		_log("  texto: mínimo %s | caja %s | líneas %d" % [str(min_t), str(rt.size), _label.get_line_count()])
		_comprobar(min_t.x <= rt.size.x + 0.5 and min_t.y <= rt.size.y + 0.5, "el texto entra entero en su caja (sin recorte)")
		_comprobar(_label.get_line_count() <= 1, "el texto va en una sola línea")

	# --- 4) Estilo.
	_log("--- 4) estilo ---")
	var sb: StyleBoxFlat = null
	if _panel != null:
		sb = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		_log("  fondo: color %s | alfa %.2f" % [str(sb.bg_color), sb.bg_color.a])
		_log("  esquinas redondeadas: %d/%d/%d/%d px" % [sb.corner_radius_top_left, sb.corner_radius_top_right, sb.corner_radius_bottom_right, sb.corner_radius_bottom_left])
		_log("  bordes (decoración): %d/%d/%d/%d px" % [sb.border_width_left, sb.border_width_top, sb.border_width_right, sb.border_width_bottom])
		_log("  márgenes interiores: %s" % str(Vector4(sb.content_margin_left, sb.content_margin_top, sb.content_margin_right, sb.content_margin_bottom)))
	_comprobar(sb != null, "el cartel tiene un StyleBoxFlat propio")
	if sb != null:
		var rojos := sb.corner_radius_top_left > 0 and sb.corner_radius_top_right > 0 and sb.corner_radius_bottom_right > 0 and sb.corner_radius_bottom_left > 0
		_comprobar(rojos, "las CUATRO puntas están redondeadas")
		var c := sb.bg_color
		_comprobar(c.r > 0.04 and c.g > 0.04 and c.b > 0.04, "el fondo NO es negro puro (%.2f, %.2f, %.2f)" % [c.r, c.g, c.b])
		_comprobar(c.r < 0.35 and c.g < 0.35 and c.b < 0.35, "el fondo es oscuro (gris muy oscuro)")
		_comprobar(maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b) < 0.08, "el fondo es gris neutro (sin color dominante)")
		_comprobar(c.a >= 0.6, "el fondo es suficientemente opaco para leer el texto (alfa %.2f)" % c.a)
		_comprobar(sb.border_width_left + sb.border_width_top + sb.border_width_right + sb.border_width_bottom == 0, "sin bordes ni decoraciones añadidas")
	if _label != null:
		var fc := _label.get_theme_color("font_color")
		var fs := _label.get_theme_font_size("font_size")
		_log("  letra: color %s | tamaño %d" % [str(fc), fs])
		_comprobar(fc.r >= 0.9 and fc.g >= 0.9 and fc.b >= 0.9 and fc.a >= 0.9, "las letras son BLANCAS")
		_comprobar(fs >= 16, "el tamaño de letra es legible (%d)" % fs)
		_comprobar(_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "el texto va centrado en el cartel")
	# El cartel no debe tragarse los clics del juego (los clics atacan).
	var filtros_ok := _panel != null and _panel.mouse_filter == Control.MOUSE_FILTER_IGNORE \
			and _label != null and _label.mouse_filter == Control.MOUSE_FILTER_IGNORE
	_comprobar(filtros_ok, "el cartel ignora el ratón (no bloquea clics ni ataques)")

	await _capturar("01_cartel_al_entrar")

	# --- 5) Localizar a Iván y al jugador.
	_obrero = _buscar_por_script(_mundo, GUION_OBRERO) as Node3D
	_jugador = get_tree().get_first_node_in_group("player") as Node3D
	var listo := false
	for i in 900:
		await _frames(1)
		if _obrero != null and bool(_obrero.get("_listo")):
			listo = true
			break
	_log("--- 5) NPC y jugador ---")
	_log("  Iván: %s | colocado: %s | posición %s" % [str(_obrero != null), str(listo), str(_obrero.global_position) if _obrero != null else "-"])
	_log("  jugador: %s | posición %s" % [str(_jugador != null), str(_jugador.global_position) if _jugador != null else "-"])
	_comprobar(listo and _jugador != null, "Iván y el jugador están en el mundo")
	if _obrero == null or _jugador == null:
		_cerrar()
		return

	# --- 6) Acercarse a Iván SIN interactuar no oculta el cartel.
	_jugador.global_position = _punto_cerca(_obrero, 2.0)
	await _fisica(8)
	var d := _jugador.global_position.distance_to(_obrero.global_position)
	_log("--- 6) acercarse sin pulsar E ---")
	_log("  distancia a Iván: %.2f m | cartel visible: %s" % [d, str(_cartel.visible)])
	_comprobar(d <= 3.0, "el jugador quedó dentro del rango (%.2f m)" % d)
	_comprobar(_cartel.visible, "acercarse a Iván (mirándolo) NO oculta el cartel")
	await _capturar("02_cerca_sin_interactuar")

	# --- 7) Pulsar E FUERA del rango válido no lo oculta.
	_jugador.global_position = _obrero.global_position + Vector3(0.0, 0.0, 25.0)
	await _fisica(8)
	var d_lejos := _jugador.global_position.distance_to(_obrero.global_position)
	var globo_lejos := await _pulsar_hasta_globo(3)
	_log("--- 7) pulsar E fuera del rango ---")
	_log("  distancia: %.2f m | globo abierto: %s | cartel visible: %s" % [d_lejos, str(globo_lejos != null), str(_cartel.visible)])
	_comprobar(globo_lejos == null, "pulsar E fuera del rango NO abre la conversación")
	_comprobar(_cartel.visible, "pulsar E fuera del rango NO oculta el cartel")

	# --- 8) Interacción correcta: la conversación empieza y el cartel desaparece.
	_jugador.global_position = _punto_cerca(_obrero, 2.0)
	await _fisica(8)
	var globo := await _pulsar_hasta_globo(6)
	var d_cerca := _jugador.global_position.distance_to(_obrero.global_position)
	_log("--- 8) interacción correcta ---")
	_log("  distancia: %.2f m | globo abierto: %s | cartel visible: %s" % [d_cerca, str(globo != null), str(_cartel.visible)])
	_comprobar(globo != null, "pulsar E dentro del rango abre la conversación con Iván")
	_comprobar(globo == null or _texto(globo) == "Hola, me llamo Iván. Veo que eres nuevo por aquí...", "la conversación empieza por el mensaje 1 de siempre")
	await _frames(3)
	_comprobar(not _cartel.visible, "la conversación empieza y el cartel DESAPARECE")
	await _capturar("03_conversacion_cartel_oculto")

	# --- 9) Cerrar el diálogo: el cartel NO vuelve.
	if globo != null:
		await _avanzar_hasta_el_final(globo)
		await _clic_boton(globo)
		await _frames(10)
	_log("--- 9) tras cerrar el diálogo ---")
	_log("  globos abiertos: %d | cartel visible: %s" % [_globos().size(), str(_cartel.visible)])
	_comprobar(_globos().is_empty(), "el diálogo se cerró")
	_comprobar(not _cartel.visible, "cerrar el diálogo NO hace reaparecer el cartel")

	# --- 10) Volver a hablar con Iván: el cartel sigue oculto.
	var globo2 := await _pulsar_hasta_globo(6)
	_log("--- 10) segunda conversación ---")
	_log("  globo abierto: %s | cartel visible: %s" % [str(globo2 != null), str(_cartel.visible)])
	_comprobar(globo2 != null, "se puede volver a hablar con Iván")
	_comprobar(not _cartel.visible, "volver a hablar con Iván NO hace reaparecer el cartel")
	await _capturar("04_segunda_conversacion")
	if globo2 != null:
		await _avanzar_hasta_el_final(globo2)
		await _clic_boton(globo2)
		await _frames(10)

	# --- 11) Alejarse del NPC: tampoco reaparece.
	_jugador.global_position = _obrero.global_position + Vector3(0.0, 0.0, 30.0)
	await _fisica(10)
	_log("--- 11) alejarse ---")
	_log("  distancia: %.1f m | cartel visible: %s" % [_jugador.global_position.distance_to(_obrero.global_position), str(_cartel.visible)])
	_comprobar(not _cartel.visible, "alejarse del NPC NO hace reaparecer el cartel")

	# --- 12) Regenerar la ciudad: el cartel sigue oculto y es el mismo nodo.
	if _ciudad != null:
		_log("--- 12) regenerar la ciudad ---")
		_ciudad.call("limpiar_ciudad")
		await _frames(3)
		_ciudad.call("generar_ciudad")
		var plazas := 0
		for i in 600:
			await _frames(1)
			plazas = _cuenta_parques(_ciudad)
			if plazas > 0:
				break
		await _frames(30)
		_log("  plazas nuevas: %d | cartel es el mismo nodo: %s | visible: %s" % [
				plazas, str(_cartel == _mundo.get_node_or_null("CartelObjetivo")), str(_cartel.visible)])
		_comprobar(plazas > 0, "la ciudad se regeneró")
		_comprobar(_cartel == _mundo.get_node_or_null("CartelObjetivo"), "tras regenerar, el cartel sigue siendo el nodo de la escena del mundo")
		_comprobar(not _cartel.visible, "tras regenerar la ciudad, el cartel NO reaparece")
		await _capturar("05_tras_regenerar")

	_log("=== RESULTADO: %d fallos ===" % _fallos.size())
	for f in _fallos:
		_log("  FALLO: " + f)
	_log("tiempo total: %.1f s" % (Time.get_ticks_msec() / 1000.0 - _t0))
	_cerrar()


# ------------------------------------------------------------------ ayudantes

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fisica(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _cuenta_parques(raiz: Node) -> int:
	if raiz == null:
		return 0
	return raiz.find_children("Parque_*", "StaticBody3D", true, false).size()


func _buscar_por_script(raiz: Node, ruta: String) -> Node:
	if raiz == null:
		return null
	for h in raiz.get_children():
		var r := _buscar_por_script(h, ruta)
		if r != null:
			return r
	var s: Script = raiz.get_script() as Script
	if s != null and s.resource_path == ruta:
		return raiz
	return null


func _punto_cerca(npc: Node3D, dist: float) -> Vector3:
	var centro := npc.global_position + Vector3(1.0, 0.0, 0.0)
	var plazas := _ciudad.find_children("Parque_*", "StaticBody3D", true, false) if _ciudad != null else []
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


func _globos() -> Array:
	var salida: Array = []
	var esc := get_tree().current_scene
	if esc == null:
		return salida
	for n in esc.get_children():
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


func _boton(globo: Node) -> Button:
	if globo == null or not is_instance_valid(globo):
		return null
	return globo.get_node_or_null("Catcher/PanelInferior/Marco/Margen/Columna/Pie/Entendido") as Button


## Pulsa la tecla E de verdad (acción del proyecto) hasta que se abra una conversación.
func _pulsar_hasta_globo(intentos: int) -> Node:
	for i in intentos:
		Input.action_press("interactuar")
		await _frames(2)
		Input.action_release("interactuar")
		await _fisica(5)
		var g := _buscar_globo()
		if g != null:
			return g
		await _frames(4)
	return null


## Clic real (evento inyectado en el sistema de entrada) en coordenadas del lienzo.
func _clic_en(pos: Vector2) -> void:
	var pr := InputEventMouseButton.new()
	pr.button_index = MOUSE_BUTTON_LEFT
	pr.button_mask = MOUSE_BUTTON_MASK_LEFT
	pr.pressed = true
	pr.position = pos
	get_viewport().push_input(pr, true)
	await _frames(1)
	var so := InputEventMouseButton.new()
	so.button_index = MOUSE_BUTTON_LEFT
	so.pressed = false
	so.position = pos
	get_viewport().push_input(so, true)
	await _frames(2)


## Avanza los 4 mensajes con clics reales (el globo empieza en el mensaje 1).
func _avanzar_hasta_el_final(globo: Node) -> void:
	for i in [1, 2, 3]:
		var antes := _texto(globo)
		if antes.length() > 40:
			antes = antes.substr(0, 40) + "…"
		_log("    avanzar: mensaje actual \"%s\"" % antes)
		await _clic_en(_punto_avance(globo))
	var b := _boton(globo)
	_log("    botón «Entendido» visible en el último mensaje: %s" % str(b != null and b.visible))


func _punto_avance(globo: Node) -> Vector2:
	var catcher := globo.get_node_or_null("Catcher") as Control
	var lienzo := get_viewport().get_visible_rect().size
	if catcher == null:
		return lienzo * 0.5
	var r := catcher.get_global_rect()
	var p := Vector2(r.get_center().x, r.position.y + minf(40.0, r.size.y * 0.2))
	_log("    catcher rect %s -> clic de avance en %s" % [str(r), str(p)])
	return p


func _clic_boton(globo: Node) -> void:
	var b := _boton(globo)
	if b == null:
		_log("    AVISO: no se encontró el botón «Entendido»")
		return
	var rect := b.get_global_rect()
	var disparos := [0]
	b.pressed.connect(func() -> void: disparos[0] += 1)
	_log("    clic en «%s» rect %s -> %s" % [b.text, str(rect), str(rect.get_center())])
	await _clic_en(rect.get_center())
	_log("    señal `pressed` del botón: %s" % str(disparos[0] > 0))


func _capturar(nombre: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ok := img.save_png(RUTA_CAPTURAS + "/" + nombre + ".png") == OK
	_log("  captura %s: %s (%dx%d)" % [nombre, str(ok), img.get_width(), img.get_height()])


func _comprobar(ok: bool, texto: String) -> void:
	if not ok:
		_fallos.append(texto)
	_log("  %s %s" % ["OK  " if ok else "FALLO", texto])


func _log(texto: String) -> void:
	print(texto)
	if _f != null:
		_f.store_line(texto)
		_f.flush()


func _cerrar() -> void:
	_log("=== FIN ===")
	if _f != null:
		_f.close()
	get_tree().quit(0 if _fallos.is_empty() else 1)