extends Node3D
## Sonda temporal: mide en MUNDO los huesos de un ciudadano que camina y los compara
## con la altura de la red/suelo y con el bounding box de su malla.

var _dir: Node
var _t := 0.0

func _ready() -> void:
	_dir = get_node_or_null("../../CiudadGenerada/Peatones")
	if _dir == null:
		var r: Node = get_tree().current_scene
		for n in r.find_children("*", "DirectorPeatones", true, false):
			_dir = n
			break
	print("[DiagAndar] director: ", _dir)

func _process(delta: float) -> void:
	_t += delta
	if _t < 4.0:
		return
	set_process(false)
	_correr()

func _correr() -> void:
	var ciudadanos: Array = _dir.get("_ciudadanos")
	var n_muestra := 0
	for c in ciudadanos:
		if c == null or not is_instance_valid(c):
			continue
		if not c.is_walking():
			continue
		var nodo := c as Node3D
		var sk := _esqueleto(nodo)
		print("")
		print("=== ", nodo.name, " (andando, fase %s) ===" % str(c.get("_postura_fase")))
		print("  nodo global  %s  scale %s" % [str(nodo.global_position), str(nodo.scale)])
		print("  clip activo  %s" % str(c.get("_active_clip")))
		print("  altura de red (suelo esperado) %.3f | nodo.y %.3f | diferencia %.3f" % [
				_c_float(c, "_altura_red"), nodo.global_position.y,
				nodo.global_position.y - _c_float(c, "_altura_red")])
		if sk != null:
			print("  esqueleto global scale %s" % str(sk.global_transform.basis.get_scale()))
			for nombre in ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_Spine1"]:
				var idx := sk.find_bone(nombre)
				if idx < 0:
					print("    %s: NO EXISTE" % nombre)
					continue
				var m := sk.global_transform * sk.get_bone_global_pose(idx)
				var r := sk.get_bone_rest(idx)
				print("    %-22s mundo %s  (rest local y %.3f)" % [nombre, str(m.origin), r.origin.y])
			var ab := _aabb_mundo(sk)
			print("  malla AABB mundo  y de %.3f a %.3f | x de %.3f a %.3f | z de %.3f a %.3f" % [
					ab.position.y, ab.end.y, ab.position.x, ab.end.x, ab.position.z, ab.end.z])
			print("  → alto de la malla %.3f | pies %.3f respecto de la red %.3f" % [
					ab.size.y, ab.position.y - _c_float(c, "_altura_red"),
					_c_float(c, "_altura_red")])
		n_muestra += 1
		if n_muestra >= 3:
			break

func _c_float(c: Node, prop: String) -> float:
	var v: Variant = c.get(prop)
	return float(v) if v != null else 0.0

func _esqueleto(n: Node) -> Skeleton3D:
	for s in n.find_children("*", "Skeleton3D", true, false):
		return s
	return null

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
	# El AABB de una malla esqueletada viene en espacio esqueleto; lo pasamos a mundo.
	return sk.global_transform * total