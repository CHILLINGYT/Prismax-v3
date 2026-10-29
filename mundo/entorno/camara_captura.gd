class_name CamaraCaptura
extends Camera3D
## =============================================================================
##  CÁMARA AÉREA DE PRESENTACIÓN (capturas del mundo completo)
## =============================================================================
##  Cámara panorámica para fotografiar la isla entera (ciudad, montañas, costa,
##  arena y océano) desde arriba. NO sustituye a la cámara del jugador: cuando
##  está activa sólo ella es la cámara actual del viewport y, al desactivarla,
##  se devuelve el control a la cámara del jugador. Nunca hay dos cámaras
##  activas a la vez.
##
##  Uso:
##    · P .... activa / desactiva la vista aérea.
##  Al activarse aparece un cartel en pantalla que lo indica.
##
##  El encuadre se calcula con las medidas reales del mundo (ver `Relieve`):
##  centro de la isla (-80,-80) y radio de costa ~410 m. La cámara se sitúa alta
##  y hacia el SUR mirando al centro, con lo que quedan en la misma toma la
##  ciudad en primer término, el relieve/montañas al fondo y el mar alrededor.
## =============================================================================

@export_group("Modo captura")
## Tecla que activa/desactiva la vista aérea (física, válida en cualquier distribución).
@export var tecla_alternar: Key = KEY_P
## Tiempo (s) antes de aceptar la tecla: da margen a que Terrain3D, el bosque y
## la ciudad terminen de generarse al arrancar la escena.
@export var retardo_activacion: float = 2.5

@export_group("Encuadre")
## Punto al que mira la cámara: centro de la isla, a media altura del relieve.
@export var objetivo: Vector3 = Vector3(-80.0, 10.0, -80.0)
## Altura (m) de la cámara sobre el objetivo.
@export var altura: float = 900.0
## Desplazamiento (m) de la cámara hacia el sur (+Z): la ciudad queda en primer
## término y las montañas al fondo. Bajarlo acerca al cenital; subirlo aplana más.
@export var distancia_sur: float = 650.0
## Campo de visión (grados) de la vista aérea.
@export var fov_captura: float = 60.0
## Plano lejano (m): debe cubrir el océano que rodea la isla.
@export var plano_lejano: float = 20000.0

var _activa: bool = false
var _listo: bool = false
var _camara_previa: Camera3D
var _capa: CanvasLayer
var _cartel: Label


func _ready() -> void:
	_aplicar_encuadre()
	_crear_cartel()
	# El mundo (Terrain3D, bosque, ciudad) tarda unos segundos en generarse: no
	# se permite encender la vista aérea hasta que haya tenido tiempo de estar listo.
	await get_tree().create_timer(retardo_activacion).timeout
	_listo = true


## Coloca la cámara en el encuadre aéreo según los parámetros exportados y la
## deja DESACTIVADA (`current = false`), para no robar la cámara del jugador.
func _aplicar_encuadre() -> void:
	var pos := objetivo + Vector3(0.0, altura, distancia_sur)
	fov = fov_captura
	near = 1.0
	far = plano_lejano
	look_at_from_position(pos, objetivo, Vector3.UP)
	current = false


## Localiza una cámara del jugador ya presente en el árbol (cualquier Camera3D
## que no sea esta). Se usa como respaldo si no se pudo recordar la anterior.
func _buscar_camara_jugador() -> Camera3D:
	var cams := get_tree().root.find_children("*", "Camera3D", true, false)
	for c: Node in cams:
		if c != self and c is Camera3D:
			return c as Camera3D
	return null


## Cartel fijo que identifica el modo de captura. Se crea por código para no
## guardar nodos temporales en la escena.
func _crear_cartel() -> void:
	_capa = CanvasLayer.new()
	_capa.name = "CartelCamaraAerea"
	add_child(_capa)
	_cartel = Label.new()
	_cartel.text = "CÁMARA AÉREA  ·  P para volver al jugador"
	_cartel.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_cartel.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_cartel.add_theme_constant_override("outline_size", 5)
	_cartel.position = Vector2(18.0, 14.0)
	_cartel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa.add_child(_cartel)
	_capa.visible = false


func _unhandled_input(evento: InputEvent) -> void:
	if not _listo:
		return
	if evento is InputEventKey and (evento as InputEventKey).pressed \
			and not (evento as InputEventKey).echo \
			and (evento as InputEventKey).physical_keycode == tecla_alternar:
		_alternar()
		get_viewport().set_input_as_handled()


## Cambia entre la vista aérea y la cámara del jugador. Al activar se recuerda
## qué cámara estaba en uso (la del jugador) y esta pasa a ser la actual del
## viewport; al desactivar se apaga esta y se devuelve el control exactamente a
## la cámara recordada, de modo que nunca quedan dos cámaras activas a la vez.
func _alternar() -> void:
	_activa = not _activa
	if _activa:
		_camara_previa = get_viewport().get_camera_3d()
		make_current()
	else:
		current = false
		if _camara_previa != null and is_instance_valid(_camara_previa) and _camara_previa != self:
			_camara_previa.make_current()
		else:
			var jugador := _buscar_camara_jugador()
			if jugador != null:
				jugador.make_current()
	if _capa != null:
		_capa.visible = _activa
	print("[CamaraAerea] %s (camara previa: %s)" % [
			("activada" if _activa else "desactivada"),
			(String(_camara_previa.name) if _camara_previa != null else "—")])