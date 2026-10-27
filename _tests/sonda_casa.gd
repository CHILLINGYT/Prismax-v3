extends Node3D
## SONDA DE LA CASA DE LEO (Fase 1).
##
## Mide el modelo REAL `res://modelos 3d casa leo/appartement.glb` y lo dibuja como
## PLANO DE PLANTA en la consola, para poder colocar el punto de aparición, la
## salida, las colisiones y las vistas de las ventanas con coordenadas exactas (no
## a ojo).
##
## Método (honesto y comprobable):
##   · cada triángulo de cada malla se clasifica por su normal y por su rango de
##     altura: las superficies VERTICALES (paredes, laterales de muebles) se
##     rasterizan sobre una rejilla en planta de 0,15 m;
##   · se usan DOS bandas de altura:
##       banda A (0,25–1,75 m) = lo que bloquea el paso de una persona;
##       banda B (1,30–1,90 m) = por encima de los antepechos.
##     Con las dos se distingue sin ambigüedad:
##       A libre + B libre  -> PUERTA / vano a pie (se pasa)
##       A ocupada + B libre -> VENTANA (antepecho abajo, hueco arriba)
##       A ocupada + B ocupada -> PARED
##   · de cada vértice se guarda, por celda, la MINIMA altura por encima de 1 m
##     (dintel de las puertas) y la MAXIMA por debajo de 1,2 m (antepecho de las
##     ventanas).
##   · al final se mide el coste de crear la colisión triangle-mesh de cada malla
##     (para decidir si es viable como solución de física).

const CASA := "res://modelos 3d casa leo/appartement.glb"
const CELDA := 0.15
const BANDA_A := Vector2(0.25, 1.75)
const BANDA_B := Vector2(1.30, 1.90)

var _min := Vector3.ZERO
var _max := Vector3.ZERO
var _cols := 0
var _rows := 0
var _bloqueo_a: PackedByteArray = []
var _bloqueo_b: PackedByteArray = []
var _min_arriba: PackedFloat32Array = []   # mínima altura > 1 m por celda
var _max_abajo: PackedFloat32Array = []    # máxima altura < 1,2 m por celda
var _mallas: Array = []

func _ready() -> void:
	var modelo := (load(CASA) as PackedScene).instantiate() as Node3D
	add_child(modelo)
	await get_tree().process_frame
	_medir_mallas(modelo)
	_rejilla()
	_rasterizar()
	_mapa_compacto()
	print("[sonda] FIN")
	await get_tree().create_timer(0.3).timeout


