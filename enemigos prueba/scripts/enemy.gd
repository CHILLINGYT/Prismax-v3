extends CharacterBody3D

## Melee enemy with a FreeFlow-oriented state machine.
##
## Self-contained: it lives in "enemigos prueba" and talks to the rest of the
## project through a small documented interface instead of hard casts, so it
## can be dropped into another project. See README.md in this folder.
## No `class_name` is declared on purpose, so copying this folder into a
## project that already has an `Enemy` class will not clash. Add one back if
## you want to reference the type by name.
##
## It registers with the encounter manager, holds a formation slot, requests an
## attack token before striking, announces a threat during its windup, and
## owns its health bar. Reads all combat values from the shared config.

signal died(enemy: Node3D)

const CombatConfig = preload("res://enemigos prueba/scripts/combat/combat_config.gd")

enum State { IDLE, ALERT, APPROACH, WAIT, WINDUP, ACTIVE, RECOVERY, HIT, STUN, DEAD }

@export_group("Wiring")
## Optional explicit encounter manager. Empty = first node in the
## "combat_manager" group. Any node with the documented interface works.
@export var combat_manager_path: NodePath
## Optional explicit target to fight. Empty = first node in the "player" group.
## Any Node3D that can be hit works; see README.md.
@export var target_path: NodePath

@export_group("Stats")
## Health of this instance. Damage per hit comes from the shared config.
@export var max_health: float = 100.0

@export_group("Movement")
@export var acceleration: float = 14.0
@export var gravity: float = 22.0
@export var turn_speed: float = 10.0

var health: float
var state: State = State.IDLE

## Encounter manager, resolved by interface (see _resolve_manager() below).
## Untyped on purpose: it may be this folder's manager or the host project's.
var _manager
## Shared tuning resource, also untyped: it may use any project's config script.
var _config
## Whoever this enemy fights: a Player, a dummy, anything that can be hit.
var _player
var _has_token: bool = false
var _registered: bool = false
var _phase_timer: float = 0.0
var _hit_done: bool = false
var _flash_timer: float = 0.0

var _stall_timer: float = 0.0
var _sidestep_timer: float = 0.0
var _sidestep_dir: Vector3 = Vector3.ZERO
var _wait_timer: float = 0.0
var _intended_speed: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO
var _last_desired: Vector3 = Vector3.ZERO

var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _base_color: Color = Color.WHITE
var _health_bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_fill_material: StandardMaterial3D
var _bar_width: float = 1.0
var _anim_tween: Tween


func _ready() -> void:
	add_to_group("enemies")
	# También se registra en "damageable": es el punto de unión que ya usan las
	# habilidades de agua y de fuerza del proyecto (mismo contrato documentado en
	# WaterAbility y FuerzaCombat). Ver take_damage()/apply_damage() más abajo.
	add_to_group("damageable")
	health = max_health

	# Per-instance body material so the hit flash does not affect other enemies.
	_body = get_node_or_null("Body") as MeshInstance3D
	if _body != null:
		var mat: Material = _body.get_active_material(0)
		if mat is StandardMaterial3D:
			_body_material = (mat as StandardMaterial3D).duplicate()
			_body.set_surface_override_material(0, _body_material)
			_base_color = _body_material.albedo_color

	# Health bar: grab the fill quad and give it its own material.
	_health_bar = get_node_or_null("HealthBar") as Node3D
	if _health_bar != null:
		_bar_fill = _health_bar.get_node_or_null("Fill") as MeshInstance3D
		if _bar_fill != null:
			var fm: Material = _bar_fill.get_active_material(0)
			if fm is StandardMaterial3D:
				_bar_fill_material = (fm as StandardMaterial3D).duplicate()
				_bar_fill.set_surface_override_material(0, _bar_fill_material)
			var quad := _bar_fill.mesh as QuadMesh
			if quad != null:
				_bar_width = quad.size.x
	_update_health_bar()


func is_alive() -> bool:
	return state != State.DEAD


func get_state_name() -> String:
	return State.keys()[state] as String


func _process(_delta: float) -> void:
	# Billboard the health bar toward the active camera.
	if _health_bar == null or not _health_bar.visible:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var t: Transform3D = _health_bar.global_transform
	t.basis = cam.global_transform.basis
	_health_bar.global_transform = t


