extends Node3D
## SONDA: mide el INSTANTE REAL DE CONTACTO de los 4 golpes del velocista
## (clips combo-1..4) muestreando la extensión hacia adelante del puño/pie que
## golpea, igual que se midió el contacto de las otras formas.
##
## Devuelve, por clip: duración, fracción y segundo del máximo avance del puño
## derecho (y del pie en los clips de patada) respecto al cuerpo.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"

func _ready() -> void:
	var jug := (load(JUGADOR) as PackedScene).instantiate() as CharacterBody3D
	add_child(jug)
	_piso()
	await get_tree().create_timer(0.8).timeout
	jug.call("_on_transformacion_elegida", &"velocista")
	var espera := 0
	while int(jug.get("forma")) != 1 and espera < 900:
		await get_tree().physics_frame
		espera += 1
	await get_tree().create_timer(0.3).timeout
	var combate: Node = jug.get_node_or_null("Combate")

	# El AnimationPlayer que tiene los clips del velocista.
	# Cada clip vive en su propia biblioteca, con el nombre del archivo como
	# biblioteca y "mixamo_com" dentro: el nombre real es "combo-1/mixamo_com".
	var ap: AnimationPlayer = null
	var clips: Dictionary = {}
	for a in jug.find_children("*", "AnimationPlayer", true, false):
		var p := a as AnimationPlayer
		var hallados := 0
		for nombre in p.get_animation_list():
			var s := String(nombre)
			for i in range(1, 5):
				if s.begins_with("combo-%d/" % i):
					clips["combo-%d" % i] = s
					hallados += 1
		if hallados > 0:
			ap = p
			break
	if ap == null or clips.size() != 4:
		print("[sonda] FALLO: no hallé los 4 combos en ningún AnimationPlayer")
		return
	print("[sonda] AnimationPlayer: ", ap.get_path(), " | clips: ", ap.get_animation_list().size())

	var esq := _esqueleto_del_animador(ap)
	if esq == null:
		print("[sonda] FALLO: sin Skeleton3D")
		return
	print("[sonda] Esqueleto: ", esq.get_path(), " | huesos: ", esq.get_bone_count())

	# Se lanzan ataques REALES encadenados (sin esperar al reinicio de 1,3 s) y se
	# mide la EXTENSIÓN de cada mano/pie respecto al torso: la parte que golpea es
	# la que más se aleja de su postura de reposo. El índice REAL del combo que
	# reporta el sistema etiqueta cada medición.
	var medidas: Dictionary = {}
	var intentos := 0
	while medidas.size() < 4 and intentos < 10:
		intentos += 1
		Input.action_press("atacar")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("atacar")
		await get_tree().physics_frame
		var idx := int(combate.golpe_actual())
		if idx < 1 or idx > 4:
			await get_tree().create_timer(1.2).timeout
			continue
		var clave := "combo-%d" % idx
		var nombre := String(clips.get(clave, ""))
		var largo := ap.get_animation(nombre).length
		var reloj := Time.get_ticks_msec()
		# Línea base de reposo (primeros fotogramas del clip) y luego el máximo.
		var base: Dictionary = {}
		var mejor: Dictionary = {}
		var veces_base := 0
		while Time.get_ticks_msec() - reloj < int(largo * 1000.0 * 0.92):
			await get_tree().process_frame
			var t := float(Time.get_ticks_msec() - reloj) / 1000.0
			var m := _medir(esq)
			if veces_base < 3:
				for h in m:
					base[h] = float(m[h])
				veces_base += 1
				continue
			for h in m:
				var ext := float(m[h]) - float(base.get(h, m[h]))
				if not mejor.has(h) or ext > float(mejor[h]):
					mejor[h] = ext
		# El hueso más extendido del golpe y el instante en que ocurrió.
		var hueso_top := ""
		var ext_top := -1e9
		for h in mejor:
			if float(mejor[h]) > ext_top:
				ext_top = float(mejor[h])
				hueso_top = h
		# Segundo pase sobre el mismo clip no: el instante del máximo se anota
		# también en el pase de medición (vuelta rápida, sólo del hueso ganador).
		medidas[idx] = {"clave": clave, "largo": largo, "hueso": hueso_top, "ext": ext_top}
		print("[sonda] %s | hueso más extendido %s (%.3f m sobre el reposo)" % [clave, hueso_top, ext_top])
		await get_tree().create_timer(0.25).timeout

	# Instante del contacto: se repite cada golpe midiendo el hueso ganador.
	for idx in range(1, 5):
		if not medidas.has(idx):
			continue
		var d: Dictionary = medidas[idx]
		var hueso := String(d["hueso"])
		var nombre := String(clips.get(String(d["clave"]), ""))
		var largo := float(d["largo"])
		Input.action_press("atacar")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("atacar")
		await get_tree().physics_frame
		var reloj := Time.get_ticks_msec()
		var base_ext := -1.0
		var mejor_ext := -1e9
		var mejor_t := 0.0
		while Time.get_ticks_msec() - reloj < int(largo * 1000.0 * 0.95):
			await get_tree().process_frame
			var t := float(Time.get_ticks_msec() - reloj) / 1000.0
			var m := _medir(esq)
			var e := float(m.get(hueso, 0.0))
			if base_ext < 0.0:
				base_ext = e
				continue
			var ext := e - base_ext
			if ext > mejor_ext:
				mejor_ext = ext
				mejor_t = t
		print("[sonda] %s | dur %.3f s | CONTACTO (máx. extensión de %s) %.3f m a %.3f s (u=%.3f)" % [
				d["clave"], largo, hueso, mejor_ext, mejor_t, mejor_t / maxf(largo, 0.0001)])
		await get_tree().create_timer(1.5).timeout
	ap.stop()
	print("[sonda] FIN")
	await get_tree().create_timer(0.3).timeout


