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

## Velocidad de la transicion visual (abrir/cerrar). No es una animacion
## exagerada: solo un fundido breve del panel y del desenfoque.
const VELOCIDAD_TRANSICION := 7.0

## Emitida al reanudar, para que el mundo pueda reaccionar si lo necesita.
signal resumed

@onready var _root: Control = $Root
@onready var _blur: ColorRect = $Blur
@onready var _items: VBoxContainer = %Items
@onready var _indicator: ColorRect = %Indicator
@onready var _description: Label = %Description

var _selected: int = 0
var _move_tween: Tween
var _fade_tween: Tween
var _abierto: bool = false
# Progreso de la transicion: 0 = cerrado (sin blur), 1 = abierto.
var _transicion: float = 0.0
# Indice de la opcion destructiva pendiente de confirmacion (-1 = ninguna).
var _pendiente: int = -1

func _ready() -> void:
	visible = false
	_blur.material.set_shader_parameter("cantidad", 0.0)
	_root.modulate.a = 0.0
	for i in _items.get_child_count():
		var row := _items.get_child(i) as MenuOptionRes
		if row == null:
			continue
		row.mouse_entered.connect(_on_row_hovered.bind(i))
		row.gui_input.connect(_on_row_gui_input.bind(i))
	_selected = 0
	_refresh(true)

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
	# ESC: interruptor. "ui_cancel" es la accion por defecto de la tecla ESC.
	if event.is_action_pressed("ui_cancel"):
		if _abierto:
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
	var count: int = _items.get_child_count()
	if count == 0:
		return
	# Cualquier movimiento cancela una confirmacion pendiente.
	_pendiente = -1
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
	var rows: Array[Node] = _items.get_children()
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
				_pedir_confirmacion(index, "NEW GAME: presiona de nuevo para confirmar.")
		MenuOptionRes.Action.QUIT:
			if _pendiente == index:
				get_tree().quit()
			else:
				_pedir_confirmacion(index, "QUIT GAME: presiona de nuevo para confirmar.")

## Marca una accion destructiva como pendiente: el segundo accept la ejecuta.
## Evita perder la partida por una pulsacion accidental.
func _pedir_confirmacion(index: int, texto: String) -> void:
	_pendiente = index
	_description.text = texto

func _nueva_partida() -> void:
	# Se reanuda antes de cambiar de escena para que el mundo nuevo arranque
	# sin quedar pausado. Se restaura la captura del raton como al iniciar.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(ESCENA_MUNDO)

func _on_row_hovered(index: int) -> void:
	if index == _selected:
		return
	_pendiente = -1
	_selected = index
	_refresh(false)

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if index != _selected:
			_pendiente = -1
			_selected = index
			_refresh(false)
		_activate(index)