extends Node
## Sonda temporal: orientación REAL de los huesos clave (basis en mundo) en reposo y en cada pose,
## más la dirección de avance que implica el ciclo de marcha (desplazamiento del pie de apoyo).
## Con esto se sabe si lo torcido es el modelo, la pelvis o el torso, y hacia dónde "camina" el clip.

const LIB := "res://NPCs/Animations/Citizen_Animations.res"
const MODELOS: Array[String] = ["res://modelos 3d npcs/Ch02_nonPBR.fbx",
		"res://modelos 3d npcs/Ch33_nonPBR.fbx"]


func _ready() -> void:
	_run()


func _run() -> void:
	var lib: AnimationLibrary = load(LIB)
	for ruta: String in MODELOS:
		var esc := load(ruta) as PackedScene
		var modelo := esc.instantiate()
		modelo.name = "Model"
		_normalizar(modelo)
		for n in modelo.find_children("*", "AnimationPlayer", true, false):
			(n as AnimationPlayer).stop()
			n.get_parent().remove_child(n)
			n.queue_free()
		var holder := Node3D.new()
		get_tree().root.add_child(holder)
		holder.add_child(modelo)
		var ap := AnimationPlayer.new()
		holder.add_child(ap)
		ap.add_animation_library("", lib)
		var sk := modelo.find_child("Skeleton3D", true, false) as Skeleton3D
		await get_tree().process_frame
		print("")
		print("########## %s ##########" % ruta.get_file())
		for h: String in ["mixamorig_Hips", "mixamorig_Spine1", "mixamorig_Spine2",
				"mixamorig_Head", "mixamorig_LeftUpLeg"]:
			var i := sk.find_bone(h)
			var r := sk.get_bone_rest(i)
			var dir := Vector3.ZERO
			for c in sk.get_children():
				pass
			print("   reposo %-22s origen %s  basis X %s Y %s Z %s" % [h,
					str(r.origin.snappedf(0.001)), str(r.basis.x.snappedf(0.01)),
					str(r.basis.y.snappedf(0.01)), str(r.basis.z.snappedf(0.01))])
		print("  --- REPOSO ---")
		_ejes(sk)
		for p: Array in [["walk_m1", 0.36], ["walk_m1", 0.9], ["idle_m1", 1.22],
				["sit_idle", 0.75], ["lie_down", 1.07]]:
			ap.play(String(p[0]))
			ap.seek(float(p[1]), true)
			await get_tree().process_frame
			print("  --- %s t=%.2f ---" % [String(p[0]), float(p[1])])
			_ejes(sk)
		# Dirección de avance implícita: se sigue al pie más bajo durante el ciclo de caminar.
		ap.play("walk_m1")
		var largo := lib.get_animation("walk_m1").length
		var prev := {}
		var suma := Vector3.ZERO
		for k in 13:
			ap.seek(largo * float(k) / 12.0, true)
			await get_tree().process_frame
			var m := _pies(sk)
			if not prev.is_empty() and String(prev["lado"]) == String(m["lado"]):
				var d: Vector3 = (m["pos"] as Vector3) - (prev["pos"] as Vector3)
				d.y = 0.0
				suma += d
			prev = m
		if suma.length_squared() > 0.000001:
			print("  marcha: el pie apoyado retrocede %s → la animación avanza hacia %+.1f° (0° = +Z)" % [
					str(suma.snappedf(0.001)), rad_to_deg(atan2(-suma.x, -suma.z))])
		holder.queue_free()
		await get_tree().process_frame
	print("[Ejes] fin")
	get_tree().quit()


func _pies(sk: Skeleton3D) -> Dictionary:
	var xf := sk.global_transform
	var izq := _p(sk, xf, "mixamorig_LeftToeBase")
	var der := _p(sk, xf, "mixamorig_RightToeBase")
	if izq.y <= der.y:
		return {"lado": "L", "pos": izq}
	return {"lado": "R", "pos": der}


func _p(sk: Skeleton3D, xf: Transform3D, h: String) -> Vector3:
	var i := sk.find_bone(h)
	return (xf * sk.get_bone_global_pose(i).origin) if i >= 0 else Vector3.ZERO


func _ejes(sk: Skeleton3D) -> void:
	for h: String in ["mixamorig_Hips", "mixamorig_Spine1", "mixamorig_Spine2",
			"mixamorig_Head", "mixamorig_LeftUpLeg", "mixamorig_LeftFoot"]:
		var i := sk.find_bone(h)
		if i < 0:
			continue
		var b := (sk.global_transform * sk.get_bone_global_pose(i)).basis
		print("     %-22s X %s (yaw %+6.1f°)  Y %s  Z %s (yaw %+6.1f°)" % [h,
				str(b.x.snappedf(0.01)), rad_to_deg(atan2(b.x.x, b.x.z)),
				str(b.y.snappedf(0.01)), str(b.z.snappedf(0.01)),
				rad_to_deg(atan2(b.z.x, b.z.z))])


func _normalizar(modelo: Node) -> void:
	var sk := modelo.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	for i in sk.get_bone_count():
		var n := _canonico(String(sk.get_bone_name(i)))
		if n != "":
			sk.set_bone_name(i, n)
	for nodo in modelo.find_children("*", "MeshInstance3D", true, false):
		var piel: Skin = (nodo as MeshInstance3D).skin
		if piel == null:
			continue
		for b in piel.get_bind_count():
			var n2 := _canonico(piel.get_bind_name(b))
			if n2 != "":
				piel.set_bind_name(b, n2)


func _canonico(nombre: String) -> String:
	if not nombre.begins_with("mixamorig"):
		return ""
	var pos := nombre.find("_")
	if pos <= 0:
		return ""
	var canon := "mixamorig_" + nombre.substr(pos + 1)
	return canon if nombre != canon else ""