func _physics_process(delta: float) -> void:
	_ensure_combat()
	_prev_pos = global_position
	_intended_speed = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_restore_color()

	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	match state:
		State.IDLE:
			_decelerate(delta)
			if _player_valid() and _distance_to_player() <= _config.enemy_detection_range:
				state = State.ALERT
				_phase_timer = 0.15
		State.ALERT:
			_decelerate(delta)
			if _player_valid():
				_face_player(delta)
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				state = State.APPROACH
		State.APPROACH:
			_state_approach(delta)
		State.WAIT:
			_state_wait(delta)
		State.WINDUP:
			_state_windup(delta)
		State.ACTIVE:
			_state_active(delta)
		State.RECOVERY:
			_state_recovery(delta)
		State.HIT:
			_decelerate(delta)
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				state = State.APPROACH
		State.STUN:
			_decelerate(delta)
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				state = State.APPROACH

	move_and_slide()
	_update_stall(delta)


## Applies damage from the player. Returns true if the hit landed on a live enemy.
func take_hit(amount: float, hit_dir: Vector3, knockback: float, stun_time: float) -> bool:
	if state == State.DEAD:
		return false
	health = maxf(health - amount, 0.0)
	_update_health_bar()
	if health <= 0.0:
		_die()
		return true
	_interrupt_attack()
	var away: Vector3 = hit_dir
	away.y = 0.0
	if away.length() > 0.001:
		velocity += away.normalized() * knockback
	if stun_time > 0.0:
		state = State.STUN
		_phase_timer = stun_time
	else:
		state = State.HIT
		_phase_timer = _config.enemy_hit_stun
	_flash()
	return true


## Daño genérico. Dos formas de llamarlo, ambas válidas:
##   take_damage(cantidad)                                    (interfaz mínima)
##   take_damage(cantidad, desde: Vector3, empuje: Vector3)   (contrato de las
##                                                             habilidades de fuerza)
## El empuje (Vector3) se traduce a la dirección + knockback que ya usa take_hit.
func take_damage(amount: float, from_position: Vector3 = Vector3.ZERO, push: Vector3 = Vector3.ZERO) -> void:
	var dir := push
	if dir.length() < 0.001 and from_position != Vector3.ZERO:
		dir = global_position - from_position
	take_hit(amount, dir, push.length(), 0.0)


## Contrato de las habilidades de agua (WaterAbility):
##   apply_damage(cantidad, desde: Vector3, tipo: StringName)
## El tipo (&"light"/&"heavy") decide el empuje real del golpe (valores
## iniciales ajustables, en la escala que ya usan esas habilidades).
func apply_damage(amount: float, from_position: Vector3, kind: StringName = &"light") -> void:
	var empuje := 1.6 if kind != &"heavy" else 5.0
	var dir := global_position - from_position
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.BACK
	take_hit(amount, dir.normalized(), empuje, 0.0)


## La prisión de agua encierra al objetivo: aquí se traduce al aturdimiento real.
func trap(duration: float) -> void:
	stun(duration)


## Centro aproximado del cuerpo (para las habilidades que apuntan al pecho).
func get_hit_center() -> Vector3:
	return global_position + Vector3.UP * 1.0


## Radio de impacto aproximado de la cápsula (contrato de agua).
func get_hit_radius() -> float:
	return 0.5


## ¿Está derrotado? (contrato de agua: filtra objetivos muertos).
func is_defeated() -> bool:
	return not is_alive()


# --- State logic -----------------------------------------------------------

func _state_approach(delta: float) -> void:
	if not _player_valid():
		state = State.IDLE
		return
	_face_player(delta)
	var dist := _distance_to_player()
	if _has_token:
		if dist <= _config.enemy_attack_range:
			_start_windup()
		else:
			_step_toward_player(delta)
	elif dist <= _config.formation_radius:
		state = State.WAIT
		if _request_token():
			state = State.APPROACH
	else:
		_step_toward_player(delta)


func _state_wait(delta: float) -> void:
	if not _player_valid():
		state = State.IDLE
		return
	_face_player(delta)
	if _request_token():
		_wait_timer = 0.0
		state = State.APPROACH
		return
	_move_to_slot(delta)
	# Do not stand still like a mannequin: after a short wait, sidestep to look
	# for a better angle while still holding the defensive ring.
	_wait_timer += delta
	if _wait_timer > _config.wait_patience:
		_start_sidestep(_last_desired)
		_wait_timer = 0.0
	if _distance_to_player() > _config.formation_radius + 1.0:
		state = State.APPROACH


func _start_windup() -> void:
	if not _has_token and not _request_token():
		state = State.WAIT
		return
	state = State.WINDUP
	_phase_timer = _config.enemy_windup
	_hit_done = false
	if _manager != null:
		_manager.threats.register(self, "melee", _config.enemy_windup, true)
	_set_tell(true)
	_play_anim_windup()


