extends Node3D

## Third-person action camera.
## Follows a target smoothly and orbits around it with the mouse.
## Captures the mouse on start; Escape releases / recaptures it.
##
## Deliberately has NO class_name: this module is meant to be dropped into other
## projects, and a global class name could collide with an existing one there.

@export var target_path: NodePath
@export var target_height: float = 1.5
@export var follow_speed: float = 12.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = -70.0
@export var max_pitch: float = 70.0
@export var start_pitch: float = -15.0

var _target: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _shake: float = 0.0
var _shake_trauma: float = 0.0
var _fov_base: float = 75.0
var _fov_punch: float = 0.0
var _fov_tween: Tween
var _cam: Camera3D
var _hitstop_timer: float = 0.0
var _slowmo_timer: float = 0.0
var _slowmo_amount: float = 1.0


func _ready() -> void:
	add_to_group("camera_rig")
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node3D
	_yaw = rotation.y
	_pitch = deg_to_rad(start_pitch)
	rotation = Vector3(_pitch, _yaw, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_cam = get_node_or_null("Camera3D") as Camera3D
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
		if _cam != null:
			_fov_base = _cam.fov


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
	# --- MEJORA #3: Hitstop y Slowmo ---
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0.0:
			Engine.time_scale = 1.0
		else:
			Engine.time_scale = 0.01
			return # freeze todo durante hitstop
	
	if _slowmo_timer > 0.0:
		_slowmo_timer -= delta
		Engine.time_scale = _slowmo_amount
		if _slowmo_timer <= 0.0:
			Engine.time_scale = 1.0
			_slowmo_amount = 1.0
	
	if _target != null:
		var desired: Vector3 = _target.global_position + Vector3(0.0, target_height, 0.0)
		global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))
	
	# Shake con trauma (mejor que random puro)
	if _shake > 0.0 or _shake_trauma > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		_shake_trauma = maxf(0.0, _shake_trauma - delta * 1.8)
		var trauma := maxf(_shake, _shake_trauma)
		# Perlin-like shake: más natural
		var shake_x := (randf() * 2.0 - 1.0) * trauma * 0.12
		var shake_y := (randf() * 2.0 - 1.0) * trauma * 0.12
		var shake_z := (randf() * 2.0 - 1.0) * trauma * 0.08
		global_position += Vector3(shake_x, shake_y, shake_z)
	
	# FOV punch recovery
	if _cam != null and _fov_punch != 0.0:
		_fov_punch = lerpf(_fov_punch, 0.0, delta * 8.0)
		_cam.fov = _fov_base + _fov_punch
	
	rotation = Vector3(_pitch, _yaw, 0.0)


## Adds a short camera shake (used as impact feedback).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
	_shake_trauma = maxf(_shake_trauma, amount * 0.8)

## FOV punch - se siente el impacto sin marear
func punch_fov(amount: float = -4.0, duration: float = 0.12) -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
		if _cam == null:
			return
		_fov_base = _cam.fov
	if _fov_tween != null and _fov_tween.is_valid():
		_fov_tween.kill()
	_fov_tween = create_tween()
	_fov_tween.tween_property(self, "_fov_punch", amount, duration * 0.3).set_ease(Tween.EASE_OUT)
	_fov_tween.tween_property(self, "_fov_punch", 0.0, duration * 0.7).set_ease(Tween.EASE_IN)

## Hitstop - freeze de 0.05s en cada hit (como Smash Bros)
func hitstop(duration: float = 0.05) -> void:
	_hitstop_timer = duration
	Engine.time_scale = 0.01

## Slowmo para counters perfectos y finishers
func slowmo(duration: float = 0.3, amount: float = 0.3) -> void:
	_slowmo_timer = duration
	_slowmo_amount = amount
	Engine.time_scale = amount

## Zoom a enemigo para counter perfecto
func zoom_to_enemy(enemy: Node3D, duration: float = 0.2) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	# Guarda yaw/pitch actuales y hace tween hacia enemigo
	var to_enemy := enemy.global_position - global_position
	to_enemy.y = 0.0
	if to_enemy.length() < 0.1:
		return
	var target_yaw := atan2(-to_enemy.x, -to_enemy.z)
	var tween := create_tween()
	tween.tween_property(self, "_yaw", target_yaw, duration * 0.5).set_ease(Tween.EASE_OUT)
	punch_fov(-6.0, duration)