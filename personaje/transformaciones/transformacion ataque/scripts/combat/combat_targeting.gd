extends RefCounted

const CombatConfig = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_config.gd")
const ThreatSystem = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/threat_system.gd")

## Contextual target selection driven by player INTENT.
##
## The desired direction is a weighted blend of the WASD movement direction,
## the camera's horizontal forward and the character's current facing. Turning
## the camera and pushing towards an enemy therefore expresses "attack that one"
## and switches immediately, even mid-combo. Enemies are then scored by how well
## they align with that intent (dominant), their distance (complementary),
## active threats, and a small bonus for the enemy already targeted so
## near-equal candidates do not flip-flop.

static func _flat(v: Vector3) -> Vector3:
	var f := v
	f.y = 0.0
	if f.length() > 0.001:
		f = f.normalized()
	return f


## Weighted blend of the input signals that expresses where the player wants to
## go / what they want to hit.
static func intent_direction(player: Node3D, move_dir: Vector3, camera_dir: Vector3, config: CombatConfig) -> Vector3:
	var facing: Vector3 = _flat(-player.global_transform.basis.z)
	var intent: Vector3 = _flat(camera_dir) * config.weight_camera + facing * config.weight_facing
	var m: Vector3 = _flat(move_dir)
	if m.length() > 0.001:
		intent = m * config.weight_move_direction + intent
	intent.y = 0.0
	if intent.length() < 0.001:
		return facing
	return intent.normalized()


static func select_target(player: Node3D, move_dir: Vector3, camera_dir: Vector3, enemies: Array, config: CombatConfig, current: Node3D, threats: ThreatSystem = null) -> Node3D:
	if config == null:
		return null
	var origin: Vector3 = player.global_position
	var intent: Vector3 = intent_direction(player, move_dir, camera_dir, config)
	var cos_limit: float = cos(deg_to_rad(config.target_max_angle_deg * 0.5))

	var best: Node3D = null
	var best_score: float = -INF
	var current_score: float = -INF
	var current_valid: bool = false

	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var to: Vector3 = (e as Node3D).global_position - origin
		to.y = 0.0
		var dist: float = to.length()
		if dist > config.target_radius or dist < 0.001:
			continue
		var align: float = intent.dot(to / dist)
		if align < cos_limit:
			continue

		var threat: float = 0.0
		if threats != null:
			threat = threats.threat_level_for(e)

		var score: float = 0.0
		score += config.weight_alignment * ((align + 1.0) * 0.5)
		score += config.weight_distance * (1.0 - dist / config.target_radius)
		score += config.weight_threat * threat
		if current != null and e == current:
			score += config.current_target_bonus
			current_score = score
			current_valid = true

		if score > best_score:
			best_score = score
			best = e

	# Hysteresis: hold the current target unless a challenger clearly wins.
	# A real change of intent produces a large margin, so it still switches at
	# once; only near-equal candidates are filtered out.
	if current_valid and best != current and (best_score - current_score) < config.target_switch_threshold:
		return current
	return best