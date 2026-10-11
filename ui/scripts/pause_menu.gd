class_name PauseMenu
extends CanvasLayer

## Menu de pausa. Reutiliza la identidad visual del menu principal (panel,
## tipografia, indicador de seleccion, descripcion) pero SIN el video de fondo:
## el fondo es el mundo actual, desenfocado por un shader de pantalla.
##
## El nodo vive dentro de la escena del mundo (ziba_prototipo.tscn) y su
## process_mode es ALWAYS, de modo que sigue recibiendo entrada aunque el arbol
## este pausado (get_tree().paused = true).
##
## ESC funciona como interruptor: abre la pausa durante la partida y la cierra
## cuando esta abierta.

const MenuOptionRes := preload("res://ui/scripts/menu_option.gd")

## Escena del mundo que se reinicia con NEW GAME.
const ESCENA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"

## Escena de carga: misma que usa el menu principal, para no duplicar la logica
## de carga del mundo (un unico flujo).
const ESCENA_CARGA := "res://ui/scenes/LoadingScreen.tscn"

## Velocidad de la transicion visual (abrir/cerrar). No es una animacion
## exagerada: solo un fundido breve del panel y del desenfoque.
const VELOCIDAD_TRANSICION := 7.0

## Titulos de las dos paginas del menu: la lista de pausa y la configuracion.
const TITULO_PAUSA := "PAUSA"
const TITULO_CONFIG := "CONFIGURACIÓN"

## Emitida al reanudar, para que el mundo pueda reaccionar si lo necesita.
signal resumed

@onready var _root: Control = $Root
@onready var _blur: ColorRect = $Blur
@onready var _title: Label = %Title
@onready var _items: VBoxContainer = %Items
@onready var _config_items: VBoxContainer = %ConfigItems
@onready var _config_panel: Control = $Root/ConfigPanel
@onready var _config_title: Label = %ConfigTitle
@onready var _indicator: ColorRect = %Indicator
@onready var _description: Label = %Description
# Contenido de la categoria GRÁFICOS (mismo panel derecho, sin duplicarlo).
@onready var _config_content: VBoxContainer = %ConfigContent
@onready var _modo_izq: Button = %ModoIzq
@onready var _modo_der: Button = %ModoDer
@onready var _modo_valor: Label = %ModoValor
@onready var _res_izq: Button = %ResolucionIzq
@onready var _res_der: Button = %ResolucionDer
@onready var _res_valor: Label = %ResolucionValor
@onready var _fps_izq: Button = %FpsIzq
@onready var _fps_der: Button = %FpsDer
@onready var _fps_valor: Label = %FpsValor
@onready var _dist_barra: BarraValor = %DistanciaBarra
@onready var _dist_valor: Label = %DistanciaValor

var _selected: int = 0
var _move_tween: Tween
var _fade_tween: Tween
var _abierto: bool = false
# Pagina activa: false = lista de pausa, true = pantalla de configuracion.
var _en_config: bool = false
# Categoria de configuracion cuyo panel de contenido esta abierto (indice en
# ConfigItems), o -1 si el panel secundario esta oculto.
var _categoria_abierta: int = -1
# Progreso de la transicion: 0 = cerrado (sin blur), 1 = abierto.
var _transicion: float = 0.0
# Indice de la opcion destructiva pendiente de confirmacion (-1 = ninguna).
var _pendiente: int = -1

func _ready() -> void:
	visible = false
	_blur.material.set_shader_parameter("cantidad", 0.0)
	_root.modulate.a = 0.0
	_conectar_lista(_items)
	_conectar_lista(_config_items)
	_conectar_opciones_graficos()
	AjustesGraficos.cambiado.connect(_actualizar_opciones_graficos)
	_en_config = false
	_title.text = TITULO_PAUSA
	_items.visible = true
	_config_items.visible = false
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_selected = 0
	_refresh(true)

## Conecta hovering y clic de cada fila de una lista (lista de pausa o la de
## configuracion). Se les pasa la lista porque ahora hay dos paginas.
func _conectar_lista(lista: VBoxContainer) -> void:
	for i in lista.get_child_count():
		var row := lista.get_child(i) as MenuOptionRes
		if row == null:
			continue
		row.mouse_entered.connect(_on_row_hovered.bind(lista, i))
		row.gui_input.connect(_on_row_gui_input.bind(lista, i))

## Lista de filas de la pagina activa.
func _filas_activas() -> VBoxContainer:
	return _config_items if _en_config else _items

