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

func _ready() -> void:
	_brazo = get_node_or_null("Brazo") as SpringArm3D
	_cam = get_node_or_null("Brazo/Camara") as Camera3D
	objetivo_largo = largo_base
	objetivo_fov = fov_base
	_pitch = pitch_objetivo_inicial
	_pitch_obj = pitch_objetivo_inicial
	rotation.x = _pitch
	if _brazo != null:
		_brazo.spring_length = largo_base
		# El brazo no debe chocar con el propio cuerpo del jugador: si lo hace,
		# se acorta hasta el pivote y la camara cae en primera persona.
		var cuerpo := get_parent()
		if cuerpo is CollisionObject3D:
			_brazo.add_excluded_object((cuerpo as CollisionObject3D).get_rid())
	if _cam != null:
		_cam.fov = fov_base

func _unhandled_input(event: InputEvent) -> void:
	if not permitir_look:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensibilidad)
		_pitch_obj = clampf(_pitch_obj - event.relative.y * sensibilidad, -limite_pitch, limite_pitch_superior)

func definir_pitch(v: float) -> void:
	_pitch_obj = clampf(v, -limite_pitch, limite_pitch_superior)

func _process(delta: float) -> void:
	_pitch = lerpf(_pitch, _pitch_obj, 10.0 * delta)
	rotation.x = _pitch
	if _brazo != null:
		_brazo.spring_length = lerpf(_brazo.spring_length, objetivo_largo, 6.0 * delta)
	if _cam != null:
		_cam.fov = lerpf(_cam.fov, objetivo_fov, 5.0 * delta)
		if vibracion > 0.001:
			var s := vibracion * 0.05
			_cam.h_offset = randf_range(-s, s)
			_cam.v_offset = randf_range(-s, s)
		else:
			_cam.h_offset = lerpf(_cam.h_offset, 0.0, 0.4)
			_cam.v_offset = lerpf(_cam.v_offset, 0.0, 0.4)