## Cajas y estadísticas de cada malla (en coordenadas del modelo).
func _medir_mallas(modelo: Node) -> void:
	print("[sonda] --- mallas ---")
	for m in modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := _transform_hasta(mi, modelo)
		var caja := _transformar_aabb(mi.get_aabb(), t)
		var tris := 0
		var verts := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			tris += int(floorf(idx.size() / 3.0)) if idx.size() > 0 \
					else int(floorf((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0))
		_mallas.append({"nodo": String(mi.name), "t": t})
		print("[sonda] %s | caja %.2f×%.2f×%.2f | min (%.2f, %.2f, %.2f) | %d verts, %d tris" % [
				mi.name, caja.size.x, caja.size.y, caja.size.z,
				caja.position.x, caja.position.y, caja.position.z, verts, tris])
	# Coste real de la colisión triangle-mesh (la posible solución de física).
	var total := 0
	for m in modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t0 := Time.get_ticks_msec()
		var forma := mi.mesh.create_trimesh_shape()
		var ms := Time.get_ticks_msec() - t0
		total += ms
		print("[sonda] triangle-mesh de %s: %d ms (%d caras)" % [mi.name, ms, forma.get_faces().size() if forma != null else -1])
	print("[sonda] coste TOTAL de crear las 6 colisiones triangle-mesh: %d ms" % total)


func _rejilla() -> void:
	# Caja total del modelo (unión de las cajas de todas las mallas).
	var caja := AABB()
	var primero := true
	for m in _mallas:
		var nombre: String = m["nodo"]
		var t: Transform3D = m["t"]
		var mi := _buscar_malla(nombre)
		if mi == null:
			continue
		var c := _transformar_aabb(mi.get_aabb(), t)
		caja = c if primero else caja.merge(c)
		primero = false
	_min = caja.position
	_max = caja.position + caja.size
	_cols = int(ceil(caja.size.x / CELDA)) + 1
	_rows = int(ceil(caja.size.z / CELDA)) + 1
	var n := _cols * _rows
	_bloqueo_a.resize(n)
	_bloqueo_b.resize(n)
	_min_arriba.resize(n)
	_max_abajo.resize(n)
	for i in n:
		_min_arriba[i] = 99.0
		_max_abajo[i] = -99.0
	print("[sonda] caja total: min (%.2f, %.2f, %.2f) max (%.2f, %.2f, %.2f)" % [
			_min.x, _min.y, _min.z, _max.x, _max.y, _max.z])
	print("[sonda] rejilla: %d × %d celdas de %.2f m" % [_cols, _rows, CELDA])


func _buscar_malla(nombre: String) -> MeshInstance3D:
	for n in find_children(nombre, "MeshInstance3D", true, false):
		return n as MeshInstance3D
	return null


func _rasterizar() -> void:
	var mallas := _mallas.duplicate()
	for m in mallas:
		var mi := _buscar_malla(String(m["nodo"]))
		if mi == null:
			continue
		var t: Transform3D = m["t"]
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			var caras := int(idx.size() / 3) if idx.size() > 0 else int(vs.size() / 3)
			for f in caras:
				var a := vs[idx[f * 3]] if idx.size() > 0 else vs[f * 3]
				var b := vs[idx[f * 3 + 1]] if idx.size() > 0 else vs[f * 3 + 1]
				var c := vs[idx[f * 3 + 2]] if idx.size() > 0 else vs[f * 3 + 2]
				a = t * a
				b = t * b
				c = t * c
				_triangulo(a, b, c)


## Clasifica un triángulo ya transformado: verticales -> rejilla; todos -> dinteles
## y antepechos por celda.
func _triangulo(a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var largo := n.length()
	if largo > 0.00001:
		n /= largo
	var y_min := minf(a.y, minf(b.y, c.y))
	var y_max := maxf(a.y, maxf(b.y, c.y))
	# Dinteles (primera geometría por encima de 1 m) y antepechos (última por debajo de 1,2 m).
	for v in [a, b, c]:
		var celda := _celda(v.x, v.z)
		if celda < 0:
			continue
		if v.y >= 1.0 and v.y < _min_arriba[celda]:
			_min_arriba[celda] = v.y
		if v.y <= 1.2 and v.y > _max_abajo[celda]:
			_max_abajo[celda] = v.y
	# Superficies verticales: se marca su huella en planta en cada banda.
	if absf(n.y) > 0.5:
		return
	if y_max >= BANDA_A.x and y_min <= BANDA_A.y:
		_rasterizar_borde(a, b, c, true)
	if y_max >= BANDA_B.x and y_min <= BANDA_B.y:
		_rasterizar_borde(a, b, c, false)


## Marca las celdas que toca el borde proyectado del triángulo (huella en planta).
func _rasterizar_borde(a: Vector3, b: Vector3, c: Vector3, banda_a: bool) -> void:
	for par in [[a, b], [b, c], [c, a]]:
		var p0: Vector3 = par[0]
		var p1: Vector3 = par[1]
		var largo := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		var pasos := maxi(1, int(largo / (CELDA * 0.4)))
		for i in pasos + 1:
			var u := float(i) / float(pasos)
			var x := lerpf(p0.x, p1.x, u)
			var z := lerpf(p0.z, p1.z, u)
			var celda := _celda(x, z)
			if celda < 0:
				continue
			if banda_a:
				_bloqueo_a[celda] = 1
			else:
				_bloqueo_b[celda] = 1


func _celda(x: float, z: float) -> int:
	var cx := int(floor((x - _min.x) / CELDA))
	var cz := int(floor((z - _min.z) / CELDA))
	if cx < 0 or cz < 0 or cx >= _cols or cz >= _rows:
		return -1
	return cz * _cols + cx


## Mapa ÚNICO de la planta con lo que importa para colocar cosas:
##   '#' = ocupada de suelo a techo (pared / mueble alto) -> no se pasa
##   'w' = ocupada abajo (0,25-1,75 m) pero hueca arriba (1,3-1,9 m) -> antepecho:
##         ventana si está en el perímetro, mueble bajo si está dentro
##   '.' = libre a las dos alturas -> se pasa (vano, puerta, suelo libre)
## PLANTA COMPACTA para leer de un vistazo: cada carácter son 2×2 celdas (0,30 m).
##   '#' = ocupada de suelo a techo (pared o mueble alto) -> no se pasa
##   'w' = ocupada abajo y hueca arriba -> antepecho (ventana en el perímetro,
##         mueble bajo dentro)
##   '.' = libre a las dos alturas -> se pasa (vanos y suelo libre)
func _mapa_compacto() -> void:
	print("[sonda] ============ PLANTA 2x2 (0,30 m/carácter): '#' pared, 'w' antepecho/ventana, '.' paso ============")
	var cab := "      "
	for cx in range(0, _cols, 10):
		cab += "%-6d" % int(round(_min.x + float(cx) * CELDA))
	print(cab)
	for cz in range(0, _rows, 2):
		var fila := "%+5.1f " % (_min.z + float(cz) * CELDA)
		for cx in range(0, _cols, 2):
			var hay_a := false
			var hay_b := false
			for dz in 2:
				for dx in 2:
					var c := (cz + dz) * _cols + (cx + dx)
					if c < _bloqueo_a.size() and _bloqueo_a[c] == 1:
						hay_a = true
						if _bloqueo_b[c] == 1:
							hay_b = true
			if hay_a:
				fila += "#" if hay_b else "w"
			else:
				fila += "."
		print(fila)





func _transform_hasta(nodo: Node, raiz: Node) -> Transform3D:
	var t := Transform3D()
	var n := nodo
	while n != null and n != raiz:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _transformar_aabb(caja: AABB, t: Transform3D) -> AABB:
	var r := AABB(t * caja.position, Vector3.ZERO)
	for i in range(1, 8):
		r = r.expand(t * caja.get_endpoint(i))
	return r