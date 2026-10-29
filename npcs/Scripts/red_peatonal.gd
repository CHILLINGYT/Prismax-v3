class_name RedPeatonal
extends RefCounted

## =============================================================================
##  RED PEATONAL — el grafo de por dónde PUEDE caminar un peatón
## =============================================================================
##  La calzada no es una superficie válida: los ciudadanos sólo se mueven por
##  las ARISTAS de esta red, y todas las aristas son de una de estas clases:
##
##    acera  · tramo de vereda (las bandas de 3 m alrededor de cada manzana)
##    cruce  · paso de peatones PINTADO (se registran los que el generador
##             realmente coloca en `_interseccion`: 4 brazos por cruce, cada uno
##             con su sorteo; aquí no se inventa ningún cruce)
##    plaza  · interior pavimentado de una plaza y su acceso desde la vereda
##    parque · senderos en cruz de un parque y su acceso desde la vereda
##    paseo  · paseo costero (la losa pavimentada que sigue la costa)
##    acceso · escalón vereda→paseo y paseo→arena (franjas de pasto/transición)
##    arena  · la arena seca de la playa (una calle de nodos elegida donde no
##             hay sombrillas, reposeras ni palmeras)
##
##  La red se construye a partir de los MISMOS datos con los que el generador
##  levanta la ciudad (`_trazado`, manzanas, plazas, parques, cruces pintados,
##  paseo costero y playa), así que sigue al mapa real y se adapta si cambia.
##
##  Geometría (medidas reales del generador):
##    · línea de calle i  ->  x = off.x + i*paso      (paso = manzana + 2*hw)
##    · calzada          ->  ±calzada/2 alrededor de la línea
##    · vereda           ->  de calzada/2 a calzada/2+acera; su eje a +7.5 m
##    · esquina de manzana -> (línea ± 7.5)
##    · cruce pintado    ->  a ±(calzada/2 + 2.27) del centro del cruce
## =============================================================================

const TIPOS_ARISTA := ["acera", "cruce", "plaza", "parque", "paseo", "acceso", "arena"]

## Vértices: {"pos": Vector3, "tipo": String}
var nodos: Array[Dictionary] = []
## Vecinos por vértice (y la clase de arista, en el mismo orden).
var _vecinos: Array[Array] = []
var _aristas: Array[Array] = []

var _claves: Dictionary = {}          # clave geométrica -> índice de vértice
var _por_tipo: Dictionary = {}        # tipo -> Array[int] (se cachea)

var _trazado: Dictionary
var _manzanas: Vector2i
## Plantas ya colocadas por el generador (troncos y canteros, Vector3): los vértices
## interiores de plazas y parques se apartan de ellas para no atravesar un árbol.
var _obstaculos: Array[Vector3] = []


# =============================================================================
#  Construcción
# =============================================================================

## Construye la red. `datos` lleva:
##   trazado: {calzada, acera, manzana, hw, paso, ext, off}, manzanas: Vector2i,
##   plazas: Array[Rect2], parques: Array[Rect2],
##   cruces: Array[{i, j, lado}]  (lado = "N"/"S"/"E"/"W", los brazos pintados),
##   paseo: Array de cadenas (cada una Array[Vector3] en orden),
##   arena: Array de cadenas (idem).
func construir(datos: Dictionary) -> void:
	nodos.clear()
	_vecinos.clear()
	_aristas.clear()
	_claves.clear()
	_por_tipo.clear()
	_trazado = datos["trazado"]
	_manzanas = datos["manzanas"]
	_obstaculos.clear()
	for p: Vector3 in datos.get("obstaculos", []):
		_obstaculos.append(p)

	# 1) Veredas: cada manzana aporta sus 4 esquinas y sus 4 tramos (con un punto
	#    medio por lado, que es donde enganchan plazas, parques y el paseo).
	for i in _manzanas.x:
		for j in _manzanas.y:
			_construir_manzana(i, j)
	_construir_vereda_exterior()

	# 2) Cruces: sólo los brazos con paso pintado (registrados por el generador).
	for cruce: Dictionary in datos.get("cruces", []):
		_construir_cruce(int(cruce["i"]), int(cruce["j"]), String(cruce["lado"]))

	# 3) Plazas y parques: interior (nodos propios) + accesos desde la vereda.
	for rect: Rect2 in datos.get("plazas", []):
		_construir_interior(rect, "plaza")
	for rect: Rect2 in datos.get("parques", []):
		_construir_interior(rect, "parque")

	# 4) Paseo costero: cadenas de nodos + enganche a la vereda exterior.
	var indice_paseo: Array[int] = []
	for cadena: Array in datos.get("paseo", []):
		indice_paseo.append_array(_construir_cadena(cadena, "paseo", 9.0))
	for idx in indice_paseo:
		_enlazar_con_tipo(idx, "acera", 9.0, "acceso")

	# 5) Arena: cadenas + enganche al paseo más cercano.
	for cadena: Array in datos.get("arena", []):
		var idxs := _construir_cadena(cadena, "arena", 11.0)
		for idx in idxs:
			_enlazar_con_tipo(idx, "paseo", 16.0, "acceso")


