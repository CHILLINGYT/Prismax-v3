extends Node3D
## SONDA DE TRANSITABILIDAD de la casa de Leo (Tarea 3).
##
## Carga la casa REAL (con sus colisiones tal como están en el juego) y pregunta
## al motor, celda a celda de una rejilla de 0,25 m, si la CÁPSULA DEL JUGADOR
## cabe ahí (PhysicsShapeQueryParameters3D + intersect_shape). Después inunda
## desde el punto donde aparece Leo y saca:
##   · un mapa  ( # tapado · o alcanzable · . libre pero sin llegar )
##   · la cuenta por ZONAS (pasillo, dormitorio, cuarto NE, baños, salón/cocina)
##   · la lista de CHOQUES que frenan el paso en la frontera (nombre del cuerpo y
##     el punto), que es lo que dice QUÉ geometría bloquea cada acceso.
##
## Con eso se ven las habitaciones que hoy no se pueden pisar y por qué.

const CASA := "res://casa_leo/casa_leo.tscn"
const PASO := 0.25          ## m por celda
const RADIO := 0.25   ## el mismo radio que usa Leo DENTRO de la casa
const ALTO := 1.80          ## m (por encima de alfombras de 1-3 cm y bajo dinteles)
const ALTURA_PIE := 1.02    ## m: centro de la cápsula (pie a 0,12 m)
const X_MIN := -4.5
const X_MAX := 4.5
const Z_MIN := -7.0
const Z_MAX := 7.0

var _casa: CasaLeo
var _cols := 0
var _filas := 0
var _libre := {}            ## Vector2i -> bool
var _alcanza := {}          ## Vector2i -> true
var _mundo: PhysicsDirectSpaceState3D
var _caps := CapsuleShape3D.new()
## Cuerpos que NO cuentan: el propio jugador (si no, su cápsula taparía el pasillo
## alrededor del punto de aparición y el mapa saldría partido en dos).
var _excluir: Array[RID] = []


func _ready() -> void:
	_casa = (load(CASA) as PackedScene).instantiate() as CasaLeo
	add_child(_casa)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_caps.radius = RADIO
	_caps.height = ALTO
	_mundo = get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("player"):
		var cuerpo := n as CollisionObject3D
		if cuerpo != null:
			_excluir.append(cuerpo.get_rid())
	print("[paso] cuerpos de jugador excluidos de la consulta: %d" % _excluir.size())
	_cols = int(round((X_MAX - X_MIN) / PASO)) + 1
	_filas = int(round((Z_MAX - Z_MIN) / PASO)) + 1
	print("[paso] rejilla %d × %d celdas de %.2f m | cápsula r=%.2f h=%.2f" % [
			_cols, _filas, PASO, RADIO, ALTO])
	_medir()
	_inundar()
	_mapa()
	_zonas()
	_frontera()
	_fina("VANO DEL DORMITORIO (este del pasillo)", -1.2, 1.6, -3.5, -1.7, Vector2(-1.0, -2.5))
	_fina("ENTRADA AL CUARTO NE (norte)", -1.6, 1.6, -5.7, -3.9, Vector2(-1.0, -4.4))
	_fina("PASO AL SALON-COCINA (sur del pasillo)", -3.2, 0.6, 1.0, 3.7, Vector2(-2.0, 2.4))
	print("[paso] FIN")


func _celda(x: float, z: float) -> Vector2i:
	return Vector2i(int(round((x - X_MIN) / PASO)), int(round((z - Z_MIN) / PASO)))


func _pos(c: Vector2i) -> Vector3:
	return Vector3(X_MIN + c.x * PASO, ALTURA_PIE, Z_MIN + c.y * PASO)


## ¿Cabe la cápsula del jugador centrada en esta celda?
func _cabe(c: Vector2i) -> bool:
	return _cabe_en(_pos(c))


## ¿Cabe la cápsula del jugador centrada en esta posición exacta?
func _cabe_en(pos: Vector3) -> bool:
	var p := PhysicsShapeQueryParameters3D.new()
	p.shape = _caps
	p.collision_mask = 1
	p.exclude = _excluir
	p.transform = Transform3D(Basis(), pos)
	return _mundo.intersect_shape(p, 1).is_empty()


func _medir() -> void:
	for i in _cols:
		for j in _filas:
			var c := Vector2i(i, j)
			_libre[c] = _cabe(c)


