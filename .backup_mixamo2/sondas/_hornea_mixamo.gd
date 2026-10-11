extends Node
## Sonda/herramienta temporal: comprueba el reposo del rig PSX (destino de la librería vieja) y
## hornea la librería nueva contra el rig de los modelos Mixamo que usa el juego ahora.

func _ready() -> void:
	_reposo_psx()
	await get_tree().process_frame
	var reporte: Array[String] = NPCAnimationBaker.build_mixamo()
	print("================ INFORME DEL HORNEADO ================")
	for linea in reporte:
		print("  ", linea)
	print("=====================================================")
	get_tree().quit()


func _reposo_psx() -> void:
	var esc := load("res://NPCs/Characters/PSX/Male/Character_01.fbx") as PackedScene
	if esc == null:
		print("[PSX] no carga el rig viejo")
		return
	var m := esc.instantiate()
	var sk := m.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		print("[PSX] sin esqueleto")
		return
	print("[PSX] %d huesos · primeros %s, %s" % [sk.get_bone_count(), sk.get_bone_name(0), sk.get_bone_name(1)])
	for h: String in ["mixamorig_Hips", "mixamorig_Spine1", "mixamorig_Head", "mixamorig_LeftUpLeg"]:
		var i := sk.find_bone(h)
		if i < 0:
			print("[PSX] %s no existe (¿nombres distintos?)" % h)
			continue
		var r := sk.get_bone_rest(i)
		print("[PSX] %-22s reposo X %s  Y %s  Z %s" % [h, str(r.basis.x.snappedf(0.01)),
				str(r.basis.y.snappedf(0.01)), str(r.basis.z.snappedf(0.01))])
	m.free()