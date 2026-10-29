extends Node
## SONDA (sólo mide, no cambia nada) del MUNDO REAL con la semilla fija:
##   · vehículos: dónde quedaron, si flotan/se hunden (suelo bajo las 4 esquinas),
##     si su caja toca un edificio y a cuánto quedan del cordón;
##   · puerta de la casa de Leo: qué portal eligió, dónde aparece Leo, y si el
##     portal, el marcador y el punto de salida se pueden pisar (o están dentro de
##     un edificio / tapados por una colisión).

const MUNDO := "res://mundo/escena/ziba_prototipo.tscn"

var _mundo: Node
var _ciudad: Node
var _veh: Node
var _puerta: Node
var _jug: Node3D


func _ready() -> void:
	EstadoCasaLeo.olvidar_portal()
	_mundo = (load(MUNDO) as PackedScene).instantiate()
	add_child(_mundo)
	_ciudad = _mundo.get_node("Ciudad")
	_veh = _mundo.get_node("Vehiculos")
	_puerta = _mundo.get_node("PuertaCasaLeo")
	_jug = _mundo.get_node("Jugador") as Node3D
	var spawn := _jug.global_position
	for i in 2400:
		await get_tree().physics_frame
		if bool(_veh.call("listo")) and (_puerta.call("portal") as Vector3) != Vector3.ZERO:
			break
	for i in 30:
		await get_tree().physics_frame
	var tr: Dictionary = _ciudad.get("_trazado")
	print("[sonda] trazado: calzada %.2f | acera %.2f | paso %.2f | hw %.2f | ext %s | off %s" % [
			float(tr.get("calzada", 0)), float(tr.get("acera", 0)), float(tr.get("paso", 0)),
			float(tr.get("hw", 0)), str(tr.get("ext")), str(tr.get("off"))])
	print("[sonda] spawn de Leo (escena): %s" % str(spawn))
	_vehiculos(tr)
	_puerta_casa(spawn)
	print("[sonda] FIN")


func _espacio() -> PhysicsDirectSpaceState3D:
	return _mundo.get_viewport().world_3d.direct_space_state


func _suelo(x: float, z: float, excluir: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 8.0, z), Vector3(x, -10.0, z), 1, excluir)
	return _espacio().intersect_ray(q)


func _vehiculos(tr: Dictionary) -> void:
	var nodos: Array = _veh.call("nodos")
	print("[sonda] VEHÍCULOS: %d instancias (hijos de Vehiculos: %d)" % [nodos.size(), _veh.get_child_count()])
	var calzada: float = float(tr.get("calzada", 0))
	var paso: float = float(tr.get("paso", 0))
	var off: Vector2 = tr.get("off", Vector2.ZERO)
	for n in nodos:
		var v := n as VehiculoAparcado
		if v == null:
			continue
		var forma := v.get_node_or_null("Colision") as CollisionShape3D
		var caja := (forma.shape as BoxShape3D).size if forma != null else Vector3.ONE
		var t := v.global_transform
		var excl: Array[RID] = [v.get_rid()]
		# Suelo bajo las 4 esquinas (sin contar el propio vehículo).
		var ys: Array = []
		for sx in [-0.45, 0.45]:
			for sz in [-0.45, 0.45]:
				var p: Vector3 = t * Vector3(caja.x * sx, 0.0, caja.z * sz)
				var s := _suelo(p.x, p.z, excl)
				ys.append(snappedf(float((s["position"] as Vector3).y), 0.01) if not s.is_empty() else -99.0)
		# Choques de la caja (un poco por encima del suelo para no contar la calzada).
		var q := PhysicsShapeQueryParameters3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(caja.x * 0.96, maxf(caja.y - 0.3, 0.2), caja.z * 0.96)
		q.shape = b
		q.transform = Transform3D(t.basis.orthonormalized(), t.origin + Vector3.UP * (0.15 + b.size.y * 0.5))
		q.collision_mask = 1
		q.exclude = excl
		var golpes: Array = []
		for r in _espacio().intersect_shape(q, 16):
			var c := r.get("collider") as Node
			golpes.append(String(c.get_path()).replace("/root/SondaMundo/ZibaPrototipo/", "") if c else "?")
		# Distancia al eje de vial más cercano y al cordón.
		var largo_x := absf(t.basis.x.normalized().x) < 0.5   # su eje X local no va por X → largo sobre X?
		var eje_mundo_largo := "x" if (v.eje_largo() == "z") == largo_x else "z"
		var coord := v.global_position.z if eje_mundo_largo == "x" else v.global_position.x
		var base := off.y if eje_mundo_largo == "x" else off.x
		var k := roundf((coord - base) / paso)
		var eje := base + k * paso
		var lateral := absf(coord - eje)
		var al_cordon := calzada * 0.5 - (lateral + v.ancho_m() * 0.5)
		print("[sonda]  %s pos %s giro %.2f | largo %.2f ancho %.2f alto %.2f | eje del auto en mundo %s | calle %d | al cordón %.2f m | suelo esquinas %s | toca: %s" % [
				v.name, str(v.global_position.snapped(Vector3.ONE * 0.01)), v.rotation.y,
				v.largo_m(), v.ancho_m(), v.alto_m(), eje_mundo_largo, int(k), al_cordon, str(ys),
				str(golpes) if not golpes.is_empty() else "nada"])


