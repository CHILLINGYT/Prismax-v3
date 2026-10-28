class_name BarcoExplorable
extends Node3D
## =============================================================================
##  BARCO GRANDE, EXPLORABLE (buque de suministro de 88 m)
## =============================================================================
##  Un ÚNICO barco en medio del océano. Se construye con geometría nativa de
##  Godot (sin modelos externos): el casco es una superficie alargada generada por
##  estaciones (afinada en proa y popa), y el resto son cajas y cilindros.
##
##  PUNTOS CLAVE DEL DISEÑO
##   * El origen local está en la LÍNEA DE FLOTACIÓN: el nodo se coloca con su Y a
##     la altura del mar, así el casco queda medio sumergido de forma natural (no
##     "flota" sobre el agua ni se hunde).
##   * +Z LOCAL ES LA PROA. El nodo se coloca de forma que +Z apunte a la costa más
##     cercana: la proa mira a tierra y la popa queda al mar abierto.
##   * La cubierta es una superficie PLANA y AMPLIA (19 m de manga, 88 de eslora),
##     con colisión propia: se puede caminar, girar, saltar y combatir por ella.
##   * Cada parte travesable tiene SU colisión; NO hay una única caja gigante: el
##     casco macizo va por debajo (repartido en tramos que siguen la afinación y la
##     quilla, para no asomar por fuera del forro), la cubierta por encima y el
##     puente de mando es una sala hueca con puerta.
##   * Los objetos de cubierta (contenedores, cajas, grúas, bote) se apartan a los
##     COSTADOS y a la toldilla, dejando libre el pasillo central y la proa: hay
##     espacio de sobra para moverse.
##   * La escalera (EscaleraBarco) es el único punto de subida, y sólo la usa la
##     forma acuática (ver controlador_leo.gd).
## =============================================================================

# --- Medidas (m, en coordenadas locales; y=0 es la línea de flotación) ---
const ESLORA := 88.0
const MANGA := 19.0
const SEMI_L := ESLORA * 0.5
const SEMI_M := MANGA * 0.5
## Cota local de la cara superior de la cubierta principal (transitable).
const CUBIERTA := 3.8
## Escalón del castillo de proa: un peldaño de 0,35 m (el controlador sube 0,26 m
## andando, así que este tramo se salva con un paso natural).
const PROA_Y := CUBIERTA + 0.35
## Cota local del fondo del casco (obra viva) en el centro.
const QUILLA := -6.4
## Altura del puente de mando sobre la cubierta principal.
const PUENTE_H := 3.4
## Media manga de la superestructura (toldilla).
const PUENTE_SEMI := 7.6
## Coordenada Z (local) de la escalera de servicio de babor y media anchura del
## HUECO que se deja en la borda a su altura: por ahí pasa el cuerpo al subir y al
## bajar (es la boca de salida de la escalera, no un adorno).
const ESC_Z := 6.0
const ESC_HUECO := 1.7

## Contorno de una cuaderna (u: -1..1 media manga, v: 0..1 del fondo a cubierta).
## El tramo del último punto al primero es la boca de cubierta: no se genera.
const SECCION := [
	Vector2(1.0, 1.0), Vector2(1.0, 0.62), Vector2(0.86, 0.24),
	Vector2(0.52, 0.05), Vector2(0.0, 0.0), Vector2(-0.52, 0.05),
	Vector2(-0.86, 0.24), Vector2(-1.0, 0.62), Vector2(-1.0, 1.0)]

# --- Oscilación (vaivén) muy leve, opcional ---
const VAIVEN_ALTURA := 0.032
const VAIVEN_INCLINA := 0.004
const VAIVEN_VELOCIDAD := 0.45

var _cuerpo: StaticBody3D
var _base_y: float = 0.0
var _t: float = 0.0

var _mat_casco: StandardMaterial3D
var _mat_cubierta: StandardMaterial3D
var _mat_super: StandardMaterial3D
var _mat_super_detalle: StandardMaterial3D
var _mat_ventana: StandardMaterial3D
var _mat_barandilla: StandardMaterial3D
var _mat_aro: StandardMaterial3D
var _mat_mastil: StandardMaterial3D
var _mat_oxido: StandardMaterial3D
var _mat_madera: StandardMaterial3D
var _mat_goma: StandardMaterial3D
var _mat_techo: StandardMaterial3D
var _mat_tablon: StandardMaterial3D
var _mat_lampara: StandardMaterial3D
var _mat_contenedor: Array[StandardMaterial3D] = []
## Tonos del entablado (se alternan tablón a tablón, como en el muelle).
var _col_madera_a := Color(0.42, 0.31, 0.20)
var _col_madera_b := Color(0.36, 0.26, 0.17)
## Pies del clip de trepada por encima del origen del cuerpo (MEDIDO con el arnés
## de diagnóstico: los huesos de los pies caen ~0,35 m sobre el origen).
const AIRE_PIE_TREPADA := 0.35


func _ready() -> void:
	_base_y = position.y
	_preparar_materiales()
	_cuerpo = StaticBody3D.new()
	_cuerpo.name = "Cuerpo"
	add_child(_cuerpo)
	_construir_casco()
	_construir_cubierta()
	_construir_escotilla()
	_construir_puente()
	_construir_chimeneas()
	_construir_mastiles()
	_construir_contenedores()
	_construir_gruas()
	_construir_bote()
	_construir_detalles_cubierta()
	_construir_barandillas()
	_construir_aros()
	_construir_portillas()
	_construir_escalera()


