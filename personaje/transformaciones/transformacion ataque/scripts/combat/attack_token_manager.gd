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
## MEJORA #4: Ahora con prioridad por distancia y amenaza
func request(enemy: Node, priority: float = 0.0) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var id: int = enemy.get_instance_id()
	if _holders.has(id) and _holders[id].get_ref() == enemy:
		return true
	if not _queue.has(id):
		_queue[id] = {"ref": weakref(enemy), "since": Time.get_ticks_msec() / 1000.0, "priority": priority}
	else:
		# Actualizar prioridad si es mayor
		var existing: float = float(_queue[id].get("priority", 0.0))
		if priority > existing:
			_queue[id].priority = priority
	return false

func request_with_context(enemy: Node, player_pos: Vector3, threat_level: float = 0.0) -> bool:
	# Calcula prioridad automáticamente: más cerca + más amenaza = más prioridad
	if enemy == null or not (enemy is Node3D):
		return request(enemy, threat_level)
	var dist := (enemy as Node3D).global_position.distance_to(player_pos)
	var dist_priority := 0.0
	if dist < 10.0:
		dist_priority = (10.0 - dist) * 0.1 # 0.0 a 1.0
	var total_priority := threat_level * 2.0 + dist_priority
	return request(enemy, total_priority)


## Grants free tokens to the longest-waiting requests, so the turn rotates
## between enemies instead of always favouring the same ones.
## MEJORA: Ahora considera prioridad - enemigo cercano con alta amenaza puede robar token
func update() -> void:
	prune()
	# Primero intentar con prioridad
	while _holders.size() < max_tokens and not _queue.is_empty():
		var best_id: int = -1
		var best_score: float = -INF
		for id in _queue.keys():
			var since: float = float(_queue[id].since)
			var prio: float = float(_queue[id].get("priority", 0.0))
			# Score = prioridad alta + tiempo esperando (evita starvation)
			var wait_bonus := (Time.get_ticks_msec() / 1000.0 - since) * 0.05
			var score := prio + wait_bonus
			if score > best_score:
				best_score = score
				best_id = id
		if best_id < 0:
			break
		var obj: Object = _queue[best_id].ref.get_ref()
		_queue.erase(best_id)
		if obj == null or not is_instance_valid(obj):
			continue
		_holders[best_id] = weakref(obj)
	
	# Si todos los tokens están ocupados pero hay enemigo con prioridad muy alta en cola, robar
	if _holders.size() >= max_tokens and not _queue.is_empty() and _holders.size() > 0:
		var highest_queue_prio := -INF
		var highest_queue_id := -1
		for id in _queue.keys():
			var p: float = float(_queue[id].get("priority", 0.0))
			if p > highest_queue_prio:
				highest_queue_prio = p
				highest_queue_id = id
		
		if highest_queue_prio > 1.5: # umbral para robo
			# Buscar holder con menor prioridad (o sin prioridad)
			var lowest_holder_id := -1
			var lowest_holder_score := INF
			# No tenemos prioridad de holders, usar tiempo (el más reciente es menos prioritario)
			# Por simplicidad, liberar el más nuevo si cola tiene prioridad alta
			if highest_queue_prio > 2.0:
				# Liberar uno
				var holder_ids := _holders.keys()
				if not holder_ids.is_empty():
					var to_release_id: int = holder_ids[0]
					_holders.erase(to_release_id)


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