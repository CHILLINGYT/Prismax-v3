extends Node

## PRUEBA DE CALLES: dobles líneas amarillas y tapas de alcantarilla.
##
## Instancia el JUEGO REAL (como las otras sondas del proyecto), espera a que la ciudad
## esté generada y MIDE lo que quedó colocado, comparándolo con lo que exige el encargo:
##
##  · Doble amarilla del eje: una sola pieza (nunca las de curva), centrada en el eje de
##    su calle, girada a 0/90°, apoyada sobre el pavimento, sin pisar los pasos de
##    peatones y teselada pieza a pieza (sin huecos ni superposiciones).
##  · Tapas de alcantarilla: exactamente UNA por cuadra, en el centro longitudinal real
##    de esa cuadra y en el centro transversal de la calzada, alineadas con el
##    pavimento y sin duplicados.
## Guarda capturas y termina el proceso por sí sola.

const RUTA_LOG := "res://.backup_tapas_lineas/log_prueba_calles.txt"
const RUTA_CAPTURAS := "res://.backup_tapas_lineas/capturas"

var _f: FileAccess = null
var _fallos: Array[String] = []
var _t0 := 0.0
var _juego: Node = null
var _gen: Node = null
var _contenedor: Node = null

var _trazado := {}
var _paso := 0.0
var _calzada := 0.0
var _off := Vector2.ZERO
var _nx := 0
var _nz := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(RUTA_CAPTURAS)
	_f = FileAccess.open(RUTA_LOG, FileAccess.WRITE)
	_log("=== PRUEBA DE CALLES (líneas amarillas y tapas) ===")
	var guardia := Timer.new()
	guardia.wait_time = 240.0
	guardia.one_shot = true
	guardia.timeout.connect(func() -> void:
		_log("!! TIEMPO AGOTADO")
		_cerrar())
	add_child(guardia)
	guardia.start()
	_ejecutar()


func _ejecutar() -> void:
	await _frames(3)
	_juego = get_node_or_null("Juego")
	if _juego == null:
		_comprobar(false, "el juego se instanció")
		_cerrar()
		return
	_gen = _juego.get_node_or_null("Ciudad")
	# Esperar a que la ciudad esté generada (los peatones entran al final).
	var espera := 0.0
	while espera < 180.0:
		await _frames(1)
		_contenedor = _juego.find_child("CiudadGenerada", true, false)
		var pe := _juego.find_child("Peatones", true, false) if _contenedor != null else null
		if pe != null and pe.get_child_count() > 20:
			break
		espera += get_process_delta_time()
	_comprobar(_gen != null and _contenedor != null, "la ciudad se generó")
	if _gen == null or _contenedor == null:
		_cerrar()
		return
	_trazado = _gen.get("_trazado")
	_paso = float(_trazado["paso"])
	_calzada = float(_trazado["calzada"])
	_off = _trazado["off"]
	_nx = int(_gen.get("manzanas_x"))
	_nz = int(_gen.get("manzanas_z"))
	_log("  trazado: calzada %.1f m | acera %.1f | manzana %.1f | paso %.1f | rejilla %dx%d | off %s" % [
			_calzada, float(_trazado["acera"]), float(_trazado["manzana"]), _paso, _nx, _nz, str(_off)])
	_log("  cuadra entre cruces: %.1f m de calzada a calzada (centro a %.1f m de cada cruce)" % [
			_paso - _calzada, (_paso - _calzada) * 0.5])

	var est: Dictionary = _gen.get("_est")
	_log("  estadísticas del generador: marcas %d | props %d" % [int(est.get("marcas", 0)), int(est.get("props", 0))])

	_medir_marcas()
	_medir_tapas()
	await _capturar_vistas()
	_log("=== RESULTADO: %d fallos ===" % _fallos.size())
	for f in _fallos:
		_log("  FALLO: " + f)
	_log("tiempo total: %.1f s" % (Time.get_ticks_msec() / 1000.0 - _t0))
	_cerrar()


