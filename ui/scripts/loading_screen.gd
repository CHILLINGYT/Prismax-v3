class_name LoadingScreen
extends Control

## Pantalla de carga reutilizable.
##
## Se usa como escena intermedia. Quien quiere cargar el mundo fija
## `LoadingScreen.destino` y hace change_scene_to_file() a ESTA escena; aquí se
## carga el PackedScene de destino en segundo plano (ResourceLoader threaded), se
## instancia el mundo SIN que genere la ciudad por su cuenta y se genera por
## etapas cediendo el fotograma, de modo que esta pantalla sigue animándose.
## Cuando el mundo está realmente listo se hace un fundido y se revela la partida.
##
## El triángulo sólo refleja progreso REAL: la carga del recurso y las etapas del
## generador (nunca un cronómetro). Mientras no existe una medida fiable se
## mantiene la animación indeterminada (los puntos siguen moviéndose). Las etapas
## del generador son una estimación por trabajo completado, no un porcentaje
## exacto de tiempo.

## Escena de destino por defecto si nadie la fijó (permite probar esta escena sola).
const ESCENA_MUNDO := "res://mundo/escena/ziba_prototipo.tscn"
## A dónde volver si algo falla.
const ESCENA_MENU := "res://ui/scenes/MainMenu.tscn"

## Ruta de la escena a cargar. La fija quien inicia la carga justo antes de
## cambiar a esta escena. Es estática para no depender de autoloads.
static var destino: String = ""

## La pantalla permanece al menos este tiempo (s) para que se aprecie el efecto.
const TIEMPO_MINIMO := 1.8
## Tope de seguridad (s): si el mundo no está listo antes, se muestra un error en
## lugar de dejar una carga eterna.
const TIEMPO_MAXIMO := 120.0

## Reparto del progreso: la carga del recurso ocupa 0..PESO_CARGA y la generación
## de la ciudad, PESO_CARGA..1. Son dos procesos distintos, no una única medida.
const PESO_CARGA := 0.35

# Animación ondulante de los tres puntos.
const AMPLITUD_PUNTO := 4.5     # píxeles de subida
const VELOCIDAD_PUNTO := 3.2    # rad/s
const DESFASE_PUNTO := 0.7      # rad de desfase entre un punto y el siguiente

@onready var _triangulo: ColorRect = $Capa/Centro/Columna/Triangulo
@onready var _centro: CenterContainer = $Capa/Centro
@onready var _palabra: Label = $Capa/Centro/Columna/Texto/Palabra
@onready var _slots: Array[Control] = [
	$Capa/Centro/Columna/Texto/Slot1,
	$Capa/Centro/Columna/Texto/Slot2,
	$Capa/Centro/Columna/Texto/Slot3,
]
@onready var _puntos: Array[Label] = [
	$Capa/Centro/Columna/Texto/Slot1/Punto,
	$Capa/Centro/Columna/Texto/Slot2/Punto,
	$Capa/Centro/Columna/Texto/Slot3/Punto,
]
@onready var _fade: ColorRect = $Capa/Fade
@onready var _error: Label = $Capa/Error

var _progreso: float = 0.0      # valor mostrado (suavizado)
var _objetivo: float = 0.0      # valor de trabajo (real)
var _t: float = 0.0             # tiempo acumulado para la animación
var _t_mostrado: float = -1.0   # instante del primer fotograma visible
var _listo: bool = false        # el mundo terminó de prepararse
var _saliendo: bool = false     # se está haciendo el fundido de salida
var _error_activo: bool = false
var _mundo: Node = null         # escena del mundo ya instanciada

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fade.color = Color(0, 0, 0, 1)   # arranca en negro y aclara al aparecer
	_error.visible = false
	get_viewport().size_changed.connect(_ajustar_tamano)
	_ajustar_tamano()
	if destino == "":
		destino = ESCENA_MUNDO
	_preparar.call_deferred()