func _state_windup(delta: float) -> void:
	_decelerate(delta)
	_face_player(delta)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		if _manager != null:
			_manager.threats.clear_for(self)
		_set_tell(false)
		state = State.ACTIVE
		_phase_timer = _config.enemy_active
		_hit_done = false
		_play_anim_strike()


func _state_active(delta: float) -> void:
	_decelerate(delta)
	_face_player(delta)
	if not _hit_done and _player_valid() and _distance_to_player() <= _config.enemy_attack_range + 0.35:
		if _player.has_method("take_damage"):
			_player.take_damage(_config.enemy_damage)
		_hit_done = true
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		state = State.RECOVERY
		_phase_timer = _config.enemy_recovery


func _state_recovery(delta: float) -> void:
	_decelerate(delta)
	_face_player(delta)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_release_token()
		state = State.APPROACH


# --- Tokens / threats ------------------------------------------------------

func _request_token() -> bool:
	if _manager == null:
		return false
	if _has_token:
		return true
	# Registers interest in the fair queue; the token is granted by the manager
	# to whoever has been waiting the longest.
	_manager.tokens.request(self)
	if _manager.tokens.has_token(self):
		_has_token = true
		return true
	return false


func _release_token() -> void:
	if _has_token and _manager != null:
		_manager.tokens.release(self)
	_has_token = false


## Withdraws a pending request so a stunned/dead enemy cannot be handed a turn.
func _cancel_token_request() -> void:
	if _manager != null:
		_manager.tokens.cancel(self)


func _interrupt_attack() -> void:
	if state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY:
		if _manager != null:
			_manager.threats.clear_for(self)
		_release_token()
	_set_tell(false)


## True while staggered; such an enemy can be finished with a takedown.
func is_stunned() -> bool:
	return state == State.STUN


func stun(duration: float) -> void:
	if state == State.DEAD:
		return
	_interrupt_attack()
	_cancel_token_request()
	velocity = Vector3.ZERO
	state = State.STUN
	_phase_timer = maxf(0.01, duration)


## Called when the player counters one of this enemy's attacks.
func on_countered(counter_stun: float) -> void:
	if state == State.DEAD:
		return
	_interrupt_attack()
	_cancel_token_request()
	velocity = Vector3.ZERO
	state = State.STUN
	_phase_timer = maxf(0.01, counter_stun)


## Contextual finisher: instantly defeats a stunned enemy.
func execute() -> void:
	if state == State.DEAD:
		return
	health = 0.0
	_update_health_bar()
	_die()


func _set_tell(on: bool) -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = Color(1.0, 0.6, 0.1) if on else _base_color


func _die() -> void:
	state = State.DEAD
	health = 0.0
	_update_health_bar()
	if _manager != null:
		_manager.threats.clear_for(self)
	_release_token()
	if _manager != null:
		_manager.notify_enemy_died(self)
	remove_from_group("enemies")
	remove_from_group("damageable")
	if _health_bar != null:
		_health_bar.visible = false
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		cs.disabled = true
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	if _body != null:
		var tw := create_tween()
		tw.tween_property(_body, "rotation:z", 1.5708, 0.35)
		tw.tween_interval(maxf(0.05, _config.enemy_death_linger - 0.2))
		tw.tween_callback(queue_free)
	else:
		queue_free()
	died.emit(self)


func _restore_color() -> void:
	if _body_material != null:
		_body_material.albedo_color = _base_color


func _flash() -> void:
	if _body_material != null:
		_body_material.albedo_color = Color(1.0, 1.0, 1.0)
	_flash_timer = _config.enemy_hit_stun


# --- Movement helpers ------------------------------------------------------

func _step_toward_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	var desired: Vector3 = to.normalized() if to.length() > 0.001 else Vector3.ZERO
	_apply_move(desired, delta)


func _move_to_slot(delta: float) -> void:
	var goal: Vector3 = _player.global_position if _player != null else global_position
	if _manager != null and _manager.formation.has_slot(self):
		goal = _manager.formation.get_slot(self)
	var to: Vector3 = goal - global_position
	to.y = 0.0
	var desired: Vector3 = to.normalized() if to.length() > 0.05 else Vector3.ZERO
	_apply_move(desired, delta)


func _apply_move(desired: Vector3, delta: float) -> void:
	_last_desired = desired
	var sep := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var off: Vector3 = global_position - (other as Node3D).global_position
		off.y = 0.0
		var d: float = off.length()
		if d > 0.001 and d < _config.formation_min_separation:
			sep += off.normalized() * (_config.formation_min_separation - d)
	var move_dir: Vector3 = desired + sep * 1.2
	# A sidestep temporarily dominates so the enemy walks around a blocker (or
	# slides along it) instead of pushing into it forever.
	if _sidestep_timer > 0.0:
		move_dir = move_dir * 0.35 + _sidestep_dir
	move_dir.y = 0.0
	if move_dir.length() > 0.001:
		move_dir = move_dir.normalized()
	var target: Vector3 = move_dir * _config.enemy_move_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	_intended_speed = velocity.length()


