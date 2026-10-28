class_name MenuOption
extends MarginContainer

## A single, self-contained menu row: its clickable label plus the descriptive
## text shown when this row is the selected one. Everything about a row
## (label, action, description) lives in the scene, so rows can be reordered,
## renamed or retargeted without touching the menu's navigation logic.

## Valores nuevos se añaden SIEMPRE al final para no cambiar el numero de las
## acciones ya existentes (las escenas guardan el valor entero de 'action').
## CONFIG: abre la pantalla de configuracion (menu de pausa y menu principal).
## CATEGORY: seccion de configuracion (abre y cierra su panel de contenido).
## BACK: vuelve del submenu de configuracion a la lista principal.
## CALIDAD: cicla el perfil grafico (BAJA -> MEDIA -> ALTA) usando el sistema
##          AjustesGraficos ya existente; no duplica su logica.
enum Action { CONTINUE, NEW_GAME, QUIT, CONFIG, CATEGORY, BACK, CALIDAD,
		OPTIMIZACION, DIST_CARGA, DIST_PRECARGA, DIAGNOSTICO, AMBIENTE }

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