func _puerta_casa(spawn: Vector3) -> void:
	var portales: Array = _ciudad.get("prueba_portales")
	var dirs: Array = _ciudad.get("prueba_portales_dir")
	var idx := int(_puerta.call("portal_indice"))
	var p: Vector3 = _puerta.call("portal")
	var g: Vector3 = (_puerta as Node3D).global_position
	var sal: Vector3 = _puerta.call("punto_de_salida")
	print("[sonda] PUERTA: %d portales | elegido %d en %s dir %s | marcador %s | salida %s | a %.1f m del spawn" % [
			portales.size(), idx, str(p), str(dirs[idx] if idx >= 0 else Vector3.ZERO), str(g), str(sal), p.distance_to(spawn)])
	# Los 6 portales más cercanos al spawn.
	var lista: Array = []
	for i in portales.size():
		lista.append([(portales[i] as Vector3).distance_to(spawn), i])
	lista.sort()
	for k in mini(6, lista.size()):
		var i: int = lista[k][1]
		print("[sonda]   portal %d a %.1f m: %s dir %s" % [i, float(lista[k][0]), str(portales[i]), str(dirs[i])])
	# ¿Cabe Leo (cápsula real r 0.4 h 1.9) en el marcador, la salida y a lo largo de la normal?
	var caps := CapsuleShape3D.new()
	caps.radius = 0.4
	caps.height = 1.9
	var excl: Array[RID] = []
	if _jug is CollisionObject3D:
		excl.append((_jug as CollisionObject3D).get_rid())
	var afuera: Vector3 = (dirs[idx] as Vector3) if idx >= 0 else Vector3.FORWARD
	afuera.y = 0.0
	afuera = afuera.normalized()
	for d in [0.35, 0.8, 1.2, 1.6, 2.4, 3.5, 5.0]:
		var pt: Vector3 = p + afuera * float(d)
		var s := _suelo(pt.x, pt.z, excl)
		var y := float((s["position"] as Vector3).y) if not s.is_empty() else -99.0
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = caps
		q.transform = Transform3D(Basis(), Vector3(pt.x, y + 0.05 + 0.95 + 0.02, pt.z))
		q.collision_mask = 1
		q.exclude = excl
		var golpes: Array = []
		for r in _espacio().intersect_shape(q, 8):
			var c := r.get("collider") as Node
			golpes.append(String(c.name) + "@" + String(c.get_parent().name) if c else "?")
		print("[sonda]   a %.2f m del portal hacia la calle: suelo y %.2f (portal y %.2f) | Leo choca con: %s" % [
				d, y, p.y, str(golpes) if not golpes.is_empty() else "NADA (se puede estar)"])
	# Rayo horizontal desde 5 m fuera hacia el portal: ¿qué tapa el acceso?
	var desde := p + afuera * 5.0 + Vector3.UP * 1.0
	var hasta := p + Vector3.UP * 1.0
	var rq := PhysicsRayQueryParameters3D.create(desde, hasta, 1, excl)
	var hit := _espacio().intersect_ray(rq)
	print("[sonda]   rayo calle→portal a 1 m de altura: %s" % (
			("choca con %s a %.2f m del portal" % [String((hit["collider"] as Node).name), (hit["position"] as Vector3).distance_to(hasta)]) if not hit.is_empty() else "libre hasta el portal"))
