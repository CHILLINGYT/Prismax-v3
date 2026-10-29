class_name SonidoUIService
extends Node

## Sonidos de INTERFAZ del juego (autoload, nombre global `SonidoUI`).
##
## Único punto de reproducción de los tres sonidos de menú. Los menús NO crean
## reproductores propios: solo piden `SonidoUI.reproducir_*()` y este nodo se
## encarga de todo (un único AudioStreamPlayer central, sin duplicar nada).
##
## Archivos (WAV reales del proyecto, no se generan ni descargan):
##   · click   -> confirmar una opción / clic en una opción interactiva.
##   · cursor  -> cambiar de una opción a otra (ratón, teclado o mando).
##   · siyno   -> cambiar el valor de un selector con flechas (SÍ/NO, gráficos...).
##
## NO se usa en las barras deslizantes (volumen, sensibilidad, distancia): esos
## controles siguen en silencio.
##
## El reproductor es PROCESS_MODE_ALWAYS: los sonidos suenan también con el árbol
## pausado (el menú de pausa se abre con get_tree().paused = true).

const RUTA_CLICK := "res://audio/UI/click.wav"
const RUTA_CURSOR := "res://audio/UI/cursor.wav"
const RUTA_SIYNO := "res://audio/UI/siyno.wav"

var _click: AudioStream
var _cursor: AudioStream
var _siyno: AudioStream
var _reproductor: AudioStreamPlayer

func _ready() -> void:
	_click = _cargar(RUTA_CLICK)
	_cursor = _cargar(RUTA_CURSOR)
	_siyno = _cargar(RUTA_SIYNO)
	_reproductor = AudioStreamPlayer.new()
	_reproductor.name = "ReproductorUI"
	# Los sonidos de interfaz son EFECTOS: van al bus "Efectos", de modo que el
	# control "VOLUMEN DE EFECTOS" los regula junto al resto de efectos, y el
	# "VOLUMEN GENERAL" (bus Master) los afecta a todos. Una sola cadena de control
	# centralizada: no se multiplica el volumen a mano en cada sonido.
	_reproductor.bus = &"Efectos"
	# Suena aunque el árbol esté pausado (menú de pausa durante la partida).
	_reproductor.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_reproductor)

## Carga un WAV de interfaz. Si el recurso no existiera, se devuelve null y el
## sonido simplemente no suena: nunca se inventa un sonido sustituto.
func _cargar(ruta: String) -> AudioStream:
	if not ResourceLoader.exists(ruta):
		push_warning("[SonidoUI] No se encontró el sonido de interfaz: %s" % ruta)
		return null
	var recurso := load(ruta)
	return recurso as AudioStream

func reproducir_click() -> void:
	_reproducir(_click)

func reproducir_cursor() -> void:
	_reproducir(_cursor)

func reproducir_siyno() -> void:
	_reproducir(_siyno)

func _reproducir(stream: AudioStream) -> void:
	if stream == null or _reproductor == null:
		return
	_reproductor.stream = stream
	_reproductor.play()