## Inunda desde donde aparece Leo (o desde la celda libre más cercana).
func _inundar() -> void:
	var jug := _casa.jugador()
	var desde := jug.global_position if jug != null else Vector3.ZERO
	var inicio := _celda(desde.x, desde.z)
	if not _libre.get(inicio, false):
		var mejor := inicio
		var mejor_d := 1e9
		for c in _libre.keys():
			if not _libre[c]:
				continue
			var d := (_pos(c) - desde).length()
			if d < mejor_d:
				mejor_d = d
				mejor = c
		inicio = mejor
		print("[paso] el punto de aparición no está libre: se inunda desde %s (a %.2f m)" % [
				str(_pos(inicio)), mejor_d])
	var cola: Array[Vector2i] = [inicio]
	_alcanza[inicio] = true
	while not cola.is_empty():
		var c: Vector2i = cola.pop_back()
		for paso: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var v: Vector2i = c + paso
			if v.x < 0 or v.y < 0 or v.x >= _cols or v.y >= _filas:
				continue
			if _alcanza.has(v) or not _libre.get(v, false):
				continue
			_alcanza[v] = true
			cola.append(v)


## Mapa compacto: cada carácter son 2×2 celdas (0,50 m).
func _mapa() -> void:
	print("[paso] MAPA (0,50 m por carácter) | # tapado · o alcanzable · . libre sin llegar")
	var cab := "        "
	for i in range(0, _cols, 2):
		var x := X_MIN + i * PASO
		cab += "%d" % (int(round(x / 2.0)) % 10) if absf(x - roundf(x / 2.0) * 2.0) < 0.01 else " "
	print(cab)
	for j in range(0, _filas, 2):
		var linea := "%+6.1f  " % (Z_MIN + j * PASO)
		for i in range(0, _cols, 2):
			var bloque: Array[Vector2i] = [
				Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]
			var algun_libre := false
			var algun_alcanza := false
			for c in bloque:
				if _alcanza.get(c, false):
					algun_alcanza = true
				if _libre.get(c, false):
					algun_libre = true
			linea += "o" if algun_alcanza else ("." if algun_libre else "#")
		print(linea)


func _zonas() -> void:
	var zonas := {
		"pasillo": [Vector2(-2.10, -5.00), Vector2(-0.80, 1.50)],
		"dormitorio (este del pasillo)": [Vector2(-0.10, -3.50), Vector2(4.20, -1.20)],
		"cuarto NE (norte, al este)": [Vector2(-0.10, -6.50), Vector2(4.20, -4.20)],
		"baños (oeste del pasillo)": [Vector2(-4.20, -4.90), Vector2(-2.20, 0.20)],
		"salón y cocina (sur)": [Vector2(-4.20, 1.60), Vector2(4.20, 6.30)],
		"oeste del salón (sur-oeste)": [Vector2(-4.20, 0.30), Vector2(-2.20, 1.50)],
	}
	for nombre in zonas.keys():
		var a: Vector2 = zonas[nombre][0]
		var b: Vector2 = zonas[nombre][1]
		var libres := 0
		var alcanza := 0
		for i in _cols:
			for j in _filas:
				var c := Vector2i(i, j)
				var p := _pos(c)
				if p.x < a.x or p.x > b.x or p.z < a.y or p.z > b.y:
					continue
				if _libre.get(c, false):
					libres += 1
					if _alcanza.get(c, false):
						alcanza += 1
		var marca := "OK" if alcanza > 0 else "SIN ACCESO"
		print("[paso] zona %-30s libres %3d | alcanzables %3d  -> %s" % [nombre, libres, alcanza, marca])