## Distancia de cada mano/pie a su referencia del torso. La parte que golpea es la
## que MÁS crece respecto a su reposo: así el puño de un jab o el pie de una patada
## se detectan igual, sin que el balanceo de la cadera los falsee.
func _medir(esq: Skeleton3D) -> Dictionary:
	var r := {}
	var refs := {
		"mixamorig_RightHand": "mixamorig_Spine2",
		"mixamorig_LeftHand": "mixamorig_Spine2",
		"mixamorig_RightFoot": "mixamorig_Hips",
		"mixamorig_LeftFoot": "mixamorig_Hips",
	}
	for hueso in refs:
		var idx := esq.find_bone(hueso)
		var idx_ref := esq.find_bone(String(refs[hueso]))
		if idx < 0 or idx_ref < 0:
			continue
		var p := esq.global_transform * esq.get_bone_global_pose(idx)
		var c := esq.global_transform * esq.get_bone_global_pose(idx_ref)
		r[hueso] = p.origin.distance_to(c.origin)
	return r


func _esqueleto(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _esqueleto(c)
		if r != null:
			return r
	return null


## El esqueleto que anima ese AnimationPlayer: el Skeleton3D hermano suyo (el
## velocista tiene su propio modelo: Visual/Pose/Volteo/Modelo con AnimadorVelocista
## y Skeleton3D juntos). Nunca el de la forma humana, que no lleva estos clips.
func _esqueleto_del_animador(ap: AnimationPlayer) -> Skeleton3D:
	var padre := ap.get_parent()
	if padre != null:
		for c in padre.get_children():
			if c is Skeleton3D:
				return c as Skeleton3D
	return null


## Suelo con colisión (sin él el personaje cae y no puede golpear: el ataque sólo
## arranca con los pies apoyados).
func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(80, 0.5, 80)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.25, 0)
	add_child(cuerpo)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.5, 6.0)
	cam.current = true
	add_child(cam)