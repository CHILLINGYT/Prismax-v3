extends CharacterBody3D

## Test-only stand-in for the player, used by scenes/test_enemies.tscn.
##
## It is NOT part of the reusable enemy resources: it only exists so the test
## scene can be opened on its own and you can watch the enemies detect,
## surround and damage something. Swap it for your own character (or for the
## player scene of this project) and delete this folder.
##
## It fulfils the minimal target interface the enemies need:
##   - being inside the "player" group
##   - is_alive() -> bool
##   - take_damage(amount: float) -> void
##   - being a Node3D, so the enemy can read global_position
##
## Controls: WASD moves it on world axes (no camera-relative movement, this is
## just a punching bag), R revives it after it runs out of health.

@export_group("Stats")
@export var max_health: float = 500.0

@export_group("Movement")
@export var move_speed: float = 4.0
@export var gravity: float = 22.0

var health: float

var _label: Label3D


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_label = get_node_or_null("Status") as Label3D
	_update_label()
	_warn_missing_actions()


## Interface: the enemies stop considering it a valid target once this is false.
func is_alive() -> bool:
	return health > 0.0


## Interface: called by an enemy when its attack lands.
func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	_update_label()


func revive() -> void:
	health = max_health
	_update_label()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if InputMap.has_action("move_left"):
		var input := Vector2(
				Input.get_axis("move_left", "move_right"),
				Input.get_axis("move_forward", "move_back"))
		if input.length() > 0.001:
			input = input.normalized()
		velocity.x = input.x * move_speed
		velocity.z = input.y * move_speed
		if _label != null:
			_label.modulate = Color(1, 1, 1) if health > 0.0 else Color(1, 0.4, 0.4)
	else:
		# Without the input actions the dummy simply stands still and is hit.
		velocity.x = 0.0
		velocity.z = 0.0

	if InputMap.has_action("jump") and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = 6.0
	if Input.is_key_pressed(KEY_R):
		revive()

	move_and_slide()


func _update_label() -> void:
	if _label != null:
		_label.text = "TEST PLAYER  %d / %d" % [int(health), int(max_health)]


func _warn_missing_actions() -> void:
	var missing: Array[String] = []
	for action in ["move_left", "move_right", "move_forward", "move_back", "jump"]:
		if not InputMap.has_action(action):
			missing.append(action)
	if not missing.is_empty():
		print("[enemigos prueba] test player: missing input actions ", missing,
				" - it will stand still. See README.md.")