class_name MainMenu
extends Control

## Main menu navigation. The visual tree (panel, title, options, logo) lives in
## MainMenu.tscn; this script only handles selection state, input and routing.
## The menu is built from MenuOption rows, so navigation never hard-codes any
## label or ordering.
##
## El menu tiene DOS paginas dentro de la MISMA escena, con el mismo sistema de
## navegacion que el menu de pausa: la lista principal (Items) y la pagina de
## AJUSTES (ConfigItems). Cambiar de pagina solo alterna que lista esta activa y
## el titulo: no recarga la escena, no reinicia nada y no toca ninguna opcion
## existente. La seccion de ajustes (p. ej. GRAFICOS) se muestra en el nodo
## ConfigPanel: se abre y se cierra al pulsar su fila, y siempre es el MISMO nodo
## (nunca se duplica).

const MenuOptionRes := preload("res://ui/scripts/menu_option.gd")

## Scene loaded when the player starts a new game. This is the existing world
## scene; the menu only decides WHEN it loads, never how the world is built.
const ESCENA_MUNDO := "res://mundo/escena/ziba_prototipo.tscn"

## Escena de carga intermedia: carga el mundo en segundo plano, lo instancia y
## genera la ciudad por etapas, y solo entonces lo revela. El menu NO carga el
## mundo directamente, para que exista un unico flujo responsable de iniciarlo.
const ESCENA_CARGA := "res://ui/scenes/LoadingScreen.tscn"

## Titulos de las dos paginas del menu: la lista principal y AJUSTES.
const TITULO_MENU := "MENÚ PRINCIPAL"
const TITULO_AJUSTES := "AJUSTES"

## Emitted when the player chooses to resume an existing save.
signal continue_requested
## Emitted when the player chooses to start a fresh game.
signal new_game_requested

@onready var _title: Label = $MenuPanel/Content/Title
@onready var _items: VBoxContainer = %Items
@onready var _config_items: VBoxContainer = %ConfigItems
@onready var _config_panel: Control = $ConfigPanel
@onready var _config_title: Label = %ConfigTitle
@onready var _config_content: VBoxContainer = %ConfigContent
@onready var _indicator: ColorRect = %Indicator
@onready var _description: Label = %Description
## Lista de filas de la sección GRÁFICOS (hoy la única sección de ajustes). Se
## navega igual que las demás listas: es la lista activa mientras la sección
## está abierta.
@onready var _seccion_graficos: VBoxContainer = %SeccionGraficos

var _selected: int = 0
var _move_tween: Tween
var _fade_tween: Tween
## Pagina activa: false = lista principal, true = pagina de AJUSTES.
var _en_ajustes: bool = false
## Seccion de ajustes cuyo panel de contenido esta abierto (indice dentro de
## ConfigItems), o -1 si el panel secundario esta oculto.
var _categoria_abierta: int = -1

func _ready() -> void:
	_conectar_lista(_items)
	_conectar_lista(_config_items)
	_conectar_lista(_seccion_graficos)
	# El menu siempre arranca en la lista principal, nunca a medias en AJUSTES.
	_en_ajustes = false
	_title.text = TITULO_MENU
	_items.visible = true
	_config_items.visible = false
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_selected = 0
	_refresh(true)

## Conecta hovering y clic de cada fila de una lista (la principal o la de
## AJUSTES). Se le pasa la lista porque ahora hay dos paginas.
func _conectar_lista(lista: VBoxContainer) -> void:
	for i in lista.get_child_count():
		var row := lista.get_child(i) as MenuOptionRes
		if row == null:
			continue
		row.mouse_entered.connect(_on_row_hovered.bind(i, lista))
		row.gui_input.connect(_on_row_gui_input.bind(i, lista))

## Lista de filas de la pagina activa.
func _filas_activas() -> VBoxContainer:
	if not _en_ajustes:
		return _items
	# Con una sección abierta, la lista activa es la de ESA sección (hoy
	# GRÁFICOS, la única): así sus filas se navegan con el teclado y el ratón
	# sin tocar ni duplicar la navegación del menú.
	if _categoria_abierta >= 0:
		return _seccion_graficos
	return _config_items

func _unhandled_input(event: InputEvent) -> void:
	# ESC: en la pagina de AJUSTES vuelve a la lista principal. En la lista
	# principal no hace nada (igual que antes).
	if event.is_action_pressed("ui_cancel"):
		if _en_ajustes:
			_salir_ajustes()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_up"):
		_move(-1)
	elif event.is_action_pressed("menu_down"):
		_move(1)
	elif event.is_action_pressed("menu_accept"):
		_activate(_selected)
	elif event.is_action_pressed("ui_left"):
		_ajustar_valor(-1)
	elif event.is_action_pressed("ui_right"):
		_ajustar_valor(1)
	else:
		return
	get_viewport().set_input_as_handled()

