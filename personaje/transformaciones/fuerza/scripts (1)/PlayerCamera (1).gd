class_name FuerzaCamera
extends Camera3D

## =============================================================================
##  PlayerCamera.gd — Cámara en tercera persona (órbita alrededor del jugador)
## =============================================================================
##  Este script vive en el nodo "Camera3D" dentro de Player.tscn.
##  Es totalmente independiente del script del personaje: puedes cambiar el
##  jugador sin tocar la cámara y viceversa.
##
##  AJUSTES DESDE EL INSPECTOR
##  --------------------------
##  · camera_distance ..... distancia al personaje
##  · camera_height ....... altura del punto al que mira (pecho / cabeza)
##  · mouse_sensitivity ... sensibilidad del ratón
##  · camera_min_pitch .... límite de giro vertical hacia abajo (grados)
##  · camera_max_pitch .... límite de giro vertical hacia arriba (grados)
##  · invert_mouse_y ...... invierte el eje vertical del ratón
##  · capture_mouse ....... captura el ratón al iniciar (Esc lo libera)
##
##  CONTROLES: mueve el ratón para orbitar. Esc libera/captura el cursor.
## =============================================================================

## Se emite cuando se captura o se libera el ratón.
signal mouse_capture_changed(captured: bool)


@export_group("Cámara")
## Distancia de la cámara al personaje (en unidades del mundo).
@export var camera_distance: float = 4.5
## Altura del punto al que mira la cámara, respecto a los pies del personaje.
@export var camera_height: float = 1.5
## Sensibilidad del ratón (radianes girados por cada píxel de movimiento).
@export_range(0.0005, 0.02, 0.0001) var mouse_sensitivity: float = 0.003
## Límite inferior del giro vertical, en grados (la cámara baja y mira hacia arriba).
@export_range(-89.0, 0.0, 0.5) var camera_min_pitch: float = -35.0
## Límite superior del giro vertical, en grados (la cámara sube y mira hacia abajo).
@export_range(0.0, 89.0, 0.5) var camera_max_pitch: float = 70.0
## Invierte el eje vertical del ratón.
@export var invert_mouse_y: bool = false
## Ángulo vertical inicial, en grados (positivo = cámara por encima).
@export_range(-89.0, 89.0, 0.5) var start_pitch: float = 15.0
## Ángulo horizontal inicial, en grados (0 = justo detrás del personaje).
@export var start_yaw: float = 0.0


@export_group("Ratón")
## Captura el ratón al arrancar el juego (recomendado en tercera persona).
@export var capture_mouse: bool = true
## Acción que libera / vuelve a capturar el ratón.
@export var toggle_capture_action: StringName = &"ui_cancel"


@export_group("Sacudida")
## Ritmo al que se apaga la sacudida (veces por segundo: 5 la encoge a la mitad
## en ~0,14 s). Más alto = el temblor desaparece antes.
@export var shake_decay: float = 5.0
## Cuánto ensancha la imagen el golpe de efecto (grados) y a qué ritmo vuelve a
## la normalidad (veces por segundo). Sirve para transmitir impacto o velocidad
## sin mover al personaje.
@export var fov_punch_degrees: float = 6.0
@export var fov_punch_decay: float = 6.0


@export_group("Referencias")
## Nodo que marca el punto al que mira la cámara (hermano de esta cámara).
@export var target_path: NodePath = ^"../CameraTarget"


var _yaw: float = 0.0
var _pitch: float = 0.0
var _player: Node3D
var _target: Node3D
## Desplazamiento vertical temporal del punto de mira (lo usa el jugador
## para bajar la cámara suavemente al agacharse). No se edita a mano.
var _height_offset: float = 0.0
## Sacudida en curso (0 = cámara quieta). No se edita a mano: usa shake().
var _shake: float = 0.0
## Golpe de campo de visión en curso (0 = normal). No se edita a mano.
var _fov_punch: float = 0.0
var _fov_base: float = 70.0
## Si está activo, ESC no libera/captura el ratón. Lo usa el jugador mientras
## apunta con la roca (Q): ahí ESC CANCELA el apuntado y no debe tocar el cursor.
var _capture_toggle_blocked: bool = false


func _ready() -> void:
	# Se apunta a este grupo para que las habilidades (onda expansiva, roca)
	# puedan sacudirla sin que el jugador y la cámara se conozcan entre sí.
	add_to_group("player_camera")
	_player = get_parent_node_3d()
	_target = get_node_or_null(target_path) as Node3D

	_yaw = deg_to_rad(start_yaw)
	_pitch = clampf(
		deg_to_rad(start_pitch),
		deg_to_rad(camera_min_pitch),
		deg_to_rad(camera_max_pitch)
	)

	# CameraTarget sólo es un marcador visual: lo mantenemos a la altura que
	# indica camera_height para que en el editor se vea dónde mira la cámara.
	if _target != null:
		_target.position = Vector3(0.0, camera_height, 0.0)

	if capture_mouse:
		set_mouse_captured(true)

	_fov_base = fov
	_update_camera_transform()