# --------------------------------------------------------------- marcas viales

func _medir_marcas() -> void:
	_log("--- A) DOBLE LÍNEA AMARILLA DEL EJE ---")
	var por_pieza := _instancias_por_prefijo("Decal_")
	# 1) Ninguna pieza de CURVA, y el eje usa una sola pieza (la recta).
	var curvas := 0
	for nombre: String in por_pieza.keys():
		if nombre.to_lower().contains("curve"):
			curvas += por_pieza[nombre].size()
	_comprobar(curvas == 0, "no se coloca ninguna pieza de curva como marca (%d)" % curvas)
	var rectas := 0
	for nombre: String in por_pieza.keys():
		if nombre.to_lower().contains("doubleyellow"):
			rectas += por_pieza[nombre].size()
			_log("  pieza de doble amarilla usada: %s x%d" % [nombre, por_pieza[nombre].size()])
	_comprobar(rectas > 0, "hay doble amarilla colocada (%d piezas)" % rectas)

	# 2) Cada pieza del eje: sobre el eje de su calle, girada a 0/90°, a cota de acera,
	#    fuera de los pasos de peatones y sin solaparse con la vecina.
	var largo_pieza := _largo_de("Decal_DoubleYellow_Straight")
	var margen := _margen_real()
	_log("  largo de la pieza: %.3f m | margen de paso de peatones: %.3f m" % [largo_pieza, margen])
	var piezas: Array = []
	for nombre: String in por_pieza.keys():
		if nombre.to_lower().contains("doubleyellow"):
			for xf: Transform3D in por_pieza[nombre]:
				piezas.append(xf)
	var max_lat := 0.0
	var min_dist_cruce := 999.0
	var y_mal := 0
	var giro_mal := 0
	for xf: Transform3D in piezas:
		var pos := xf.origin
		var lat := _distancia_al_eje_mas_cercano(pos, true)
		max_lat = maxf(max_lat, lat)
		var d := _distancia_al_cruce_mas_cercano(pos)
		min_dist_cruce = minf(min_dist_cruce, d)
		if absf(pos.y - 0.0) > 0.02:
			y_mal += 1
		if not _giro_recto(xf.basis):
			giro_mal += 1
	_log("  piezas: %d | desvío máximo del eje %.4f m | distancia mínima a un cruce %.2f m (borde de la pieza: %.2f m; hace falta >= %.2f)" % [
			piezas.size(), max_lat, min_dist_cruce, min_dist_cruce - largo_pieza * 0.5, margen])
	_comprobar(piezas.size() > 0, "hay piezas de eje colocadas")
	_comprobar(max_lat < 0.02, "todas las piezas del eje están centradas en el eje de su calzada (desvío máx %.4f m)" % max_lat)
	_comprobar(giro_mal == 0, "todas van giradas 0° o 90° (torcidas: %d)" % giro_mal)
	_comprobar(y_mal == 0, "todas a cota de acera, sobre el pavimento (fuera de cota: %d)" % y_mal)
	_comprobar(min_dist_cruce - largo_pieza * 0.5 >= margen - 0.02,
			"ninguna pieza pisa el paso de peatones (borde más cercano a %.2f m >= %.2f m)" % [min_dist_cruce - largo_pieza * 0.5, margen])

	# 3) Continuidad: piezas contiguas de la misma calzada, sin huecos ni escalones.
	var por_calle := {}
	for xf: Transform3D in piezas:
		var clave := _calle_de(xf.origin)
		if not por_calle.has(clave):
			por_calle[clave] = []
		por_calle[clave].append(xf)
	var hueco_max := 0.0
	var escalon_max := 0.0
	var tramos_por_calle := 0
	for clave: String in por_calle.keys():
		var lista: Array = por_calle[clave]
		lista.sort_custom(func(a: Transform3D, b: Transform3D) -> bool:
			return _coord(a.origin) < _coord(b.origin))
		var tramos := 1
		for i in range(1, lista.size()):
			var anterior: Transform3D = lista[i - 1]
			var actual: Transform3D = lista[i]
			var d := absf(_coord(actual.origin) - _coord(anterior.origin))
			if d > largo_pieza * 2.0:
				tramos += 1                      # otro tramo: el hueco es el cruce, es correcto
				continue
			var hueco: float = d - largo_pieza
			hueco_max = maxf(hueco_max, absf(hueco))
			# Escalón lateral REAL: diferencia de desvío respecto del eje de la calle.
			escalon_max = maxf(escalon_max, absf(_offset_lateral(actual.origin) - _offset_lateral(anterior.origin)))
		tramos_por_calle = tramos
	_log("  continuidad: hueco máximo entre piezas contiguas %.4f m | escalón lateral máximo %.4f m" % [hueco_max, escalon_max])
	_comprobar(hueco_max < 0.02, "las piezas del eje se tocan (hueco máximo %.4f m)" % hueco_max)
	_comprobar(escalon_max < 0.02, "no hay escalones laterales entre piezas (máx %.4f m)" % escalon_max)

	# 4) Cuántas piezas debería haber: por tramo, las que caben en la franja libre.
	var libre := (_paso - _calzada) - 2.0 * margen
	var por_tramo := int(floor(libre / largo_pieza)) if largo_pieza > 0.0 else 0
	var esperadas := por_tramo * _nz * (_nx + 1) + por_tramo * _nx * (_nz + 1)
	_log("  franja libre por cuadra: %.2f m -> %d piezas de %.1f m por tramo; esperadas %d piezas de eje" % [
			libre, por_tramo, largo_pieza, esperadas])
	_comprobar(piezas.size() == esperadas, "el número de piezas del eje es el esperado (%d de %d)" % [piezas.size(), esperadas])

	# 5) Discontinuas de carril: también en su sitio, a ±calzada/4 del eje.
	var nc := 0
	var lat_desv := 0.0
	for nombre: String in por_pieza.keys():
		if nombre.to_lower().contains("brokenline"):
			for xf: Transform3D in por_pieza[nombre]:
				nc += 1
				var esperado := _calzada * 0.25
				var lat: float = absf(_offset_lateral(xf.origin))
				lat_desv = maxf(lat_desv, absf(lat - esperado))
	_log("--- B) DISCONTINUAS DE CARRIL ---")
	_log("  piezas: %d | desvío máximo respecto de ±%.2f m: %.4f m" % [nc, _calzada * 0.25, lat_desv])
	_comprobar(nc > 0, "hay discontinuas de carril (%d)" % nc)
	_comprobar(lat_desv < 0.02, "las discontinuas están a la distancia de carril exacta (desvío %.4f m)" % lat_desv)