func _construir_manzana(i: int, j: int) -> void:
	var nw := _esquina(i, j, 1, 1)
	var ne := _esquina(i + 1, j, -1, 1)
	var sw := _esquina(i, j + 1, 1, -1)
	var se := _esquina(i + 1, j + 1, -1, -1)
	var centro := _centro_manzana(i, j)
	# Puntos medios de cada lado: mitad de la línea de vereda del lado.
	_lado_vereda(nw, ne, Vector3(centro.x, 0.0, _linea_z(j) + _sep()), "acera")
	_lado_vereda(sw, se, Vector3(centro.x, 0.0, _linea_z(j + 1) - _sep()), "acera")
	_lado_vereda(nw, sw, Vector3(_linea_x(i) + _sep(), 0.0, centro.y), "acera")
	_lado_vereda(ne, se, Vector3(_linea_x(i + 1) - _sep(), 0.0, centro.y), "acera")


## Un tramo de vereda entre dos esquinas, partido en dos por su punto medio (el
## eje de la vereda lo da el propio punto medio; las esquinas van al mismo eje).
func _lado_vereda(a: int, b: int, medio: Vector3, clase: String) -> void:
	if a < 0 or b < 0:
		return
	var m := _nodo(medio, "acera")
	_unir(a, m, clase)
	_unir(m, b, clase)


func _construir_cruce(i: int, j: int, lado: String) -> void:
	var nw := _esquina(i, j, -1, 1)
	var ne := _esquina(i, j, 1, 1)
	var se := _esquina(i, j, 1, -1)
	var sw := _esquina(i, j, -1, -1)
	match lado:
		"N":
			_unir(nw, ne, "cruce")   # se cruza la calle vertical por el brazo norte
		"S":
			_unir(sw, se, "cruce")
		"E":
			_unir(ne, se, "cruce")   # se cruza la calle horizontal por el brazo este
		"W":
			_unir(nw, sw, "cruce")


## Interior de una plaza (pavimento) o de un parque (senderos en cruz).
func _construir_interior(rect: Rect2, clase: String) -> void:
	var c := rect.get_center()
	var y := 0.0 if clase == "plaza" else -0.15
	var centro := _nodo(_apartar_de_plantas(Vector3(c.x, y, c.y)), clase)
	# Bocas del interior: en el parque son las bocas de los senderos en cruz; en
	# la plaza, los cuatro puntos medios del pavimento (mismo sitio, sin camino).
	var lados: Array = [
		Vector3(c.x, y, rect.position.y + 1.5),
		Vector3(c.x, y, rect.end.y - 1.5),
		Vector3(rect.position.x + 1.5, y, c.y),
		Vector3(rect.end.x - 1.5, y, c.y),
	]
	var idxs: Array[int] = []
	for l: Vector3 in lados:
		var idx := _nodo(_apartar_de_plantas(l), clase)
		_unir(centro, idx, clase)
		idxs.append(idx)
	# Anillo del interior (para pasear sin volver siempre por el centro).
	for k in idxs.size():
		var a: int = idxs[k]
		var b: int = idxs[(k + 1) % idxs.size()]
		_unir(a, b, clase)
	# Acceso desde la vereda: cada boca engancha con el punto medio de vereda
	# más cercano de su mismo lado (la franja de vereda es pavimento, sin calle).
	for idx2 in idxs:
		_enlazar_con_tipo(idx2, "acera", 12.0, "acceso")


