class_name MenuOption
extends MarginContainer

## A single, self-contained menu row: its clickable label plus the descriptive
## text shown when this row is the selected one. Everything about a row
## (label, action, description) lives in the scene, so rows can be reordered,
## renamed or retargeted without touching the menu's navigation logic.

enum Action { CONTINUE, NEW_GAME, QUIT }

@export var action: Action = Action.CONTINUE
@export_multiline var description: String = ""

const COLOR_SELECTED := Color(0.99, 0.99, 1.0, 1.0)
const COLOR_IDLE := Color(0.80, 0.82, 0.86, 1.0)

@onready var _label: Label = $Label

## Brightens the label when this row is the selected one.
func set_highlight(highlighted: bool) -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color", COLOR_SELECTED if highlighted else COLOR_IDLE)