# --------------------------------------------------------------- tapas

func _medir_tapas() -> void:
	_log("--- C) TAPAS DE ALCANTARILLA ---")
	var tapas: Array = []
	for n in _todos(_contenedor):
		var nodo: Node = n as Node
		var nom := String(nodo.name)
		if not nom.begins_with("Prop_ManholeCover"):
			continue
		# La pieza trae su malla dentro de un nodo con el MISMO nombre (el glTF exporta
		# un nodo y su malla): se cuenta sólo el nodo más externo, que es la tapa física.
		# Si de verdad hubiera dos tapas en la misma cuadra serían nodos independientes y
		# se contarían las dos.
		var padre: Node = nodo.get_parent()
		if padre != null and String(padre.name).begins_with("Prop_ManholeCover"):
			continue
		tapas.append(nodo as Node3D)
	var esperadas: Array = []
	for i in _nx + 1:
		for k in _nz:
			esperadas.append(Vector3(_off.x + float(i) * _paso, 0.0, _off.y + _paso * (float(k) + 0.5)))
	for j in _nz + 1:
		for k in _nx:
			esperadas.append(Vector3(_off.x + _paso * (float(k) + 0.5), 0.0, _off.y + float(j) * _paso))
	_log("  tapas colocadas: %d | cuadras en la rejilla: %d (%d calles x %d cuadras + %d calles x %d cuadras)" % [
			tapas.size(), esperadas.size(), _nx + 1, _nz, _nz + 1, _nx])
	for t: Node3D in tapas:
		_log("    tapa %s | clase %s | pos %s | padre %s" % [
				String(t.name), t.get_class(), str(t.global_position), String(t.get_parent().name)])
	_comprobar(tapas.size() == esperadas.size(), "hay exactamente UNA tapa por cuadra (%d de %d)" % [tapas.size(), esperadas.size()])

	var sin_centro := 0
	var desv_max := 0.0
	var usadas := {}
	var dmin := 999.0
	for t: Node3D in tapas:
		var p := t.global_position
		# Cuadra a la que pertenece: la más cercana de la lista esperada.
		var mejor := -1
		var mejor_d := 999.0
		for i in esperadas.size():
			var e: Vector3 = esperadas[i]
			var d := Vector2(p.x - e.x, p.z - e.z).length()
			if d < mejor_d:
				mejor_d = d
				mejor = i
		desv_max = maxf(desv_max, mejor_d)
		if mejor_d > 0.02:
			sin_centro += 1
		if usadas.has(mejor):
			usadas[mejor] = int(usadas[mejor]) + 1
		else:
			usadas[mejor] = 1
	for i in tapas.size():
		for j in range(i + 1, tapas.size()):
			dmin = minf(dmin, (tapas[i] as Node3D).global_position.distance_to((tapas[j] as Node3D).global_position))
	var repetidas := 0
	for k: int in usadas.keys():
		if int(usadas[k]) > 1:
			repetidas += 1
	_log("  desvío máximo respecto del centro exacto de su cuadra: %.4f m (fuera de centro: %d)" % [desv_max, sin_centro])
	_log("  distancia mínima entre dos tapas: %.2f m | cuadras con más de una tapa: %d" % [dmin, repetidas])
	_comprobar(desv_max < 0.02, "cada tapa está en el centro exacto de su cuadra (desvío máx %.4f m)" % desv_max)
	_comprobar(sin_centro == 0, "ninguna tapa fuera del centro de su cuadra (%d)" % sin_centro)
	_comprobar(repetidas == 0, "no hay cuadras con tapas duplicadas (%d)" % repetidas)
	_comprobar(dmin > 5.0, "ninguna tapa superpuesta (distancia mínima %.2f m)" % dmin)

	# Centrado transversal y cota: sobre el eje de su calzada y apoyada en el asfalto.
	var lat_max := 0.0
	var y := 0.0
	var giro_mal := 0
	var dist_cruce := 999.0
	for t: Node3D in tapas:
		var p := t.global_position
		lat_max = maxf(lat_max, _distancia_perp_al_eje(p))
		y = p.y
		if absf(t.rotation.y) > 0.001:
			giro_mal += 1
		dist_cruce = minf(dist_cruce, _distancia_al_cruce_mas_cercano(p))
	_log("  desvío transversal máximo respecto del eje de la calzada: %.4f m | cota y = %.4f (calzada %.2f) | sin alinear: %d" % [
			lat_max, y, -0.15, giro_mal])
	_log("  distancia mínima de una tapa a un cruce: %.2f m (media cuadra = %.2f m)" % [dist_cruce, (_paso - _calzada) * 0.5 + _calzada * 0.5])
	_comprobar(lat_max < 0.02, "todas las tapas están en el centro transversal de la calzada (desvío máx %.4f m)" % lat_max)
	_comprobar(y > -0.16 and y < -0.10, "las tapas están apoyadas en el asfalto, ni enterradas ni flotando (y = %.4f)" % y)
	_comprobar(giro_mal == 0, "todas las tapas van alineadas con el pavimento (%d torcidas)" % giro_mal)
	_comprobar(dist_cruce > _calzada * 0.5 + 3.0, "ninguna tapa cae dentro de un cruce (mínimo %.2f m)" % dist_cruce)


