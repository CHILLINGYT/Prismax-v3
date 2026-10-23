class_name CombatDamageNumbers
## Sistema de números de daño flotantes - Fase 3
## Muestra daño sobre enemigo con color por tipo y animación ascendente
## Uso: CombatDamageNumbers.spawn(parent, pos, cantidad, tipo)

static var _pool: Array[Label3D] = []
const POOL_SIZE := 20

static func _get_label(parent: Node3D) -> Label3D:
	# Reusa label del pool o crea nuevo
	for lbl in _pool:
		if is_instance_valid(lbl) and not lbl.visible:
			return lbl
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.fixed_size = true
	lbl.font_size = 48
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.no_depth_test = false
	lbl.visible = false
	_pool.append(lbl)
	if parent != null:
		parent.add_child(lbl)
	# Limitar pool
	if _pool.size() > POOL_SIZE:
		var old: Label3D = _pool.pop_front()
		if is_instance_valid(old):
			old.queue_free()
		_pool.append(lbl)
	return lbl

static func spawn(parent: Node3D, pos: Vector3, cantidad: float, tipo: String = "normal", es_critico: bool = false) -> void:
	if parent == null or cantidad <= 0.0:
		return
	
	var lbl := _get_label(parent)
	if lbl.get_parent() == null and parent != null:
		parent.add_child(lbl)
	elif lbl.get_parent() != parent and parent != null:
		lbl.reparent(parent)
	
	# Texto
	var texto := "%d" % int(round(cantidad))
	if es_critico:
		texto = "%s!" % texto
	
	lbl.text = texto
	lbl.global_position = pos + Vector3(randf_range(-0.3, 0.3), 1.8 + randf_range(0.0, 0.4), randf_range(-0.3, 0.3))
	lbl.visible = true
	lbl.modulate = Color(1,1,1,1)
	lbl.scale = Vector3.ONE * (1.4 if es_critico else 1.0)
	
	# Color por tipo
	match tipo:
		"light":
			lbl.modulate = Color(1, 1, 1, 1)
		"medium":
			lbl.modulate = Color(1, 0.9, 0.4, 1)
		"heavy":
			lbl.modulate = Color(1, 0.6, 0.2, 1)
		"finisher":
			lbl.modulate = Color(1, 0.25, 0.2, 1)
		"agua":
			lbl.modulate = Color(0.3, 0.7, 1.0, 1)
		"fuerza":
			lbl.modulate = Color(1.0, 0.5, 0.1, 1)
		"critico":
			lbl.modulate = Color(1, 0.9, 0.0, 1)
		_:
			lbl.modulate = Color(1, 1, 1, 1)
	
	if es_critico:
		lbl.modulate = Color(1, 0.9, 0.0, 1)
	
	var dur := 0.9 if not es_critico else 1.2
	var tween := parent.create_tween()
	tween.set_parallel(true)
	# Sube
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.2, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Escala pop
	if es_critico:
		tween.tween_property(lbl, "scale", Vector3.ONE * 1.6, 0.12).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(lbl, "scale", Vector3.ONE * 1.0, 0.2).set_ease(Tween.EASE_IN)
	# Fade out
	tween.tween_property(lbl, "modulate:a", 0.0, dur).set_delay(dur * 0.4)
	tween.chain().tween_callback(func(): lbl.visible = false)

## Versión que funciona sin parent (para enemigos)
static func spawn_on_enemy(enemigo: Node3D, cantidad: float, tipo: String = "normal", es_critico: bool = false) -> void:
	if enemigo == null:
		return
	var pos := enemigo.global_position
	if enemigo.has_method("get_hit_center"):
		pos = enemigo.call("get_hit_center")
	else:
		pos += Vector3.UP * 1.5
	var parent := enemigo.get_parent() as Node3D
	if parent == null:
		parent = enemigo as Node3D
	spawn(parent, pos, cantidad, tipo, es_critico)
