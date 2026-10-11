extends Node
## Sonda temporal: mide en MUNDO los huesos de ciudadanos que CAMINAN y compara con la
## altura de la red (suelo) y con la caja de la malla, para detectar cuerpos hundidos.

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	Engine.time_scale = 6.0
	_run.call_deferred()


func _run() -> void:
	while _dir == null:
		await get_tree().process_frame
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	print("[SondaAndar] director listo")
	await get_tree().create_timer(3.0).timeout
	var ciudadanos: Array = _dir.get("peatones")
	print("[SondaAndar] ciudadanos en la lista: %d" % ciudadanos.size())
	var caminando := 0
	for c in ciudadanos:
		if c != null and is_instance_valid(c) and c.is_walking():
			caminando += 1
	print("[SondaAndar] caminando ahora: %d" % caminando)
	var vistos := 0
	for c in ciudadanos:
		if c == null or not is_instance_valid(c):
			continue
		if not c.is_walking():
			continue
		_mide(c)
		vistos += 1
		if vistos >= 4:
			break
	print("[SondaAndar] fin (%d medidos)" % vistos)


func _mide(c: Node) -> void:
	var nodo := c as Node3D
	var sk: Skeleton3D = null
	for s in nodo.find_children("*", "Skeleton3D", true, false):
		sk = s
		break
	var red := float(c.call("_altura_red", nodo.global_position))
	print("")
	print("=== %s · clip %s · camina=%s ===" % [nodo.name, str(c.get("_active_clip")), str(c.is_walking())])
	print("  nodo mundo %s | escala %s" % [str(nodo.global_position), str(nodo.scale)])
	print("  altura de red %.3f | nodo.y − red = %+.3f" % [red, nodo.global_position.y - red])
	if sk == null:
		print("  (sin esqueleto)")
		return
	print("  esqueleto: %d huesos | escala mundo %s" % [sk.get_bone_count(), str(sk.global_transform.basis.get_scale())])
	for nombre in ["mixamorig_Hips", "mixamorig_Spine1", "mixamorig_Head", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
		var idx := sk.find_bone(nombre)
		if idx < 0:
			print("    %-24s NO EXISTE" % nombre)
			continue
		var mundo := sk.global_transform * sk.get_bone_global_pose(idx)
		print("    %-24s y=%+.3f (sobre red %+.3f) | rest local y %.3f" % [
				nombre, mundo.origin.y, mundo.origin.y - red, sk.get_bone_rest(idx).origin.y])
	var ab := _aabb_mundo(sk)
	if ab.size.y > 0.0:
		print("  malla: y de %+.3f a %+.3f (alto %.3f) | base sobre red %+.3f" % [
				ab.position.y, ab.end.y, ab.size.y, ab.position.y - red])


func _aabb_mundo(sk: Skeleton3D) -> AABB:
	var total := AABB()
	var primera := true
	for h in sk.get_children():
		if h is MeshInstance3D and (h as MeshInstance3D).mesh != null:
			var ab: AABB = (h as MeshInstance3D).get_aabb()
			total = ab if primera else total.merge(ab)
			primera = false
	if primera:
		return AABB()
	return sk.global_transform * total