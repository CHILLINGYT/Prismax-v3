extends Camera3D
class_name ExploreCamera

## Minimal free-fly camera so the coastal zone (and the underwater effect) can be
## explored right away. Click to capture the mouse, WASD to move, Q/E for down/up,
## Shift to boost, Escape to release the mouse. Delete this node if your own
## player already provides a camera.

@export var move_speed: float = 40.0
@export var boost_multiplier: float = 3.5
@export var mouse_sensitivity: float = 0.0018
@export var min_pitch: float = -1.45
@export var max_pitch: float = 1.45

var _pitch: float = 0.0


func _ready() -> void:
	_pitch = rotation.x
	# Only take over if nothing else in the scene already provides a camera.
	await get_tree().process_frame
	if get_viewport().get_camera_3d() == null:
		current = true


func _unhandled_input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseButton and p_event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if p_event is InputEventKey and p_event.pressed and p_event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if p_event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= p_event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - p_event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
		rotation.x = _pitch
		orthonormalize()


func _process(p_delta: float) -> void:
	var direction: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += global_transform.basis.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		direction -= Vector3.UP
	if direction == Vector3.ZERO:
		return
	var speed: float = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier
	global_position += direction.normalized() * speed * p_delta