## Aparta un vértice interior de la vegetación plantada (troncos y canteros de la plaza
## o el parque): si el punto cae a menos de 1,2 m de una planta, se desplaza en línea
## recta hasta dejarla libre. El desplazamiento es corto y nunca sale del solar.
func _apartar_de_plantas(p: Vector3) -> Vector3:
	if _obstaculos.is_empty():
		return p
	var q := p
	for _vuelta in 2:
		for o: Vector3 in _obstaculos:
			var d := Vector2(q.x - o.x, q.z - o.z)
			var largo := d.length()
			if largo > 1.2:
				continue
			var dir := d / largo if largo > 0.001 else Vector2(1.0, 0.0)
			var empuje := 1.2 - largo
			q.x += dir.x * empuje
			q.z += dir.y * empuje
	return q


func _construir_cadena(cadena: Array, clase: String, max_paso: float) -> Array[int]:
	var idxs: Array[int] = []
	var anterior := -1
	var pos_anterior := Vector3.ZERO
	for p: Vector3 in cadena:
		var idx := _nodo(p, clase)
		idxs.append(idx)
		if anterior >= 0 and pos_anterior.distance_to(Vector3(p.x, pos_anterior.y, p.z)) <= max_paso:
			_unir(anterior, idx, clase)
		anterior = idx
		pos_anterior = Vector3(p.x, p.y, p.z)
	return idxs


## Enlaza un vértice con el vértice del tipo pedido más cercano dentro de `radio`.
func _enlazar_con_tipo(idx: int, tipo_buscado: String, radio: float, clase: String) -> void:
	var mejor := -1
	var mejor_d := radio * radio
	var p: Vector3 = nodos[idx]["pos"]
	for otro in nodos_de_tipo([tipo_buscado]):
		var d := (nodos[otro]["pos"] as Vector3).distance_squared_to(p)
		if d < mejor_d:
			mejor_d = d
			mejor = otro
	if mejor >= 0:
		_unir(idx, mejor, clase)


# =============================================================================
#  Piezas de la retícula
# =============================================================================

func _linea_x(i: int) -> float:
	return float(_trazado.off.x) + float(i) * float(_trazado.paso)


func _linea_z(j: int) -> float:
	return float(_trazado.off.y) + float(j) * float(_trazado.paso)


## Eje de la vereda respecto de la línea de calle: 2/3 del ancho de acera. NO se usa el
## centro (6+1,5 = 7,5 m) porque los árboles de alineación van arrimados al bordillo
## (0,7 m hacia la calzada, con su cantero de hasta 0,7 m de radio) y los peldaños de los
## portales salen hacia la vereda: a 8,0 m el peatón pasa entre el cantero y el portal.
func _sep() -> float:
	return float(_trazado.calzada) * 0.5 + float(_trazado.acera) * (2.0 / 3.0)


func _centro_manzana(i: int, j: int) -> Vector2:
	return Vector2(_linea_x(i) + float(_trazado.paso) * 0.5,
			_linea_z(j) + float(_trazado.paso) * 0.5)