# --------------------------------------------------------------- capturas

func _capturar_vistas() -> void:
	_log("--- D) CAPTURAS ---")
	# Vista aérea cenital de una cuadra completa: se ven los dos cruces, la raya y la tapa.
	var i_v := _nx / 2
	var x_v := _off.x + float(i_v) * _paso
	var k_v := _nz / 2
	var z_c := _off.y + _paso * (float(k_v) + 0.5)
	await _vista(Vector3(x_v, 34.0, z_c), Vector3(x_v, 0.0, z_c), "01_cuadra_cenital")
	# Vista desde el cruce hacia la cuadra, a la altura de un peatón.
	await _vista(Vector3(x_v, 1.7, z_c - (_paso - _calzada) * 0.5 - 1.0), Vector3(x_v, 0.6, z_c + 8.0), "02_calle_desde_cruce")
	# Otra calle, la perpendicular, para comprobar que el eje de las horizontales también está bien.
	var j_h := _nz / 2
	var z_h := _off.y + float(j_h) * _paso
	var x_c := _off.x + _paso * (float(_nx / 2) + 0.5)
	await _vista(Vector3(x_c, 30.0, z_h), Vector3(x_c, 0.0, z_h), "03_cuadra_cenital_horizontal")


func _vista(desde: Vector3, hacia: Vector3, nombre: String) -> void:
	var cam := Camera3D.new()
	cam.top_level = true
	add_child(cam)
	cam.global_position = desde
	var dir := hacia - desde
	var arriba := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > 0.99:
		arriba = Vector3.FORWARD
	cam.look_at(hacia, arriba)
	cam.current = true
	await _frames(6)
	await _capturar(nombre)
	cam.queue_free()