func _move(step: int) -> void:
	# Navega sólo por filas NAVEGABLES (MenuOption visibles): salta las etiquetas
	# de la sección y las filas dependientes ocultas. `_selected` sigue siendo un
	# índice de hijo, así el hover (que usa el índice de hijo) no se desincroniza.
	var idx := _indices_navegables()
	if idx.is_empty():
		return
	if idx.size() > 1:
		SonidoUI.reproducir_cursor()
	var pos := idx.find(_selected)
	if pos < 0:
		pos = 0
	else:
		pos = wrapi(pos + step, 0, idx.size())
	_selected = int(idx[pos])
	_refresh(false)

func _refresh(instant: bool) -> void:
	var rows: Array[Node] = _filas_activas().get_children()
	_actualizar_calidad()
	_actualizar_optimizacion()
	if _selected < 0 or _selected >= rows.size():
		return
	for i in rows.size():
		var row := rows[i] as MenuOptionRes
		if row != null:
			row.set_highlight(i == _selected)

	# El indicador pertenece a la lista principal: cuando la lista activa es la
	# de una sección (otro contenedor, otras coordenadas) se oculta en vez de
	# colocarlo mal.
	var target := rows[_selected] as Control
	if _filas_activas() == _seccion_graficos:
		_indicator.visible = false
	else:
		_indicator.visible = true
		if target != null:
			_slide_indicator(target, instant)

	var current := rows[_selected] as MenuOptionRes
	if current != null:
		_description.text = current.description
		if not instant:
			if _fade_tween != null and _fade_tween.is_valid():
				_fade_tween.kill()
			_description.modulate.a = 0.0
			_fade_tween = create_tween()
			_fade_tween.tween_property(_description, "modulate:a", 1.0, 0.15)

func _slide_indicator(row: Control, instant: bool) -> void:
	var target_y: float = row.position.y
	if instant:
		_indicator.position.y = target_y
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(_indicator, "position:y", target_y, 0.12)

func _activate(index: int) -> void:
	var rows: Array[Node] = _filas_activas().get_children()
	if index < 0 or index >= rows.size():
		return
	var row := rows[index] as MenuOptionRes
	if row == null:
		return
	SonidoUI.reproducir_click()
	match row.action:
		MenuOptionRes.Action.CONTINUE:
			continue_requested.emit()
			# TODO: resume the existing save once the save system exists.
			# No save system yet, so we do NOT invent one and we do NOT load
			# the world here: the entry point stays in the menu until the
			# host game connects this signal to its own load routine.
		MenuOptionRes.Action.NEW_GAME:
			new_game_requested.emit()
			# Start the game through the loading screen: the world scene is
			# loaded and prepared by LoadingScreen, which only reveals it once
			# everything is ready. Deferred so the current input event finishes
			# handling before the menu node is removed from the tree.
			_ir_al_mundo.call_deferred()
		MenuOptionRes.Action.QUIT:
			get_tree().quit()
		MenuOptionRes.Action.CONFIG:
			# AJUSTES: cambia a la pagina de ajustes dentro de esta misma escena.
			_entrar_ajustes()
		MenuOptionRes.Action.BACK:
			# VOLVER: regresa a la lista principal del menu.
			_salir_ajustes()
		MenuOptionRes.Action.CATEGORY:
			# Seccion de ajustes: interruptor por activacion (abre/cierra su
			# panel). Es el mismo comportamiento que en el menu de pausa.
			_toggle_categoria(index, row)
		MenuOptionRes.Action.CALIDAD:
			# CALIDAD GRÁFICA: cicla BAJA -> MEDIA -> ALTA con el sistema
			# AjustesGraficos ya existente (perfiles, aplicación y guardado
			# no se duplican aquí).
			_ciclar_calidad()
			_refresh(true)
		MenuOptionRes.Action.AMBIENTE:
			# MODO DE AMBIENTE: REALISTA <-> PS2, en caliente (AjustesGraficos).
			AjustesGraficos.pasar_modo_ambiente(1)
			_actualizar_calidad()
			_refresh(true)
		MenuOptionRes.Action.OPTIMIZACION:
			# P10-B2: mismo interruptor compartido con el menú de pausa.
			AjustesGraficos.alternar_optimizacion_agresiva()
			_refresh(true)
		MenuOptionRes.Action.DIST_CARGA:
			AjustesGraficos.poner_distancia_carga(AjustesGraficos.distancia_carga + 1)
			_refresh(true)
		MenuOptionRes.Action.DIST_PRECARGA:
			AjustesGraficos.poner_distancia_precarga(AjustesGraficos.distancia_precarga + 1)
			_refresh(true)
		MenuOptionRes.Action.DIAGNOSTICO:
			AjustesGraficos.alternar_diagnostico_stream()
			_refresh(true)