## Vértice de esquina (sx, sz = ±1): la esquina de la manzana que la toca, o el
## nodo de la vereda EXTERIOR cuando esa manzana no existe (sólo en los bordes
## este y sur, que son los que dan al paseo; al norte y al oeste no hay nada).
func _esquina(i: int, j: int, sx: int, sz: int) -> int:
	var x := _linea_x(i) + float(sx) * _sep()
	var z := _linea_z(j) + float(sz) * _sep()
	var bi := i if sx > 0 else i - 1
	var bj := j if sz > 0 else j - 1
	var bi_ok := bi >= 0 and bi < _manzanas.x
	var bj_ok := bj >= 0 and bj < _manzanas.y
	if bi_ok and bj_ok:
		return _nodo(Vector3(x, 0.0, z), "acera", "esq_%d_%d_%d_%d" % [i, j, sx, sz])
	# Vereda EXTERIOR del borde costero: falta la manzana del borde en un eje y
	# el otro eje tiene manzana (o es también el borde, en la esquina sureste).
	var este := sx > 0 and i == _manzanas.x and (bj_ok or (sz > 0 and j == _manzanas.y))
	var sur := sz > 0 and j == _manzanas.y and (bi_ok or (sx > 0 and i == _manzanas.x))
	if este or sur:
		return _nodo(Vector3(x, 0.0, z), "acera", "ext_%d_%d_%d_%d" % [i, j, sx, sz])
	return -1


## Vereda exterior del borde costero: las dos líneas que dan al mar (este y sur)
## también tienen acera por fuera, y por ahí se llega al paseo. Se teje igual
## que un lado de manzana (esquina - punto medio - esquina).
func _construir_vereda_exterior() -> void:
	var nx := _manzanas.x
	var ny := _manzanas.y
	var paso := float(_trazado.paso)
	var x_ext := _linea_x(nx) + _sep()
	var z_ext := _linea_z(ny) + _sep()
	# Borde este (discurre en Z), con sus puntos medios por manzana.
	for j in ny:
		var a := _esquina(nx, j, 1, 1)
		var b := _esquina(nx, j + 1, 1, -1)
		if a >= 0 and b >= 0:
			_lado_vereda(a, b, Vector3(x_ext, 0.0, _linea_z(j) + paso * 0.5), "acera")
	# Borde sur (discurre en X).
	for i in nx:
		var a2 := _esquina(i, ny, 1, 1)
		var b2 := _esquina(i + 1, ny, -1, 1)
		if a2 >= 0 and b2 >= 0:
			_lado_vereda(a2, b2, Vector3(_linea_x(i) + paso * 0.5, 0.0, z_ext), "acera")


# =============================================================================
#  Grafo
# =============================================================================

func _nodo(punto: Vector3, tipo_nodo: String, clave := "") -> int:
	if clave != "" and _claves.has(clave):
		return _claves[clave]
	nodos.append({"pos": punto, "tipo": tipo_nodo})
	_vecinos.append([])
	_aristas.append([])
	var idx := nodos.size() - 1
	if clave != "":
		_claves[clave] = idx
	_por_tipo.clear()
	return idx


func _unir(a: int, b: int, clase: String) -> void:
	if a < 0 or b < 0 or a == b:
		return
	if _vecinos[a].has(b) or _vecinos[b].has(a):
		return
	_vecinos[a].append(b)
	_aristas[a].append(clase)
	_vecinos[b].append(a)
	_aristas[b].append(clase)


func pos(i: int) -> Vector3:
	return nodos[i]["pos"]


func tipo(i: int) -> String:
	return String(nodos[i]["tipo"])


## Clase de la arista entre dos vértices ("" si no hay arista).
func arista(a: int, b: int) -> String:
	if a < 0 or b < 0 or a >= nodos.size() or b >= nodos.size():
		return ""
	var k: int = _vecinos[a].find(b)
	return String(_aristas[a][k]) if k >= 0 else ""


func vecinos(i: int) -> Array:
	return _vecinos[i]


func nodos_de_tipo(tipos: Array) -> Array:
	var clave := String(",".join(tipos))
	if not _por_tipo.has(clave):
		var lista: Array = []
		for i in nodos.size():
			if tipos.has(tipo(i)):
				lista.append(i)
		_por_tipo[clave] = lista
	return _por_tipo[clave]


## Nodo más cercano de entre los tipos pedidos (en horizontal; la altura va con
## el nodo, que es lo que hace que el peatón suba o baje el escalón del paseo).
func nodo_mas_cercano(p: Vector3, tipos: Array = []) -> int:
	var lista: Array = nodos_de_tipo(tipos) if not tipos.is_empty() else range(nodos.size())
	var mejor := -1
	var mejor_d := INF
	for i: int in lista:
		var q: Vector3 = nodos[i]["pos"]
		var d := Vector2(q.x, q.z).distance_squared_to(Vector2(p.x, p.z))
		if d < mejor_d:
			mejor_d = d
			mejor = i
	return mejor


