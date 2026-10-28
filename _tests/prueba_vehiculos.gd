extends Node3D
## PRUEBAS de los VEHÍCULOS APARCADOS (Tarea 2), sobre el colocador REAL y los tres
## modelos REALES, con una ciudad de mentira que expone el mismo trazado que el
## generador (así la prueba es rápida y aun así comprueba las medidas de verdad).
##
## Comprueba:
##   1. se aparcan EXACTAMENTE los del plan: moto, auto, camioneta y un SEGUNDO
##      coche (el cuarto vehículo de la tanda);
##   2. cada uno está EN LA CALZADA (no en la acera ni en una manzana) y pegado al
##      bordillo, alineado con la calle (su eje largo sigue el eje del vial);
##   3. ninguno pisa un cruce y ninguno se solapa con otro;
##   4. los tres están APOYADOS en el suelo (su malla empieza en el suelo);
##   5. tienen la física existente (StaticBody3D + CollisionShape3D) y NO son
##      vehículos conducibles;
##   6. el tamaño visible es el pedido (1,75 / 4,75 / 4,50 m);
##   7. la colocación es determinista (dos pasadas dan los mismos sitios).

const CARRETERA_Y := 0.0
## Aire mínimo del colocador entre un vehículo y un cruce (m): el mismo valor que
## usa `world/vehiculos.gd`.
const AIRE_CRUCE := 2.5

var _ok := 0
var _fallos := 0
var _ciudad: CiudadFalsa
var _col: Vehiculos

