extends Node
## Sonda temporal: imprime posiciones crudas de huesos clave en cada pose para saber QUÉ parte del
## cuerpo queda girada. El frente se deduce de tres pares independientes:
##   pelvis  = LeftUpLeg  - RightUpLeg
##   hombros = LeftArm    - RightArm
##   manos   = LeftHand   - RightHand
## (0° = +Z del modelo, que es el frente del reposo).

const LIB := "res://NPCs/Animations/Citizen_Animations.res"
const MODELOS: Array[String] = ["res://modelos 3d npcs/Ch02_nonPBR.fbx",
		"res://modelos 3d npcs/Ch33_nonPBR.fbx"]
const POSES := [["walk_m1", 0.36], ["idle_m1", 1.22], ["sit_idle", 0.75], ["lie_down", 1.07]]
const HUESOS: Array[String] = ["mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
		"mixamorig_LeftArm", "mixamorig_RightArm", "mixamorig_LeftHand", "mixamorig_RightHand",
		"mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_Head"]


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
		_volcar(sk, "REPOSO", true)
		for p: Array in POSES:
			ap.play(String(p[0]))
			ap.seek(float(p[1]), true)
			await get_tree().process_frame
			_volcar(sk, String(p[0]), false)
		holder.queue_free()
		await get_tree().process_frame
	print("[Huesos] fin")
	get_tree().quit()


func _volcar(sk: Skeleton3D, etiqueta: String, imprimir_huesos: bool) -> void:
	var xf := sk.global_transform
	var p := {}
	for h: String in HUESOS:
		var i := sk.find_bone(h)
		p[h] = (xf * sk.get_bone_global_pose(i).origin) if i >= 0 else Vector3.ZERO
	if imprimir_huesos:
		for h: String in HUESOS:
			print("   %-24s x %+.3f  y %+.3f  z %+.3f" % [h, p[h].x, p[h].y, p[h].z])
	print("  %-9s pelvis %+6.1f°  hombros %+6.1f°  manos %+6.1f°" % [etiqueta,
			_frente(p["mixamorig_LeftUpLeg"], p["mixamorig_RightUpLeg"]),
			_frente(p["mixamorig_LeftArm"], p["mixamorig_RightArm"]),
			_frente(p["mixamorig_LeftHand"], p["mixamorig_RightHand"])])


func _frente(izq: Vector3, der: Vector3) -> float:
	var lado := izq - der
	lado.y = 0.0
	if lado.length_squared() < 0.000001:
		return 0.0
	var f: Vector3 = lado.normalized().cross(Vector3.UP)
	return rad_to_deg(atan2(f.x, f.z))


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