## Ruta peatonal entre dos vértices (A* con heurística en línea recta sobre la
## red, así que el resultado SÓLO usa aristas válidas). Devuelve los vértices.
func ruta(a: int, b: int) -> PackedInt32Array:
	var vacia := PackedInt32Array()
	if a < 0 or b < 0 or a >= nodos.size() or b >= nodos.size():
		return vacia
	var meta: Vector3 = nodos[b]["pos"]
	var abiertos: Array[int] = [a]
	var g: Dictionary = {a: 0.0}
	var f: Dictionary = {a: 0.0}
	var de: Dictionary = {}
	while not abiertos.is_empty():
		# Mínimo por f (la lista abierta se queda corta: es una retícula).
		var mejor_k := 0
		for k in abiertos.size():
			if float(f.get(abiertos[k], INF)) < float(f.get(abiertos[mejor_k], INF)):
				mejor_k = k
		var actual: int = abiertos[mejor_k]
		abiertos.remove_at(mejor_k)
		if actual == b:
			var salida := PackedInt32Array()
			var paso := b
			while paso != a:
				salida.insert(0, paso)
				paso = de[paso]
			salida.insert(0, a)
			return salida
		var pa: Vector3 = nodos[actual]["pos"]
		for v in _vecinos[actual]:
			var pv: Vector3 = nodos[v]["pos"]
			var coste := float(g[actual]) + Vector2(pa.x, pa.z).distance_to(Vector2(pv.x, pv.z))
			if coste < float(g.get(v, INF)):
				g[v] = coste
				de[v] = actual
				f[v] = coste + Vector2(pv.x, pv.z).distance_to(Vector2(meta.x, meta.z))
				if not abiertos.has(v):
					abiertos.append(v)
	return vacia


## Longitud (m) de una ruta, en horizontal.
func longitud(r: PackedInt32Array) -> float:
	var total := 0.0
	for k in r.size() - 1:
		var a: Vector3 = nodos[r[k]]["pos"]
		var b: Vector3 = nodos[r[k + 1]]["pos"]
		total += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	return total


## ¿La posición cae sobre una calzada? (geometría real del trazado: cada línea de calle
## SÓLO tiene asfalto a lo largo del núcleo urbano, así que también se comprueba el
## recorrido: fuera de la ciudad —la costa, el paseo, la playa— no hay calzada ninguna).
func es_calzada(p: Vector3) -> bool:
	var medio := float(_trazado.calzada) * 0.5
	var x0 := _linea_x(0)
	var x1 := _linea_x(_manzanas.x)
	var z0 := _linea_z(0)
	var z1 := _linea_z(_manzanas.y)
	if p.z >= z0 - 0.001 and p.z <= z1 + 0.001:
		for i in _manzanas.x + 1:
			if absf(p.x - _linea_x(i)) <= medio:
				return true
	if p.x >= x0 - 0.001 and p.x <= x1 + 0.001:
		for j in _manzanas.y + 1:
			if absf(p.z - _linea_z(j)) <= medio:
				return true
	return false


## ¿La ruta usa sólo aristas válidas y ningún cruce fuera de los pintados?
func ruta_valida(r: PackedInt32Array) -> bool:
	for k in r.size() - 1:
		if arista(r[k], r[k + 1]) == "":
			return false
	return true


## Recuento de la red (para informes y pruebas).
func resumen() -> Dictionary:
	var por_tipo := {}
	for i in nodos.size():
		por_tipo[tipo(i)] = int(por_tipo.get(tipo(i), 0)) + 1
	var por_arista := {}
	for i in _aristas.size():
		for t: String in _aristas[i]:
			por_arista[t] = float(por_arista.get(t, 0.0)) + 0.5
	var aristas := {}
	for k: String in por_arista:
		aristas[k] = int(por_arista[k])
	return {"nodos": nodos.size(), "por_tipo": por_tipo, "aristas": aristas}