## Anima el desenfoque y el fundido del panel. Corre en process_mode ALWAYS,
## por lo que sigue avanzando con el arbol pausado.
func _process(delta: float) -> void:
	var objetivo := 1.0 if _abierto else 0.0
	if is_equal_approx(_transicion, objetivo):
		return
	_transicion = move_toward(_transicion, objetivo, VELOCIDAD_TRANSICION * delta)
	_blur.material.set_shader_parameter("cantidad", _transicion)
	_root.modulate.a = _transicion
	if _transicion <= 0.0:
		visible = false

func esta_abierto() -> bool:
	return _abierto

func _unhandled_input(event: InputEvent) -> void:
	# ESC: interruptor. En la lista de pausa abre/cierra la pausa; en la pantalla
	# de configuracion vuelve a la lista de pausa (no reanuda la partida).
	if event.is_action_pressed("ui_cancel"):
		if _abierto and _en_config:
			_salir_config()
		elif _abierto:
			cerrar()
		else:
			abrir()
		get_viewport().set_input_as_handled()
		return

	if not _abierto:
		return

	if event.is_action_pressed("menu_up"):
		_move(-1)
	elif event.is_action_pressed("menu_down"):
		_move(1)
	elif event.is_action_pressed("menu_accept"):
		_activate(_selected)
	else:
		return
	get_viewport().set_input_as_handled()

