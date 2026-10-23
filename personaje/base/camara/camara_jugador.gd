class_name CamaraZiba
extends Node3D

# Camara en tercera persona vinculada al jugador.
# - El mouse controla yaw (rotacion Y) y pitch (rotacion X).
# - Durante la carga: zoom progresivo, pitch de dibujo y vibracion ligera.
# - Durante la ejecucion: FOV ampliado + vibracion (efecto cinematografico).
# Nunca se separa del jugador: es un hijo del CharacterBody3D.

@export var sensibilidad: float = 0.0025
# Limite inferior (mirar hacia abajo / camara alta): mantiene la 3a persona.
@export var limite_pitch: float = 1.25
# Limite superior (mirar hacia arriba): evita que la camara entre en el
# personaje / primera persona. Se conserva el control vertical del mouse.
@export var limite_pitch_superior: float = 0.20
@export var largo_base: float = 2.6
@export var fov_base: float = 70.0
@export var pitch_objetivo_inicial: float = -0.25

var permitir_look: bool = true
var objetivo_largo: float = 2.6
var objetivo_fov: float = 70.0
var vibracion: float = 0.0

var _pitch: float = -0.25
var _pitch_obj: float = -0.25
var _brazo: SpringArm3D
var _cam: Camera3D
var _shake: float = 0.0
var _fov_punch: float = 0.0
var _fov_tween: Tween
var _hitstop_timer: float = 0.0
var _slowmo_timer: float = 0.0

func _ready() -> void:
	add_to_group("camera_rig") # Para compatibilidad con FreeFlow
	_brazo = get_node_or_null("Brazo") as SpringArm3D
	_cam = get_node_or_null("Brazo/Camara") as Camera3D
	objetivo_largo = largo_base
	objetivo_fov = fov_base
	_pitch = pitch_objetivo_inicial
	_pitch_obj = pitch_objetivo_inicial
	rotation.x = _pitch
	if _brazo != null:
		_brazo.spring_length = largo_base
		var cuerpo := get_parent()
		if cuerpo is CollisionObject3D:
			_brazo.add_excluded_object((cuerpo as CollisionObject3D).get_rid())
	if _cam != null:
		_cam.fov = fov_base

func _unhandled_input(event: InputEvent) -> void:
	if not permitir_look:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = sensibilidad * AjustesJugabilidad.factor_sensibilidad()
		var signo_y: float = AjustesJugabilidad.signo_eje_vertical()
		rotate_y(-event.relative.x * s)
		_pitch_obj = clampf(_pitch_obj - event.relative.y * s * signo_y, -limite_pitch, limite_pitch_superior)

func definir_pitch(v: float) -> void:
	_pitch_obj = clampf(v, -limite_pitch, limite_pitch_superior)

func _process(delta: float) -> void:
	# Hitstop y slowmo (igual que camera_rig.gd)
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0.0:
			Engine.time_scale = 1.0
		else:
			Engine.time_scale = 0.01
			return
	if _slowmo_timer > 0.0:
		_slowmo_timer -= delta
		if _slowmo_timer <= 0.0:
			Engine.time_scale = 1.0
	
	_pitch = lerpf(_pitch, _pitch_obj, 10.0 * delta)
	rotation.x = _pitch
	if _brazo != null:
		_brazo.spring_length = lerpf(_brazo.spring_length, objetivo_largo, 6.0 * delta)
	if _cam != null:
		var target_fov := objetivo_fov + _fov_punch
		_cam.fov = lerpf(_cam.fov, target_fov, 5.0 * delta)
		_fov_punch = lerpf(_fov_punch, 0.0, delta * 8.0)
		var total_shake := vibracion + _shake
		if total_shake > 0.001:
			var s := total_shake * 0.05
			_cam.h_offset = randf_range(-s, s)
			_cam.v_offset = randf_range(-s, s)
		else:
			_cam.h_offset = lerpf(_cam.h_offset, 0.0, 0.4)
			_cam.v_offset = lerpf(_cam.v_offset, 0.0, 0.4)
		_shake = maxf(_shake - delta * 2.5, 0.0)

# --- API FreeFlow compatible ---
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
	vibracion = maxf(vibracion, amount)

func punch_fov(amount: float = -4.0, duration: float = 0.12) -> void:
	_fov_punch = amount
	if _fov_tween != null and _fov_tween.is_valid():
		_fov_tween.kill()
	_fov_tween = create_tween()
	_fov_tween.tween_property(self, "_fov_punch", 0.0, duration).set_ease(Tween.EASE_OUT)

func hitstop(duration: float = 0.05) -> void:
	_hitstop_timer = duration
	Engine.time_scale = 0.01

func slowmo(duration: float = 0.3, amount: float = 0.3) -> void:
	_slowmo_timer = duration
	Engine.time_scale = amount

func punch_fov_simple() -> void:
	punch_fov(-4.0, 0.12)