# --------------------------------------------------------------- utilidades

## Todas las instancias (transformaciones) de las MultiMesh cuyo nodo empieza por el
## prefijo dado, agrupadas por nombre de pieza.
func _instancias_por_prefijo(prefijo: String) -> Dictionary:
	var salida := {}
	for n in _todos(_contenedor):
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var nombre := String(mmi.name)
		if not nombre.begins_with(prefijo):
			continue
		var pieza := nombre.split("_x")[0]
		if not salida.has(pieza):
			salida[pieza] = []
		var base := mmi.global_transform
		for i in mmi.multimesh.instance_count:
			(salida[pieza] as Array).append(base * mmi.multimesh.get_instance_transform(i))
	return salida


func _todos(n: Node) -> Array:
	var s: Array = []
	var pila: Array[Node] = [n]
	while not pila.is_empty():
		var x: Node = pila.pop_back()
		s.append(x)
		for h in x.get_children():
			pila.append(h)
	return s


func _largo_de(pieza: String) -> float:
	var ruta := "res://Exports/glTF (Godot)/%s.gltf" % pieza
	if not ResourceLoader.exists(ruta):
		return 0.0
	var ps := ResourceLoader.load(ruta) as PackedScene
	var n := ps.instantiate()
	var m := _mallas(n)
	var caja := AABB()
	var primero := true
	for mi: MeshInstance3D in m:
		for i in mi.mesh.get_surface_count():
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for p in v:
				caja = AABB(p, Vector3.ZERO) if primero else caja.expand(p)
				primero = false
	n.free()
	return caja.size.x


func _mallas(n: Node) -> Array:
	var s: Array = []
	for h in _todos(n):
		if h is MeshInstance3D:
			s.append(h)
	return s


## Margen real del paso de peatones (2.27 m de separación + media pieza más holgura).
func _margen_real() -> float:
	return 2.27 + 4.666 * 0.5 + 0.15