func _process(delta: float) -> void:
	# La sacudida y el golpe de campo de visión se apagan solos.
	# Se apagan de forma EXPONENCIAL, no "x unidades por segundo": así un
	# fotograma lento no se los lleva por delante de un plumazo y duran lo
	# mismo a 30 que a 144 FPS.
	_shake = _apagar(_shake, shake_decay, delta)
	_fov_punch = _apagar(_fov_punch, fov_punch_decay, delta)
	if not is_equal_approx(fov, _fov_base + _fov_punch):
		fov = _fov_base + _fov_punch
	_update_camera_transform()


## Encoge un valor hacia cero a un ritmo proporcional a su tamaño.
## rate es "veces por segundo": 5 encoge a la mitad en ~0,14 s.
func _apagar(valor: float, rate: float, delta: float) -> float:
	var v: float = valor * exp(-maxf(rate, 0.0) * delta)
	return 0.0 if absf(v) < 0.0005 else v


func _unhandled_input(event: InputEvent) -> void:
	# Giro con el ratón (sólo mientras está capturado).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		_yaw = wrapf(_yaw - motion.relative.x * mouse_sensitivity, -PI, PI)

		var pitch_delta: float = motion.relative.y * mouse_sensitivity
		if invert_mouse_y:
			pitch_delta = -pitch_delta
		_pitch = clampf(
			_pitch + pitch_delta,
			deg_to_rad(camera_min_pitch),
			deg_to_rad(camera_max_pitch)
		)
		return

	if event.is_action_pressed(toggle_capture_action):
		if _capture_toggle_blocked:
			return
		set_mouse_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)


# =============================================================================
#  POSICIÓN DE LA CÁMARA
# =============================================================================

func _update_camera_transform() -> void:
	if _player == null:
		return

	# Punto al que mira la cámara: el personaje, a la altura configurada.
	# _height_offset lo mueve el jugador (bajada suave al agacharse).
	var pivot: Vector3 = _player.global_position + Vector3.UP * (camera_height + _height_offset)

	# Posición en órbita: yaw alrededor del personaje + pitch en vertical.
	var offset: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * camera_distance

	global_position = pivot + offset
	look_at(pivot, Vector3.UP)

	# --- Sacudida -------------------------------------------------------------
	# Ruido barato pero continuo: suma de senos desfasados (no da tirones como
	# el azar puro) y en coordenadas locales de la cámara, para que sacuda
	# respecto a lo que se ve.
	if _shake > 0.0005:
		var t: float = Time.get_ticks_msec() * 0.001
		var nx: float = sin(t * 57.1) * 0.6 + sin(t * 123.7) * 0.4
		var ny: float = sin(t * 63.3 + 1.7) * 0.6 + sin(t * 141.1 + 0.3) * 0.4
		var nz: float = sin(t * 71.9 + 3.1) * 0.6 + sin(t * 117.3 + 2.2) * 0.4
		global_position += global_transform.basis * Vector3(nx, ny, 0.0) * _shake * 0.3
		rotate_object_local(Vector3.RIGHT, ny * _shake * 0.05)
		rotate_object_local(Vector3.UP, nx * _shake * 0.05)
		rotate_object_local(Vector3.FORWARD, nz * _shake * 0.03)


# =============================================================================
#  API PÚBLICA
# =============================================================================

## Ángulo horizontal actual de la cámara (radianes).
func get_yaw() -> float:
	return _yaw


## Desplaza verticalmente el punto al que mira la cámara. Lo usa el jugador
## para acompañar la postura agachada (valor negativo = cámara más baja).
func set_height_offset(offset: float) -> void:
	_height_offset = offset
	if _target != null:
		_target.position = Vector3(0.0, camera_height + _height_offset, 0.0)


## Activa o desactiva la captura del ratón.
func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(captured)


## Bloquea (o desbloquea) que ESC libere/capture el ratón. El jugador lo activa
## mientras apunta con la roca: en ese estado ESC cancela el apuntado y el ratón
## debe quedarse capturado para poder seguir moviendo la cámara.
func set_capture_toggle_blocked(blocked: bool) -> void:
	_capture_toggle_blocked = blocked


## Sacude la cámara. Lo usan las habilidades pesadas para transmitir impacto.
## intensity es en unidades del mundo (0.15 = temblor sutil, 0.6 = golpe fuerte);
## se apaga solo a razón de shake_decay unidades por segundo.
## Llamadas repetidas NO se suman: se queda con la sacudida más fuerte.
func shake(intensity: float) -> void:
	_shake = maxf(_shake, maxf(intensity, 0.0))


## Ensancha la imagen de golpe (grados) y la devuelve sola a la normalidad.
## Transmite impacto o velocidad sin mover al personaje.
func punch_fov(amount: float = -1.0) -> void:
	var value: float = fov_punch_degrees if amount < 0.0 else amount
	_fov_punch = maxf(_fov_punch, value)


## ¿Está la cámara temblando de forma que se NOTE ahora mismo?
## (Por debajo de 0.02 unidades el temblor ya es invisible, así que no cuenta.)
func is_shaking() -> bool:
	return _shake > 0.02


## Alterna entre ratón capturado y visible.
func toggle_mouse_capture() -> void:
	set_mouse_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)


## Coloca la cámara detrás del personaje, mirando en la dirección indicada.
func align_behind(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	_yaw = atan2(-direction.x, -direction.z)
