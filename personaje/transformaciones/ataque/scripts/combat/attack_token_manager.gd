extends RefCounted

## Limits how many enemies may execute an offensive attack at the same time.

var max_tokens: int = 2
var _holders: Dictionary = {}  # instance_id -> WeakRef(enemy)
var _queue: Dictionary = {}    # instance_id -> {"ref": WeakRef, "since": float}


func _init(p_max_tokens: int = 2) -> void:
	max_tokens = maxi(1, p_max_tokens)


func prune() -> void:
	var dead_ids: Array = []
	for id in _holders.keys():
		var ref: WeakRef = _holders[id]
		var obj: Object = ref.get_ref()
		if obj == null or not is_instance_valid(obj):
			dead_ids.append(id)
	for id in dead_ids:
		_holders.erase(id)
	dead_ids.clear()
	for id in _queue.keys():
		var ref2: WeakRef = _queue[id].ref
		var obj2: Object = ref2.get_ref()
		if obj2 == null or not is_instance_valid(obj2):
			dead_ids.append(id)
	for id in dead_ids:
		_queue.erase(id)


## Registers interest in attacking. Returns true only if this enemy already
## holds a token; otherwise the request waits in the queue until update()
## grants it. Re-requesting does NOT lose the original waiting time, so a
## patient enemy keeps its place in line.
func request(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var id: int = enemy.get_instance_id()
	if _holders.has(id) and _holders[id].get_ref() == enemy:
		return true
	if not _queue.has(id):
		_queue[id] = {"ref": weakref(enemy), "since": Time.get_ticks_msec() / 1000.0}
	return false


## Grants free tokens to the longest-waiting requests, so the turn rotates
## between enemies instead of always favouring the same ones.
func update() -> void:
	prune()
	while _holders.size() < max_tokens and not _queue.is_empty():
		var best_id: int = -1
		var best_since: float = INF
		for id in _queue.keys():
			var since: float = float(_queue[id].since)
			if since < best_since:
				best_since = since
				best_id = id
		if best_id < 0:
			break
		var obj: Object = _queue[best_id].ref.get_ref()
		_queue.erase(best_id)
		if obj == null or not is_instance_valid(obj):
			continue
		_holders[best_id] = weakref(obj)


## Withdraws a pending request (used when the enemy no longer wants to attack).
func cancel(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_queue.erase(enemy.get_instance_id())


func release(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	cancel(enemy)
	return _holders.erase(enemy.get_instance_id())


func has_token(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var id: int = enemy.get_instance_id()
	if not _holders.has(id):
		return false
	return _holders[id].get_ref() == enemy


func count_used() -> int:
	prune()
	return _holders.size()


func count_available() -> int:
	return maxi(0, max_tokens - count_used())