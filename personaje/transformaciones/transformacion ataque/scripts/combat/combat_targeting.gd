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

	# Cache space state once for occlusion checks (perf)
	var space_state: PhysicsDirectSpaceState3D = null
	if player.get_world_3d() != null:
		space_state = player.get_world_3d().direct_space_state

	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var enemy_node := e as Node3D
		var to_full: Vector3 = enemy_node.global_position - origin
		# --- MEJORA #1: Distancia 3D con peso Y=0.4 (como FuerzaCombat) ---
		# Permite targetear enemigos en barco/muelle sin que altura domine
		var to_flat := to_full
		to_flat.y *= 0.4
		var dist: float = to_flat.length()
		if dist > config.target_radius or dist < 0.001:
			continue
		
		# Para alignment usamos flat (intención horizontal del jugador)
		var to_dir_flat := to_full
		to_dir_flat.y = 0.0
		if to_dir_flat.length() < 0.001:
			continue
		to_dir_flat = to_dir_flat.normalized()
		var align: float = intent.dot(to_dir_flat)
		if align < cos_limit:
			continue

		# Altura: penalizar si diferencia > 2m (enemigo en techo, etc)
		var height_diff := absf(to_full.y)
		var height_penalty := 0.0
		if height_diff > 2.0:
			height_penalty = (height_diff - 2.0) * 0.15 # -0.15 por metro extra
			height_penalty = minf(height_penalty, 0.5)

		var threat: float = 0.0
		if threats != null:
			threat = threats.threat_level_for(e)

		var score: float = 0.0
		score += config.weight_alignment * ((align + 1.0) * 0.5)
		score += config.weight_distance * (1.0 - dist / config.target_radius)
		score += config.weight_threat * threat
		score -= height_penalty
		
		# --- MEJORA #2: Oclusión - penalizar enemigos detrás de paredes ---
		if space_state != null:
			var occlusion := _check_occlusion(space_state, player, enemy_node, origin)
			if occlusion > 0.0:
				score *= (1.0 - occlusion) # 0.7 si hay pared = -70%
		
		if current != null and e == current:
			score += config.current_target_bonus
			current_score = score
			current_valid = true

		if score > best_score:
			best_score = score
			best = e

	# Hysteresis: hold the current target unless a challenger clearly wins.
	if current_valid and best != current and (best_score - current_score) < config.target_switch_threshold:
		return current
	return best

## Raycast para detectar si hay pared entre jugador y enemigo
## Devuelve 0.0 = sin oclusión, 0.7 = pared bloqueando
static func _check_occlusion(space_state: PhysicsDirectSpaceState3D, player: Node3D, enemy: Node3D, origin: Vector3) -> float:
	if space_state == null:
		return 0.0
	var from := origin + Vector3.UP * 1.2 # pecho del jugador
	var to := enemy.global_position + Vector3.UP * 1.2 # pecho enemigo
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 # solo capa mundo (edificios, suelo)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	if enemy is CollisionObject3D:
		query.exclude.append((enemy as CollisionObject3D).get_rid())
	
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return 0.0
	
	# Hay algo en medio - verificar si está más cerca que el enemigo
	var hit_pos: Vector3 = result.get("position", to)
	var dist_to_hit := origin.distance_to(hit_pos)
	var dist_to_enemy := origin.distance_to(enemy.global_position)
	# Si el hit está a menos del 90% de la distancia al enemigo, es oclusión real
	if dist_to_hit < dist_to_enemy * 0.9:
		return 0.7 # penalización fuerte
	return 0.0