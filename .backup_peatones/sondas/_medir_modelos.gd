extends Node
## Sonda de POSTURA (temporal, no forma parte del juego): monta cada modelo PSX con su ciudadano,
## le pone la pose de caminar y mide con números lo que a ojo no se ve:
##   - inclinación de la espalda (caderas -> cabeza respecto a la vertical): encorvado si es alta.
##   - giro de la cabeza respecto a la dirección de los pies: "cabeza torcida" si es alto.
##   - orientación del cuerpo: hacia dónde apuntan los pies en el espacio del ciudadano.
## Se mide en reposo y con la animación de caminar puesta. No escribe nada del juego.

const DIR_PSX := "res://NPCs/Characters/PSX/"
const ESCENA := "res://NPCs/Scenes/NPC_Citizen.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var escena: PackedScene = load(ESCENA)
	var raiz := Node3D.new()
	add_child(raiz)
	var filas: Array[String] = []
	for sexo: String in ["Male", "Female"]:
		var nombres: Array[String] = []
		for f in DirAccess.get_files_at(DIR_PSX + sexo + "/"):
			if f.ends_with(".fbx") and f != "Character_Female_01.fbx":
				nombres.append(f)
		nombres.sort()
		for n in nombres:
			var c2: Node = escena.instantiate()
			c2.set("model_scene", load(DIR_PSX + sexo + "/" + n))
			c2.set("body_type", "female" if sexo == "Female" else "male")
			c2.set("vary_model_parts", false)
			raiz.add_child(c2)
			c2.set_physics_process(false)
			await get_tree().process_frame
			var sk: Skeleton3D = (c2 as Node).find_child("Skeleton3D", true, false) as Skeleton3D
			if sk == null:
				filas.append("%-4s %-30s SIN ESQUELETO" % [sexo, n])
				raiz.remove_child(c2)
				c2.queue_free()
				continue
			var reposo := _medir(sk)
			# Pose de caminar: misma vía que en el juego (AnimationTree del ciudadano).
			var arboles := c2.find_children("*", "AnimationTree", true, false)
			if not arboles.is_empty():
				var arbol: AnimationTree = arboles[0]
				arbol.active = true
				var pb := arbol.get("parameters/playback") as AnimationNodeStateMachinePlayback
				pb.travel("walk")
				for i in 40:
					await get_tree().process_frame
			var andando := _medir(sk)
			var estab := c2.find_child("EstabilizaCabeza", true, false)
			var cola := ""
			if estab != null:
				cola = "  [estab: gira %6.1f° deja %.1f° activo=%s]" % [estab.ultimo,
						estab.giro_actual(), str(estab.activo)]
			if andando["cara"] > 18.0 or andando["espalda"] > 14.0:
				cola += "  <-- REVISAR"
			print("[Postura] %-4s %-30s reposo: pecho %5.1f° cuello %5.1f° cara %6.1f° pies %6.1f° | andando: pecho %5.1f° cuello %5.1f° cara %6.1f°%s" % [
					sexo, n, reposo["espalda"], reposo["cuello"], reposo["cara"], reposo["pies"],
					andando["espalda"], andando["cuello"], andando["cara"], cola])
			raiz.remove_child(c2)
			c2.queue_free()
	print("[Postura] fin")
	get_tree().quit()


## Devuelve, en grados: inclinación del pecho (caderas->Spine2 vs vertical), inclinación del
## cuello/cabeza (Spine2->cabeza), giro de la cara respecto a la cadera (referencia robusta: el
## vaivén de brazos y piernas no la contamina) y hacia dónde apuntan los pies en reposo.
func _medir(sk: Skeleton3D) -> Dictionary:
	var out := {"espalda": 0.0, "cuello": 0.0, "cara": 0.0, "pies": 0.0, "vacio": true}
	var i_cad := _hueso(sk, ["mixamorig_Hips", "root.x", "B_Pelvis"])
	var i_pecho := _hueso(sk, ["mixamorig_Spine2", "spine_03.x", "B_Spine2"])
	var i_cab := _hueso(sk, ["mixamorig_Head", "head.x", "B_Head"])
	var i_pie := _hueso(sk, ["mixamorig_LeftFoot", "foot.l", "B_L_Foot"])
	var i_dedo := _hueso(sk, ["mixamorig_LeftToeBase", "toes_01.l", "B_L_Toe0"])
	if i_cad < 0 or i_cab < 0 or i_pie < 0 or i_dedo < 0:
		return out
	var arriba := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var cad := sk.get_bone_global_pose(i_cad).origin
	var cab := sk.get_bone_global_pose(i_cab).origin
	# Inclinación del pecho (lo que se ve como "encorvado") y del conjunto cuello-cabeza.
	var tronco := cad
	if i_pecho >= 0:
		tronco = sk.get_bone_global_pose(i_pecho).origin
		out["espalda"] = rad_to_deg((tronco - cad).normalized().angle_to(arriba))
		out["cuello"] = rad_to_deg((cab - tronco).normalized().angle_to(arriba))
	else:
		out["espalda"] = rad_to_deg((cab - cad).normalized().angle_to(arriba))
	# Referencia de dirección del cuerpo: la cadera (casi no gira al andar). El "hacia delante"
	# se mide en REPOSO y se guarda en el marco local de la cadera, así vale para cualquier pose.
	var pies_rest := sk.get_bone_global_rest(i_dedo).origin - sk.get_bone_global_rest(i_pie).origin
	pies_rest -= arriba * pies_rest.dot(arriba)
	if pies_rest.length_squared() < 0.000001:
		return out
	pies_rest = pies_rest.normalized()
	var cad_rest := sk.get_bone_global_rest(i_cad).basis
	var fwd_local := cad_rest.inverse() * pies_rest
	var cuerpo := (sk.get_bone_global_pose(i_cad).basis * fwd_local)
	cuerpo -= arriba * cuerpo.dot(arriba)
	if cuerpo.length_squared() < 0.000001:
		return out
	cuerpo = cuerpo.normalized()
	# Cara de la cabeza: su eje local más alineado con el "hacia delante" en reposo.
	var cab_rest := sk.get_bone_global_rest(i_cab).basis
	var cara_local := Vector3.FORWARD
	var mejor := -2.0
	for eje: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var d := (cab_rest * eje).normalized()
		var plano := d - arriba * d.dot(arriba)
		if plano.length_squared() < 0.000001:
			continue
		var val := plano.normalized().dot(pies_rest)
		if val > mejor:
			mejor = val
			cara_local = eje
	var cara := (sk.get_bone_global_pose(i_cab).basis * cara_local)
	cara -= arriba * cara.dot(arriba)
	if cara.length_squared() < 0.000001:
		return out
	cara = cara.normalized()
	out["cara"] = rad_to_deg(cuerpo.signed_angle_to(cara, arriba))
	out["pies"] = rad_to_deg(cuerpo.signed_angle_to(pies_rest, arriba))
	out["vacio"] = false
	return out


func _hueso(sk: Skeleton3D, candidatos: Array) -> int:
	for c: String in candidatos:
		var i := sk.find_bone(c)
		if i >= 0:
			return i
	return -1