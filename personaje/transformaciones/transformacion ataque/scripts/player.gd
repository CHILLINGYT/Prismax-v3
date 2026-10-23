extends CharacterBody3D

## Third-person player controller with FreeFlow-style combat.
## Part of the "transformacion ataque" module: self-contained and portable.
##
## WASD moves relative to the camera, Space jumps, left mouse attacks. Attacks
## run through a state machine (FREE/APPROACH/WINDUP/ACTIVE/RECOVERY/HIT/DEAD),
## a contextual targeting pass, an automatic approach when the target is far,
## and an input buffer for chaining combos.
##
## Deliberately has NO class_name: this module is meant to be dropped into other
## projects, where a global class name could collide with an existing one.

signal health_changed(current: float, max_health: float)
signal died
signal combo_changed(count: int)

const CombatManager = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const CombatConfig = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_config.gd")
const CombatTargeting = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_targeting.gd")
const AttackData = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/attack_data.gd")
const PlayerAnimator = preload("res://personaje/transformaciones/transformacion ataque/scripts/player_animator.gd")

enum State { FREE, APPROACH, WINDUP, ACTIVE, RECOVERY, COUNTER, EVADE, HIT, DEAD }

## Sprint: the player's FIVE-hit basic combo - MEJORA #4
## Orden: jab (recto rápido) -> cros (cruzado) -> gancho (hook) -> dos (segundo recto, del set viejo) -> remate (finisher)
## Cada número viene del clip fuente, donde impact es el pico de alcance del puño medido.
## Clips del módulo: jab, cros, gancho, dos en player_anim_library.tres
## El 5to es remate: reusa gancho pero más lento, más daño y con VFX grande
##
## windup = impact, active = HIT_WINDOW, recovery = resto del clip
## speed = playback speed por ataque: timers se dividen por speed para que daño caiga en contacto visual
const HIT_WINDOW := 0.10
const SPRINT: Array = [
	{"id": "jab", "anim": "jab", "clip": 0.467, "impact": 0.233, "damage": 1.0, "knockback": 1.0, "speed": 1.35, "stamina": 5.0, "type": "light"},
	{"id": "cros", "anim": "cros", "clip": 0.733, "impact": 0.147, "damage": 1.4, "knockback": 1.3, "speed": 1.25, "stamina": 8.0, "type": "light"},
	{"id": "gancho", "anim": "gancho", "clip": 0.633, "impact": 0.327, "damage": 1.7, "knockback": 1.5, "speed": 1.20, "stamina": 12.0, "type": "medium"},
	{"id": "dos", "anim": "dos", "clip": 0.600, "impact": 0.135, "damage": 1.5, "knockback": 1.4, "speed": 1.30, "stamina": 10.0, "type": "light"}, # del set viejo, ahora parte de cadena
	{"id": "remate", "anim": "gancho", "clip": 0.633, "impact": 0.327, "damage": 2.8, "knockback": 3.5, "speed": 0.90, "stamina": 18.0, "type": "heavy", "finisher": true}, # finisher: mismo clip gancho pero lento y devastador
]

@export_group("Movement")
@export var walk_speed: float = 6.0
@export var acceleration: float = 30.0
@export var deceleration: float = 40.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 22.0
@export var turn_speed: float = 14.0

@export_group("Wiring")
## Camera pivot whose horizontal orientation drives movement. Leave empty to fall
## back to the first node in the "camera_rig" group.
@export var camera_rig_path: NodePath = NodePath("../CameraRig")
## Explicit CombatManager. Leave empty to use the manager already present in the
## scene, or to let the character create its own so it works on its own.
@export var combat_manager_path: NodePath
## Tuning used when the character has to create its own manager.
@export var combat_config: CombatConfig
## Create a private manager when the scene has none. Keeps the character usable
## in an empty project; turn it off if your project owns the encounter manager.
@export var create_manager_if_missing: bool = true

@export_group("Combat")
@export var max_health: float = 100.0

@export_group("Input actions")
## Rename any of these to the action names your project already uses. Nothing is
## overwritten in the project's input map; this only tells the module what to read.
@export var action_move_forward: StringName = &"move_forward"
@export var action_move_back: StringName = &"move_back"
@export var action_move_left: StringName = &"move_left"
@export var action_move_right: StringName = &"move_right"
@export var action_jump: StringName = &"jump"
@export var action_attack: StringName = &"combat_attack"
@export var action_counter: StringName = &"combat_counter"
@export var action_evade: StringName = &"combat_evade"
@export var action_stun: StringName = &"combat_stun"
@export var action_special: StringName = &"combat_special"
@export var action_takedown: StringName = &"combat_takedown"
@export var action_gadget: StringName = &"combat_gadget"