func _process(delta: float) -> void:
	_t += delta
	var s := sin(_t * VAIVEN_VELOCIDAD)
	position.y = _base_y + s * VAIVEN_ALTURA
	rotation.z = sin(_t * VAIVEN_VELOCIDAD * 0.72) * VAIVEN_INCLINA
	rotation.x = sin(_t * VAIVEN_VELOCIDAD * 0.53) * VAIVEN_INCLINA * 0.6


# ============================================================ MATERIALES
func _preparar_materiales() -> void:
	_mat_casco = _mat(Color(0.13, 0.17, 0.23))
	_mat_casco.cull_mode = BaseMaterial3D.CULL_DISABLED      # casco de doble cara
	_mat_casco.roughness = 0.55
	_mat_cubierta = _mat(Color(0.34, 0.36, 0.34))            # gris antideslizante
	_mat_cubierta.roughness = 0.92
	_mat_super = _mat(Color(0.86, 0.88, 0.9))                # blanco del casco alto
	_mat_super_detalle = _mat(Color(0.62, 0.66, 0.7))        # gris claro de detalles
	_mat_ventana = _mat(Color(0.04, 0.11, 0.15))
	_mat_ventana.metallic = 0.65
	_mat_ventana.roughness = 0.12
	_mat_barandilla = _mat(Color(0.82, 0.66, 0.12))          # amarillo seguridad
	_mat_aro = _mat(Color(0.95, 0.42, 0.08))                 # naranja salvavidas
	_mat_mastil = _mat(Color(0.58, 0.58, 0.6))
	_mat_mastil.metallic = 0.35
	_mat_oxido = _mat(Color(0.45, 0.26, 0.16))               # óxido / herrumbre
	_mat_oxido.roughness = 0.95
	_mat_madera = _mat(Color(0.52, 0.36, 0.21))              # cajas de madera
	_mat_goma = _mat(Color(0.09, 0.09, 0.1))                 # defensas de goma
	_mat_goma.roughness = 0.98
	_mat_techo = _mat(Color(0.5, 0.52, 0.5))                 # techo del puente
	# Entablado: el color lo pone cada tablón (instance color del MultiMesh), así
	# que el material va blanco y usa el color de instancia como albedo.
	_mat_tablon = _mat(Color(1.0, 1.0, 1.0))
	_mat_tablon.vertex_color_use_as_albedo = true
	_mat_tablon.roughness = 0.88
	# Lámparas del interior del puente: emiten luz propia (el interior es
	# transitable y quedaba a oscuras al no haber luces dentro del barco).
	_mat_lampara = _mat(Color(1.0, 0.95, 0.82))
	_mat_lampara.emission_enabled = true
	_mat_lampara.emission = Color(1.0, 0.92, 0.75)
	_mat_lampara.emission_energy_multiplier = 2.2
	_mat_contenedor = [
		_mat(Color(0.72, 0.21, 0.15)), _mat(Color(0.13, 0.32, 0.56)),
		_mat(Color(0.18, 0.46, 0.28)), _mat(Color(0.78, 0.62, 0.14)),
		_mat(Color(0.42, 0.2, 0.42))]


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


# ============================================================ CASCO
func _construir_casco() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ns := 38
	var estaciones: Array = []
	for i in ns:
		var t := float(i) / float(ns - 1)
		var z := lerpf(-SEMI_L, SEMI_L, t)
		var bw := _manga_factor(t)
		var ky := _quilla(t)
		var pts: Array = []
		for s in SECCION.size():
			var sec: Vector2 = SECCION[s]
			pts.append(Vector3(sec.x * SEMI_M * bw, ky + sec.y * (CUBIERTA - ky), z))
		estaciones.append(pts)
	for i in ns - 1:
		for s in SECCION.size() - 1:
			var a: Vector3 = estaciones[i][s]
			var b: Vector3 = estaciones[i][s + 1]
			var c: Vector3 = estaciones[i + 1][s + 1]
			var d: Vector3 = estaciones[i + 1][s]
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	_tapa(st, estaciones[0])
	_tapa(st, estaciones[ns - 1])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Casco"
	mi.mesh = st.commit()
	mi.material_override = _mat_casco
	add_child(mi)

	# Franjas pintadas (obra viva y cinta) sobre el propio forro: dan escala al
	# casco y marcan dónde está el agua sin tocar la forma.
	_caja("FranjaFlotacion", Vector3(0.0, 0.15, 0.0), Vector3(MANGA + 0.04, 0.5, ESLORA - 12.0),
			_mat_oxido, false)
	_caja("Cinta", Vector3(0.0, 2.4, 0.0), Vector3(MANGA + 0.03, 0.22, ESLORA - 11.0),
			_mat_super_detalle, false)

	# Colisión del casco: TRAMOS que siguen la afinación y la quilla reales, de
	# modo que la caja nunca asoma por fuera del forro (nada de una caja gigante).
	var tramos := 7
	for i in tramos:
		var t0 := float(i) / float(tramos)
		var t1 := float(i + 1) / float(tramos)
		var z0 := lerpf(-SEMI_L, SEMI_L, t0)
		var z1 := lerpf(-SEMI_L, SEMI_L, t1)
		var ancho: float = MANGA * minf(_manga_factor(t0), _manga_factor(t1)) - 0.7
		var fondo: float = minf(_quilla(t0), _quilla(t1)) + 0.25
		var alto: float = CUBIERTA - 0.25 - fondo
		_colision(Vector3(0.0, fondo + alto * 0.5, (z0 + z1) * 0.5),
				Vector3(maxf(ancho, 1.6), alto, (z1 - z0) + 0.4))


