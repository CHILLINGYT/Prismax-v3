extends RefCounted

const CombatConfig = preload("res://personaje/transformaciones/ataque/scripts/combat/combat_config.gd")

## Distributes enemies on an even ring around the player so they surround and
## flank instead of piling onto the same point.
##
## Slot assignment is PERSISTENT: an enemy keeps its previous slot while it is
## still roughly in that direction, and only unassigned enemies take the nearest
## free slot. Rebuilding the assignment from scratch every frame made enemies at
## similar angles swap places continuously (visible jitter / oscillation), which
## is what made the group look like it was pushing itself around.

var _slots: Dictionary = {}   # enemy instance_id -> Vector3 world slot
var _assign: Dictionary = {}  # enemy instance_id -> slot index


func compute(enemies: Array, center: Vector3, config: CombatConfig) -> void:
	if config == null:
		_slots.clear()
		_assign.clear()
		return

	var entries: Array = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var off: Vector3 = (e as Node3D).global_position - center
		off.y = 0.0
		entries.append({
			"enemy": e,
			"id": e.get_instance_id(),
			"angle": atan2(off.z, off.x),
		})
	var n: int = entries.size()
	if n == 0:
		_slots.clear()
		_assign.clear()
		return

	# Deterministic order (angle, then instance id) so equal angles never swap.
	entries.sort_custom(func(a, b):
		if absf(a.angle - b.angle) > 0.0001:
			return a.angle < b.angle
		return a.id < b.id)

	# Rotate the even ring to match the current spread, so no enemy is ever
	# asked to travel across the player (which would push it into them).
	var offset: float = 0.0
	for i in n:
		offset += wrapf(entries[i].angle - TAU * (float(i) / float(n)), -PI, PI)
	offset /= float(n)

	var base_angles: Array = []
	for i in n:
		base_angles.append(TAU * (float(i) / float(n)) + offset)

	# Pass 1: keep the previous slot when it is still a sensible fit.
	var taken: Dictionary = {}
	var new_assign: Dictionary = {}
	var half_step: float = PI / float(n)
	for i in n:
		var id: int = entries[i].id
		if not _assign.has(id):
			continue
		var idx: int = int(_assign[id])
		if idx < 0 or idx >= n or taken.has(idx):
			continue
		if absf(wrapf(entries[i].angle - float(base_angles[idx]), -PI, PI)) <= half_step:
			taken[idx] = true
			new_assign[id] = idx

	# Pass 2: everyone else takes the nearest free slot.
	for i in n:
		var id: int = entries[i].id
		if new_assign.has(id):
			continue
		var best_idx: int = -1
		var best_err: float = INF
		for idx in n:
			if taken.has(idx):
				continue
			var err: float = absf(wrapf(entries[i].angle - float(base_angles[idx]), -PI, PI))
			if err < best_err:
				best_err = err
				best_idx = idx
		if best_idx < 0:
			continue
		taken[best_idx] = true
		new_assign[id] = best_idx

	_assign = new_assign
	_slots.clear()
	for i in n:
		var id: int = entries[i].id
		if not _assign.has(id):
			continue
		var angle: float = float(base_angles[int(_assign[id])])
		_slots[id] = center + Vector3(cos(angle), 0.0, sin(angle)) * config.formation_radius


func get_slot(enemy: Node) -> Vector3:
	if enemy == null or not is_instance_valid(enemy):
		return Vector3.ZERO
	return _slots.get(enemy.get_instance_id(), Vector3.ZERO)


func has_slot(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	return _slots.has(enemy.get_instance_id())