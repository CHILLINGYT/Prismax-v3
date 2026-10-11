extends RefCounted

## Encounter-wide combo counter plus a short input buffer.
## The buffer stores just-pressed actions so a chain can be queued during an
## attack's cancel window and consumed when the current action ends.

var keep_time: float = 2.0
var buffer_time: float = 0.2
var count: int = 0
var timer: float = 0.0
var multiplier: float = 1.0

var _buffer: Array = []  # {action, dir, priority, life}


func _init(p_keep_time: float = 2.0, p_buffer_time: float = 0.2) -> void:
	keep_time = p_keep_time
	buffer_time = p_buffer_time


func register_hit() -> void:
	count += 1
	timer = keep_time


func break_combo() -> void:
	count = 0
	timer = 0.0


func update(dt: float) -> void:
	if timer > 0.0:
		timer -= dt
		if timer <= 0.0:
			count = 0
	for i in range(_buffer.size() - 1, -1, -1):
		_buffer[i].life -= dt
		if _buffer[i].life <= 0.0:
			_buffer.remove_at(i)


func push_input(action: String, dir: Vector3, priority: int) -> void:
	_buffer.append({"action": action, "dir": dir, "priority": priority, "life": buffer_time})


## Returns the highest-priority buffered entry that the given predicate accepts,
## consuming it. Empty Dictionary if nothing valid is buffered.
func pop_valid(is_valid: Callable) -> Dictionary:
	var best_idx: int = -1
	var best_priority: int = -2147483648
	for i in _buffer.size():
		if not is_valid.call(_buffer[i].action):
			continue
		var p: int = int(_buffer[i].priority)
		if p > best_priority:
			best_priority = p
			best_idx = i
	if best_idx < 0:
		return {}
	var chosen: Dictionary = _buffer[best_idx]
	_buffer.remove_at(best_idx)
	return chosen


func peek_buffer() -> Array:
	return _buffer