extends Node3D
## SONDA DE HOJAS de las puertas del modelo de la casa (Tareas 1 y 3).
##
## Carga el MODELO importado tal cual (appartement.glb) y, para cada puerta
## conocida, mira los TRIÁNGULOS que caen dentro de una caja alrededor del vano:
##   · cuántos triángulos hay y de qué malla (Object_4, Object_8, Object_10...);
##   · su caja envolvente (para saber si hay una hoja y cómo está puesta);
##   · un PLANO EN PLANTA (x, z) de 0,10 m por carácter con el número de
##     triángulos de cada celda: la hoja cerrada sale como una raya pegada al
##     vano; una hoja abierta, como una raya diagonal; un mueble, como un bloque.
##
## No modifica nada: sólo mide.

const MODELO := "res://mundo/casa_leo/modelo/appartement.glb"

## Cajas a medir, en coordenadas del MODELO (las del GLB). Son los vanos
## detectados con las sondas de paso.
const CAJAS := [
	["VANO DEL DORMITORIO (este del pasillo)", Vector3(-3.90, 0.02, -3.55), Vector3(-2.80, 2.30, -2.55)],
	["VANO DE LOS BAÑOS (oeste del pasillo)", Vector3(-5.40, 0.02, -4.75), Vector3(-4.80, 2.30, -3.95)],
	["VANO DEL CUARTO NE (norte)", Vector3(-3.80, 0.02, -4.90), Vector3(-3.05, 2.30, -4.10)],
	["PASO DEL PASILLO AL SALÓN (sur)", Vector3(-5.40, 0.02, -0.15), Vector3(-3.55, 2.30, 0.80)],
]

const PASO_PLANO := 0.10


func _ready() -> void:
	var escena := load(MODELO) as PackedScene
	var modelo := escena.instantiate() as Node3D
	add_child(modelo)
	var mallas: Array[MeshInstance3D] = []
	_juntar(modelo, mallas)
	print("[hojas] mallas del modelo: %d" % mallas.size())
	for m: MeshInstance3D in mallas:
		print("[hojas]   %-42s superficies %d" % [String(m.get_path()), m.mesh.get_surface_count()])
	for caja: Array in CAJAS:
		_medir(String(caja[0]), caja[1] as Vector3, caja[2] as Vector3, mallas)
	print("[hojas] FIN")


func _juntar(n: Node, fuera: Array[MeshInstance3D]) -> void:
	var m := n as MeshInstance3D
	if m != null and m.mesh != null:
		fuera.append(m)
	for h in n.get_children():
		_juntar(h, fuera)


func _medir(nombre: String, a: Vector3, b: Vector3, mallas: Array[MeshInstance3D]) -> void:
	# caja ordenada
	var mn := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var mx := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var por_malla := {}
	var total := 0
	var caja_min := Vector3(1e9, 1e9, 1e9)
	var caja_max := Vector3(-1e9, -1e9, -1e9)
	# plano en planta: columnas x de mn.x a mx.x, filas z de mn.z a mx.z
	var cols := int(round((mx.x - mn.x) / PASO_PLANO)) + 1
	var filas := int(round((mx.z - mn.z) / PASO_PLANO)) + 1
	var plano := {}
	var alturas := {}
	for m: MeshInstance3D in mallas:
		var nombre_corto := String(m.name)
		for s in m.mesh.get_surface_count():

			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var n := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
			for t in range(n):
				var v0: Vector3
				var v1: Vector3
				var v2: Vector3
				if idx.size() > 0:
					v0 = verts[idx[t * 3]]
					v1 = verts[idx[t * 3 + 1]]
					v2 = verts[idx[t * 3 + 2]]
				else:
					v0 = verts[t * 3]
					v1 = verts[t * 3 + 1]
					v2 = verts[t * 3 + 2]
				var c := (v0 + v1 + v2) / 3.0
				if c.x < mn.x or c.x > mx.x or c.y < mn.y or c.y > mx.y or c.z < mn.z or c.z > mx.z:
					continue
				total += 1
				por_malla[nombre_corto] = int(por_malla.get(nombre_corto, 0)) + 1
				for v: Vector3 in [v0, v1, v2]:
					caja_min = caja_min.min(v)
					caja_max = caja_max.max(v)
				var i := int(round((c.x - mn.x) / PASO_PLANO))
				var j := int(round((c.z - mn.z) / PASO_PLANO))
				var clave := Vector2i(i, j)
				plano[clave] = int(plano.get(clave, 0)) + 1
				var amax: float = alturas.get(clave, -1e9)
				if c.y > amax:
					alturas[clave] = c.y
	print("")
	print("[hojas] %s" % nombre)
	print("[hojas] caja modelo x %+.2f..%+.2f | y %+.2f..%+.2f | z %+.2f..%+.2f" % [
			mn.x, mx.x, mn.y, mx.y, mn.z, mx.z])
	print("[hojas] triángulos dentro: %d" % total)
	var nombres: Array = por_malla.keys()
	nombres.sort_custom(func(x: String, y: String) -> bool: return int(por_malla[x]) > int(por_malla[y]))
	for nm in nombres:
		print("[hojas]   %-22s %5d triángulos" % [nm, int(por_malla[nm])])
	if total == 0:
		return
	print("[hojas] envolvente de esos triángulos: x %+.2f..%+.2f | y %+.2f..%+.2f | z %+.2f..%+.2f" % [
			caja_min.x, caja_max.x, caja_min.y, caja_max.y, caja_min.z, caja_max.z])
	print("[hojas] PLANTA (x a lo ancho, z hacia abajo) · dígitos = triángulos por celda de %.2f m" % PASO_PLANO)
	var cabecera := "        "
	for i in range(cols):
		var x := mn.x + i * PASO_PLANO
		if absf(round(x * 2.0) / 2.0 - x) < 0.001:
			cabecera += "%4.1f" % x
		else:
			cabecera += "    "
	print(cabecera)
	for j in range(filas):
		var linea := "%+6.2f  " % (mn.z + j * PASO_PLANO)
		for i in range(cols):
			var c := plano.get(Vector2i(i, j), 0) as int
			if c == 0:
				linea += "."
			elif c < 10:
				linea += str(c)
			else:
				linea += "#"
		print(linea)