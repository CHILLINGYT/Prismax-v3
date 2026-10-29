class_name AimReticle
extends CanvasLayer
## =============================================================================
##  RETÍCULA DE APUNTADO (pantalla)
## =============================================================================
##  Dibuja una pequeña mira en el CENTRO de la pantalla mientras el personaje
##  apunta con el balón de agua. No es un nodo 3D: es un Control a pantalla
##  completa que se dibuja a sí mismo, así que no depende de la cámara ni del
##  tamaño de la ventana.
##
##  Estados:
##    * Apagada si el personaje NO está apuntando.
##    * Azul claro mientras apunta sin objetivo.
##    * Naranja (enganchada) cuando la retícula tiene un objetivo seleccionado.
##
##  Se cuelga del jugador como hija (Player/AimReticle) y le pregunta a él el
##  estado, así que no guarda copia de nada: siempre está en sintonía.
## =============================================================================

## Jugador al que sigue. Si se deja vacío se usa el padre.
@export var player_path: NodePath

var _player: Node = null
var _canvas: Control = null


func _ready() -> void:
	layer = 10
	_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_parent()
	_canvas = Control.new()
	_canvas.name = "ReticleCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_reticle)
	add_child(_canvas)
	visible = false


func _process(_delta: float) -> void:
	var targeting := false
	var locked := false
	if _player != null and _player.has_method("is_aiming"):
		# Se enseña desde que la FORMACIÓN ha empezado (fase >= FORM), para que la
		# mira aparezca mientras el balón se forma y no de golpe.
		targeting = _player.call("is_aiming") and int(_player.call("get_aim_phase")) >= 2
		locked = _player.call("get_aim_target") != null
	if targeting != visible:
		visible = targeting
	if targeting:
		_locked_color = locked
		_canvas.queue_redraw()


## Color según haya objetivo o no; se refresca una vez por frame antes de dibujar.
var _locked_color := false


func _draw_reticle() -> void:
	if _canvas == null or _player == null:
		return
	var color := Color(1.0, 0.42, 0.25, 0.95) if _locked_color else Color(0.82, 0.95, 1.0, 0.8)
	var center := _canvas.size * 0.5
	var radius := 11.0
	_canvas.draw_arc(center, radius, 0.0, TAU, 40, color, 2.0, true)
	var gap := radius + 3.0
	var length := 8.0
	_canvas.draw_line(center + Vector2(-gap - length, 0.0), center + Vector2(-gap, 0.0), color, 2.0, true)
	_canvas.draw_line(center + Vector2(gap, 0.0), center + Vector2(gap + length, 0.0), color, 2.0, true)
	_canvas.draw_line(center + Vector2(0.0, -gap - length), center + Vector2(0.0, -gap), color, 2.0, true)
	_canvas.draw_line(center + Vector2(0.0, gap), center + Vector2(0.0, gap + length), color, 2.0, true)
	_canvas.draw_circle(center, 1.8, color)