## Media manga (u) en la estación t (0 = popa, 1 = proa). La afinación de proa NO
## llega a cero: el forro termina en punta roma, de modo que las cubiertas de proa
## caigan SIEMPRE dentro del casco (nada de tablones al aire).
func _manga_factor(t: float) -> float:
	if t < 0.14:
		return lerpf(0.74, 1.0, t / 0.14)
	if t > 0.70:
		var s := (t - 0.70) / 0.30
		return lerpf(1.0, 0.30, s * s)
	return 1.0


## Cota de la quilla en la estación t: sube hacia la proa (finura) y algo en popa.
func _quilla(t: float) -> float:
	if t > 0.66:
		var s := (t - 0.66) / 0.34
		return lerpf(QUILLA, -1.6, s * s)
	if t < 0.07:
		var s := (0.07 - t) / 0.07
		return lerpf(QUILLA, -4.6, s)
	return QUILLA


## Semiancho REAL del casco en una coordenada z local. Lo usan las piezas de
## cubierta para no salirse del forro.
func _semi_ancho_en(z: float) -> float:
	var t := clampf((z + SEMI_L) / ESLORA, 0.0, 1.0)
	return SEMI_M * _manga_factor(t)


func _tapa(st: SurfaceTool, pts: Array) -> void:
	var centro := Vector3.ZERO
	for p: Vector3 in pts:
		centro += p
	centro /= float(pts.size())
	for s in pts.size():
		var a: Vector3 = pts[s]
		var b: Vector3 = pts[(s + 1) % pts.size()]
		st.add_vertex(centro)
		st.add_vertex(a)
		st.add_vertex(b)


# ============================================================ CUBIERTA
func _construir_cubierta() -> void:
	# Cubierta principal: superficie plana y amplia, con colisión propia. Su ancho
	# es el del casco en la boca de cubierta (menos 10 cm por lado): así no queda
	# una ranura oscura entre la tablazón y el forro.
	var ancho_cub := _semi_ancho_en(26.0) * 2.0 - 0.2
	_caja("Cubierta", Vector3(0.0, CUBIERTA - 0.2, -2.0),
			Vector3(ancho_cub, 0.4, 58.0), _mat_cubierta, true)
	_tablonaje("TablonCubierta", -31.0, 27.0, ancho_cub - 0.6, CUBIERTA)
	# Cubierta de proa: tramos que siguen la afinación del casco. Cada tramo usa el
	# ancho del casco en su punto MÁS ESTRECHO, así nunca sobresale del forro.
	for tramo in [[26.0, 32.0], [32.0, 37.0], [37.0, 43.0]]:
		var za: float = tramo[0]
		var zb: float = tramo[1]
		var ancho_tramo := _semi_ancho_en(zb) * 2.0 - 0.3
		_caja("CubiertaProa", Vector3(0.0, PROA_Y - 0.2, (za + zb) * 0.5),
				Vector3(ancho_tramo, 0.4, zb - za + 0.25), _mat_cubierta, true)
		_tablonaje("TablonProa", za - 0.1, zb + 0.1, ancho_tramo - 0.6, PROA_Y)
	# Toldilla (cubierta de popa): un escalón por encima, base del puente.
	_caja("Toldilla", Vector3(0.0, CUBIERTA + 0.12, -33.0),
			Vector3(MANGA - 1.0, 0.3, 20.0), _mat_cubierta, true)
	_tablonaje("TablonToldilla", -42.5, -23.5, MANGA - 1.6, CUBIERTA + 0.27)
	# Borda (peto) de los costados: es una PARED REAL, con colisión. Impide caerse
	# por la borda; se sale del barco por la escalera. En BABOR se deja el HUECO de
	# la escalera (ESC_HUECO a cada lado de ESC_Z): es la boca de salida, por ahí
	# pasa el cuerpo al subir y al bajar, así que no puede haber pared.
	_caja("BordaBaborPopa", Vector3(-SEMI_M + 0.45, CUBIERTA + 0.5, (-18.0 + (ESC_Z - ESC_HUECO)) * 0.5),
			Vector3(0.6, 1.0, (ESC_Z - ESC_HUECO) + 18.0), _mat_super, true)
	_caja("BordaBaborProa", Vector3(-SEMI_M + 0.45, CUBIERTA + 0.5, ((ESC_Z + ESC_HUECO) + 26.0) * 0.5),
			Vector3(0.6, 1.0, 26.0 - (ESC_Z + ESC_HUECO)), _mat_super, true)
	_caja("BordaEstribor", Vector3(SEMI_M - 0.45, CUBIERTA + 0.5, 4.0),
			Vector3(0.6, 1.0, 44.0), _mat_super, true)
	# Cantoneras del hueco: rematan los dos cantos vivos de la boca de la escalera.
	for dz in [-ESC_HUECO, ESC_HUECO]:
		_caja("Cantonera", Vector3(-SEMI_M + 0.45, CUBIERTA + 0.52, ESC_Z + dz),
				Vector3(0.72, 1.06, 0.18), _mat_super_detalle, false)
	# Defensas de goma colgadas del costado (detalle de atraque).
	for z in [-30.0, -14.0, 2.0, 18.0, 32.0]:
		_cilindro("Defensa", Vector3(-SEMI_M - 0.12, 1.5, z), 0.42, 1.5, _mat_goma, false)
		_cilindro("Defensa", Vector3(SEMI_M + 0.12, 1.5, z), 0.42, 1.5, _mat_goma, false)


