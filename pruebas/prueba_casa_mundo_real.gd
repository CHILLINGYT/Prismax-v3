extends Node
## PRUEBA EN LA ESCENA PRINCIPAL (ziba_prototipo, semilla fija): ciclo COMPLETO de
## la casa de Leo, con los mandos del juego y los cambios de escena de verdad.
##
## Este nodo NO es la escena actual: pone el mundo como escena actual y se queda
## colgado de la raíz, así sobrevive a la pantalla de carga, al interior y a la vuelta.

const MUNDO := "res://mundo/escena/ziba_prototipo.tscn"
const TEXTO_ENTRAR := "Presiona E para entrar a la casa de Leo"
const TEXTO_SALIR := "Presiona E para salir a la ciudad"

var _ok := 0
var _fallos := 0


func _ready() -> void:
	call_deferred("_arrancar")


func _check(c: bool, t: String) -> void:
	if c:
		_ok += 1
		print("[casa-mundo] OK    ", t)
	else:
		_fallos += 1
		print("[casa-mundo] FALLO ", t)


func _fisica(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _arrancar() -> void:
	EstadoCasaLeo.olvidar_portal()
	# Esta escena deja de ser la actual: el mundo pasa a serlo (como en el juego).
	var vieja := get_tree().current_scene
	reparent(get_tree().root)
	var mundo := (load(MUNDO) as PackedScene).instantiate()
	get_tree().root.add_child(mundo)
	get_tree().current_scene = mundo
	if vieja != null and vieja != self:
		vieja.queue_free()
	var puerta := mundo.get_node("PuertaCasaLeo") as PuertaCasaLeo
	for i in 3000:
		await get_tree().physics_frame
		if puerta.portal() != Vector3.ZERO:
			break
	await _fisica(10)
	var jug := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var idx := puerta.portal_indice()
	# Se guarda aquí: este mundo se libera al entrar en la casa.
	var portal_inicial := puerta.portal()
	print("[casa-mundo] portal elegido %d en %s | marcador %s | Leo en %s" % [
			idx, str(puerta.portal()), str(puerta.global_position), str(jug.global_position)])
	_check(idx >= 0 and idx != 38,
			"la puerta NO es el portal 38 (el que da a la medianera del edificio vecino): es el %d" % idx)
	_check(puerta.call("_portal_accesible", puerta.portal(), (puerta.global_position - puerta.portal())),
			"el portal elegido es ACCESIBLE (Leo cabe delante y en la salida, sobre el suelo)")
	_check(puerta.portal().distance_to(jug.global_position) < 60.0,
			"y sigue cerca del inicio de Leo (%.1f m)" % puerta.portal().distance_to(jug.global_position))
	# --- Minimapa: una sola marca de casa, en la puerta -----------------------
	_check(get_tree().get_nodes_in_group("puerta_casa_leo").size() == 1, "hay UNA sola puerta de casa en el mundo")
	var mini := _buscar_minimapa()
	if mini != null:
		if mini.has_method("_rehacer_fuentes"):
			mini.call("_rehacer_fuentes")
		for k in 30:
			await get_tree().process_frame
		var fuente: Array = mini.get("_fuente_casa")
		_check(fuente.size() == 1 and (fuente[0]["posicion"] as Vector3).distance_to(puerta.global_position) < 0.05,
				"el minimapa marca la casa UNA vez y en la puerta (%d marcas)" % fuente.size())
	else:
		_check(false, "no se encontró el minimapa para comprobar la marca")
	# --- Acercarse ANDANDO: Leo se planta a 6 m por fuera y camina hasta la puerta -
	var afuera := (puerta.global_position - puerta.portal())
	afuera.y = 0.0
	afuera = afuera.normalized()
	var arranque := puerta.global_position + afuera * 6.0
	jug.call("colocar_en", arranque + Vector3.UP * 0.1, puerta.global_position)
	await _fisica(20)
	_check(String(jug.call("texto_interaccion")) != TEXTO_ENTRAR, "a 6 m de la puerta NO hay cartel")
	# En la vereda, delante de la puerta, hay una farola (con colisión): se rodea
	# por un lado, como haría el jugador, y se llega de frente a la puerta.
	var p2d := Vector2(puerta.global_position.x, puerta.global_position.z)
	var a2d := Vector2(afuera.x, afuera.z)
	var lado := Vector2(-a2d.y, a2d.x)
	await _ir_a(jug, p2d + a2d * 3.0 + lado * 1.3, 300)
	await _ir_a(jug, p2d + a2d * 1.0 + lado * 0.4, 300)
	await _fisica(20)
	var d := Vector2(jug.global_position.x, jug.global_position.z).distance_to(p2d)
	_check(puerta.en_rango(), "Leo llega ANDANDO hasta la puerta (a %.2f m)" % d)
	await _fisica(3)
	_check(String(jug.call("texto_interaccion")) == TEXTO_ENTRAR,
			"el cartel aparece al acercarse ('%s')" % String(jug.call("texto_interaccion")))
	# --- E: entrar ------------------------------------------------------------
	Input.action_press("interactuar")
	await _fisica(3)
	Input.action_release("interactuar")
	var en_casa := false
	for i in 2400:
		await get_tree().physics_frame
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path == EstadoCasaLeo.CASA and cs.has_method("listo") and bool(cs.call("listo")):
			en_casa = true
			break
	_check(en_casa, "con E entra: pantalla de carga y aparece DENTRO de la casa")
	if not en_casa:
		_fin()
		return
	await _fisica(20)
	var casa := get_tree().current_scene
	var jug_casa := get_tree().get_first_node_in_group("player") as CharacterBody3D
	_check(jug_casa != null and jug_casa.global_position.distance_to(casa.call("spawn")) < 0.8,
			"reaparece dentro, en su punto de entrada")
	_check(get_tree().get_nodes_in_group("player").size() == 1, "un solo jugador (sin duplicados)")
	_check(String(jug_casa.call("texto_interaccion")) == TEXTO_SALIR, "dentro, junto a la puerta, se ofrece salir")
	# --- E: salir por la MISMA puerta -----------------------------------------
	Input.action_press("interactuar")
	await _fisica(3)
	Input.action_release("interactuar")
	var fuera := false
	for i in 3000:
		await get_tree().physics_frame
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path == MUNDO:
			var p2 := cs.get_node_or_null("PuertaCasaLeo") as PuertaCasaLeo
			if p2 != null and p2.portal() != Vector3.ZERO and not EstadoCasaLeo.hay_vuelta():
				fuera = true
				break
	_check(fuera, "con E sale: vuelve a la ciudad por la pantalla de carga")
	if not fuera:
		_fin()
		return
	await _fisica(10)
	var mundo2 := get_tree().current_scene
	var puerta2 := mundo2.get_node("PuertaCasaLeo") as PuertaCasaLeo
	var jug2 := get_tree().get_first_node_in_group("player") as CharacterBody3D
	_check(puerta2.portal_indice() == idx and puerta2.portal().distance_to(portal_inicial) < 0.01,
			"la ciudad recargada usa la MISMA puerta (portal %d)" % puerta2.portal_indice())
	_check(jug2.global_position.distance_to(puerta2.punto_de_salida()) < 0.7,
			"reaparece delante de SU puerta (a %.2f m del punto de salida)" % jug2.global_position.distance_to(puerta2.punto_de_salida()))
	var piv := jug2.get("pivote") as Node3D
	var mira := -piv.global_transform.basis.z
	mira.y = 0.0
	var afuera2 := (puerta2.global_position - puerta2.portal())
	afuera2.y = 0.0
	_check(mira.normalized().dot(afuera2.normalized()) > 0.9,
			"orientado hacia la calle (dot %.2f)" % mira.normalized().dot(afuera2.normalized()))
	_check(absf(jug2.rotation.y) < 0.02, "sin girar la raíz del jugador (yaw %.3f)" % jug2.rotation.y)
	_check(puerta2.esperando_alejarse(),
			"recién salido la puerta espera a que Leo se aleje (a %.2f m del marcador)" % jug2.global_position.distance_to(puerta2.global_position))
	_check(not puerta2.puede_usar() and String(jug2.call("texto_interaccion")) != TEXTO_ENTRAR,
			"recién salido NO se ofrece entrar otra vez (texto '%s')" % String(jug2.call("texto_interaccion")))
	# Se aleja andando: el cartel no está; al volver a acercarse, reaparece.
	# Se aleja por la VEREDA (de lado), no de frente: delante está la farola.
	var a2 := Vector2(afuera2.normalized().x, afuera2.normalized().z)
	var lejos := Vector2(jug2.global_position.x, jug2.global_position.z) + Vector2(-a2.y, a2.x) * 5.0
	await _ir_a(jug2, lejos, 300)
	await _fisica(3)
	_check(not puerta2.esperando_alejarse() and String(jug2.call("texto_interaccion")) != TEXTO_ENTRAR,
			"al alejarse el cartel queda oculto (a %.1f m)" % jug2.global_position.distance_to(puerta2.global_position))
	# Y al volver a acercarse, la puerta se ofrece otra vez.
	var cerca := Vector2(puerta2.global_position.x, puerta2.global_position.z) + a2 * 1.0 + Vector2(-a2.y, a2.x) * 0.4
	await _ir_a(jug2, cerca, 300)
	await _fisica(5)
	_check(String(jug2.call("texto_interaccion")) == TEXTO_ENTRAR and puerta2.puede_usar(),
			"al volver a acercarse el cartel reaparece y la E funciona (a %.1f m)" % jug2.global_position.distance_to(puerta2.global_position))
	var mini2 := _buscar_minimapa()
	if mini2 != null:
		if mini2.has_method("_rehacer_fuentes"):
			mini2.call("_rehacer_fuentes")
		for k in 30:
			await get_tree().process_frame
		var f2: Array = mini2.get("_fuente_casa")
		_check(f2.size() == 1 and (f2[0]["posicion"] as Vector3).distance_to(puerta2.global_position) < 0.05,
				"tras volver, el mapa sigue con UNA marca de casa en la puerta (%d)" % f2.size())
	_fin()


func _fin() -> void:
	Input.action_release("interactuar")
	print("==================== CASA EN EL MUNDO REAL: %d OK / %d FALLO ====================" % [_ok, _fallos])


func _buscar_minimapa() -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		var s: Script = n.get_script()
		if s != null and s.resource_path.ends_with("hud_transformacion/scripts/minimapa.gd"):
			return n
	return null


## Piloto automático con los mandos reales (relativos a la cámara del jugador).
func _ir_a(jug: CharacterBody3D, destino: Vector2, max_frames: int) -> void:
	var mandos := ["mover_adelante", "mover_atras", "mover_izquierda", "mover_derecha"]
	for m in mandos:
		Input.action_release(m)
	for usados in max_frames:
		var pos := Vector2(jug.global_position.x, jug.global_position.z)
		var falta := destino - pos
		if falta.length() < 0.35:
			break
		var base: Basis = (jug.get("pivote") as Node3D).global_transform.basis
		var dirs := [Vector3(-base.z.x, 0, -base.z.z).normalized(), Vector3(base.z.x, 0, base.z.z).normalized(),
				Vector3(-base.x.x, 0, -base.x.z).normalized(), Vector3(base.x.x, 0, base.x.z).normalized()]
		var deseo := falta.normalized()
		for i in mandos.size():
			var peso := Vector2(dirs[i].x, dirs[i].z).dot(deseo)
			var pulsado := Input.is_action_pressed(mandos[i])
			if peso > 0.35 and not pulsado:
				Input.action_press(mandos[i])
			elif peso <= 0.35 and pulsado:
				Input.action_release(mandos[i])
		await get_tree().physics_frame
	for m in mandos:
		Input.action_release(m)
	await _fisica(2)
	var final := Vector2(jug.global_position.x, jug.global_position.z)
	if final.distance_to(destino) >= 0.35:
		var mira := Vector3(destino.x - final.x, 0.0, destino.y - final.y).normalized()
		var pecho := jug.global_position + Vector3.UP
		var q := PhysicsRayQueryParameters3D.create(pecho, pecho + mira * 1.5, 1, [jug.get_rid()])
		var g := jug.get_world_3d().direct_space_state.intersect_ray(q)
		print("[casa-mundo] el piloto se detuvo a %.2f m del destino | delante: %s" % [
				final.distance_to(destino), String((g["collider"] as Node).get_path()) if not g.is_empty() else "nada"])