## Abre la pausa: detiene el mundo, muestra el menu y libera el raton.
func abrir() -> void:
	if _abierto:
		return
	_abierto = true
	_pendiente = -1
	visible = true
	# Al abrir la pausa siempre se empieza en la lista de pausa, nunca a medias
	# en la pantalla de configuracion.
	_en_config = false
	_title.text = TITULO_PAUSA
	_items.visible = true
	_config_items.visible = false
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_selected = 0
	_refresh(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

## Cierra la pausa: reanuda el mundo, oculta el menu y recaptura el raton.
func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	_pendiente = -1
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()

func _move(step: int) -> void:
	var count: int = _filas_activas().get_child_count()
	if count == 0:
		return
	# Cualquier movimiento cancela una confirmacion pendiente.
	_pendiente = -1
	_selected = wrapi(_selected + step, 0, count)
	_refresh(false)

func _refresh(instant: bool) -> void:
	var rows: Array[Node] = _filas_activas().get_children()
	if _selected < 0 or _selected >= rows.size():
		return
	for i in rows.size():
		var row := rows[i] as MenuOptionRes
		if row != null:
			row.set_highlight(i == _selected)

	var target := rows[_selected] as Control
	if target != null:
		_slide_indicator(target, instant)

	var current := rows[_selected] as MenuOptionRes
	if current != null:
		# El panel de contenido NO depende del resaltado (hover/seleccion): se
		# abre y cierra al PULSAR una categoria (ver _toggle_categoria). Aqui solo
		# se actualiza la descripcion de la fila.
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
	match row.action:
		MenuOptionRes.Action.CONTINUE:
			cerrar()
		MenuOptionRes.Action.NEW_GAME:
			if _pendiente == index:
				_nueva_partida.call_deferred()
			else:
				_pedir_confirmacion(index, "NUEVA PARTIDA: pulsa de nuevo para confirmar.")
		MenuOptionRes.Action.QUIT:
			if _pendiente == index:
				get_tree().quit()
			else:
				_pedir_confirmacion(index, "SALIR DEL JUEGO: pulsa de nuevo para confirmar.")
		MenuOptionRes.Action.CONFIG:
			_entrar_config()
		MenuOptionRes.Action.BACK:
			_salir_config()
		MenuOptionRes.Action.CATEGORY:
			# Interruptor por activacion: pulsar una categoria abre su panel;
			# volver a pulsarla lo cierra; pulsar otra cambia el titulo.
			_toggle_categoria(index, row)

## Entra en la pantalla de configuracion: misma pausa, misma escena, solo se
## alternan los nodos visibles y el titulo. No reanuda ni reinicia nada.
func _entrar_config() -> void:
	_en_config = true
	_pendiente = -1
	_selected = 0
	_items.visible = false
	_config_items.visible = true
	# El panel de contenido empieza OCULTO: solo aparece al pulsar una categoria.
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_title.text = TITULO_CONFIG
	_refresh(true)

## Vuelve de la configuracion a la lista de pausa. La partida sigue pausada.
func _salir_config() -> void:
	_en_config = false
	_pendiente = -1
	_selected = 0
	_config_items.visible = false
	_items.visible = true
	# Se oculta el panel y se restablece la categoria, para que al volver a
	# entrar en CONFIGURACIÓN el panel no aparezca abierto.
	_config_panel.visible = false
	_config_content.visible = false
	_categoria_abierta = -1
	_title.text = TITULO_PAUSA
	_refresh(true)

## Interruptor del panel de contenido (SIEMPRE el mismo nodo, nunca se duplica):
## - pulsar la categoria ya abierta -> oculta el panel;
## - pulsar otra categoria        -> mantiene el panel y cambia solo el titulo.
func _toggle_categoria(index: int, row: MenuOptionRes) -> void:
	if _categoria_abierta == index:
		_categoria_abierta = -1
		_config_panel.visible = false
		_config_content.visible = false
		return
	_categoria_abierta = index
	_config_title.text = _titulo_categoria(row)
	_config_panel.visible = true
	_actualizar_contenido_categoria()

## Nombre de la categoria para el titulo del panel de contenido. Se toma de la
## propia etiqueta de la fila (p. ej. "> AUDIO" -> "AUDIO"), de modo que el titulo
## del panel y el boton nunca se desincronizan.
func _titulo_categoria(row: MenuOptionRes) -> String:
	var etiqueta := row.get_node_or_null("Label") as Label
	if etiqueta == null:
		return ""
	return etiqueta.text.trim_prefix("> ").strip_edges()

# ---------------------------------------------------------------- GRÁFICOS
## Conecta los controles del panel de GRÁFICOS. Se hace UNA sola vez (en _ready),
## así no hay señales duplicadas. Todos los cambios se aplican/guardan a través
## del singleton AjustesGraficos.
func _conectar_opciones_graficos() -> void:
	_modo_izq.pressed.connect(AjustesGraficos.alternar_pantalla)
	_modo_der.pressed.connect(AjustesGraficos.alternar_pantalla)
	_res_izq.pressed.connect(_on_resolucion_paso.bind(-1))
	_res_der.pressed.connect(_on_resolucion_paso.bind(1))
	_fps_izq.pressed.connect(_on_fps_paso)
	_fps_der.pressed.connect(_on_fps_paso)
	_dist_barra.valor_cambiado.connect(AjustesGraficos.poner_distancia)

func _on_resolucion_paso(paso: int) -> void:
	AjustesGraficos.poner_resolucion(AjustesGraficos.resolucion_idx + paso)

func _on_fps_paso() -> void:
	AjustesGraficos.poner_mostrar_fps(not AjustesGraficos.mostrar_fps)

## Refleja en la interfaz el estado REAL que vive en AjustesGraficos.
func _actualizar_opciones_graficos() -> void:
	_modo_valor.text = "PANTALLA COMPLETA" if AjustesGraficos.pantalla_completa else "VENTANA"
	_res_valor.text = AjustesGraficos.texto_resolucion()
	_fps_valor.text = "SÍ" if AjustesGraficos.mostrar_fps else "NO"
	_dist_barra.poner_valor(AjustesGraficos.distancia)
	_dist_valor.text = str(AjustesGraficos.distancia)

## Muestra el contenido de GRÁFICOS solo cuando ESA categoría está abierta; las
## demás categorías mantienen su área vacía. Siempre es el MISMO nodo.
func _actualizar_contenido_categoria() -> void:
	if _categoria_abierta < 0:
		_config_content.visible = false
		return
	var row := _config_items.get_child(_categoria_abierta) as MenuOptionRes
	var es_graficos := row != null and String(row.name) == "GraficosOption"
	_config_content.visible = es_graficos
	if es_graficos:
		AjustesGraficos.sincronizar_estado_ventana()
		_actualizar_opciones_graficos()

## Marca una accion destructiva como pendiente: el segundo accept la ejecuta.
## Evita perder la partida por una pulsacion accidental.
func _pedir_confirmacion(index: int, texto: String) -> void:
	_pendiente = index
	_description.text = texto

func _nueva_partida() -> void:
	# Se reanuda antes de cambiar de escena para que la carga arranque sin el
	# arbol pausado. La partida nueva pasa por la MISMA pantalla de carga que el
	# menu principal: un unico flujo responsable de cargar el mundo.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	LoadingScreen.destino = ESCENA_MUNDO
	get_tree().change_scene_to_file(ESCENA_CARGA)

func _on_row_hovered(lista: VBoxContainer, index: int) -> void:
	if lista != _filas_activas():
		return
	if index == _selected:
		return
	_pendiente = -1
	_selected = index
	_refresh(false)

func _on_row_gui_input(event: InputEvent, lista: VBoxContainer, index: int) -> void:
	if lista != _filas_activas():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if index != _selected:
			_pendiente = -1
			_selected = index
			_refresh(false)
		_activate(index)