## Starts a new game through the single loading flow: fixes the destination and
## switches to the loading screen, which loads and prepares the world before
## revealing it. Called deferred from _activate so the menu is still in the tree
## while the triggering input event is being handled.
func _ir_al_mundo() -> void:
	LoadingScreen.destino = ESCENA_MUNDO
	get_tree().change_scene_to_file(ESCENA_CARGA)

# ------------------------------------------------------------------- AJUSTES
## Entra en la pagina de AJUSTES: misma escena y mismos nodos, solo se alternan
## los nodos visibles y el titulo. No recarga el menu ni toca la partida.
func _entrar_ajustes() -> void:
	_en_ajustes = true
	_selected = 0
	_items.visible = false
	_config_items.visible = true
	# El panel de contenido empieza OCULTO: solo aparece al pulsar una seccion.
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_title.text = TITULO_AJUSTES
	_refresh(true)

## Vuelve de AJUSTES a la lista principal del menu.
func _salir_ajustes() -> void:
	_en_ajustes = false
	_selected = 0
	_config_items.visible = false
	_items.visible = true
	# Se oculta el panel y se restablece la seccion, para que al volver a entrar
	# en AJUSTES el panel no aparezca abierto.
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_title.text = TITULO_MENU
	_refresh(true)

## Interruptor del panel de seccion (SIEMPRE el mismo nodo, nunca se duplica):
## - pulsar la seccion ya abierta -> oculta el panel;
## - pulsar otra seccion          -> mantiene el panel y cambia solo el titulo.
func _toggle_categoria(index: int, row: MenuOptionRes) -> void:
	if _categoria_abierta == index:
		_categoria_abierta = -1
		_config_panel.visible = false
		_config_content.visible = false
		# La lista activa vuelve a ser la de secciones: se recoloca la
		# selección y el indicador en ella.
		_selected = 0
		_refresh(true)
		return
	_categoria_abierta = index
	_config_title.text = _titulo_categoria(row)
	_config_panel.visible = true
	# Contenido de la seccion abierta. Hoy GRÁFICOS es la unica seccion, asi que
	# su contenido es el unico: cuando se añadan mas secciones, aqui se elegira
	# cual de los nodos de contenido se muestra (igual que en el menu de pausa).
	_config_content.visible = true
	# La lista activa pasa a ser la de la seccion: selección al principio y
	# refresco para que el indicador y la descripción sigan a la nueva lista.
	_selected = _primer_navegable()
	_refresh(true)

## Nombre de la seccion para el titulo del panel. Se toma de la propia etiqueta
## de la fila (p. ej. "> GRÁFICOS" -> "GRÁFICOS"), de modo que el titulo del
## panel y la fila nunca se desincronizan.
func _titulo_categoria(row: MenuOptionRes) -> String:
	var etiqueta := row.get_node_or_null("Label") as Label
	if etiqueta == null:
		return ""
	return etiqueta.text.trim_prefix("> ").strip_edges()

## Cicla el perfil gráfico con el sistema existente y refresca la fila.
func _ciclar_calidad() -> void:
	AjustesGraficos.pasar_calidad(1)
	_actualizar_calidad()


## Refresca la fila de CALIDAD con el perfil activo. El perfil lo posee
## AjustesGraficos: aquí sólo se muestra, para que el menú nunca se
## desincronice de lo que está realmente aplicado.
func _actualizar_calidad() -> void:
	if _seccion_graficos == null:
		return
	var texto: String = AjustesGraficos.texto_calidad()
	for nodo: Node in _seccion_graficos.get_children():
		var fila := nodo as MenuOptionRes
		if fila != null and fila.action == MenuOptionRes.Action.AMBIENTE:
			var et := fila.get_node_or_null("Label") as Label
			if et != null:
				et.text = "MODO DE AMBIENTE: %s" % AjustesGraficos.texto_modo_ambiente()
			fila.description = ("Modo de ambiente: %s. PS2 = estética de PlayStation 2 "
					+ "(baja resolución, color de 16 bits con trama, niebla cercana) y "
					+ "más FPS; REALISTA = el juego como siempre. Se aplica al instante.") \
					% AjustesGraficos.texto_modo_ambiente()
			continue
		if fila == null or fila.action != MenuOptionRes.Action.CALIDAD:
			continue
		var etiqueta := fila.get_node_or_null("Label") as Label
		if etiqueta != null:
			etiqueta.text = "CALIDAD: %s" % texto
		fila.description = ("Calidad gráfica: %s. Actívala para cambiarla "
				+ "(BAJA / MEDIA / ALTA). BAJA usa un cielo estático y recorta "
				+ "sombras, distancia de visión y escala 3D; ALTA es el ajuste "
				+ "original del juego.") % texto