## --- Vista fina (12,5 cm) de los accesos conflictivos ------------------------
## La rejilla de 0,25 m funde cuatro celdas en un carácter y esconde los huecos
## estrechos (los vanos del piso miden ~0,85 m). Aquí se repite lo mismo sobre
## rectángulos pequeños con celdas de 0,125 m, sembrando la inundación desde la
## celda libre más cercana al punto que se le pase, y se listan los cuerpos que
## frenan la frontera de esa vista.
func _fina(nombre: String, x0: float, x1: float, z0: float, z1: float, semilla: Vector2) -> void:
	var paso := 0.125
	var cols := int(round((x1 - x0) / paso)) + 1
	var filas := int(round((z1 - z0) / paso)) + 1
	var libre := {}
	var alcanza := {}
	var pendiente: Array[Vector2i] = []
	var inicio := Vector2i(-1, -1)
	var mejor := 1e9
	for j in range(filas):
		for i in range(cols):
			var c := Vector2i(i, j)
			var pos := Vector3(x0 + i * paso, ALTURA_PIE, z0 + j * paso)
			if not _cabe_en(pos):
				continue
			libre[c] = true
			var d := Vector2(pos.x - semilla.x, pos.z - semilla.y).length()
			if d < mejor:
				mejor = d
				inicio = c
	if inicio.x >= 0:
		alcanza[inicio] = true
		pendiente.append(inicio)
		while not pendiente.is_empty():
			var c: Vector2i = pendiente.pop_back()
			for paso2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var v: Vector2i = c + paso2
				if v.x < 0 or v.y < 0 or v.x >= cols or v.y >= filas:
					continue
				if not libre.has(v) or alcanza.has(v):
					continue
				alcanza[v] = true
				pendiente.append(v)
	print("[fina] %s" % nombre)
	print("[fina] rejilla %d × %d de %.3f m | libres %d | alcanzables %d | semilla %s" % [
			cols, filas, paso, libre.size(), alcanza.size(), str(semilla)])
	var cabecera := "        "
	for i in range(cols):
		var x := x0 + i * paso
		if absf(round(x * 2.0) / 2.0 - x) < 0.001:
			cabecera += "%4.1f" % x
		else:
			cabecera += "    "
	print(cabecera)
	for j in range(filas):
		var linea := "%+6.2f  " % (z0 + j * paso)
		for i in range(cols):
			var c := Vector2i(i, j)
			if alcanza.has(c):
				linea += "o"
			elif libre.has(c):
				linea += "."
			else:
				linea += "#"
		print(linea)
	var esfera := SphereShape3D.new()
	esfera.radius = 0.10
	var nombres := {}
	for c in alcanza.keys():
		for paso3: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var v: Vector2i = c + paso3
			if v.x < 0 or v.y < 0 or v.x >= cols or v.y >= filas or libre.has(v):
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = esfera
			q.collision_mask = 1
			q.exclude = _excluir
			q.transform = Transform3D(Basis(), Vector3(x0 + v.x * paso, ALTURA_PIE, z0 + v.y * paso))
			for r in _mundo.intersect_shape(q, 6):
				var cuerpo: Node = r.get("collider") as Node
				var n := String(cuerpo.name) if cuerpo != null else "?"
				nombres[n] = int(nombres.get(n, 0)) + 1
	var lista: Array = nombres.keys()
	lista.sort_custom(func(a: String, b: String) -> bool: return int(nombres[a]) > int(nombres[b]))
	for n in lista:
		print("[fina]   frena %-18s %4d" % [n, int(nombres[n])])


## Frontera: celdas alcanzables con un vecino TAPADO. En cada vecino tapado se
## consulta una ESFERA pequeña en dos alturas: los cuerpos que salen son la
## geometría que frena ese acceso (los nombres son <malla>_col, así que dicen qué
## parte del modelo bloquea).
func _frontera() -> void:
	var esfera := SphereShape3D.new()
	esfera.radius = 0.20
	var choques := {}
	var muestras := {}
	for c in _alcanza.keys():
		for paso: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var v: Vector2i = c + paso
			if v.x < 0 or v.y < 0 or v.x >= _cols or v.y >= _filas:
				continue
			if _libre.get(v, false):
				continue
			var p := PhysicsShapeQueryParameters3D.new()
			p.shape = esfera
			p.collision_mask = 1
			p.exclude = _excluir
			for altura in [0.35, 0.95]:
				p.transform = Transform3D(Basis(), _pos(v) + Vector3.UP * (altura - ALTURA_PIE))
				for r in _mundo.intersect_shape(p, 8):
					var cuerpo: Node = r.get("collider") as Node
					var nombre := String(cuerpo.name) if cuerpo != null else "?"
					choques[nombre] = int(choques.get(nombre, 0)) + 1
					if not muestras.has(nombre):
						muestras[nombre] = _pos(v)
	print("[paso] CHOQUES en la frontera (qué frena cada acceso):")
	var lista: Array = choques.keys()
	lista.sort_custom(func(a: String, b: String) -> bool: return int(choques[a]) > int(choques[b]))
	for nombre in lista:
		print("[paso]   %-22s %4d | muestra %s" % [nombre, int(choques[nombre]),
				str(muestras[nombre])])
