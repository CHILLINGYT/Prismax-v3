extends Node3D
## SONDA v2: mide el INSTANTE REAL DE CONTACTO de los 4 golpes del velocista
## (clips combo-1..4) con el flujo de verdad: pulsaciones de la tecla de ataque
## encadenadas (cada ~1,0 s, dentro de la ventana de combo de 1,3 s) y muestreo de
## la EXTENSIÓN de cada mano/pie respecto a su referencia del torso (la parte que
## golpea es la que más se aleja de su reposo). El índice REAL que reporta el
## sistema de combate etiqueta cada medición.
##
## Imprime, por clip: hueso que golpea, extensión máxima y el segundo (y fracción)
## en que ocurre: eso es el contacto.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const CADENCIA := 1.0  # s entre pulsaciones (menos que el reinicio de combo de 1,3 s)

func _ready() -> void:
	_piso()
	var jug := (load(JUGADOR) as PackedScene).instantiate() as CharacterBody3D
	add_child(jug)
	await get_tree().create_timer(0.8).timeout
	jug.call("_on_transformacion_elegida", &"velocista")
	var espera := 0
	while int(jug.get("forma")) != 1 and espera < 900:
		await get_tree().physics_frame
		espera += 1
	await get_tree().create_timer(0.4).timeout
	var combate: Node = jug.get_node_or_null("Combate")
	if combate == null:
		print("[sonda] FALLO: sin nodo Combate")
		return

	# Cada clip vive en su propia biblioteca: el nombre real es "combo-N/mixamo_com".
	var ap: AnimationPlayer = null
	var clips := {}
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
		print("[sonda] FALLO: no hallé los 4 combos (", clips.size(), ")")
		return
	var esq := _esqueleto_del_animador(ap)
	if esq == null:
		print("[sonda] FALLO: sin Skeleton3D")
		return
	print("[sonda] clips:", clips.size(), " | esqueleto:", esq.get_path())

	# Un pase: en cada pulsación se mide el clip que el sistema REALMENTE lanzó.
	var resultados := {}
	var intentos := 0
	while resultados.size() < 4 and intentos < 8:
		intentos += 1
		Input.action_press("atacar")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("atacar")
		await get_tree().physics_frame
		var idx := int(combate.golpe_actual())
		if idx < 1 or idx > 4:
			await get_tree().create_timer(CADENCIA).timeout
			continue
		var clave := "combo-%d" % idx
		var nombre := String(clips[clave])
		var largo := ap.get_animation(nombre).length
		var reloj := Time.get_ticks_msec()
		var base := {}
		var base_n := 0
		var filas: Array = []   # [t, {hueso: alcance}] de cada fotograma
		while float(Time.get_ticks_msec() - reloj) < CADENCIA * 1000.0 - 60.0:
			await get_tree().process_frame
			var t := float(Time.get_ticks_msec() - reloj) / 1000.0
			var adelante := -jug.global_transform.basis.z
			adelante.y = 0.0
			adelante = adelante.normalized() if adelante.length() > 0.001 else Vector3.FORWARD
			var m := _medir(esq, adelante)
			if base_n < 3:
				for h in m:
					base[h] = float(m[h])
				base_n += 1
				continue
			var exts := {}
			for h in m:
				exts[h] = float(m[h]) - float(base.get(h, m[h]))
			filas.append([t, exts])
		# El hueso que más se adelantó es el que golpea: se busca en cada fotograma.
		var hueso_top := ""
		var datos: Array = []
		for fila in filas:
			var fila_arr: Array = fila
			var exts: Dictionary = fila_arr[1]
			for h in exts:
				var ext := float(exts[h])
				if hueso_top.is_empty() or ext > float(datos[0]):
					hueso_top = h
					datos = [ext, float(fila_arr[0]), float(fila_arr[0]) / maxf(largo, 0.0001)]
		if hueso_top.is_empty():
			print("[sonda] %s: sin muestras" % clave)
			continue
		var primero := not resultados.has(idx)
		resultados[idx] = {"clave": clave, "largo": largo, "hueso": hueso_top,
				"ext": float(datos[0]), "t": float(datos[1]), "u": float(datos[2])}
		print("[sonda] %s | dur %.3f s | %s se adelanta %.3f m a %.3f s (u=%.3f)%s" % [
				clave, largo, hueso_top, float(datos[0]), float(datos[1]), float(datos[2]),
				"" if primero else " (re-medición)"])
		# Curvas de TODOS los miembros (cada ~4 fotogramas): así se distinguen el
		# puñetazo (pico temprano de una mano) y la patada (pico tardío de un pie).
		for hueso in ["mixamorig_LeftHand", "mixamorig_RightHand", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
			var linea := ""
			var visto := 0
			for fila in filas:
				var fila_arr: Array = fila
				var exts: Dictionary = fila_arr[1]
				if not exts.has(hueso):
					continue
				visto += 1
				if visto % 4 != 0:
					continue
				linea += "%.2f:%.2f " % [float(fila_arr[0]), float(exts[hueso])]
			print("[sonda]   ", hueso, " -> ", linea)

	print("[sonda] ---- RESUMEN ----")
	for i in range(1, 5):
		if resultados.has(i):
			var d: Dictionary = resultados[i]
			print("[sonda] %s: u=%.3f (%.3f s de %.3f s) golpea con %s" % [
					d["clave"], d["u"], d["t"], d["largo"], d["hueso"]])
		else:
			print("[sonda] combo-%d: NO medido" % i)
	print("[sonda] FIN")
	await get_tree().create_timer(0.3).timeout


## ALCANCE de cada mano/pie hacia adelante respecto a su referencia del torso: la
## parte que golpea es la que más se adelanta respecto a su reposo. Es la medida
## directa de "cuánto llega el golpe", así el puño de un jab y el pie de una patada
## se detectan igual, sin que el balanceo de la cadera los falsee.
func _medir(esq: Skeleton3D, adelante: Vector3) -> Dictionary:
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
		r[hueso] = (p.origin - c.origin).dot(adelante)
	return r


## El esqueleto que anima ese AnimationPlayer: el Skeleton3D hermano suyo (el
## velocista tiene Visual/Pose/Volteo/Modelo con AnimadorVelocista y Skeleton3D).
func _esqueleto_del_animador(ap: AnimationPlayer) -> Skeleton3D:
	var padre := ap.get_parent()
	if padre != null:
		for c in padre.get_children():
			if c is Skeleton3D:
				return c as Skeleton3D
	return null


## Suelo con colisión (el ataque sólo arranca con los pies apoyados).
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