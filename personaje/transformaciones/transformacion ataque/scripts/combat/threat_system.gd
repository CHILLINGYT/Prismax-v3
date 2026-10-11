extends RefCounted

## Tracks enemy attack windups ("threats") so the player can react to them.
## Each threat records who is attacking, whether it is counterable, and how
## long remains before the impact.

var _threats: Array = []


func register(enemy: Node, attack_type: String = "melee", windup: float = 0.4, counterable: bool = true) -> void:
	clear_for(enemy)
	_threats.append({
		"enemy": enemy,
		"type": attack_type,
		"time_left": windup,
		"total": windup,
		"counterable": counterable,
	})


func clear_for(enemy: Node) -> void:
	for i in range(_threats.size() - 1, -1, -1):
		if _threats[i].enemy == enemy:
			_threats.remove_at(i)


func update(dt: float) -> void:
	for i in range(_threats.size() - 1, -1, -1):
		var t: Dictionary = _threats[i]
		if not is_instance_valid(t.enemy):
			_threats.remove_at(i)
			continue
		t.time_left -= dt
		if t.time_left <= 0.0:
			_threats.remove_at(i)


func get_active() -> Array:
	return _threats


func threat_level_for(enemy: Node) -> float:
	for t in _threats:
		if t.enemy == enemy:
			return 1.0
	return 0.0


## Returns the most imminent counterable threat that lies within max_dist and in
## front of the player (dot >= min_arc). Empty Dictionary if none qualifies, so
## a counter pressed too early / too late / facing the wrong way simply whiffs.
func find_counterable(player_pos: Vector3, dir: Vector3, max_dist: float, min_arc: float) -> Dictionary:
	var d: Vector3 = dir
	d.y = 0.0
	if d.length() < 0.001:
		return {}
	d = d.normalized()
	var best: Dictionary = {}
	var best_time: float = INF
	for t in _threats:
		if not bool(t.counterable):
			continue
		var e: Node = t.enemy
		if not is_instance_valid(e):
			continue
		var to: Vector3 = (e as Node3D).global_position - player_pos
		to.y = 0.0
		var dist: float = to.length()
		if dist > max_dist or dist < 0.001:
			continue
		if d.dot(to / dist) < min_arc:
			continue
		if float(t.time_left) < best_time:
			best_time = float(t.time_left)
			best = t
	return best