## Entablado visible de un piso: tablones transversales de ~1,15 m que alternan dos
## tonos de madera, con el color por INSTANCIA (un solo MultiMeshInstance3D por
## piso: barato y sin nodos de más). Su cara superior queda 5 mm por encima de la
## cota de colisión (imperceptible a los pies y sin z-fighting con la losa).
func _tablonaje(nombre: String, z0: float, z1: float, ancho: float, cota: float) -> void:
	var n := maxi(int(round((z1 - z0) / 1.15)), 1)
	var largo_tablon := (z1 - z0) / float(n)
	var bm := BoxMesh.new()
	bm.size = Vector3(ancho, 0.05, largo_tablon - 0.04)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = bm
	multi.instance_count = n
	for i in n:
		var z := z0 + (float(i) + 0.5) * largo_tablon
		multi.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, cota - 0.02, z)))
		multi.set_instance_color(i, _col_madera_a if i % 2 == 0 else _col_madera_b)
	var nodo := MultiMeshInstance3D.new()
	nodo.name = nombre
	nodo.multimesh = multi
	nodo.material_override = _mat_tablon
	add_child(nodo)


# ============================================================ ESCOTILLA
func _construir_escotilla() -> void:
	# Boca de bodega: tapa plana con refuerzos, pisable (un peldaño de 0,22 m).
	_caja("Escotilla", Vector3(0.0, CUBIERTA + 0.11, -6.0), Vector3(11.0, 0.22, 18.0),
			_mat_super_detalle, true)
	for z in [-14.0, -10.0, -6.0, -2.0, 2.0]:
		_caja("Refuerzo", Vector3(0.0, CUBIERTA + 0.26, z), Vector3(11.2, 0.12, 0.35),
				_mat_oxido, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cilindro("Perrillo", Vector3(sx * 4.6, CUBIERTA + 0.34, -6.0 + sz * 7.6),
					0.16, 0.3, _mat_mastil, false)


# ============================================================ PUENTE DE MANDO
func _construir_puente() -> void:
	var z0 := -42.0                                   # popa
	var z1 := -22.0                                   # frente (hacia proa)
	var cy := CUBIERTA + 0.27 + PUENTE_H * 0.5        # sobre la toldilla
	var hz := PUENTE_H
	var ancho := PUENTE_SEMI
	# Paredes: popa, dos costados y frente con HUECO DE PUERTA (dos tramos).
	_caja("PuentePopa", Vector3(0.0, cy, z0), Vector3(ancho * 2.0, hz, 0.4), _mat_super, true)
	_caja("PuenteBabor", Vector3(-ancho, cy, (z0 + z1) * 0.5),
			Vector3(0.4, hz, (z1 - z0)), _mat_super, true)
	_caja("PuenteEstribor", Vector3(ancho, cy, (z0 + z1) * 0.5),
			Vector3(0.4, hz, (z1 - z0)), _mat_super, true)
	_caja("PuenteFrenteIzq", Vector3(-4.2, cy, z1), Vector3(6.8, hz, 0.4), _mat_super, true)
	_caja("PuenteFrenteDer", Vector3(4.2, cy, z1), Vector3(6.8, hz, 0.4), _mat_super, true)
	# Dintel sobre la puerta.
	_caja("PuenteDintel", Vector3(0.0, CUBIERTA + 0.27 + hz - 0.5, z1),
			Vector3(1.6, 1.0, 0.4), _mat_super, true)
	# Techo + alero que vuela sobre los costados (ala del puente).
	_caja("PuenteTecho", Vector3(0.0, CUBIERTA + 0.27 + hz, (z0 + z1) * 0.5),
			Vector3(ancho * 2.0 + 1.2, 0.45, (z1 - z0) + 1.0), _mat_techo, true)
	# Ventanas: cinturón acristalado de proa y costados. El frente va PARTIDO en dos
	# paños para no tapar el hueco de la puerta (antes un único paño de 13,6 m
	# cruzaba el vano y se veía un panel negro en la entrada).
	_caja("VentanaProaIzq", Vector3(-4.2, cy + 0.4, z1 - 0.03),
			Vector3(6.4, 1.5, 0.06), _mat_ventana, false)
	_caja("VentanaProaDer", Vector3(4.2, cy + 0.4, z1 - 0.03),
			Vector3(6.4, 1.5, 0.06), _mat_ventana, false)
	_caja("VentanaBabor", Vector3(-ancho - 0.03, cy + 0.4, (z0 + z1) * 0.5),
			Vector3(0.06, 1.5, 15.0), _mat_ventana, false)
	_caja("VentanaEstribor", Vector3(ancho + 0.03, cy + 0.4, (z0 + z1) * 0.5),
			Vector3(0.06, 1.5, 15.0), _mat_ventana, false)
	# Marco de la puerta: DOS postes y el dintel, dejando el vano libre de verdad
	# (antes era un paño oscuro de 1,9 m en medio de la puerta).
	for sx in [-1.0, 1.0]:
		_caja("PuertaPoste", Vector3(sx * 0.9, CUBIERTA + 0.27 + 1.05, z1),
				Vector3(0.14, 2.1, 0.5), _mat_super_detalle, false)
	_caja("PuertaDintelMarco", Vector3(0.0, CUBIERTA + 0.27 + 2.1, z1),
			Vector3(1.94, 0.16, 0.5), _mat_super_detalle, false)
	# Consola y mamparo interior: el puente es una sala hueca y transitable. La
	# consola es SÓLIDA (es un mueble de verdad, no un adorno).
	_caja("Consola", Vector3(0.0, CUBIERTA + 0.27 + 0.6, z1 + 1.3), Vector3(5.0, 1.2, 0.9),
			_mat_super_detalle, true)
	_caja("ConsolaAlta", Vector3(0.0, CUBIERTA + 0.27 + 1.5, z1 + 1.5), Vector3(3.6, 0.7, 0.4),
			_mat_ventana, false)
	_caja("Mamparo", Vector3(0.0, CUBIERTA + 0.27 + 1.4, -37.0), Vector3(8.0, 2.8, 0.3),
			_mat_super_detalle, true)
	# Lámparas del techo del puente: el interior es transitable y quedaba a oscuras.
	_caja("LamparaPuente", Vector3(-3.0, CUBIERTA + 0.27 + hz - 0.35, -30.0),
			Vector3(1.6, 0.12, 1.0), _mat_lampara, false)
	_caja("LamparaPuente", Vector3(3.0, CUBIERTA + 0.27 + hz - 0.35, -30.0),
			Vector3(1.6, 0.12, 1.0), _mat_lampara, false)
	# Barandilla del techo (alas de babor y estribor).
	_tramo_barandilla(Vector3(-ancho - 0.6, CUBIERTA + 0.27 + hz + 0.22, z1),
			Vector3(-ancho - 0.6, CUBIERTA + 0.27 + hz + 0.22, z0 + 1.0))
	_tramo_barandilla(Vector3(ancho + 0.6, CUBIERTA + 0.27 + hz + 0.22, z1),
			Vector3(ancho + 0.6, CUBIERTA + 0.27 + hz + 0.22, z0 + 1.0))


# ============================================================ CHIMENEAS
func _construir_chimeneas() -> void:
	var y := CUBIERTA + 0.27 + PUENTE_H
	_cilindro("Chimenea", Vector3(0.0, y + 2.3, -31.0), 1.45, 4.6, _mat_super, true)
	_cilindro("ChimeneaAro", Vector3(0.0, y + 4.3, -31.0), 1.6, 0.5, _mat_barandilla, false)
	_cilindro("ChimeneaBoca", Vector3(0.0, y + 4.7, -31.0), 1.15, 0.4, _mat_ventana, false)
	_cilindro("EscapeA", Vector3(-3.4, y + 0.9, -28.0), 0.32, 1.8, _mat_mastil, true)
	_cilindro("EscapeB", Vector3(3.4, y + 0.9, -28.0), 0.32, 1.8, _mat_mastil, true)


# ============================================================ MÁSTILES Y ANTENAS
func _construir_mastiles() -> void:
	var base := CUBIERTA + 0.27 + PUENTE_H
	_cilindro("Mastil", Vector3(0.0, base + 5.0, -25.5), 0.26, 10.0, _mat_mastil, true)
	_caja("Cruceta", Vector3(0.0, base + 7.0, -25.5), Vector3(4.4, 0.14, 0.14), _mat_mastil, false)
	_cilindro("Radar", Vector3(0.0, base + 10.2, -25.5), 0.9, 0.22, _mat_super_detalle, false)
	_caja("RadarBarra", Vector3(0.0, base + 10.4, -25.5), Vector3(0.22, 0.12, 3.2), _mat_mastil, false)
	_cilindro("AntenaA", Vector3(-1.6, base + 8.4, -25.5), 0.07, 4.2, _mat_mastil, false)
	_cilindro("AntenaB", Vector3(1.6, base + 8.4, -25.5), 0.07, 4.2, _mat_mastil, false)
	# Mástil de proa: está SOBRE la cubierta transitable, así que lleva colisión
	# (es lo único que el cuerpo puede tocar de todo el palo).
	_cilindro("MastilProa", Vector3(0.0, PROA_Y + 3.4, 30.0), 0.2, 7.0, _mat_mastil, true)
	_caja("CrucetaProa", Vector3(0.0, PROA_Y + 5.6, 30.0), Vector3(3.0, 0.12, 0.12), _mat_mastil, false)
	_cilindro("LuzProa", Vector3(0.0, PROA_Y + 6.9, 30.0), 0.14, 0.4, _mat_super_detalle, false)


# ============================================================ CONTENEDORES Y CARGA
func _construir_contenedores() -> void:
	# Los contenedores van a los DOS COSTADOS: el pasillo central y toda la proa
	# quedan libres para caminar, girar, saltar y combatir.
	_contenedor(Vector3(-6.4, CUBIERTA + 1.35, 14.0), 0)
	_contenedor(Vector3(-6.4, CUBIERTA + 1.35, 20.5), 1)
	_contenedor(Vector3(-6.4, CUBIERTA + 4.05, 14.0), 2)
	_contenedor(Vector3(6.4, CUBIERTA + 1.35, 14.0), 3)
	_contenedor(Vector3(6.4, CUBIERTA + 1.35, 20.5), 4)
	# Cajas de madera apiladas cerca de la toldilla (carga menuda).
	_caja("CajaMadera0", Vector3(-5.4, CUBIERTA + 0.85, -16.0), Vector3(2.2, 1.4, 2.2),
			_mat_madera, true)
	_caja("CajaMadera1", Vector3(-7.4, CUBIERTA + 0.85, -16.0), Vector3(1.6, 1.4, 2.2),
			_mat_madera, true)
	_caja("CajaMadera2", Vector3(-6.3, CUBIERTA + 2.25, -16.0), Vector3(2.0, 1.4, 2.0),
			_mat_madera, true)
	_caja("CajaMadera3", Vector3(6.4, CUBIERTA + 0.85, -14.0), Vector3(2.4, 1.4, 2.4),
			_mat_madera, true)
	_caja("CajaMadera4", Vector3(6.4, CUBIERTA + 2.25, -14.0), Vector3(1.8, 1.4, 1.8),
			_mat_madera, true)


func _contenedor(centro: Vector3, i: int) -> void:
	var mat := _mat_contenedor[i % _mat_contenedor.size()]
	_caja("Contenedor%d" % i, centro, Vector3(3.0, 2.7, 6.5), mat, true)
	for dz in [-2.2, 0.0, 2.2]:
		_caja("Refuerzo", Vector3(centro.x, centro.y, centro.z + dz),
				Vector3(3.06, 2.76, 0.16), _mat_super_detalle, false)


# ============================================================ GRÚAS
func _construir_gruas() -> void:
	# Dos grúas de carga sobre la cubierta principal, con la pluma recogida hacia
	# proa y SIN salirse del casco.
	for lado in [-1.0, 1.0]:
		var x: float = lado * 6.6
		# El poste de la grúa es un obstáculo REAL de cubierta: lleva colisión para
		# que el cuerpo no lo atraviese (la pluma va 4,4 m por encima: no estorba).
		_cilindro("GruaPoste", Vector3(x, CUBIERTA + 2.6, 22.0), 0.55, 5.2, _mat_barandilla, true)
		_caja("GruaBase", Vector3(x, CUBIERTA + 0.25, 22.0), Vector3(2.2, 0.5, 2.2),
				_mat_super_detalle, true)
		var pluma := _caja("GruaPluma", Vector3(x, CUBIERTA + 4.4, 24.6),
				Vector3(0.42, 0.42, 5.6), _mat_barandilla, false)
		pluma.rotation.x = deg_to_rad(-16.0)
		_caja("GruaCable", Vector3(x, CUBIERTA + 3.0, 26.8), Vector3(0.06, 3.0, 0.06),
				_mat_mastil, false)


# ============================================================ BOTE SALVAVIDAS
func _construir_bote() -> void:
	var y := CUBIERTA + 0.27 + PUENTE_H + 0.6
	var x := PUENTE_SEMI + 1.5
	_caja("Bote", Vector3(x, y + 0.55, -32.0), Vector3(2.4, 1.1, 6.0), _mat_aro, false)
	_caja("BoteRegala", Vector3(x, y + 1.15, -32.0), Vector3(2.5, 0.15, 6.1), _mat_super, false)
	for dz in [-2.6, 2.6]:
		_caja("Pescante", Vector3(x - 0.9, y + 1.0, -32.0 + dz), Vector3(0.16, 2.0, 0.16),
				_mat_mastil, false)


# ============================================================ DETALLES DE CUBIERTA
func _construir_detalles_cubierta() -> void:
	# Norayes (bollards) repartidos por los costados. Son SÓLIDOS: llevan colisión
	# de cilindro (bajos y redondos: el cuerpo se desliza a su alrededor, no vibra).
	for z in [-24.0, -4.0, 12.0, 38.0]:
		for lado in [-1.0, 1.0]:
			var x: float = lado * (SEMI_M - 1.2)
			_cilindro("Noray", Vector3(x, CUBIERTA + 0.28, z), 0.26, 0.56, _mat_oxido, true)
			_cilindro("NorayTapa", Vector3(x, CUBIERTA + 0.6, z), 0.34, 0.14, _mat_oxido, false)
	# Molinete de proa y ancla.
	_caja("Molinete", Vector3(0.0, PROA_Y + 0.55, 39.0), Vector3(1.8, 1.1, 1.4),
			_mat_super_detalle, true)
	var ancla := _caja("Ancla", Vector3(-1.9, PROA_Y + 0.5, 41.5), Vector3(0.5, 1.6, 0.3),
			_mat_oxido, false)
	ancla.rotation_degrees = Vector3(0.0, 0.0, 22.0)
	# Conductos pegados a la borda, a lo largo del pasillo: bajos (22 cm) y con
	# colisión, así que se pasan por ENCIMA andando (como un bordillo) y no impiden
	# llegar a la barandilla. Van por dentro de los norayes, sin solaparse.
	for lado2 in [-1.0, 1.0]:
		_caja("Conducto", Vector3(lado2 * 7.75, CUBIERTA + 0.11, 2.0), Vector3(0.45, 0.22, 44.0),
				_mat_super_detalle, true)
	# Escalinata de DOS escalones entre la cubierta principal y el castillo de proa
	# (0,35 m en total). Cada escalón queda dentro del paso máximo del controlador,
	# así que se sube andando; con un único escalón de 0,35 m el paso quedaba
	# bloqueado y la cubierta de proa era inalcanzable caminando.
	for lado3 in [-1.0, 1.0]:
		_caja("EscalonProa0", Vector3(lado3 * 5.2, CUBIERTA + 0.09, 24.9), Vector3(5.2, 0.18, 1.6),
				_mat_super_detalle, true)
		_caja("EscalinataProa", Vector3(lado3 * 5.2, PROA_Y - 0.18, 26.2), Vector3(5.6, 0.35, 1.8),
				_mat_super_detalle, true)
	# Armarios y cajas eléctricas: APOYADOS en la cubierta (antes quedaban 20 cm en
	# el aire, parecían flotar) y sólidos.
	for z2 in [-20.0, 0.0, 22.0]:
		_caja("Armario", Vector3(-8.35, CUBIERTA + 0.55, z2), Vector3(0.35, 1.1, 0.9),
				_mat_oxido, true)
		_caja("Armario", Vector3(8.35, CUBIERTA + 0.55, z2), Vector3(0.35, 1.1, 0.9),
				_mat_oxido, true)


# ============================================================ BARANDILLAS
func _construir_barandillas() -> void:
	var y := CUBIERTA
	var yp := PROA_Y
	var xb := -SEMI_M + 0.65
	var xe := SEMI_M - 0.65
	# Costado de babor: se interrumpe donde está la escalera (z≈6).
	_tramo_barandilla(Vector3(xb, y, -12.0), Vector3(xb, y, 2.0))
	_tramo_barandilla(Vector3(xb, y, 10.0), Vector3(xb, y, 24.0))
	# Costado de estribor completo hasta la proa.
	_tramo_barandilla(Vector3(xe, y, -12.0), Vector3(xe, y, 24.0))
	# Toldilla: cerrada por popa y costados.
	_tramo_barandilla(Vector3(-SEMI_M + 0.9, y + 0.25, -43.0), Vector3(SEMI_M - 0.9, y + 0.25, -43.0))
	_tramo_barandilla(Vector3(-SEMI_M + 0.9, y + 0.25, -43.0), Vector3(xb, y + 0.25, -31.0))
	_tramo_barandilla(Vector3(SEMI_M - 0.9, y + 0.25, -43.0), Vector3(xe, y + 0.25, -31.0))
	# Castillo de proa: costados y pico (todo dentro del forro).
	var xp: float = _semi_ancho_en(31.0) - 0.7
	_tramo_barandilla(Vector3(-xp, yp, 26.0), Vector3(-4.0, yp, 39.0))
	_tramo_barandilla(Vector3(4.0, yp, 39.0), Vector3(xp, yp, 26.0))
	_tramo_barandilla(Vector3(-4.0, yp, 39.0), Vector3(0.0, yp, 42.6))
	_tramo_barandilla(Vector3(0.0, yp, 42.6), Vector3(4.0, yp, 39.0))
	# Amurada de proa (peto de la borda alta), del ancho real del casco ahí.
	_caja("BordaProa", Vector3(0.0, PROA_Y + 0.5, 42.6),
			Vector3(_semi_ancho_en(42.0) * 1.8, 1.0, 0.5), _mat_super, false)


func _tramo_barandilla(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	dir.y = 0.0
	var largo := dir.length()
	var n := maxi(2, int(round(largo / 3.2)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_caja("Poste", Vector3(p.x, p.y + 0.55, p.z), Vector3(0.09, 1.1, 0.09), _mat_barandilla, false)
	# Tres travesaños (pasamanos alto, medio y bajo).
	for altura in [1.05, 0.7, 0.35]:
		var centro := Vector3((a.x + b.x) * 0.5, a.y + altura, (a.z + b.z) * 0.5)
		var d := b - a
		d.y = 0.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(absf(d.x), 0.09), 0.07, maxf(absf(d.z), 0.09))
		mi.mesh = bm
		mi.material_override = _mat_barandilla
		mi.position = centro
		add_child(mi)
	# COLISIÓN de la barandilla: una pared FINA que sigue el tramo (orientada, para
	# que los tramos del pico de proa no tapen la cubierta). Así el cuerpo choca con
	# ella y no se cae por la borda; es plana, no atrapa ni vibra.
	if largo > 0.05:
		_colision(Vector3((a.x + b.x) * 0.5, a.y + 0.57, (a.z + b.z) * 0.5),
				Vector3(0.14, 1.14, largo + 0.16), atan2(dir.x, dir.z))


# ============================================================ AROS SALVAVIDAS
func _construir_aros() -> void:
	for z in [-40.0, -20.0, 4.0, 24.0]:
		for lado in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.5
			tm.outer_radius = 0.72
			mi.mesh = tm
			mi.material_override = _mat_aro
			mi.position = Vector3(lado * (SEMI_M - 0.55), CUBIERTA + 0.95, z)
			mi.rotation.x = PI * 0.5
			add_child(mi)


# ============================================================ PORTILLAS
## Ventanucos redondos a lo largo de los DOS costados: dan escala al casco y rompen
## la pared lisa. Son huecos, no obstáculos: sin colisión.
func _construir_portillas() -> void:
	for z in range(-26, 40, 6):
		for lado in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.30
			cm.bottom_radius = 0.30
			cm.height = 0.34
			mi.mesh = cm
			mi.material_override = _mat_ventana
			mi.position = Vector3(lado * (_semi_ancho_en(float(z)) + 0.02), 2.30, float(z))
			mi.rotation.z = PI * 0.5
			add_child(mi)


# ============================================================ ESCALERA
## Escalera de servicio del costado de BABOR, la única entrada al barco. El nodo
## EscaleraBarco de debajo es el punto de agarre que usa la forma acuática: define
## dónde está el pie (en el agua), dónde se corona (sobre la cubierta) y hacia
## dónde mira el cuerpo mientras trepa.
func _construir_escalera() -> void:
	var x := -SEMI_M - 0.45     # justo por fuera del forro (babor)
	var z := ESC_Z
	var y_arriba := CUBIERTA + 0.9
	var y_abajo := -3.6
	for dz in [-0.42, 0.42]:
		_caja("Larguero", Vector3(x, (y_arriba + y_abajo) * 0.5, z + dz),
				Vector3(0.12, y_arriba - y_abajo, 0.12), _mat_barandilla, false)
	var n := 17
	for i in n:
		var y := lerpf(y_abajo + 0.25, y_arriba - 0.25, float(i) / float(n - 1))
		_caja("Peldano", Vector3(x, y, z), Vector3(0.14, 0.1, 0.95), _mat_barandilla, false)
	for y2 in [-2.6, -1.2, 0.2, 1.6, 3.0]:
		_caja("AroEscalera", Vector3(x + 0.06, y2, z), Vector3(0.06, 0.7, 1.15), _mat_mastil, false)
	# Los peldaños NO llevan colisión a propósito: el cuerpo trepa por un recorrido
	# guiado (EscaleraBarco, abajo) y una colisión ahí sólo estorbaría al agarre.
	#
	# --- Punto de agarre que usa el controlador (forma acuática) ---
	# Todo el recorrido se describe en el marco LOCAL de este nodo y con los
	# números MEDIDOS de la escalera, no con valores a ojo:
	#   * separacion_peldanos = la separación real entre peldaños.
	#   * El cuerpo trepa 0,25 m por FUERA del plano de los peldaños: MEDIDO con el
	#     arnés de diagnóstico, es el punto en el que las manos del clip (que van
	#     0,45 m por delante del cuerpo) agarran los peldaños y los pies quedan
	#     cerca de ellos. Con 0,35 las manos entraban de más en la escalera.
	#   * Los pies arrancan en el primer peldaño que asoma por encima del agua y el
	#     clip los deja AIRE_PIE_TREPADA por encima del origen del cuerpo.
	var esc := EscaleraBarco.new()
	esc.name = "Escalera"
	esc.position = Vector3(x - 0.55, -2.7, z)
	esc.radio_agarre = 2.6
	esc.texto_prompt = "Presioná E para subir al barco"
	esc.texto_prompt_bajada = "Presioná E para bajar al agua"
	esc.mirada_local = Vector3(1.0, 0.0, 0.0)
	# El clip de trepada mira al lado CONTRARIO que el resto de la librería (viene
	# retargeteado de Mixamo): medido con la sonda de la trepada, sin esta
	# compensación las manos suben 0,26 m del lado del MAR, o sea que el cuerpo
	# trepa DE ESPALDAS. Con PI las manos quedan del lado del casco, sobre los
	# peldaños. Al terminar, el controlador gira el cuerpo a la orientación normal.
	esc.giro_cuerpo = PI
	var paso := (y_arriba - 0.25 - (y_abajo + 0.25)) / float(n - 1)
	esc.separacion_peldanos = paso
	esc.peldanos_por_ciclo = 2.0
	var y_peldano_0 := y_abajo + 0.25
	var k := ceili((0.0 - y_peldano_0) / paso)         # primer peldaño sobre el agua
	var y_pies := y_peldano_0 + float(k) * paso
	var cara := (x - 0.25) - esc.position.x            # plano del cuerpo (local del nodo)
	var x_cubierta := -SEMI_M + 1.2                    # ya dentro de la cubierta
	esc.inicio_local = Vector3(cara, (y_pies - AIRE_PIE_TREPADA) - esc.position.y, 0.0)
	esc.tope_local = Vector3(cara, (CUBIERTA + 0.30) - esc.position.y, 0.0)
	esc.fin_local = Vector3(x_cubierta - esc.position.x, CUBIERTA - esc.position.y, 0.0)
	add_child(esc)


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
	# Las barandillas diagonales (pico de proa) necesitan una caja ORIENTADA: la
	# caja alineada a los ejes de un tramo diagonal taparía media cubierta.
	if absf(rot_y) > 0.0001:
		cs.rotation.y = rot_y
	_cuerpo.add_child(cs)