# --------------------------------------------------- P10-B2: opciones de streaming
## Refresca las filas de la sección GRÁFICOS ligadas a AjustesGraficos
## (OPTIMIZACIÓN AGRESIVA + sus controles dependientes). Los valores viven en el
## autoload: aquí sólo se muestran, así que no se duplican ni se desincronizan
## respecto del menú de pausa.
func _actualizar_optimizacion() -> void:
	if _seccion_graficos == null:
		return
	for nodo: Node in _seccion_graficos.get_children():
		var fila := nodo as MenuOptionRes
		if fila == null:
			continue
		match fila.action:
			MenuOptionRes.Action.OPTIMIZACION:
				_poner_texto_fila(fila, "OPTIMIZACIÓN AGRESIVA DEL MUNDO: %s"
						% AjustesGraficos.texto_optimizacion())
			MenuOptionRes.Action.DIST_CARGA:
				_poner_texto_fila(fila, "DISTANCIA DE CARGA: %s"
						% AjustesGraficos.texto_carga())
			MenuOptionRes.Action.DIST_PRECARGA:
				_poner_texto_fila(fila, "DISTANCIA DE PRECARGA: %s"
						% AjustesGraficos.texto_precarga())
			MenuOptionRes.Action.DIAGNOSTICO:
				_poner_texto_fila(fila, "MODO DE DIAGNÓSTICO: %s"
						% AjustesGraficos.texto_diagnostico_stream())
	# Los controles dependientes sólo se ven con la optimización encendida.
	var visibles := AjustesGraficos.optimizacion_agresiva
	for nodo2: Node in _seccion_graficos.get_children():
		var fila2 := nodo2 as MenuOptionRes
		if fila2 == null:
			continue
		if fila2.action in [MenuOptionRes.Action.DIST_CARGA,
				MenuOptionRes.Action.DIST_PRECARGA, MenuOptionRes.Action.DIAGNOSTICO]:
			fila2.visible = visibles
	# No dejar la selección sobre una fila oculta.
	if _filas_activas() == _seccion_graficos and not _indices_navegables().has(_selected):
		_selected = _primer_navegable()

func _poner_texto_fila(fila: MenuOptionRes, texto: String) -> void:
	var etiqueta := fila.get_node_or_null("Label") as Label
	if etiqueta != null:
		etiqueta.text = texto

## Índices (dentro de la lista activa) de las filas navegables: MenuOption
## VISIBLES. Salta las etiquetas de la sección y las filas dependientes ocultas.
func _indices_navegables() -> Array:
	var out: Array = []
	var hijos := _filas_activas().get_children()
	for i in hijos.size():
		var c := hijos[i]
		if c is MenuOptionRes and (c as Control).visible:
			out.append(i)
	return out

func _primer_navegable() -> int:
	var idx := _indices_navegables()
	return int(idx[0]) if not idx.is_empty() else 0

## Ajusta con las flechas el valor de la fila seleccionada (CALIDAD, CARGA,
## PRECARGA). Enter sigue funcionando como "pasar al siguiente valor".
func _ajustar_valor(paso: int) -> void:
	var rows := _filas_activas().get_children()
	if _selected < 0 or _selected >= rows.size():
		return
	var row := rows[_selected] as MenuOptionRes
	if row == null:
		return
	match row.action:
		MenuOptionRes.Action.CALIDAD:
			AjustesGraficos.pasar_calidad(paso)
		MenuOptionRes.Action.AMBIENTE:
			AjustesGraficos.pasar_modo_ambiente(paso)
			_actualizar_calidad()
		MenuOptionRes.Action.DIST_CARGA:
			AjustesGraficos.poner_distancia_carga(AjustesGraficos.distancia_carga + paso)
		MenuOptionRes.Action.DIST_PRECARGA:
			AjustesGraficos.poner_distancia_precarga(AjustesGraficos.distancia_precarga + paso)
		_:
			return
	_refresh(true)


func _on_row_hovered(index: int, lista: VBoxContainer = null) -> void:
	# La lista que no es la activa esta oculta: sus eventos no cuentan.
	var filas: VBoxContainer = _items if lista == null else lista
	if filas != _filas_activas():
		return
	if index == _selected:
		return
	# El cursor entró en OTRA opción: un único sonido de navegación (no se repite
	# mientras el ratón permanece sobre la misma fila).
	SonidoUI.reproducir_cursor()
	_selected = index
	_refresh(false)

func _on_row_gui_input(event: InputEvent, index: int, lista: VBoxContainer = null) -> void:
	var filas: VBoxContainer = _items if lista == null else lista
	if filas != _filas_activas():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if index != _selected:
			_selected = index
			_refresh(false)
		_activate(index)
