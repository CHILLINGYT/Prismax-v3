class_name IntroVideo
extends Control

## Presentación de PRISMAX.
##
## Reproduce el video de presentación a pantalla completa como PRIMER paso del
## arranque del juego y, cuando termina o cuando el jugador lo omite, abre el menú
## principal EXISTENTE (res://ui/scenes/MainMenu.tscn).
##
## Por qué es una escena aparte y no un nodo del menú: así la presentación sólo se
## reproduce al INICIAR una sesión. Entrar al mapa, iniciar partida, volver al
## menú, reiniciar una misión o cambiar de transformación van directos al menú o a
## la pantalla de carga, sin pasar por aquí, de modo que la introducción no se
## repite sola.
##
## Una ÚNICA salida (`_salir`) atiende los cuatro caminos posibles —fin del video,
## ESPACIO, ENTER y clic izquierdo— y sólo actúa la primera vez, así que ni varias
## pulsaciones simultáneas ni la señal de fin del video pueden cambiar de escena
## dos veces.

## Menú principal EXISTENTE: destino único de la presentación.
const ESCENA_MENU := "res://ui/scenes/MainMenu.tscn"

## Espera máxima (s) a que el video empiece a reproducirse. Si se agota, se
## registra el error y se continúa al menú: el juego nunca se queda en negro.
const ESPERA_MAXIMA := 6.0

## Velocidad del fundido de entrada (por segundo). Sólo evita el parpadeo de la
## aparición: se retira en ~0,3 s, no es una pantalla negra de espera.
const VELOCIDAD_FUNDIDO := 3.5

@onready var _video: VideoStreamPlayer = $Aspecto/Video
@onready var _velo: ColorRect = $Velo

var _espera: float = 0.0
var _arrancado: bool = false
var _saliendo: bool = false


func _ready() -> void:
	# La presentación manda: árbol reanudado y cursor visible (el jugador puede
	# omitirla con el ratón, así que necesita verlo).
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_velo.color.a = 1.0
	if _video.stream == null:
		_error("el recurso de video no se pudo cargar")
		return
	_video.play()


func _process(delta: float) -> void:
	if _saliendo:
		return
	# Fundido de entrada: el negro se retira en cuanto hay imagen que mostrar.
	if _velo.color.a > 0.0:
		_velo.color.a = maxf(0.0, _velo.color.a - delta * VELOCIDAD_FUNDIDO)
	if _arrancado:
		return
	if _video.is_playing():
		_arrancado = true
		return
	# Red de seguridad: si el video no llega a arrancar, no nos quedamos mirando
	# una pantalla negra para siempre.
	_espera += delta
	if _espera >= ESPERA_MAXIMA:
		_error("el video no llegó a reproducirse")


## Toda la entrada de la presentación. Sólo ESPACIO, ENTER (principal y numérico)
## y el clic IZQUIERDO omiten; cualquier otra tecla o botón se ignora y el video
## sigue reproduciéndose. El evento se consume para que no lo vea nada más.
func _input(evento: InputEvent) -> void:
	if _saliendo or not _es_omision(evento):
		return
	# El evento se marca como consumido ANTES de cambiar de escena: así, aunque el
	# cambio retire este nodo del árbol a mitad del manejador, ya no hay que tocar
	# el viewport después.
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
	_salir()


func _es_omision(evento: InputEvent) -> bool:
	if evento is InputEventMouseButton:
		var clic := evento as InputEventMouseButton
		# Sólo el botón IZQUIERDO: el clic derecho no omite la presentación.
		return clic.pressed and clic.button_index == MOUSE_BUTTON_LEFT
	if evento is InputEventKey:
		var tecla := evento as InputEventKey
		if not tecla.pressed:
			return false
		# Se miran las dos codificaciones porque una misma tecla física puede
		# traer una u otra según el teclado: así ESPACIO y ENTER funcionan siempre.
		return _es_tecla_de_omision(tecla.keycode) \
				or _es_tecla_de_omision(tecla.physical_keycode)
	return false


func _es_tecla_de_omision(codigo: Key) -> bool:
	return codigo == KEY_SPACE or codigo == KEY_ENTER or codigo == KEY_KP_ENTER


func _on_video_finished() -> void:
	_salir()


## ÚNICA salida de la presentación: venga del final del video o de una omisión,
## siempre detiene imagen y audio, suelta el recurso y abre el menú principal. El
## guardado `_saliendo` garantiza que la escena sólo cambie una vez.
func _salir() -> void:
	if _saliendo:
		return
	_saliendo = true
	_detener_video()
	# El cambio se difiere: la salida puede llegar desde _ready (cuando el árbol
	# todavía está añadiendo hijos) y desde la entrada; diferirlo evita tocar la
	# escena a mitad de una operación del árbol.
	get_tree().change_scene_to_file.call_deferred(ESCENA_MENU)


func _detener_video() -> void:
	if not is_instance_valid(_video):
		return
	# Que el final del video no vuelva a disparar la salida.
	if _video.finished.is_connected(_on_video_finished):
		_video.finished.disconnect(_on_video_finished)
	# stop() corta la imagen Y el audio: no queda sonido sonando por detrás.
	_video.stop()
	# Se suelta el recurso para liberar el descodificador y su pista de audio.
	_video.stream = null


## Error de carga o de reproducción: se registra y se continúa al menú principal.
## Nunca se deja al jugador bloqueado en una pantalla negra y nunca se oculta el
## problema afirmando que la reproducción fue correcta.
func _error(motivo: String) -> void:
	push_error("[intro] No se pudo reproducir la presentación de PRISMAX (%s). Se abre el menú principal." % motivo)
	_salir()
