extends RefCounted

const CombatConfig = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_config.gd")

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

	entries.sort_custom(func(a, b):
		if absf(a.angle - b.angle) > 0.0001:
			return a.angle < b.angle
		return a.id < b.id)

	var offset: float = 0.0
	for i in n:
		offset += wrapf(entries[i].angle - TAU * (float(i) / float(n)), -PI, PI)
	offset /= float(n)

	# --- MEJORA: Radio dinámico + doble anillo para muchos enemigos ---
	var base_radius := config.formation_radius
	var dynamic_radius := base_radius
	if n > 4:
		dynamic_radius = base_radius + float(n - 4) * 0.35 # +0.35m por enemigo extra
		dynamic_radius = minf(dynamic_radius, base_radius + 2.5) # tope
	
	var inner_count := n
	var outer_count := 0
	var outer_radius := dynamic_radius + 1.8
	if n > 6:
		# Doble anillo: 4-5 cerca, resto lejos (evita amontonamiento)
		inner_count = 4 + int((n - 4) * 0.4) # 40% cerca
		outer_count = n - inner_count
	
	var base_angles_inner: Array = []
	for i in inner_count:
		base_angles_inner.append(TAU * (float(i) / float(inner_count)) + offset)
	
	var base_angles_outer: Array = []
	if outer_count > 0:
		for i in outer_count:
			# Offset de medio paso para que no queden alineados con inner
			base_angles_outer.append(TAU * (float(i) / float(outer_count)) + offset + PI / float(outer_count))

	var taken: Dictionary = {}
	var new_assign: Dictionary = {}
	var half_step: float = PI / float(maxi(n, 1))
	for i in n:
		var id: int = entries[i].id
		if not _assign.has(id):
			continue
		var idx: int = int(_assign[id])
		if idx < 0 or idx >= n or taken.has(idx):
			continue
		var expected_angle: float
		if idx < inner_count:
			expected_angle = float(base_angles_inner[idx])
		else:
			expected_angle = float(base_angles_outer[idx - inner_count])
		if absf(wrapf(entries[i].angle - expected_angle, -PI, PI)) <= half_step:
			taken[idx] = true
			new_assign[id] = idx

	for i in n:
		var id: int = entries[i].id
		if new_assign.has(id):
			continue
		var best_idx: int = -1
		var best_err: float = INF
		for idx in n:
			if taken.has(idx):
				continue
			var expected: float
			if idx < inner_count:
				expected = float(base_angles_inner[idx])
			else:
				expected = float(base_angles_outer[idx - inner_count])
			var err: float = absf(wrapf(entries[i].angle - expected, -PI, PI))
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
		var idx: int = int(_assign[id])
		var angle: float
		var radius: float
		if idx < inner_count:
			angle = float(base_angles_inner[idx])
			radius = dynamic_radius
		else:
			angle = float(base_angles_outer[idx - inner_count])
			radius = outer_radius
		_slots[id] = center + Vector3(cos(angle), 0.0, sin(angle)) * radius


func get_slot(enemy: Node) -> Vector3:
	if enemy == null or not is_instance_valid(enemy):
		return Vector3.ZERO
	return _slots.get(enemy.get_instance_id(), Vector3.ZERO)


func has_slot(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	return _slots.has(enemy.get_instance_id())