## Bloquea el teclado/ratón mientras se carga para que el mundo que se está
## preparando (incluido su menú de pausa) no reaccione antes de tiempo. Si hubo un
## error, acepta Enter/clic para volver al menú.
func _input(event: InputEvent) -> void:
	if _error_activo:
		var acepta: bool = event.is_action_pressed("menu_accept") \
				or (event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
		if acepta:
			_volver_al_menu()
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _t_mostrado < 0.0:
		_t_mostrado = Time.get_ticks_msec() / 1000.0
	_t += delta

	if _saliendo:
		# Fundido de salida a negro y, al terminar, se revela el mundo.
		_fade.color.a = minf(1.0, _fade.color.a + delta / 0.45)
		_animar_puntos()
		if _fade.color.a >= 1.0:
			_finalizar()
		return

	# Fundido de entrada (breve) para que la pantalla no parpadee al aparecer.
	_fade.color.a = maxf(0.0, _fade.color.a - delta / 0.35)

	# Suaviza el progreso mostrado hacia el objetivo real (nada de saltos).
	var k: float = clampf(delta * 6.0, 0.0, 1.0)
	if _error_activo:
		k = 1.0
	_progreso = lerpf(_progreso, _objetivo, k)
	_triangulo.material.set_shader_parameter("progress", _progreso)
	_animar_puntos()

	# Salida: sólo cuando el mundo está listo, el progreso llegó al final y se
	# cumplió el tiempo mínimo en pantalla.
	if _listo and not _saliendo and _progreso >= 0.995:
		if Time.get_ticks_msec() / 1000.0 - _t_mostrado >= TIEMPO_MINIMO:
			_saliendo = true

## Sube y baja cada punto con un desfase, formando una onda continua. La palabra
## permanece inmóvil: sólo se mueve la Y de cada punto.
func _animar_puntos() -> void:
	for i in _puntos.size():
		var fase: float = _t * VELOCIDAD_PUNTO - float(i) * DESFASE_PUNTO
		_puntos[i].position.y = -AMPLITUD_PUNTO * maxf(0.0, sin(fase))

## Ajusta triángulo, tipografía y separación a la resolución actual y desplaza el
## conjunto un poco por encima del centro vertical.
func _ajustar_tamano() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var base: float = clampf(vp.y / 1080.0, 0.55, 2.2)
	var ancho: float = clampf(140.0 * base, 90.0, 320.0)
	var alto: float = roundf(ancho * 0.866)
	_triangulo.custom_minimum_size = Vector2(ancho, alto)
	var fs: int = int(clampf(42.0 * base, 22.0, 96.0))
	_palabra.add_theme_font_size_override("font_size", fs)
	for p: Label in _puntos:
		p.add_theme_font_size_override("font_size", fs)
	for slot: Control in _slots:
		slot.custom_minimum_size = Vector2(roundf(float(fs) * 0.42), float(fs))
	# El shader necesita el tamaño real en píxeles para el borde y el frente.
	var mat := _triangulo.material as ShaderMaterial
	mat.set_shader_parameter("tam", Vector2(maxf(ancho, 1.0), maxf(alto, 1.0)))
	# Composición ligeramente por encima del centro (proporcional a la pantalla).
	var desplaz: float = clampf(vp.y * 0.09, 16.0, 180.0)
	_centro.offset_top = -desplaz
	_centro.offset_bottom = -desplaz

## Carga el recurso de destino y prepara el mundo. Es una corrutina.
func _preparar() -> void:
	# 1) Pedir la carga del recurso en segundo plano.
	var err := ResourceLoader.load_threaded_request(destino, "PackedScene")
	if err != OK:
		_mostrar_error("No se pudo iniciar la carga de\n%s\n(error %d)" % [destino, err])
		return

	# 2) Esperar a que el recurso esté cargado, reflejando el progreso real.
	var prog: Array = []
	while true:
		var estado := ResourceLoader.load_threaded_get_status(destino, prog)
		if estado == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if prog.size() > 0:
				_objetivo = float(prog[0]) * PESO_CARGA
		elif estado == ResourceLoader.THREAD_LOAD_LOADED:
			break
		else:
			_mostrar_error("No se pudo cargar la escena de destino:\n%s" % destino)
			return
		if _agotado():
			_mostrar_error("La carga tardó demasiado tiempo.")
			return
		await get_tree().process_frame
	_objetivo = PESO_CARGA

	var packed := ResourceLoader.load_threaded_get(destino) as PackedScene
	if packed == null:
		_mostrar_error("La escena de destino llegó vacía.")
		return

	# 3) Instanciar el mundo SIN que genere la ciudad (la genera el paso 4).
	_mundo = packed.instantiate()
	if _mundo == null:
		_mostrar_error("No se pudo instanciar la escena de destino.")
		return
	var ciudad := _mundo.get_node_or_null("Ciudad") as GeneradorCiudad3D
	if ciudad != null:
		# La ciudad la genera esta pantalla por etapas: se desactiva la
		# generación automática del _ready para no generarla dos veces.
		ciudad.generar_al_iniciar = false
		if not ciudad.progreso_generacion.is_connected(_on_progreso_generacion):
			ciudad.progreso_generacion.connect(_on_progreso_generacion)
	# Se añade con el árbol en pausa: los _ready se ejecutan, pero el jugador no
	# recibe entradas ni física antes de tiempo. Se reanuda al revelar el mundo.
	get_tree().paused = true
	get_tree().root.add_child(_mundo)
	await get_tree().process_frame

	# 4) Generar la ciudad por etapas (el progreso llega por la señal).
	if ciudad != null:
		var ok: bool = await ciudad.generar_ciudad_por_etapas()
		if not ok:
			_mostrar_error("Falló la generación de la ciudad.")
			return
	_objetivo = 1.0

	# 5) Un par de fotogramas para que el mundo asiente y queda listo.
	await get_tree().process_frame
	await get_tree().process_frame
	_listo = true

## Traduce el progreso del generador (0..1) al tramo PESO_CARGA..1.
func _on_progreso_generacion(valor: float, _etapa: String) -> void:
	_objetivo = PESO_CARGA + (1.0 - PESO_CARGA) * clampf(valor, 0.0, 1.0)

## ¿Se superó el tope de seguridad de tiempo?
func _agotado() -> bool:
	if _t_mostrado < 0.0:
		return false
	return Time.get_ticks_msec() / 1000.0 - _t_mostrado > TIEMPO_MAXIMO

## Revela el mundo ya preparado y retira la pantalla de carga.
func _finalizar() -> void:
	if is_instance_valid(_mundo):
		get_tree().current_scene = _mundo
	get_tree().paused = false
	destino = ""
	queue_free()

## Muestra un error legible y permite volver al menú; nunca deja una carga eterna.
func _mostrar_error(msg: String) -> void:
	if _error_activo:
		return
	_error_activo = true
	_objetivo = _progreso
	get_tree().paused = false
	if is_instance_valid(_mundo) and _mundo.is_inside_tree():
		_mundo.queue_free()
		_mundo = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_error.text = "%s\n\nPulsa ENTER o haz clic para volver al menú." % msg
	_error.visible = true

func _volver_al_menu() -> void:
	get_tree().paused = false
	if is_instance_valid(_mundo) and _mundo.is_inside_tree():
		_mundo.queue_free()
	_mundo = null
	destino = ""
	get_tree().change_scene_to_file(ESCENA_MENU)
