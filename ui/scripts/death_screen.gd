class_name DeathScreen
extends CanvasLayer

## PANTALLA FINAL DE MUERTE (fade a negro + logo de Prismax + dos botones).
##
## La instancia el controlador del jugador cuando termina la secuencia de muerte
## (`muerte` una vez y `morido` en bucle). Vive en una CanvasLayer por encima de
## todo (layer 128: HUD, menú radial y pausa quedan por debajo), con un ColorRect
## negro a pantalla completa que empieza transparente y sube hasta opaco: la
## transición cubre el mundo, la ciudad y la interfaz, sin pantallas blancas ni
## saltos de escena.
##
## Reutiliza la identidad visual del menú principal tal cual: el logo real
## (`GameLogo.tscn`) y las mismas filas de menú (`menu_option.gd`), con los mismos
## sonidos de interfaz (`SonidoUI`: cursor al pasar por encima, click al activar).
## Los botones llevan al MISMO flujo de partida nueva (pantalla de carga ->
## mundo) y al MISMO menú principal que ya existen: aquí no se duplica nada.
##
## `process_mode` es ALWAYS: la secuencia termina aunque el árbol esté pausado.

const MenuOptionRes := preload("res://ui/scripts/menu_option.gd")

## Escena del mundo que se reinicia con NUEVA PARTIDA (la misma que usan el menú
## principal y el menú de pausa: un único flujo de carga).
const ESCENA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
## Pantalla de carga intermedia: carga y prepara el mundo antes de revelarlo.
const ESCENA_CARGA := "res://ui/scenes/LoadingScreen.tscn"
## Menú principal real del juego.
const ESCENA_MENU := "res://ui/scenes/MainMenu.tscn"

## Duración del fundido a negro y de la aparición del contenido final.
const DURACION_FUNDIDO := 1.6
const DURACION_APARICION := 0.5
## Índices de las dos filas (por posición: la escena las declara en este orden).
const FILA_NUEVA_PARTIDA := 0
const FILA_MENU := 1

@onready var _negro: ColorRect = $Negro
@onready var _centro: CenterContainer = $Centro
@onready var _items: VBoxContainer = %Items
@onready var _indicador: ColorRect = %Indicator

var _selected: int = 0
## La entrada se habilita cuando el contenido final ya está en pantalla: antes no
## se puede activar nada (evita pulsaciones a ciegas durante el fundido).
var _entrada_activa: bool = false
## Evita activar dos veces (una pulsación durante el cambio de escena).
var _accion_en_curso: bool = false
var _move_tween: Tween


func _ready() -> void:
	_negro.modulate.a = 0.0
	_centro.visible = false
	_centro.modulate.a = 0.0
	for i in _items.get_child_count():
		var row := _items.get_child(i) as MenuOptionRes
		if row == null:
			continue
		row.mouse_entered.connect(_on_row_hovered.bind(i))
		row.gui_input.connect(_on_row_gui_input.bind(i))
	_selected = 0
	_refresh(true)


## Arranca la secuencia final: espera [param espera] segundos (el cadáver con
## `morido` en bucle a la vista), funde TODA la pantalla a negro y, cuando el
## negro es opaco, muestra el logo y los dos botones. La llama el controlador al
## pasar al estado MORIDO; se ejecuta una sola vez por muerte.
func iniciar_fundido(espera: float) -> void:
	if _entrada_activa or _accion_en_curso:
		return
	await get_tree().create_timer(maxf(espera, 0.0), true).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_negro, "modulate:a", 1.0, DURACION_FUNDIDO)
	await tween.finished
	if not is_inside_tree():
		return
	# El negro ya es opaco: bloquea el ratón (nada de la escena de detrás puede
	# recibir clics) y aparece el contenido final sobre el fondo negro.
	_negro.mouse_filter = Control.MOUSE_FILTER_STOP
	_centro.visible = true
	var t2 := create_tween()
	t2.tween_property(_centro, "modulate:a", 1.0, DURACION_APARICION)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_entrada_activa = true
	_refresh(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _entrada_activa:
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


func _move(step: int) -> void:
	var count: int = _items.get_child_count()
	if count == 0:
		return
	if count > 1:
		SonidoUI.reproducir_cursor()
	_selected = wrapi(_selected + step, 0, count)
	_refresh(false)


func _refresh(instant: bool) -> void:
	var rows: Array[Node] = _items.get_children()
	if _selected < 0 or _selected >= rows.size():
		return
	for i in rows.size():
		var row := rows[i] as MenuOptionRes
		if row != null:
			row.set_highlight(i == _selected)
	var target := rows[_selected] as Control
	if target != null:
		_slide_indicador(target, instant)


func _slide_indicador(row: Control, instant: bool) -> void:
	var target_y: float = row.position.y
	if instant:
		_indicador.position.y = target_y
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(_indicador, "position:y", target_y, 0.12)


func _activate(index: int) -> void:
	if _accion_en_curso:
		return
	var rows: Array[Node] = _items.get_children()
	if index < 0 or index >= rows.size():
		return
	if rows[index] as MenuOptionRes == null:
		return
	SonidoUI.reproducir_click()
	match index:
		FILA_NUEVA_PARTIDA:
			_nueva_partida.call_deferred()
		FILA_MENU:
			_volver_al_menu.call_deferred()


## NUEVA PARTIDA: el MISMO flujo que el menú principal y el de pausa (pantalla de
## carga -> mundo). Al instanciarse el mundo otra vez, el jugador, su vida, su
## escudo, los enemigos y las misiones arrancan limpios: no se hereda nada del
## estado de muerte (ni la animación ni las señales del jugador anterior).
func _nueva_partida() -> void:
	if _accion_en_curso:
		return
	_accion_en_curso = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	LoadingScreen.destino = ESCENA_MUNDO
	get_tree().change_scene_to_file(ESCENA_CARGA)


## VOLVER AL MENÚ: el menú principal REAL del proyecto, sin duplicarlo.
func _volver_al_menu() -> void:
	if _accion_en_curso:
		return
	_accion_en_curso = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(ESCENA_MENU)


func _on_row_hovered(index: int) -> void:
	if not _entrada_activa or index == _selected:
		return
	# Mismo comportamiento que el menú: un único sonido de navegación al entrar en
	# OTRA opción (no se repite mientras el ratón sigue encima).
	SonidoUI.reproducir_cursor()
	_selected = index
	_refresh(false)


func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if not _entrada_activa:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if index != _selected:
			_selected = index
			_refresh(false)
		_activate(index)