var health: float
var state: State = State.FREE

var _manager: CombatManager
## Manager created by this character when the scene provides none.
var _own_manager: CombatManager
var _config: CombatConfig
var _camera_rig: Node3D
var _target: Node3D
var _attack_chain: Array = []
var _chain_index: int = 0
## Remaining seconds of the COMBO WINDOW (the config's combo_keep_time), counted
## from the last CONFIRMED hit: while it is alive the next attack CONTINUES the
## chain (jab -> cros -> gancho -> jab); once it expires the combo starts over at
## the first hit. This is what lets three hits chain at a natural rhythm, not only
## inside the 0.2 s input buffer.
var _combo_window: float = 0.0
var _attack: AttackData
var _action_kind: String = "attack"
var _phase_timer: float = 0.0
var _hit_done: bool = false
var _approach_timer: float = 0.0
var _evade_timer: float = 0.0
var _evade_dir: Vector3 = Vector3.ZERO
var _iframe_timer: float = 0.0
var _gadget_timer: float = 0.0

var _alive: bool = true
var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _base_color: Color = Color.WHITE
var _flash_timer: float = 0.0
var _anim_tween: Tween

## Presentation: the skeletal model and the node that plays its clips. Neither is
## ever allowed to move the body, change the collision or block the controls.
var _visual: Node3D
var _animator: PlayerAnimator
var _visual_materials: Array[StandardMaterial3D] = []
var _visual_base_colors: Array[Color] = []


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_warn_missing_actions()

	# Resolve by explicit path first; group lookup is a fallback.
	if not camera_rig_path.is_empty():
		_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	if _camera_rig == null:
		_camera_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D

	# Give this instance its own body material so the damage flash stays local.
	_body = get_node_or_null("Body") as MeshInstance3D
	if _body != null:
		var mat: Material = _body.get_active_material(0)
		if mat is StandardMaterial3D:
			_body_material = (mat as StandardMaterial3D).duplicate()
			_body.set_surface_override_material(0, _body_material)
			_base_color = _body_material.albedo_color

	# The skeletal model replaces the placeholder capsule art. The capsule node
	# itself stays in the scene and keeps doing every physics query.
	_visual = get_node_or_null("Visual") as Node3D
	_prepare_visual()
	_animator = get_node_or_null("AnimationPlayer") as PlayerAnimator

	_ensure_combat()


## Hides the placeholder capsule art and gives the skeletal model its own
## materials, so the existing damage flash keeps working on the new visual.
func _prepare_visual() -> void:
	var placeholder := get_node_or_null("Body") as MeshInstance3D
	if placeholder != null:
		placeholder.visible = false
	var nose := get_node_or_null("Nose") as MeshInstance3D
	if nose != null:
		nose.visible = false
	if _visual == null:
		return
	var stack: Array[Node] = [_visual]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh != null:
				for s in mesh.get_surface_count():
					var mat: Material = mi.get_surface_override_material(s)
					if mat == null:
						mat = mesh.surface_get_material(s)
					if mat is StandardMaterial3D:
						var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						mi.set_surface_override_material(s, dup)
						_visual_materials.append(dup)
						_visual_base_colors.append(dup.albedo_color)
		for c in n.get_children():
			stack.append(c)


func is_alive() -> bool:
	return _alive


func get_state_name() -> String:
	return State.keys()[state] as String


func get_target() -> Node3D:
	return _target


func _ensure_combat() -> void:
	if _manager == null or not is_instance_valid(_manager):
		_manager = _resolve_manager()
	if _manager != null and _config == null:
		_config = _manager.config
	if _config == null:
		_config = CombatConfig.new()
	if _attack_chain.is_empty():
		_attack_chain = _build_attack_chain(_config)