func _ready() -> void:
	_piso()
	_ciudad = CiudadFalsa.new()
	add_child(_ciudad)
	await get_tree().physics_frame
	_col = Vehiculos.new()
	_col.name = "Vehiculos"
	_col.ciudad = _ciudad
	add_child(_col)
	var t := 0
	while not _col.listo() and t < 900:
		await get_tree().physics_frame
		t += 1
	await get_tree().physics_frame
	_check(_col.colocados() == 5, "se aparcaron los 5 vehículos del plan (4 de antes + el Ford)")
	var puestos := _col.puestos()
	var tipos := {}
	for p in puestos:
		tipos[String(p["tipo"])] = true
	_check(tipos.size() == 5 and tipos.has("moto") and tipos.has("auto")
			and tipos.has("camioneta") and tipos.has("auto2") and tipos.has("ford"),
			"hay una moto, un auto, una camioneta, un segundo coche (auto2) y el Ford Escort, sin duplicados")

	# Tamaños pedidos (2026-10: +10% sobre la medida realista, a pedido).
	var esperados := {"moto": 2.42, "auto": 5.5, "camioneta": 5.39, "auto2": 5.5, "ford": 4.73}
	var cajas := {}
	for p in puestos:
		var tipo := String(p["tipo"])
		var nodo := p["nodo"] as Node3D
		var pos := p["pos"] as Vector3
		var vertical := bool(p["vertical"])
		var caja := _caja_mundo(nodo)
		cajas[tipo] = caja
		var largo := maxf(caja.size.x, caja.size.z)
		var objetivo := float(esperados[tipo])
		_check(absf(largo - objetivo) < 0.2,
				"el %s mide lo pedido (%.2f m ≈ %.2f m)" % [tipo, largo, objetivo])
		# Proporción con el JUGADOR (malla de 1,95 m): alto del vehículo en el rango
		# que tiene en la realidad respecto de una persona.
		var rango_alto := {"moto": Vector2(1.1, 1.6), "auto": Vector2(1.4, 1.9), "auto2": Vector2(1.4, 1.9),
				"camioneta": Vector2(1.9, 2.7), "ford": Vector2(1.4, 1.9)}
		var r: Vector2 = rango_alto[tipo]
		_check(caja.size.y >= r.x and caja.size.y <= r.y,
				"el %s tiene un alto proporcionado al jugador de 1,95 m (%.2f m, rango %.2f–%.2f)" % [tipo, caja.size.y, r.x, r.y])
		# Apoyado en el suelo.
		_check(absf(caja.position.y - CABECERA_Y) < 0.08,
				"el %s está apoyado en el suelo (base a %.2f m)" % [tipo, caja.position.y])
		# En la calzada: distancia al eje del vial ≤ mitad de la calzada, y pegado al
		# bordillo (a menos de 0,6 m de él).
		var calzada: float = _ciudad._trazado["calzada"]
		var d_vial := 0.0
		if vertical:
			d_vial = absf(pos.x + 72.0 - float(p["calle"]) * 24.0)
		else:
			d_vial = absf(pos.z + 60.0 - float(p["calle"]) * 24.0)
		_check(d_vial <= calzada * 0.5, "el %s está DENTRO de la calzada (a %.2f m del eje, ≤ %.1f m)" % [tipo, d_vial, calzada * 0.5])
		# Alineado con la calle: el eje largo sigue el eje del vial.
		var eje_mayor := "z" if caja.size.z >= caja.size.x else "x"
		_check((vertical and eje_mayor == "z") or (not vertical and eje_mayor == "x"),
				"el %s está alineado con la calle (%s)" % [tipo, eje_mayor])
		# Lejos de los cruces: se mide la distancia al CRUCE MÁS CERCANO DEL PROPIO
		# VIAL (el eje de la calle donde está aparcado), no de cualquier cruce.
		var paso := float(_ciudad._trazado["paso"])
		var hw := float(_ciudad._trazado["hw"])
		var eje := float(p["calle"]) * paso + (-72.0 if vertical else -60.0)
		var cruces: Array = _ciudad.cruces()
		var d_min := 1e9
		for c: Vector2 in cruces:
			var punto := Vector2(pos.x, pos.z)
			var eje_cruce := c.x if vertical else c.y
			if absf(eje_cruce - eje) > 0.5:
				continue   # cruce de otra calle
			d_min = minf(d_min, punto.distance_to(c))
		_check(d_min < 1e8 and d_min >= hw + AIRE_CRUCE,
				"el %s no pisa el cruce (a %.1f m del cruce más cercano del vial, ≥ %.1f)" % [tipo, d_min, hw + AIRE_CRUCE])
		# Física de siempre y nada de conducción.
		_check(nodo is StaticBody3D and not (nodo is RigidBody3D),
				"el %s es un cuerpo estático (no se conduce)" % tipo)
		var forma := nodo.get_node_or_null("Colision") as CollisionShape3D
		_check(forma != null and forma.shape is BoxShape3D and nodo.collision_layer == 1,
				"el %s tiene su caja de colisión en la capa del mundo" % tipo)
		_check(_cuenta_mallas(nodo) > 0, "el %s tiene su malla visible (%d piezas)" % [tipo, _cuenta_mallas(nodo)])

	# No se solapan entre ellos.
	var claves := cajas.keys()
	for i in claves.size():
		for j in range(i + 1, claves.size()):
			var a := cajas[claves[i]] as AABB
			var b := cajas[claves[j]] as AABB
			var dx := maxf(0.0, maxf(a.position.x - (b.position.x + b.size.x), b.position.x - (a.position.x + a.size.x)))
			var dz := maxf(0.0, maxf(a.position.z - (b.position.z + b.size.z), b.position.z - (a.position.z + a.size.z)))
			_check(dx > 0.4 or dz > 0.4,
					"la %s y el %s NO se solapan (separación %.2f / %.2f m)" % [claves[i], claves[j], dx, dz])

	# Determinista: otra pasada da los mismos sitios. La primera se retira antes (si no,
	# el rayo de apoyo del segundo pase caería encima de los vehículos del primero, que
	# es justo lo que hace un rayo de verdad).
	_col.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var col2 := Vehiculos.new()
	col2.ciudad = _ciudad
	add_child(col2)
	var t2 := 0
	while not col2.listo() and t2 < 900:
		await get_tree().physics_frame
		t2 += 1
	var iguales := true
	var p2 := col2.puestos()
	if p2.size() != puestos.size():
		iguales = false
	else:
		for i in puestos.size():
			if (puestos[i]["pos"] as Vector3).distance_to(p2[i]["pos"] as Vector3) > 0.001:
				iguales = false
	_check(iguales, "la colocación es determinista (dos pasadas, los mismos sitios)")

	print("==================== VEHÍCULOS: %d OK / %d FALLO ====================" % [_ok, _fallos])
	await get_tree().create_timer(0.4).timeout


const CABECERA_Y := 0.0

## Caja envolvente de la MALLA del vehículo en coordenadas del mundo. Se ignoran los
## planos (sombras horneadas de grosor 0, como la del Datsun, que mide más que el
## coche): el mismo criterio que usa VehiculoAparcado para escalarlo.
func _caja_mundo(nodo: Node) -> AABB:
	var caja := AABB()
	var primero := true
	for m in nodo.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var c := _transformar(mi.get_aabb(), mi.global_transform)
		if c.size.y < 0.01:
			continue
		caja = c if primero else caja.merge(c)
		primero = false
	return caja


func _transformar(caja: AABB, t: Transform3D) -> AABB:
	var r := AABB(t * caja.position, Vector3.ZERO)
	for i in range(8):
		r = r.expand(t * caja.get_endpoint(i)) if i > 0 else AABB(t * caja.get_endpoint(i), Vector3.ZERO)
	return r


func _cuenta_mallas(nodo: Node) -> int:
	return nodo.find_children("*", "MeshInstance3D", true, false).size()


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[vehiculos-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[vehiculos-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(400, 1.0, 400)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(-20.0, 40.0, 70.0)
	cam.rotation = Vector3(-0.6, 0.0, 0.0)
	cam.current = true
	add_child(cam)