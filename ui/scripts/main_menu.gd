class_name MainMenu
extends Control

## Main menu navigation. The visual tree (panel, title, options, logo) lives in
## MainMenu.tscn; this script only handles selection state, input and routing.
## The menu is built from MenuOption rows, so navigation never hard-codes any
## label or ordering.

const MenuOptionRes := preload("res://ui/scripts/menu_option.gd")

## Scene loaded when the player starts a new game. This is the existing world
## scene; the menu only decides WHEN it loads, never how the world is built.
const ESCENA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"

## Emitted when the player chooses to resume an existing save.
signal continue_requested
## Emitted when the player chooses to start a fresh game.
signal new_game_requested

@onready var _items: VBoxContainer = %Items
@onready var _indicator: ColorRect = %Indicator
@onready var _description: Label = %Description

var _selected: int = 0
var _move_tween: Tween
var _fade_tween: Tween

func _ready() -> void:
	for i in _items.get_child_count():
		var row := _items.get_child(i) as MenuOptionRes
		if row == null:
			continue
		row.mouse_entered.connect(_on_row_hovered.bind(i))
		row.gui_input.connect(_on_row_gui_input.bind(i))
	_selected = 0
	_refresh(true)

func _unhandled_input(event: InputEvent) -> void:
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
			continue_requested.emit()
			# TODO: resume the existing save once the save system exists.
			# No save system yet, so we do NOT invent one and we do NOT load
			# the world here: the entry point stays in the menu until the
			# host game connects this signal to its own load routine.
		MenuOptionRes.Action.NEW_GAME:
			new_game_requested.emit()
			# Start the game: the menu scene ends and the existing world scene
			# is loaded exactly as it was before (same scene, same generation).
			# Deferred so the current input event finishes handling before the
			# menu node is removed from the tree.
			_ir_al_mundo.call_deferred()
		MenuOptionRes.Action.QUIT:
			get_tree().quit()

## Loads the world scene. Called deferred from _activate so the menu is still
## in the tree while the triggering input event is being handled.
func _ir_al_mundo() -> void:
	get_tree().change_scene_to_file(ESCENA_MUNDO)

func _on_row_hovered(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	_refresh(false)

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if index != _selected:
			_selected = index
			_refresh(false)
		_activate(index)
