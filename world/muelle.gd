class_name Muelle
extends Node3D
## =============================================================================
##  MUELLE DE MADERA DE LA PLAYA
## =============================================================================
##  Pasarela de tablones que sale de la arena urbana y entra en el océano: une el
##  paseo con el agua sin tocar la isla, la costa ni el relieve (la arena se queda
##  exactamente como está; aquí sólo se apoya encima).
##
##  PUNTOS CLAVE
##   * El origen local está en el ARRANQUE del muelle (el borde de la arena) y el
##     local +Z recorre el muelle hacia el mar. La cara superior del entablado
##     queda en y=0 local, así que el nodo se coloca a la cota de la arena.
##   * Los tablones se ven uno a uno (dos tonos de madera alternos) y llevan
##     viguetas por debajo. Los pilotes BAJAN HASTA EL FONDO REAL: su altura se
##     mide con `Relieve` en la posición de cada uno, así que ninguno flota ni
##     atraviesa la arena.
##   * La colisión es UNA losa por tramo transitable, con la cara superior
##     exactamente a la altura del entablado (coincide con lo que se ve).
##   * La escalera del extremo es una EscaleraBarco más: la forma acuática puede
##     subir desde el agua con E, igual que en el barco (el aviso del HUD cambia
##     su texto solo).
##   * El mobiliario de playa (palmeras, sombrillas, reposeras) que cayera DENTRO
##     de la huella del muelle se hunde bajo el terreno al construir: son
##     instancias de MultiMesh, se ocultan sin tocar la playa ni el generador.
## =============================================================================

## Longitud total (m) desde el arranque en la arena hasta la punta.
## 92 m: la orilla queda a ~42 m del arranque, así que la punta se adentra ~50 m en
## el mar. Medido con `Relieve`: la escalera del agua (z = largo − 3.2) cae donde el
## fondo está a −3.9 y hay ~1.5 m de calado, suficiente para llegar NADANDO y subir.
@export var largo: float = 92.0
## Ancho (m) de la pasarela.
@export var ancho: float = 4.6
## Ancho (m) de la plataforma del extremo.
@export var ancho_plataforma: float = 8.4
## Longitud (m) de la plataforma del extremo.
@export var largo_plataforma: float = 8.0
## Separación (m) entre parejas de pilotes.
@export var paso_pilotes: float = 5.0
## Separación (m) entre el arranque y el primer pilote (la arena no lleva pilotes).
@export var margen_arena: float = 12.0
## Hundimiento (m) del pilote por debajo del fondo marino, para que se clave.
@export var clavar_pilote: float = 1.2
## Grueso (m) del tablón y de las viguetas.
@export var grueso_tablon: float = 0.24
@export var canto_vigueta: float = 0.34

var _cuerpo: StaticBody3D
var _mat_madera_a: StandardMaterial3D
var _mat_madera_b: StandardMaterial3D
var _mat_madera_oscura: StandardMaterial3D
var _mat_pilote: StandardMaterial3D
var _mat_barandilla: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _relieve: Relieve


func _ready() -> void:
	_relieve = Relieve.new()
	_preparar_materiales()
	_cuerpo = StaticBody3D.new()
	_cuerpo.name = "Cuerpo"
	add_child(_cuerpo)
	_construir_tablones()
	_construir_viguetas()
	_construir_pilotes()
	_construir_barandillas()
	_construir_plataforma()
	_construir_detalles()
	_construir_escalera()
	# El mobiliario de playa se reparte al construir la ciudad: se oculta lo que
	# caiga dentro del muelle DESPUÉS de que todo el árbol esté listo.
	call_deferred("_ocultar_mobiliario_en_la_huella")


# ============================================================ MATERIALES
func _preparar_materiales() -> void:
	_mat_madera_a = _mat(Color(0.55, 0.38, 0.22))
	_mat_madera_b = _mat(Color(0.47, 0.32, 0.18))
	_mat_madera_oscura = _mat(Color(0.35, 0.24, 0.14))
	_mat_pilote = _mat(Color(0.29, 0.21, 0.14))
	_mat_pilote.roughness = 0.95
	_mat_barandilla = _mat(Color(0.44, 0.31, 0.18))
	_mat_metal = _mat(Color(0.5, 0.5, 0.52))
	_mat_metal.metallic = 0.4


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