## Manager resolution, most explicit first:
##   1. the NodePath set in the inspector,
##   2. a CombatManager already present in the scene,
##   3. one created by the character itself, so it also works on its own.
## The manager is told who the player is, so it never has to search for it.
func _resolve_manager() -> CombatManager:
	if not combat_manager_path.is_empty():
		var explicit: Node = get_node_or_null(combat_manager_path)
		if explicit is CombatManager:
			var m: CombatManager = explicit
			m.set_player(self)
			return m
		push_warning("PlayerAtaque: combat_manager_path does not point to this module's CombatManager.")
	var found: CombatManager = get_tree().get_first_node_in_group("combat_manager") as CombatManager
	if found != null:
		found.set_player(self)
		return found
	if not create_manager_if_missing or _own_manager != null:
		return _own_manager
	_own_manager = CombatManager.new()
	_own_manager.name = "PlayerCombatManager"
	if combat_config != null:
		_own_manager.config = combat_config
	add_child(_own_manager)
	_own_manager.set_player(self)
	return _own_manager


## Reports missing input actions once, with their real names. Nothing is hidden:
## the console names exactly which action to create (or which property to rename
## in the "Input actions" group).
func _warn_missing_actions() -> void:
	var missing: Array[String] = []
	for a: StringName in [action_move_forward, action_move_back, action_move_left, action_move_right, action_jump, action_attack, action_counter, action_evade, action_stun, action_special, action_takedown, action_gadget]:
		if not InputMap.has_action(a):
			missing.append(String(a))
	if not missing.is_empty():
		push_warning("PlayerAtaque: missing input actions -> %s. Add them in Project > Input Map, or rename the matching properties in the 'Input actions' group." % ", ".join(missing))


func _build_attack_chain(c: CombatConfig) -> Array:
	var chain: Array = []
	for row in SPRINT:
		var a := AttackData.new()
		a.id = String(row.id)
		a.animation = String(row.anim)
		a.damage = c.attack_damage * float(row.damage)
		a.attack_range = c.attack_range
		a.ideal_distance = c.attack_ideal_distance
		a.approach_speed = c.approach_speed
		var sp: float = maxf(0.05, float(row.get("speed", 1.0)))
		a.speed = sp
		a.windup = float(row.impact) / sp
		a.active = HIT_WINDOW
		a.recovery = maxf(0.05, (float(row.clip) - float(row.impact)) / sp - HIT_WINDOW)
		a.cancel_window = c.attack_cancel_window
		a.knockback = c.attack_knockback * float(row.knockback)
		a.stun = 0.0
		# MEJORA #4: Nuevos campos
		a.stamina_cost = float(row.get("stamina", 5.0))
		a.attack_type = String(row.get("type", "light"))
		a.is_finisher = bool(row.get("finisher", false))
		a.hitstop_duration = 0.08 if a.is_finisher else 0.05
		a.camera_shake = 0.8 if a.is_finisher else (0.5 if a.attack_type == "medium" else 0.3)
		chain.append(a)
	return chain

## MEJORA #4: Detecta input direccional para variantes (W=uppercut, S=barrido, A/D=lateral)
func _get_directional_attack() -> String:
	var dir := _input_dir()
	if dir.length() < 0.3:
		return "" # sin dirección = ataque normal de cadena
	var cam_f := _camera_dir()
	var forward_dot := dir.dot(cam_f)
	var right := Vector3(cam_f.z, 0, -cam_f.x) # perpendicular derecha
	var right_dot := dir.dot(right)
	
	if forward_dot > 0.7:
		return "uppercut" # W + ataque = lanza al aire
	elif forward_dot < -0.7:
		return "sweep" # S + ataque = barrido bajo
	elif absf(right_dot) > 0.7:
		return "lateral" # A/D + ataque = golpe con desplazamiento lateral
	return ""


func _physics_process(delta: float) -> void:
	_ensure_combat()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			if _body_material != null:
				_body_material.albedo_color = _base_color
			_restore_visual_tint()

	if not is_on_floor():
		velocity.y -= gravity * delta

	# Once defeated the player stops acting but still settles on the ground.
	if not _alive:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		move_and_slide()
		return

	if _just_pressed(action_jump) and is_on_floor():
		velocity.y = jump_velocity
		# Purely visual: the controller keeps owning gravity and vertical speed.
		if _animator != null:
			_animator.play_action(PlayerAnimator.JUMP)

	if _gadget_timer > 0.0:
		_gadget_timer -= delta
	if _iframe_timer > 0.0:
		_iframe_timer -= delta
	if _combo_window > 0.0:
		_combo_window = maxf(_combo_window - delta, 0.0)

	# Buffer chainable combat actions; consumed when the state allows it.
	if _manager != null:
		if _just_pressed(action_attack):
			_manager.combo.push_input("attack", _input_dir(), 10)
		if _just_pressed(action_stun):
			_manager.combo.push_input("stun", _input_dir(), 8)
		if _just_pressed(action_special):
			_manager.combo.push_input("special", _input_dir(), 9)
		if _just_pressed(action_takedown):
			_manager.combo.push_input("takedown", _input_dir(), 12)

	match state:
		State.FREE:
			_state_free(delta)
		State.APPROACH:
			_state_approach(delta)
		State.WINDUP:
			_state_windup(delta)
		State.ACTIVE:
			_state_active(delta)
		State.RECOVERY:
			_state_recovery(delta)
		State.COUNTER:
			_state_counter(delta)
		State.EVADE:
			_state_evade(delta)
		State.HIT:
			_state_hit(delta)

	move_and_slide()
	_update_animation()


