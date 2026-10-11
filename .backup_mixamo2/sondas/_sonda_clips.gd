extends Node
## Sonda temporal (no forma parte del juego).
##
## Mide, para CADA modelo Mixamo y CADA clip que el juego usa, la orientación que la pose produce
## respecto del eje +Z del modelo, más los datos de colocación (cadera y pies) de sentarse/tumbarse.
## Sirve para distinguir tres causas posibles de "camina de costado":
##   a) el modelo importado mira a otro lado (reposo),
##   b) el CLIP gira el cuerpo respecto del reposo (horneado),
##   c) el clip desplaza lateralmente la cadera (root motion).
## No toca nada del juego: sólo carga, mide e informa.

const LIB := "res://NPCs/Animations/Citizen_Animations_Mixamo.res"
const MODELOS: Array[String] = [
	"res://modelos 3d npcs/Ch01_nonPBR.fbx",
	"res://modelos 3d npcs/Ch02_nonPBR.fbx",
	"res://modelos 3d npcs/Ch12_nonPBR.fbx",
	"res://modelos 3d npcs/Ch13_nonPBR.fbx",
	"res://modelos 3d npcs/Ch17_nonPBR.fbx",
	"res://modelos 3d npcs/Ch26_nonPBR.fbx",
	"res://modelos 3d npcs/Ch33_nonPBR.fbx",
]
const CLIPS: Array[String] = ["walk_m1", "walk_f1", "walk_u1", "idle_m1", "jog_u1", "turn_l",
		"sit_idle", "lie_down"]


func _ready() -> void:
	_run()


func _run() -> void:
	var lib: AnimationLibrary = load(LIB)
	if lib == null:
		print("[Clips] no cargó ", LIB)
		get_tree().quit()
		return
	print("[Clips] clips en la librería: %d" % lib.get_animation_list().size())
	for ruta: String in MODELOS:
		var nombre := ruta.get_file()
		var esc := load(ruta) as PackedScene
		if esc == null:
			print("%s: NO CARGA" % nombre)
			continue
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
		if sk == null:
			print("%s: sin esqueleto" % nombre)
			continue
		print("")
		print("=== %s | raíz %s | esqueleto %s ===" % [nombre, _cadena_xf(modelo), _cadena_xf(sk)])
		var rest := _cuerpo(sk)
		print("  REPOSO    cuerpo %+6.1f°  pies %+6.1f°  cadera (x %+.3f y %+.3f z %+.3f)" % [
				rest["cuerpo"], rest["pies"], rest["x"], rest["y"], rest["z"]])
		for clip: String in CLIPS:
			var a: Animation = lib.get_animation(clip)
			if a == null:
				continue
			ap.play(clip)
			var cuerpos: Array[float] = []
			var pies: Array[float] = []
			var xs: Array[float] = []
			for f: float in [0.2, 0.45, 0.7]:
				ap.seek(a.length * f, true)
				await get_tree().process_frame
				var m := _cuerpo(sk)
				cuerpos.append(m["cuerpo"])
				pies.append(m["pies"])
				xs.append(m["x"])
				print("  %-7s t=%.2f  cuerpo %+6.1f°  pies %+6.1f°  cadera (x %+.3f y %+.3f z %+.3f)" % [
						clip, a.length * f, m["cuerpo"], m["pies"], m["x"], m["y"], m["z"]])
			print("            rango cuerpo %+.1f..%+.1f° | pies %+.1f..%+.1f° | cadera x %+.3f..%+.3f" % [
					cuerpos.min(), cuerpos.max(), pies.min(), pies.max(), xs.min(), xs.max()])
		holder.queue_free()
		await get_tree().process_frame
	print("[Clips] fin")
	get_tree().quit()


func _cadena_xf(n: Node) -> String:
	var t := (n as Node3D).transform if n is Node3D else Transform3D()
	var nodos: Array[String] = []
	var c := n
	while c is Node3D and c.get_parent() is Node3D:
		c = c.get_parent()
		nodos.append(String(c.name))
	return "esc %s rot %s | arriba: %s" % [
			str(t.basis.get_scale().snappedf(0.001)), str(t.basis.get_euler().snappedf(0.01)),
			str(nodos)]


## Mide la pose actual: hacia dónde mira el cuerpo y los pies (0° = +Z del modelo) y dónde está la
## cadera respecto del origen del modelo.
func _cuerpo(sk: Skeleton3D) -> Dictionary:
	var xf := sk.global_transform
	var lu := _h(sk, "mixamorig_LeftUpLeg")
	var ru := _h(sk, "mixamorig_RightUpLeg")
	var li := _h(sk, "mixamorig_LeftFoot")
	var ri := _h(sk, "mixamorig_RightFoot")
	var lt := _h(sk, "mixamorig_LeftToeBase")
	var rt := _h(sk, "mixamorig_RightToeBase")
	var cad := _h(sk, "mixamorig_Hips")
	var out := {"cuerpo": 0.0, "pies": 0.0, "x": 0.0, "y": 0.0, "z": 0.0}
	if cad >= 0:
		var p := (xf * sk.get_bone_global_pose(cad).origin) - sk.global_position
		out["x"] = p.x
		out["y"] = p.y
		out["z"] = p.z
	if lu >= 0 and ru >= 0:
		var lado := (xf * sk.get_bone_global_pose(lu).origin) - (xf * sk.get_bone_global_pose(ru).origin)
		lado.y = 0.0
		if lado.length_squared() > 0.000001:
			var frente: Vector3 = lado.normalized().cross(Vector3.UP)
			out["cuerpo"] = rad_to_deg(atan2(frente.x, frente.z))
	if li >= 0 and ri >= 0 and lt >= 0 and rt >= 0:
		var d := Vector3.ZERO
		d += (xf * sk.get_bone_global_pose(lt).origin) - (xf * sk.get_bone_global_pose(li).origin)
		d += (xf * sk.get_bone_global_pose(rt).origin) - (xf * sk.get_bone_global_pose(ri).origin)
		d.y = 0.0
		if d.length_squared() > 0.000001:
			out["pies"] = rad_to_deg(atan2(d.x, d.z))
	return out


func _h(sk: Skeleton3D, nombre: String) -> int:
	return sk.find_bone(nombre)


## Renombra huesos y bind names al prefijo canónico (misma regla que el juego).
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