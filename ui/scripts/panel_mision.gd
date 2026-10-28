extends CanvasLayer

## PANEL DE MISIÓN (VISTA). Vive en la esquina SUPERIOR IZQUIERDA, justo DEBAJO del
## minimapa. Sólo PINTA el estado del gestor `Misiones`: no guarda progreso ni decide
## nada, y no toca el resto del HUD.
##
## · Permanece oculto hasta que la misión se activa (al terminar el diálogo).
## · Mientras está activa muestra el título y el contador "N / 20".
## · Al completarse, la segunda línea pasa a "(completado)" en ROJO y el panel sigue
##   visible.
##
## Es una capa de interfaz propia y reutilizable: para otra misión bastaría con
## escuchar el mismo gestor con otro `id`.

const TITULO := "Derrota a los\ncriminales"
const TEXTO_COMPLETADO := "(completado)"
const COLOR_TEXTO := Color(0.95, 0.96, 0.98, 1.0)
const COLOR_COMPLETADO := Color(0.95, 0.24, 0.20, 1.0)

@onready var _raiz: Control = $Raiz
@onready var _titulo: Label = $Raiz/Panel/Fila/Columna/Titulo
@onready var _estado: Label = $Raiz/Panel/Fila/Columna/Estado

func _ready() -> void:
	_titulo.text = TITULO
	Misiones.mision_activada.connect(_al_cambiar)
	Misiones.progreso_cambiado.connect(_al_cambiar_progreso)
	Misiones.mision_completada.connect(_al_cambiar)
	_refrescar()

## Relee el estado del gestor y lo vuelca en la interfaz (fuente única de verdad).
func _refrescar() -> void:
	var id: StringName = Misiones.MISION_PROFUGOS
	var completada: bool = Misiones.esta_completada(id)
	_raiz.visible = Misiones.mision_activa(id) or completada
	var datos: Dictionary = Misiones.progreso_de(id)
	_pintar_estado(int(datos.get("progreso", 0)), int(datos.get("objetivo", 0)), completada)

func _pintar_estado(actual: int, objetivo: int, completada: bool) -> void:
	if completada:
		_estado.text = TEXTO_COMPLETADO
		_estado.add_theme_color_override("font_color", COLOR_COMPLETADO)
	else:
		_estado.text = "%d / %d" % [actual, objetivo]
		_estado.add_theme_color_override("font_color", COLOR_TEXTO)

func _al_cambiar(_id: StringName) -> void:
	_refrescar()

func _al_cambiar_progreso(_id: StringName, _actual: int, _objetivo: int) -> void:
	_refrescar()