## Detects "I want to move but I am not moving" and triggers a sidestep so the
## enemy steps around whoever is blocking it.
func _update_stall(delta: float) -> void:
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
	if _intended_speed < 0.8:
		_stall_timer = maxf(0.0, _stall_timer - delta)
		return
	var moved: Vector2 = Vector2(global_position.x - _prev_pos.x, global_position.z - _prev_pos.z)
	var wanted: float = _intended_speed * delta
	if moved.length() < wanted * 0.35:
		_stall_timer += delta
	else:
		_stall_timer = maxf(0.0, _stall_timer - delta * 1.5)
	if _stall_timer > _config.stall_time and _sidestep_timer <= 0.0:
		_start_sidestep(_last_desired)
		_stall_timer = 0.0


## Picks a lateral direction (towards the emptier side) and moves along it for
## a moment, so the enemy goes around allies instead of shoving them.
func _start_sidestep(base: Vector3) -> void:
	var b: Vector3 = base
	b.y = 0.0
	if b.length() < 0.001:
		b = -global_transform.basis.z
		b.y = 0.0
		if b.length() < 0.001:
			return
	b = b.normalized()
	var side: Vector3 = Vector3(-b.z, 0.0, b.x)
	var lateral: float = 0.0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var off: Vector3 = (other as Node3D).global_position - global_position
		off.y = 0.0
		if off.length() < 2.5:
			lateral += side.dot(off)
	_sidestep_dir = -side if lateral > 0.0 else side
	_sidestep_timer = _config.sidestep_time


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _ensure_combat() -> void:
	if _manager == null or not is_instance_valid(_manager):
		_manager = _resolve_manager()
		if _manager != null and not _registered:
			_manager.register_enemy(self)
			_registered = true
	if _config == null and _manager != null:
		_config = _manager.config
	if _config == null:
		# Nobody is coordinating: keep sane defaults so the enemy still walks
		# around. It will not attack, because striking needs an attack token.
		_config = CombatConfig.new()
	if _player == null or not is_instance_valid(_player):
		_player = _resolve_target()


## Finds the encounter manager: the explicit path wins, then the first node in
## the "combat_manager" group. Any node exposing the documented methods is
## accepted, so this enemy works with the manager bundled in this folder and
## with a manager owned by the host project.
func _resolve_manager() -> Node:
	if not combat_manager_path.is_empty():
		var wired: Node = get_node_or_null(combat_manager_path)
		if _is_manager(wired):
			return wired
	var found: Node = get_tree().get_first_node_in_group("combat_manager")
	return found if _is_manager(found) else null


func _is_manager(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.has_method("register_enemy") and node.has_method("notify_enemy_died")


## Finds who to fight: the explicit path wins, then the first node in the
## "player" group.
func _resolve_target() -> Node3D:
	if not target_path.is_empty():
		var wired: Node = get_node_or_null(target_path)
		if wired is Node3D:
			return wired
	return get_tree().get_first_node_in_group("player") as Node3D


## The target counts as valid while it is alive. A target without is_alive() is
## assumed to be alive.
func _player_valid() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.has_method("is_alive"):
		return _player.is_alive()
	return true


func _distance_to_player() -> float:
	if _player == null or not is_instance_valid(_player):
		return INF
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	return to.length()


func _face_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	if to.length() > 0.001:
		var target_yaw: float = atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


# --- Presentation ----------------------------------------------------------

func _update_health_bar() -> void:
	if _bar_fill == null:
		return
	var ratio: float = clampf(health / max_health, 0.0, 1.0)
	_bar_fill.scale.x = maxf(ratio, 0.0001)
	_bar_fill.position.x = -_bar_width * 0.5 * (1.0 - ratio)
	if _bar_fill_material != null:
		_bar_fill_material.albedo_color = Color(1.0 - ratio, 0.2 + 0.65 * ratio, 0.15)


func _play_anim_windup() -> void:
	if _body == null:
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = create_tween()
	_anim_tween.tween_property(_body, "rotation:x", -0.3, maxf(0.05, _config.enemy_windup * 0.9))


func _play_anim_strike() -> void:
	if _body == null:
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = create_tween()
	_anim_tween.tween_property(_body, "rotation:x", 0.4, 0.07)
	_anim_tween.tween_property(_body, "rotation:x", 0.0, 0.18)