# ============================================================ ENCADENADO (madera)
func _construir_tablones() -> void:
	# Tablones TRANSVERSALES, uno a uno, alternando dos tonos: es lo que hace que
	# el muelle se lea como madera desde cualquier distancia.
	var n := int(round(largo / 1.0))
	for i in n:
		var z := 0.5 + i * 1.0
		var mat := _mat_madera_a if i % 2 == 0 else _mat_madera_b
		_caja("Tablon", Vector3(0.0, -grueso_tablon * 0.5, z),
				Vector3(ancho, grueso_tablon, 0.86), mat, false)
	# Losa de colisión del tramo transitable: su cara superior coincide EXACTAMENTE
	# con la cara superior de los tablones (y=0 local).
	_colision(Vector3(0.0, -grueso_tablon * 0.5, largo * 0.5),
			Vector3(ancho, grueso_tablon, largo))


func _construir_viguetas() -> void:
	# Tres viguetas longitudinales bajo el entablado (los dos cantos y el centro).
	for x in [-ancho * 0.5 + 0.35, 0.0, ancho * 0.5 - 0.35]:
		_caja("Vigueta", Vector3(x, -grueso_tablon - canto_vigueta * 0.5, largo * 0.5),
				Vector3(0.3, canto_vigueta, largo), _mat_madera_oscura, false)


func _construir_pilotes() -> void:
	var n := int(floor((largo - margen_arena) / paso_pilotes))
	for i in n + 1:
		var z := margen_arena + i * paso_pilotes
		if z > largo - 0.6:
			continue
		for lado in [-1.0, 1.0]:
			var x: float = lado * (ancho * 0.5 - 0.3)
			_pilote(Vector3(x, 0.0, z))
		# Traviesa que ata la pareja de pilotes por debajo del entablado.
		var y_traviesa := -grueso_tablon - canto_vigueta - 0.16
		_caja("Traviesa", Vector3(0.0, y_traviesa, z), Vector3(ancho - 0.4, 0.32, 0.34),
				_mat_madera_oscura, false)


## Pilote: baja desde la vigueta hasta el FONDO REAL medido con Relieve. Si el
## terreno está prácticamente a la cota del muelle (arena al principio), el pilote
## se acorta: nunca queda flotando ni sobresale por debajo del fondo.
func _pilote(local: Vector3) -> void:
	var arriba := -grueso_tablon - canto_vigueta
	var mundo := to_global(Vector3(local.x, 0.0, local.z))
	var terreno := _relieve.altura(mundo.x, mundo.z)
	var abajo_local := (terreno - clavar_pilote) - global_position.y
	var alto := arriba - abajo_local
	if alto < 1.2:
		return
	var centro := Vector3(local.x, (arriba + abajo_local) * 0.5, local.z)
	# El pilote es SÓLIDO: lleva colisión de cilindro. Está por debajo del
	# entablado, así que no estorba al que camina por arriba; sí frena al que nada
	# por debajo (es una pata de verdad, no un adorno).
	_cilindro("Pilote", centro, 0.24, alto, _mat_pilote, true)


func _construir_barandillas() -> void:
	var x := ancho * 0.5 - 0.12
	var y := 0.0
	var z_ini := 1.6
	var z_fin := largo - largo_plataforma + 1.0
	# Barandilla PARCIAL: sólo los tramos donde hace falta sujeción (los dos lados,
	# con huecos al principio y al llegar a la plataforma).
	for lado in [-1.0, 1.0]:
		var cha: float = lado * x
		_tramo_barandilla(Vector3(cha, y, z_ini), Vector3(cha, y, z_fin))
	# Hueco a propósito en el arranque (para entrar andando desde la arena) y en el
	# final (para pasar a la plataforma).


