class_name CamaraLibre
extends Camera3D
## =============================================================================
##  CÁMARA LIBRE (vuelo) para recorrer la ciudad generada.
## -----------------------------------------------------------------------------
##  Controles:
##   · Ratón ................... mirar alrededor (al iniciar se captura el ratón)
##   · W / S ................... avanzar / retroceder
##   · A / D ................... desplazarse a izquierda / derecha
##   · E / Q ................... subir / bajar
##   · Shift ................... vuelo rápido
##   · R ....................... volver a la vista inicial
##   · Esc ..................... liberar el ratón (clic para volver a capturarlo)
## =============================================================================

@export_group("Movimiento")
@export var velocidad := 16.0            ## m/s de vuelo normal
@export var factor_rapido := 3.5         ## multiplicador con Shift
@export var suavizado := 10.0            ## 0 = sin inercia
@export_group("Vista")
@export var sensibilidad := 0.0022       ## radianes por píxel de ratón
@export var limite_pitch := 88.0         ## grados máximos de inclinación
@export var capturar_raton := true       ## capturar el ratón al empezar
@export var volver_con_r := true         ## R devuelve a la vista inicial
@export var mostrar_ayuda := true        ## ayuda con los controles al empezar

var _yaw := 0.0
var _pitch := 0.0
var _velocidad_actual := Vector3.ZERO
var _inicial := Transform3D()
var _ayuda: Label = null
var _ayuda_restante := 12.0


func _ready() -> void:
	_inicial = transform
	var giro := rotation
	_yaw = giro.y
	_pitch = giro.x
	if not Engine.is_editor_hint() and capturar_raton:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not Engine.is_editor_hint() and mostrar_ayuda:
		_crear_ayuda()


## Etiqueta con los controles; se desvanece sola a los pocos segundos.
func _crear_ayuda() -> void:
	var capa := CanvasLayer.new()
	capa.name = "AyudaCamara"
	var etiqueta := Label.new()
	etiqueta.text = "Cámara libre:  ratón para mirar  ·  W/A/S/D volar  ·  E/Q subir/bajar  ·  Shift rápido  ·  R reiniciar  ·  Esc soltar ratón"
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	etiqueta.position = Vector2(16.0, 12.0)
	etiqueta.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	etiqueta.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	etiqueta.add_theme_constant_override("outline_size", 4)
	capa.add_child(etiqueta)
	add_child(capa)
	_ayuda = etiqueta


## Tecla pulsada, comprobando tanto el código físico (WASD en cualquier
## distribución) como el lógico.
func _pulsada(tecla: Key) -> bool:
	return Input.is_physical_key_pressed(tecla) or Input.is_key_pressed(tecla)


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var movimiento := (evento as InputEventMouseMotion).relative
		_yaw -= movimiento.x * sensibilidad
		var limite := deg_to_rad(limite_pitch)
		_pitch = clampf(_pitch - movimiento.y * sensibilidad, -limite, limite)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif evento is InputEventMouseButton:
		if (evento as InputEventMouseButton).pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif evento is InputEventKey and (evento as InputEventKey).pressed \
			and not (evento as InputEventKey).echo:
		var tecla := (evento as InputEventKey).physical_keycode
		if tecla == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif tecla == KEY_R and volver_con_r:
			transform = _inicial
			_yaw = _inicial.basis.get_euler().y
			_pitch = _inicial.basis.get_euler().x
			_velocidad_actual = Vector3.ZERO


func _process(delta: float) -> void:
	var direccion := Vector3.ZERO
	if _pulsada(KEY_W):
		direccion.z -= 1.0
	if _pulsada(KEY_S):
		direccion.z += 1.0
	if _pulsada(KEY_D):
		direccion.x += 1.0
	if _pulsada(KEY_A):
		direccion.x -= 1.0
	if _pulsada(KEY_E):
		direccion.y += 1.0
	if _pulsada(KEY_Q):
		direccion.y -= 1.0

	var objetivo := Vector3.ZERO
	if direccion != Vector3.ZERO:
		var horizontal := Vector3(direccion.x, 0.0, direccion.z)
		if horizontal != Vector3.ZERO:
			objetivo += (basis * horizontal).normalized()
		objetivo += Vector3.UP * direccion.y
		if objetivo.length() > 0.0:
			objetivo = objetivo.normalized()
		var rapidez := velocidad * (factor_rapido if _pulsada(KEY_SHIFT) else 1.0)
		objetivo *= rapidez

	# Pequeña inercia para que el vuelo no sea a tirones.
	var mezcla := clampf(suavizado * delta, 0.0, 1.0) if suavizado > 0.0 else 1.0
	_velocidad_actual = _velocidad_actual.lerp(objetivo, mezcla)
	if _velocidad_actual.length() > 0.001:
		global_position += _velocidad_actual * delta

	# La ayuda se apaga sola: primero se desvanece y luego se borra.
	if _ayuda != null:
		_ayuda_restante -= delta
		if _ayuda_restante <= 0.0:
			_ayuda.queue_free()
			_ayuda = null
		elif _ayuda_restante < 1.5:
			_ayuda.modulate.a = clampf(_ayuda_restante / 1.5, 0.0, 1.0)