## ¿La pieza está sobre el eje de una calle vertical u horizontal?
func _calle_de(p: Vector3) -> String:
	var mejor := ""
	var mejor_d := 999.0
	for i in _nx + 1:
		var x := _off.x + float(i) * _paso
		var d := absf(p.x - x)
		if d < mejor_d and p.z >= _off.y - 1.0 and p.z <= _off.y + float(_nz) * _paso + 1.0:
			mejor_d = d
			mejor = "V%d" % i
	for j in _nz + 1:
		var z := _off.y + float(j) * _paso
		var d2 := absf(p.z - z)
		if d2 < mejor_d and p.x >= _off.x - 1.0 and p.x <= _off.x + float(_nx) * _paso + 1.0:
			mejor_d = d2
			mejor = "H%d" % j
	return mejor


func _coord(p: Vector3) -> float:
	return p.z if _calle_de(p).begins_with("V") else p.x


func _distancia_al_eje_mas_cercano(p: Vector3, _cualquiera: bool) -> float:
	return _distancia_perp_al_eje(p)


func _distancia_perp_al_eje(p: Vector3) -> float:
	var mejor := 999.0
	for i in _nx + 1:
		mejor = minf(mejor, absf(p.x - (_off.x + float(i) * _paso)))
	for j in _nz + 1:
		mejor = minf(mejor, absf(p.z - (_off.y + float(j) * _paso)))
	return mejor


## Desvío lateral de una pieza respecto del eje de SU calle.
func _offset_lateral(p: Vector3) -> float:
	var calle := _calle_de(p)
	if calle.begins_with("V"):
		return p.x - (_off.x + float(int(calle.substr(1))) * _paso)
	if calle.begins_with("H"):
		return p.z - (_off.y + float(int(calle.substr(1))) * _paso)
	return 999.0


func _distancia_perp(a: Vector3, b: Vector3, _calle: String) -> float:
	var d := a - b
	return Vector2(d.x, d.z).length() - absf(_coord(a) - _coord(b))


func _distancia_al_cruce_mas_cercano(p: Vector3) -> float:
	var mejor := 999.0
	if _calle_de(p).begins_with("V"):
		for j in _nz + 1:
			mejor = minf(mejor, absf(p.z - (_off.y + float(j) * _paso)))
	else:
		for i in _nx + 1:
			mejor = minf(mejor, absf(p.x - (_off.x + float(i) * _paso)))
	return mejor


func _giro_recto(b: Basis) -> bool:
	# Vale cualquier giro que lleve los ejes locales sobre los ejes del mundo
	# (0°, 90°, 180°, 270°): cada columna debe tener un único componente ±1.
	for eje in [b.x, b.y, b.z]:
		var c: Vector3 = (eje as Vector3).abs()
		var alineado := (absf(c.x - 1.0) < 0.001 and c.y < 0.001 and c.z < 0.001) \
				or (c.x < 0.001 and absf(c.y - 1.0) < 0.001 and c.z < 0.001) \
				or (c.x < 0.001 and c.y < 0.001 and absf(c.z - 1.0) < 0.001)
		if not alineado:
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _capturar(nombre: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ok := img.save_png(RUTA_CAPTURAS + "/" + nombre + ".png") == OK
	_log("  captura %s: %s (%dx%d)" % [nombre, str(ok), img.get_width(), img.get_height()])


func _comprobar(ok: bool, texto: String) -> void:
	if not ok:
		_fallos.append(texto)
	_log("  %s %s" % ["OK  " if ok else "FALLO", texto])


func _log(texto: String) -> void:
	print(texto)
	if _f != null:
		_f.store_line(texto)
		_f.flush()


func _cerrar() -> void:
	_log("=== FIN ===")
	if _f != null:
		_f.close()
	get_tree().quit(0 if _fallos.is_empty() else 1)