## Locomotion animation is only driven while the player is free to move. During
## an attack, jump or evade the action clip keeps playing untouched, so no
## animation is ever able to lock the controls or the target switching.
func _update_animation() -> void:
	if _animator == null:
		return
	match state:
		State.FREE, State.APPROACH:
			var hspeed: float = Vector2(velocity.x, velocity.z).length()
			_animator.update_locomotion(hspeed, is_on_floor())
		_:
			pass


func _state_free(delta: float) -> void:
	if _handle_immediate_input():
		return
	var dir := _input_dir()
	var target_vel: Vector3 = dir * walk_speed
	var rate: float = acceleration if dir.length() > 0.001 else deceleration
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)
	if dir.length() > 0.001:
		_face_dir(dir, delta)
	if _manager != null:
		var act := _manager.combo.pop_valid(_can_start)
		if not act.is_empty():
			_start_action(act)


func _can_start(action: String) -> bool:
	return action == "attack" or action == "stun" or action == "special" or action == "takedown"


func _start_action(act: Dictionary) -> void:
	match String(act.get("action", "")):
		"attack":
			_begin_attack()
		"stun":
			_begin_stun()
		"special":
			_begin_special()
		"takedown":
			_begin_takedown()


func _begin_attack() -> void:
	_action_kind = "attack"

	# (Re)select the target at the start of EVERY new action, so a combo can
	# travel from enemy to enemy. The intent blends WASD, camera and facing, so
	# turning towards another enemy switches to it immediately, mid-combo.
	var enemies: Array = _manager.get_active_enemies() if _manager != null else []
	var threats = _manager.threats if _manager != null else null
	# A dead, already-freed target is not valid as the "current" of the selection
	# call (the parameter is typed, and passing a freed object errors out): it
	# counts as no target, and the chain still restarts because the selection
	# changed.
	var previous: Node3D = _target if is_instance_valid(_target) else null
	_target = CombatTargeting.select_target(self, _input_dir(), _camera_dir(), enemies, _config, previous, threats)

	# A dead combo (no confirmed hit for combo_keep_time) starts over at the first
	# hit; a live one keeps the chain going where it was.
	if _combo_window <= 0.0:
		_chain_index = 0

	# FreeFlow rule: a CONFIRMED change of target restarts the Sprint at jab, so
	# half a sequence is never carried over to another enemy. Only the next attack
	# is affected: the hit already running keeps its own target and its own clip,
	# and resolves its damage against that target alone.
	if _target != previous:
		_chain_index = 0

	if _attack_chain.is_empty():
		_attack = AttackData.new()
	else:
		_chain_index = clampi(_chain_index, 0, _attack_chain.size() - 1)
		_attack = _attack_chain[_chain_index]

	if _target != null and is_instance_valid(_target):
		if _flat_distance(_target) > _attack.ideal_distance:
			state = State.APPROACH
			_approach_timer = _config.approach_max_time
			return
	_start_windup()


func _start_windup() -> void:
	state = State.WINDUP
	_phase_timer = _attack.windup
	_hit_done = false
	# The clip starts with the action and runs at its own natural speed; the
	# phases above are aligned to the clip's measured impact instant.
	if _animator != null:
		_animator.notify_attack_started()
		_animator.play_action(_attack.animation, -1.0, _attack.speed)


func _state_windup(delta: float) -> void:
	_decelerate(delta)
	if _target != null and is_instance_valid(_target):
		_turn_towards(_flat_dir(_target), delta, _config.player_turn_speed)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		state = State.ACTIVE
		_phase_timer = _attack.active


