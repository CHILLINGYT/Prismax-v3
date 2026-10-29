extends Node

# Verificación de los 10 PUNTOS DE EVENTO sobre el MUNDO REAL (ziba_prototipo.tscn):
#   · se instancia el mundo, se espera a que la ciudad termine de generarse;
#   · se cuentan 10 puntos terrestres + 2 sobre el barco (por definición);
#   · se fuerza la aparición de los 10 tubos y se comprueba que TODOS encuentren
#     una ubicación válida (suelo/superficie), sin inventar coordenadas.
#
#   godot --headless --path <proyecto> res://pruebas/prueba_eventos_mundo.tscn

const MUNDO := preload("res://mundo/escena/ziba_prototipo.tscn")
const IDS := [&"E1", &"E2", &"E3", &"E4", &"E5", &"E6", &"E7", &"E8", &"E9", &"E10", &"B1", &"B2"]

var _pasadas := 0
var _falladas := 0

func _ready() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, (" — " + detalle) if detalle != "" else "")
	else:
		_falladas += 1
		print("[FALLA] ", nombre, (" — " + detalle) if detalle != "" else "")

func _correr() -> void:
	var mundo := MUNDO.instantiate()
	add_child(mundo)

	var generada := false
	for _i in 900:
		await get_tree().process_frame
		if mundo.get_node_or_null("Ciudad/CiudadGenerada") != null:
			generada = true
			break
	_check("La ciudad terminó de generarse", generada)
	# Dejar que el Terrain3D termine de construir su colisión (es diferido).
	for _i in 240:
		await get_tree().process_frame
	await get_tree().physics_frame

	# --- Diagnóstico del terreno/colisión bajo un punto natural (E1) ---
	var terreno := mundo.get_node_or_null("Terreno")
	if terreno != null:
		var t: Object = terreno.get("terreno")
		if t != null:
			print("[diag] terreno collision_layer=", t.get("collision_layer"),
					" mask=", t.get("collision_mask"))
	var sp: PhysicsDirectSpaceState3D = mundo.get_world_3d().direct_space_state
	for m in [1, 16, 0xFFFFF]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(42, 300, -210), Vector3(42, -100, -210), m)
		var h := sp.intersect_ray(q)
		print("[diag] rayo (42,-210) mask=", m, " -> ", h)

	var dir := mundo.get_node_or_null("DirectorEventos")
	_check("DirectorEventos presente en el mundo", dir != null)
	if dir == null:
		get_tree().quit()
		return

	var terrestres := 0
	var barco := 0
	for id in IDS:
		if String(id).begins_with("E"):
			terrestres += 1
		else:
			barco += 1
	_check("10 puntos terrestres", terrestres == 10, "n=%d" % terrestres)
	_check("2 puntos sobre el barco", barco == 2, "n=%d" % barco)

	var ok := 0
	for id in IDS:
		if bool(dir.call("forzar_aparicion", id)):
			ok += 1
		else:
			print("[!] El punto ", id, " no encontró ubicación válida.")
	_check("Los 12 puntos son válidos en el mapa real", ok == 12, "%d/12" % ok)

	print("==================================================")
	print("RESULTADO: %d OK, %d FALLAS" % [_pasadas, _falladas])
	print("==================================================")
	get_tree().quit()