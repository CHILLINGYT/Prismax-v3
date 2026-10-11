extends Node3D

## Third-person action camera.
## Follows a target smoothly and orbits around it with the mouse.
## Captures the mouse on start; Escape releases / recaptures it.
##
## Deliberately has NO class_name: this module is meant to be dropped into other
## projects, and a global class name could collide with an existing one there.

@export var target_path: NodePath
@export var target_height: float = 1.6
@export var follow_speed: float = 12.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = -70.0
@export var max_pitch: float = 70.0
@export var start_pitch: float = -15.0

var _target: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _shake: float = 0.0


func _ready() -> void:
	add_to_group("camera_rig")
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node3D
	_yaw = rotation.y
	_pitch = deg_to_rad(start_pitch)
	rotation = Vector3(_pitch, _yaw, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch -= motion.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if _target != null:
		var desired: Vector3 = _target.global_position + Vector3(0.0, target_height, 0.0)
		global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		global_position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 0.12
	# Euler order is YXZ, so yaw is applied around the world up axis first.
	rotation = Vector3(_pitch, _yaw, 0.0)


## Adds a short camera shake (used as impact feedback).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)