func _state_active(delta: float) -> void:
	_decelerate(delta)
	if _target != null and is_instance_valid(_target):
		_turn_towards(_flat_dir(_target), delta, _config.player_turn_speed)
	if not _hit_done and _target != null and is_instance_valid(_target):
		if _flat_distance(_target) <= _attack.attack_range and _in_front(_target):
			_apply_hit(_target)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		state = State.RECOVERY
		_phase_timer = _attack.recovery


func _apply_hit(t: Node3D) -> void:
	_hit_done = true
	var dir := _flat_dir(t)
	if _action_kind == "takedown":
		if t.has_method("execute"):
			t.execute()
	elif t.has_method("take_hit"):
		t.take_hit(_attack.damage, dir, _attack.knockback, _attack.stun)
	if _manager != null:
		_manager.combo.register_hit()
		combo_changed.emit(_manager.combo.count)
	# The hit CONNECTED: the combo window is refreshed
	_combo_window = _config.combo_keep_time if _config != null else 2.0
	
	# --- MEJORA #3: Feedback AAA - Hitstop, Shake, FOV ---
	if _camera_rig != null:
		# Hitstop: 0.05s freeze en cada hit (Smash Bros feel)
		var is_finisher := _chain_index == _attack_chain.size() - 1
		var hitstop_dur := 0.08 if is_finisher else 0.05
		if _camera_rig.has_method("hitstop"):
			_camera_rig.hitstop(hitstop_dur)
		
		# Shake escalado por combo y por tipo de golpe
		var base_shake := 0.3 + float(_manager.combo.count) * 0.08
		if is_finisher:
			base_shake = 0.8
		if _action_kind == "special":
			base_shake = 1.0
		if _camera_rig.has_method("shake"):
			_camera_rig.shake(base_shake)
		
		# FOV punch: -4 normal, -8 finisher
		var fov_punch := -8.0 if is_finisher else -4.0
		if _action_kind == "special":
			fov_punch = -10.0
		if _camera_rig.has_method("punch_fov"):
			_camera_rig.punch_fov(fov_punch, 0.15 if is_finisher else 0.10)
	
	# Slowmo en finisher
	if _chain_index == _attack_chain.size() - 1 and _camera_rig != null and _camera_rig.has_method("slowmo"):
		_camera_rig.slowmo(0.25, 0.4)


func _state_recovery(delta: float) -> void:
	_decelerate(delta)
	# No orientation correction here: the hit already landed, so the body stays
	# committed to the direction it struck in and the impact keeps its weight.
	# The recovery is cancellable: as soon as a valid action is buffered (e.g.
	# the player mashed attack while steering towards another enemy) it chains
	# right away instead of waiting for the timer, which is what makes the combo
	# flow between enemies feel immediate.
	if _try_consume_buffered():
		return
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_end_action()


func _end_action() -> void:
	if _try_consume_buffered():
		return
	_chain_index = 0
	state = State.FREE


## Consumes a buffered action when one is valid and starts it immediately.
## Returns true when an action was started. Used both at the end of an action
## and from the recovery, so a queued attack flows into the next hit (possibly
## against a different enemy) instead of being dropped.
func _try_consume_buffered() -> bool:
	if _manager == null:
		return false
	var act := _manager.combo.pop_valid(_can_start)
	if act.is_empty():
		return false
	var a := String(act.get("action", ""))
	if a == "attack":
		_chain_index = (_chain_index + 1) % maxi(1, _attack_chain.size())
		_begin_attack()
	else:
		_start_action(act)
	return true


var _approach_stuck_time: float = 0.0
var _approach_sidestep_dir: int = 0 # -1 izq, 1 der, 0 ninguno