func _tramo_barandilla(a: Vector3, b: Vector3) -> void:
	var largo_tramo := a.distance_to(b)
	var n := maxi(2, int(round(largo_tramo / 2.6)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_caja("Poste", Vector3(p.x, p.y + 0.55, p.z), Vector3(0.13, 1.1, 0.13),
				_mat_barandilla, false)
	for altura in [1.05, 0.6]:
		var centro := Vector3((a.x + b.x) * 0.5, a.y + altura, (a.z + b.z) * 0.5)
		_caja("Pasamanos", Vector3(centro.x, centro.y, centro.z),
				Vector3(maxf(absf(b.x - a.x), 0.12), 0.11, maxf(absf(b.z - a.z), 0.12)),
				_mat_barandilla, false)
	# COLISIÓN: pared fina que sigue el tramo (el cuerpo choca con la barandilla y
	# no se cae al agua por los lados). Es plana: no atrapa ni hace vibrar.
	var d := b - a
	d.y = 0.0
	if d.length() > 0.05:
		_colision(Vector3((a.x + b.x) * 0.5, a.y + 0.57, (a.z + b.z) * 0.5),
				Vector3(maxf(absf(d.x), 0.14) + 0.08, 1.14, maxf(absf(d.z), 0.14) + 0.08),
				atan2(d.x, d.z))


# ============================================================ PLATAFORMA DEL EXTREMO
func _construir_plataforma() -> void:
	var z0 := largo - largo_plataforma
	var zc := z0 + largo_plataforma * 0.5
	# Entablado de la plataforma, más ancho que la pasarela.
	var n := int(round(largo_plataforma / 1.0))
	for i in n:
		var z := z0 + 0.5 + i * 1.0
		var mat := _mat_madera_a if i % 2 == 0 else _mat_madera_b
		_caja("TablonPlataforma", Vector3(0.0, -grueso_tablon * 0.5, z),
				Vector3(ancho_plataforma, grueso_tablon, 0.86), mat, false)
	_colision(Vector3(0.0, -grueso_tablon * 0.5, zc),
			Vector3(ancho_plataforma, grueso_tablon, largo_plataforma))
	for x in [-ancho_plataforma * 0.5 + 0.4, 0.0, ancho_plataforma * 0.5 - 0.4]:
		_caja("ViguetaPlataforma", Vector3(x, -grueso_tablon - canto_vigueta * 0.5, zc),
				Vector3(0.32, canto_vigueta, largo_plataforma), _mat_madera_oscura, false)
	# Pilotes de las cuatro esquinas + los dos del centro.
	for x in [-ancho_plataforma * 0.5 + 0.6, ancho_plataforma * 0.5 - 0.6]:
		for z in [z0 + 0.9, zc, largo - 0.9]:
			_pilote(Vector3(x, 0.0, z))
	# Barandilla del perímetro, con el HUECO de la escalera y del costado del agua.
	var xb := -ancho_plataforma * 0.5 + 0.12
	var xe := ancho_plataforma * 0.5 - 0.12
	_tramo_barandilla(Vector3(xb, 0.0, z0), Vector3(xb, 0.0, largo - 0.4))
	_tramo_barandilla(Vector3(xb, 0.0, largo - 0.4), Vector3(-1.4, 0.0, largo - 0.4))
	_tramo_barandilla(Vector3(1.4, 0.0, largo - 0.4), Vector3(xe, 0.0, largo - 0.4))
	_tramo_barandilla(Vector3(xe, 0.0, z0), Vector3(xe, 0.0, largo - 6.4))
	_tramo_barandilla(Vector3(xe, 0.0, z0), Vector3(ancho * 0.5 - 0.12, 0.0, z0))
	_tramo_barandilla(Vector3(xb, 0.0, z0), Vector3(-ancho * 0.5 + 0.12, 0.0, z0))


# ============================================================ DETALLES NÁUTICOS
func _construir_detalles() -> void:
	var z0 := largo - largo_plataforma
	# Norayes (postes de amarre) en el canto de la plataforma.
	for z in [z0 + 1.6, largo - 1.6]:
		_cilindro("Noray", Vector3(ancho_plataforma * 0.5 - 0.9, 0.34, z), 0.28, 0.68,
				_mat_metal, false)
		_cilindro("NorayTapa", Vector3(ancho_plataforma * 0.5 - 0.9, 0.72, z), 0.36, 0.16,
				_mat_metal, false)
	# Farol de muelle (decorativo: no añade luz al mundo, sólo la forma).
	_caja("FarolPoste", Vector3(-ancho * 0.5 + 0.45, 0.9, largo * 0.32), Vector3(0.16, 1.8, 0.16),
			_mat_metal, false)
	_caja("FarolCabeza", Vector3(-ancho * 0.5 + 0.45, 1.95, largo * 0.32), Vector3(0.42, 0.4, 0.42),
			_mat_madera_oscura, false)
	_caja("FarolPoste2", Vector3(ancho * 0.5 - 0.45, 0.9, largo * 0.62), Vector3(0.16, 1.8, 0.16),
			_mat_metal, false)
	_caja("FarolCabeza2", Vector3(ancho * 0.5 - 0.45, 1.95, largo * 0.62), Vector3(0.42, 0.4, 0.42),
			_mat_madera_oscura, false)
	# Cajas, barriles y un banco junto al arranque (detalles de muelle pesquero).
	_caja("CajaMuelle0", Vector3(-ancho * 0.5 + 0.75, 0.3, 5.5), Vector3(1.1, 0.6, 1.1),
			_mat_madera_oscura, true)
	_caja("CajaMuelle1", Vector3(-ancho * 0.5 + 0.75, 0.85, 5.5), Vector3(0.9, 0.5, 0.9),
			_mat_madera_b, false)
	_cilindro("Barril", Vector3(ancho * 0.5 - 0.85, 0.42, 9.0), 0.42, 0.84, _mat_madera_oscura, false)
	_cilindro("Barril", Vector3(ancho * 0.5 - 1.9, 0.42, 9.6), 0.42, 0.84, _mat_madera_oscura, false)
	# Aros metálicos de refuerzo en los pilotes de la punta.
	for x in [-ancho_plataforma * 0.5 + 0.6, ancho_plataforma * 0.5 - 0.6]:
		for z in [z0 + 0.9, largo - 0.9]:
			_cilindro("Aro", Vector3(x, -0.75, z), 0.28, 0.16, _mat_metal, false)


# ============================================================ ESCALERA AL AGUA
## Escalera del costado de la plataforma, la que permite volver del agua al muelle.
## Es una EscaleraBarco: la MISMA pieza que la del barco, así que la forma acuática
## la sube con E y el HUD muestra su aviso (aquí, "subir al muelle").
func _construir_escalera() -> void:
	var z := largo - 3.2
	var x_ladera := ancho_plataforma * 0.5 + 0.05
	var y_arriba := 0.35
	var y_abajo := -2.6
	# Largueros CON colisión (son las dos guías de la escalera: lo que el cuerpo
	# puede tocar). Los peldaños quedan sin colisión, igual que en el barco: el
	# ascenso es un recorrido guiado y una colisión ahí sólo estorbaría al agarre.
	for dx in [-0.3, 0.3]:
		_caja("LargueroMuelle", Vector3(x_ladera + 0.15, (y_arriba + y_abajo) * 0.5, z + dx),
				Vector3(0.1, y_arriba - y_abajo, 0.1), _mat_metal, true)
	var n := 9
	for i in n:
		var y := lerpf(y_abajo + 0.2, y_arriba - 0.2, float(i) / float(n - 1))
		_caja("PeldanoMuelle", Vector3(x_ladera + 0.15, y, z), Vector3(0.1, 0.08, 0.78),
				_mat_metal, false)
	# --- Punto de agarre (el MISMO nodo EscaleraBarco que usa el barco) ---
	# El recorrido se describe con los números MEDIDOS de esta escalera, en el marco
	# local del nodo: peldaños cada `paso`, cuerpo 0,30 m por fuera del plano de los
	# peldaños, pies en el primer peldaño que asoma por encima del agua y paso final
	# hacia dentro de la plataforma.
	var esc := EscaleraBarco.new()
	esc.name = "EscaleraMuelle"
	esc.position = Vector3(x_ladera + 0.8, -0.4, z)
	esc.radio_agarre = 2.4
	esc.radio_bajada = 2.0
	esc.texto_prompt = "Presioná E para subir al muelle"
	esc.texto_prompt_bajada = "Presioná E para bajar al agua"
	esc.mirada_local = Vector3(-1.0, 0.0, 0.0)
	var paso := (y_arriba - 0.2 - (y_abajo + 0.2)) / float(n - 1)
	esc.separacion_peldanos = paso
	esc.peldanos_por_ciclo = 2.0
	var y_agua := -2.05 - global_position.y            # cota del agua en local
	var y_peldano_0 := y_abajo + 0.2
	var k := ceili((y_agua - y_peldano_0) / paso)
	var y_pies := y_peldano_0 + float(k) * paso
	var cara := (x_ladera + 0.15 + 0.25) - esc.position.x
	var x_plataforma := ancho_plataforma * 0.5 - 1.2
	esc.inicio_local = Vector3(cara,
			(y_pies - EscaleraBarco.AIRE_PIE_TREPADA) - esc.position.y, 0.0)
	esc.tope_local = Vector3(cara, 0.30 - esc.position.y, 0.0)
	esc.fin_local = Vector3(x_plataforma - esc.position.x, 0.0 - esc.position.y, 0.0)
	add_child(esc)


# ============================================================ MOBILIARIO DE PLAYA
## Hunde bajo el terreno las instancias de MultiMesh (palmeras, sombrillas,
## reposeras, macetas...) cuya posición cae dentro de la huella del muelle. Son
## recursos compartidos por nodo, así que se trabaja sobre las copias de cada
## MultiMeshInstance3D y nunca sobre la playa ni el generador.
func _ocultar_mobiliario_en_la_huella() -> void:
	var raiz := get_tree().root if is_inside_tree() else null
	if raiz == null:
		return
	# Esfera envolvente (mundo) de la huella del muelle: sirve para DESCARTAR de un
	# golpe los MultiMesh que están lejos (la ciudad, las marcas viales...) sin
	# recorrer sus miles de instancias una por una. Es sólo un prefiltro: los que
	# pasan se siguen comprobando instancia a instancia con `_dentro_de_la_huella`.
	var semiancho_huella: float = maxf(ancho, ancho_plataforma) * 0.5 + 1.6
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for esq in [Vector3(-semiancho_huella, -16.0, -2.0), Vector3(semiancho_huella, -16.0, largo + 2.0),
			Vector3(-semiancho_huella, 16.0, -2.0), Vector3(semiancho_huella, 16.0, largo + 2.0)]:
		var w: Vector3 = to_global(esq as Vector3)
		mn = mn.min(w)
		mx = mx.max(w)
	var centro_huella := (mn + mx) * 0.5
	var radio_huella := (mx - mn).length() * 0.5
	var hundidos := 0
	for nodo in raiz.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := nodo as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count == 0:
			continue
		var mm := mmi.multimesh
		var aabb := mmi.get_aabb()
		var b := mmi.global_transform.basis
		var esc := maxf(b.x.length(), maxf(b.y.length(), b.z.length()))
		var centro_mm: Vector3 = mmi.global_transform * aabb.get_center()
		var radio_mm := aabb.size.length() * 0.5 * esc + 8.0
		if centro_mm.distance_squared_to(centro_huella) > pow(radio_huella + radio_mm, 2.0):
			continue
		var cambios := false
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var p := mmi.global_transform * xf.origin
			if _dentro_de_la_huella(p):
				xf.origin.y -= 80.0
				mm.set_instance_transform(i, xf)
				cambios = true
				hundidos += 1
		if cambios and mmi.multimesh == mm:
			mmi.multimesh = mm
	if hundidos > 0:
		print("Muelle: %d instancias de mobiliario de playa ocultas bajo la huella." % hundidos)


func _dentro_de_la_huella(p: Vector3) -> bool:
	var local := to_local(p)
	var semiancho: float = maxf(ancho, ancho_plataforma) * 0.5 + 1.6
	if absf(local.x) > semiancho:
		return false
	if local.z < -2.0 or local.z > largo + 2.0:
		return false
	# Sólo el mobiliario BAJO el entablado (no el que esté lejos por altura).
	var y_mundo := (to_global(Vector3(0.0, 0.0, local.z))).y
	return absf(p.y - y_mundo) < 14.0


# ============================================================ UTILIDADES
func _caja(nombre: String, centro: Vector3, tam: Vector3, mat: Material,
		colision: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = centro
	add_child(mi)
	if colision:
		_colision(centro, tam)
	return mi


func _cilindro(nombre: String, centro: Vector3, radio: float, alto: float,
		mat: Material, colision: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var cm := CylinderMesh.new()
	cm.top_radius = radio
	cm.bottom_radius = radio
	cm.height = alto
	mi.mesh = cm
	mi.material_override = mat
	mi.position = centro
	add_child(mi)
	if colision:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radio
		cyl.height = alto
		cs.shape = cyl
		cs.position = centro
		_cuerpo.add_child(cs)
	return mi


func _colision(centro: Vector3, tam: Vector3, rot_y: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	cs.position = centro
	# Las barandillas diagonales necesitan una caja ORIENTADA (una caja alineada a
	# los ejes de un tramo oblicuo taparía parte de la pasarela).
	if absf(rot_y) > 0.0001:
		cs.rotation.y = rot_y
	_cuerpo.add_child(cs)