func _state_approach(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		state = State.FREE
		_approach_stuck_time = 0.0
		_approach_sidestep_dir = 0
		return
	if _target.has_method("is_alive") and not _target.is_alive():
		state = State.FREE
		_approach_stuck_time = 0.0
		_approach_sidestep_dir = 0
		return
	_turn_towards(_flat_dir(_target), delta, _config.player_turn_speed)
	var to: Vector3 = _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dirn: Vector3 = to.normalized() if dist > 0.001 else Vector3.ZERO
	var spd: float = _attack.approach_speed if _attack != null else _config.approach_speed
	
	# --- MEJORA #2: Pathfinding con sidestep si hay obstáculo ---
	var desired_vel := dirn * spd
	
	# Detectar si estamos trabados contra pared/banco/farola
	if is_on_wall():
		_approach_stuck_time += delta
		if _approach_stuck_time > 0.15: # 150ms trabado = intentar sidestep
			if _approach_sidestep_dir == 0:
				# Elegir dirección de sidestep: probar izq y der, quedarse con la que tiene más espacio
				var left := Vector3(-dirn.z, 0, dirn.x) # perpendicular izq
				var right := Vector3(dirn.z, 0, -dirn.x) # perpendicular der
				var left_free := not test_move(global_transform, left * 0.8)
				var right_free := not test_move(global_transform, right * 0.8)
				if left_free and not right_free:
					_approach_sidestep_dir = -1
				elif right_free and not left_free:
					_approach_sidestep_dir = 1
				elif left_free and right_free:
					# Elegir lado que más se acerca al target después del sidestep
					var left_pos := global_position + left * 0.8
					var right_pos := global_position + right * 0.8
					var left_dist := left_pos.distance_to(_target.global_position)
					var right_dist := right_pos.distance_to(_target.global_position)
					_approach_sidestep_dir = -1 if left_dist < right_dist else 1
				else:
					# Ambos bloqueados, intentar escalón como en ControladorLeo
					_intentar_escalon_approach(dirn)
			# Aplicar sidestep
			if _approach_sidestep_dir != 0:
				var sidestep := Vector3(-dirn.z, 0, dirn.x) * float(_approach_sidestep_dir)
				desired_vel = (dirn * 0.6 + sidestep * 0.8).normalized() * spd
				# Si llevamos 0.6s haciendo sidestep, resetear para reevaluar
				if _approach_stuck_time > 0.75:
					_approach_stuck_time = 0.0
					_approach_sidestep_dir = 0
	else:
		_approach_stuck_time = maxf(_approach_stuck_time - delta * 2.0, 0.0)
		if _approach_stuck_time < 0.05:
			_approach_sidestep_dir = 0
	
	velocity.x = move_toward(velocity.x, desired_vel.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, acceleration * delta)
	_approach_timer -= delta
	if _flat_distance(_target) <= _attack.ideal_distance:
		_start_windup()
		_approach_stuck_time = 0.0
		_approach_sidestep_dir = 0
	elif _approach_timer <= 0.0:
		state = State.FREE
		_approach_stuck_time = 0.0
		_approach_sidestep_dir = 0

## Intenta subir bordillo como en ControladorLeo (escalón 0.26m)
func _intentar_escalon_approach(dir_mov: Vector3) -> bool:
	var col := get_last_slide_collision()
	if col == null:
		return false
	var normal := col.get_normal()
	if absf(normal.y) >= 0.7:
		return false
	var altura := 0.26
	var avance := 0.4
	if test_move(global_transform, Vector3.UP * altura):
		return false
	var elevado := global_transform
	elevado.origin.y += altura
	if test_move(elevado, dir_mov * avance):
		return false
	var mundo := get_world_3d()
	if mundo == null:
		return false
	var desde := elevado.origin + dir_mov * avance + Vector3.UP * 0.05
	var q := PhysicsRayQueryParameters3D.create(desde, desde + Vector3.DOWN * (altura + 0.25))
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var golpe := mundo.direct_space_state.intersect_ray(q)
	if golpe.is_empty():
		return false
	var desnivel: float = (golpe["position"] as Vector3).y - global_position.y
	if desnivel <= 0.05 or desnivel > altura + 0.03:
		return false
	move_and_collide(Vector3.UP * (desnivel + 0.03))
	move_and_collide(dir_mov * avance)
	move_and_collide(Vector3.DOWN * (desnivel + 0.08))
	return true


func _state_hit(delta: float) -> void:
	_decelerate(delta)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		state = State.FREE


## Called by enemies. Reduces health, flashes the body, interrupts an attack
## in progress (breaking the combo) and triggers defeat at zero.
func take_damage(amount: float) -> void:
	if not _alive:
		return
	if _iframe_timer > 0.0:
		return  # dodge invulnerability window
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_flash_damage()
	# Impact feedback goes through the camera this character is already wired to,
	# so nothing has to be looked up globally.
	if _camera_rig != null and _camera_rig.has_method("shake"):
		_camera_rig.shake(0.5)
	if health <= 0.0:
		_die()
		return
	if state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY or state == State.APPROACH or state == State.COUNTER or state == State.EVADE:
		state = State.HIT
		_phase_timer = 0.25
		if _manager != null:
			_manager.combo.break_combo()
			combo_changed.emit(0)


## Red flash on damage. The feedback now lives on the skeletal model's own
## materials, since the placeholder capsule is hidden.
func _flash_damage() -> void:
	if _body_material != null:
		_body_material.albedo_color = Color(1.0, 0.3, 0.3)
	for m: StandardMaterial3D in _visual_materials:
		m.albedo_color = Color(1.0, 0.35, 0.35)
	_flash_timer = 0.12


func _restore_visual_tint() -> void:
	for i in _visual_materials.size():
		var m: StandardMaterial3D = _visual_materials[i]
		if is_instance_valid(m):
			m.albedo_color = _visual_base_colors[i]


func _die() -> void:
	_alive = false
	state = State.DEAD
	velocity.x = 0.0
	velocity.z = 0.0
	if _manager != null:
		_manager.combo.break_combo()
	died.emit()


# --- Helpers ---------------------------------------------------------------

func _input_dir() -> Vector3:
	var ix: float = _axis(action_move_left, action_move_right)
	var iy: float = _axis(action_move_forward, action_move_back)
	var v := Vector3.ZERO
	if _camera_rig != null:
		var b: Basis = _camera_rig.global_transform.basis
		var f: Vector3 = -b.z
		f.y = 0.0
		f = f.normalized()
		var r: Vector3 = b.x
		r.y = 0.0
		r = r.normalized()
		v = (f * -iy) + (r * ix)
	else:
		v = Vector3(ix, 0.0, iy)
	if v.length() > 1.0:
		v = v.normalized()
	return v


func _flat_dir(n: Node3D) -> Vector3:
	var to: Vector3 = n.global_position - global_position
	to.y = 0.0
	if to.length() > 0.001:
		return to.normalized()
	return Vector3.ZERO


func _flat_distance(n: Node3D) -> float:
	var to: Vector3 = n.global_position - global_position
	to.y = 0.0
	return to.length()


func _in_front(n: Node3D) -> bool:
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d := _flat_dir(n)
	return d.length() > 0.001 and fwd.dot(d) >= _config.attack_hit_arc


func _face_dir(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length() > 0.001:
		var target_yaw: float = atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


## Turns towards a direction at a capped angular rate (rad/s): quick enough to
## feel responsive, but never an instant 180 degree snap.
func _turn_towards(dir: Vector3, delta: float, rate: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var goal: float = atan2(-dir.x, -dir.z)
	var diff: float = wrapf(goal - rotation.y, -PI, PI)
	var max_step: float = maxf(0.0001, rate) * delta
	rotation.y = wrapf(rotation.y + clampf(diff, -max_step, max_step), -PI, PI)


## Horizontal forward of the camera rig (falls back to the body's facing).
func _camera_dir() -> Vector3:
	if _camera_rig != null:
		var f: Vector3 = -_camera_rig.global_transform.basis.z
		f.y = 0.0
		if f.length() > 0.001:
			return f.normalized()
	var b: Vector3 = -global_transform.basis.z
	b.y = 0.0
	return b.normalized()


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)


func _play_anim_windup() -> void:
	if _body == null:
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = create_tween()
	_anim_tween.tween_property(_body, "rotation:x", -0.25, maxf(0.05, _attack.windup))


func _play_anim_strike() -> void:
	if _body == null:
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = create_tween()
	_anim_tween.tween_property(_body, "rotation:x", 0.45, 0.07)
	_anim_tween.tween_property(_body, "rotation:x", 0.0, 0.18)


# --- Counter / evade / stun / special / takedown / gadget -------------------

func _handle_immediate_input() -> bool:
	if _just_pressed(action_counter):
		_try_counter()
		return true
	if _just_pressed(action_evade):
		_start_evade()
		return true
	if _just_pressed(action_gadget):
		_use_gadget()
	return false


# --- Input helpers ---------------------------------------------------------
# Every action is read by name so a target project can map the module onto the
# action names it already uses. A missing action is reported once by
# _warn_missing_actions() instead of flooding the console every frame.

func _axis(negative: StringName, positive: StringName) -> float:
	if not (InputMap.has_action(negative) and InputMap.has_action(positive)):
		return 0.0
	return Input.get_axis(negative, positive)


func _just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _try_counter() -> void:
	state = State.COUNTER
	_phase_timer = _config.counter_duration
	var dir: Vector3 = -global_transform.basis.z
	dir.y = 0.0
	if _manager != null:
		var threat: Dictionary = _manager.threats.find_counterable(global_position, dir, _config.counter_range, _config.counter_arc)
		if not threat.is_empty():
			var e = threat.enemy
			if is_instance_valid(e):
				_face_dir(_flat_dir(e), 1.0)
				if e.has_method("on_countered"):
					e.on_countered(_config.counter_stun)
				_manager.combo.register_hit()
				combo_changed.emit(_manager.combo.count)
	_play_anim_strike()


func _state_counter(delta: float) -> void:
	_decelerate(delta)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		state = State.FREE


func _state_evade(delta: float) -> void:
	velocity.x = _evade_dir.x * _config.evade_speed
	velocity.z = _evade_dir.z * _config.evade_speed
	_evade_timer -= delta
	if _evade_timer <= 0.0:
		state = State.FREE


func _start_evade() -> void:
	var d := _input_dir()
	if d.length() < 0.001:
		d = -global_transform.basis.z
		d.y = 0.0
		d = d.normalized()
	_evade_dir = d
	_evade_timer = _config.evade_duration
	_iframe_timer = _config.evade_iframes
	state = State.EVADE
	_face_dir(d, 1.0)


func _use_gadget() -> void:
	if _gadget_timer > 0.0 or _manager == null:
		return
	_gadget_timer = _config.gadget_cooldown
	for e in _manager.get_active_enemies():
		if e is Node3D and _flat_distance(e) <= _config.gadget_radius and e.has_method("take_hit"):
			e.take_hit(_config.gadget_damage, _flat_dir(e), 0.0, _config.gadget_stun)
	_play_anim_strike()


func _begin_stun() -> void:
	var d := AttackData.new()
	d.id = "stun"
	d.damage = _config.stun_attack_damage
	d.stun = _config.stun_attack_stun
	d.attack_range = _config.attack_range
	d.ideal_distance = _config.attack_ideal_distance
	d.approach_speed = _config.approach_speed
	d.windup = _config.stun_windup
	d.active = _config.stun_active
	d.recovery = _config.stun_recovery
	d.knockback = 0.0
	_begin_sequence(d, "stun")


func _begin_special() -> void:
	if _manager == null or _manager.combo.count < _config.special_min_combo:
		state = State.FREE
		return
	var d := AttackData.new()
	d.id = "special"
	d.damage = _config.special_damage
	d.attack_range = _config.attack_range + 0.4
	d.ideal_distance = _config.attack_ideal_distance
	d.approach_speed = _config.approach_speed
	d.windup = _config.special_windup
	d.active = _config.special_active
	d.recovery = _config.special_recovery
	d.knockback = _config.attack_knockback * 2.0
	_begin_sequence(d, "special")


func _begin_takedown() -> void:
	var victim := _find_stunned_target()
	if victim == null:
		state = State.FREE
		return
	_target = victim
	var d := AttackData.new()
	d.id = "takedown"
	d.attack_range = _config.takedown_range + 0.2
	d.ideal_distance = _config.attack_ideal_distance
	d.approach_speed = _config.approach_speed
	d.windup = _config.takedown_windup
	d.active = 0.12
	d.recovery = _config.takedown_recovery
	d.knockback = 0.0
	_begin_sequence(d, "takedown", true)


func _find_stunned_target() -> Node3D:
	if _manager == null:
		return null
	var best: Node3D = null
	var best_dist: float = INF
	for e in _manager.get_active_enemies():
		if not (e is Node3D):
			continue
		if e.has_method("is_stunned") and e.is_stunned() and _in_front(e):
			var d: float = _flat_distance(e)
			if d < best_dist:
				best_dist = d
				best = e
	return best


func _begin_sequence(data: AttackData, kind: String, keep_target: bool = false) -> void:
	_attack = data
	_action_kind = kind
	if not keep_target:
		var enemies: Array = _manager.get_active_enemies() if _manager != null else []
		var threats = _manager.threats if _manager != null else null
		var previo: Node3D = _target if is_instance_valid(_target) else null
		_target = CombatTargeting.select_target(self, _input_dir(), _camera_dir(), enemies, _config, previo, threats)
	if _target != null and is_instance_valid(_target) and _flat_distance(_target) > _attack.ideal_distance:
		state = State.APPROACH
		_approach_timer = _config.approach_max_time
		return
	_start_windup()
