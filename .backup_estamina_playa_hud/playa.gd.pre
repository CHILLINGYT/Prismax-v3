class_name Playa
extends Object
## =============================================================================
##  MOBILIARIO DE PLAYA: PALMERAS, SOMBRILLAS Y REPOSERAS
## =============================================================================
##  Los tres modelos son mallas geométricas construidas por código, el mismo
##  camino que ya usan las farolas de la calle (world/farolas.gd) y los bancos
##  (world/bancos.gd): no hay que importar ningún modelo nuevo y el estilo se
##  mantiene. Las mallas se construyen UNA vez y las comparte toda la playa.
##
##  Uso: el generador de ciudad pide `malla_*()` (quedan cacheadas), acumula las
##  matrices de cada ejemplar y lo dibuja todo con MultiMeshInstance3D: un solo
##  dibujado por modelo (con una superficie por material).
##
##  Convenciones locales de cada modelo (la base siempre en y = 0):
##    · palmera   : ADULTA de verdad: tronco grueso de 7,6 m con inclinación,
##                  copa de 12 hojas largas (3,3-4 m), 4 hojas secas colgando y
##                  racimo de cocos. Escala 1 ≈ 8,5 m de alto.
##                  Superficies: 0 = hojas, 1 = tronco y cocos.
##    · sombrilla : mástil central de 2,58 m con placa base, 12 varillas y lona
##                  cónica de 12 paños (3 m de boca) con borde ondulado y falda.
##                  Esquemas: 0 = coral, 1 = azul, 2 = amarilla (a franjas con
##                  blanco). Superficies: 0 = lona, 1 = mástil y herrajes.
##    · reposera  : ≈1,9 x 0,66 m, listones de tela, cabecera y patas con
##                  travesaño. Largo en Z con los PIES hacia +Z (para orientarla
##                  al mar). Variante 0 tumbada (20°) y 1 reclinada (40°).
##                  Superficies: 0 = tela, 1 = bastidor metálico.
##
##  El color va en los COLORES DE VÉRTICE (lona a franjas, hojas, patas) y la
##  variación por ejemplar llega por el color de instancia de la MultiMesh, que
##  multiplica al anterior. Así una sola malla da ejemplares distintos.
##
##  Es una clase de utilidades: se usan sus funciones estáticas.
## =============================================================================

# --- Paleta veraniega, en armonía con la arena y el césped ---------------------
const CORAL := Color(0.83, 0.27, 0.22)
const AZUL := Color(0.16, 0.42, 0.70)
const AMARILLO := Color(0.94, 0.72, 0.20)
const BLANCO_LONA := Color(0.93, 0.92, 0.87)
const TELA := Color(0.90, 0.89, 0.84)
const TRONCO := Color(0.42, 0.33, 0.22)
const TRONCO_CLARO := Color(0.55, 0.46, 0.31)
const HOJA := Color(0.22, 0.43, 0.15)
const HOJA_CLARA := Color(0.37, 0.58, 0.21)
const HOJA_SECA := Color(0.51, 0.42, 0.24)
const COCO := Color(0.44, 0.38, 0.22)
const METAL := Color(0.30, 0.30, 0.32)

# --- Medidas de la palmera (malla, en metros) ----------------------------------
const PALMA_ALTO := 7.6          ## altura del tronco
const PALMA_INCLINACION := 0.50  ## cuánto se aparta la punta respecto de la base
const PALMA_HOJAS := 12
const PALMA_LARGO_HOJA := 3.3

static var _mallas := {}
static var _materiales := {}


# =============================================================================
#  Materiales (compartidos; el detalle lo ponen los colores de vértice)
# =============================================================================

## Hojas de la palmera: planos delgados, dos caras y algo de translucidez (a
## contraluz no quedan negras).
static func material_hoja() -> StandardMaterial3D:
	if _materiales.has("hoja"):
		return _materiales["hoja"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.55, 0.75, 0.35)
	_materiales["hoja"] = m
	return m


## Tronco de la palmera (y cocos): mate y rugoso.
static func material_tronco() -> StandardMaterial3D:
	if _materiales.has("tronco"):
		return _materiales["tronco"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.93
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materiales["tronco"] = m
	return m


## Lona (sombrilla y tela de reposera): dos caras visibles y colores de vértice.
static func material_lona() -> StandardMaterial3D:
	if _materiales.has("lona"):
		return _materiales["lona"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.72
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materiales["lona"] = m
	return m


## Herrajes: mástil, varillas y bastidor de la reposera. Metal pintado.
static func material_metal() -> StandardMaterial3D:
	if _materiales.has("metal"):
		return _materiales["metal"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.55
	m.roughness = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materiales["metal"] = m
	return m


# =============================================================================
#  Palmera (dos superficies: hojas / tronco y cocos)
# =============================================================================

## Malla de la palmera adulta. La punta del tronco (la corona) está en
## (PALMA_INCLINACION, PALMA_ALTO, 0): las hojas y los cocos salen de allí.
static func malla_palmera() -> ArrayMesh:
	if _mallas.has("palmera"):
		return _mallas["palmera"]
	var punta := Vector3(PALMA_INCLINACION, PALMA_ALTO, 0.0)
	# --- Superficie 0: hojas ------------------------------------------------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 12 hojas repartidas en círculo, con largos y curvas algo distintos (según
	# el índice, para que la copa no salga simétrica como un molde).
	for i in PALMA_HOJAS:
		var phi := TAU * float(i) / float(PALMA_HOJAS) + 0.11 * float(i % 4)
		var largo := PALMA_LARGO_HOJA * (0.82 + 0.26 * float((i * 7) % 5) / 4.0)
		var col := HOJA.lerp(HOJA_CLARA, 0.20 + 0.55 * float((i * 3) % 4) / 3.0)
		_hoja(st, punta, phi, largo, i * 0.35, col)
	# 4 hojas secas colgando junto al tronco (dan la silueta "de palmera").
	for i in 4:
		var phi := TAU * float(i) / 4.0 + 0.7
		_hoja_seca(st, punta, phi, 1.9 + 0.25 * float(i))
	st.generate_normals()
	var malla := st.commit()
	# --- Superficie 1: tronco, base y cocos ---------------------------------
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tronco: 7 tramos con radios decrecientes y una inclinación suave (+X).
	var tramos := 7
	for k in tramos:
		var t0 := float(k) / float(tramos)
		var t1 := float(k + 1) / float(tramos)
		var c0 := Vector3(PALMA_INCLINACION * t0 * t0, PALMA_ALTO * t0, 0.0)
		var c1 := Vector3(PALMA_INCLINACION * t1 * t1, PALMA_ALTO * t1, 0.0)
		var r0 := lerpf(0.26, 0.155, t0)
		var r1 := lerpf(0.26, 0.155, t1)
		var col := TRONCO.lerp(TRONCO_CLARO, 0.5 + 0.5 * sin(t0 * 9.0))
		_cilindro(st, r0, r1, c0, c1, 8, col)
	# Abultamiento de la base (raíces) y remate de la corona.
	_cilindro(st, 0.40, 0.26, Vector3(0.0, -0.16, 0.0), Vector3(0.0, 0.30, 0.0), 8, TRONCO)
	_esfera(st, 0.27, punta + Vector3(0.0, 0.04, 0.0), 6, 9, TRONCO_CLARO)
	# Racimo de cocos bajo la corona.
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		_esfera(st, 0.10, punta + Vector3(cos(a) * 0.34, -0.26 - 0.05 * float(i % 2),
				sin(a) * 0.34), 4, 6, COCO)
	st.generate_normals()
	malla = st.commit(malla)
	malla.surface_set_material(0, material_hoja())
	malla.surface_set_material(1, material_tronco())
	_mallas["palmera"] = malla
	return malla


## Una hoja: cinta curva que sale de la corona, se arquea hacia arriba y cae
## hacia la punta, con un pliegue central (nervio) y color por tramo.
static func _hoja(st: SurfaceTool, base: Vector3, phi: float, largo: float,
		_fase: float, col: Color) -> void:
	var hor := Vector3(cos(phi), 0.0, sin(phi))
	var lado := hor.cross(Vector3.UP).normalized()
	var pasos := 7
	var prev_izq := Vector3.ZERO
	var prev_der := Vector3.ZERO
	var prev_med := Vector3.ZERO
	for s in pasos + 1:
		var t := float(s) / float(pasos)
		var cur := base + hor * (t * largo) \
				+ Vector3.UP * (0.50 + 1.15 * t - 2.15 * t * t) \
				+ lado * (0.22 * sin(t * 4.0 + _fase))
		var ancho := 0.05 + 0.34 * pow(sin(clampf(t, 0.0, 1.0) * PI), 0.8)
		var izq := cur - lado * (ancho * 0.5)
		var der := cur + lado * (ancho * 0.5)
		var med := cur + Vector3.UP * (0.06 * (1.0 - t))
		if s > 0:
			var c0 := col.lerp(HOJA_CLARA, tono_hoja(s - 1, pasos))
			var c1 := col.lerp(HOJA_CLARA, tono_hoja(s, pasos))
			_cuad(st, prev_izq, izq, prev_med, med, c0, c1)
			_cuad(st, prev_med, med, prev_der, der, c0, c1)
		prev_izq = izq
		prev_der = der
		prev_med = med


## Factor (0..1) para aclarar la hoja hacia su punta.
static func tono_hoja(s: int, pasos: int) -> float:
	return 0.15 + 0.85 * float(s) / float(pasos)


## Hoja seca: cuelga del punto de la corona hacia abajo.
static func _hoja_seca(st: SurfaceTool, base: Vector3, phi: float, largo: float) -> void:
	var hor := Vector3(cos(phi), 0.0, sin(phi))
	var lado := hor.cross(Vector3.UP).normalized()
	var pasos := 4
	var prev_izq := Vector3.ZERO
	var prev_der := Vector3.ZERO
	for s in pasos + 1:
		var t := float(s) / float(pasos)
		var cur := base + hor * (t * largo * 0.45) + Vector3.UP * (0.05 - 1.55 * t)
		var ancho := 0.05 + 0.18 * sin(clampf(t, 0.0, 1.0) * PI)
		var izq := cur - lado * (ancho * 0.5)
		var der := cur + lado * (ancho * 0.5)
		if s > 0:
			_cuad(st, prev_izq, izq, prev_der, der, HOJA_SECA, HOJA_SECA)
		prev_izq = izq
		prev_der = der


# =============================================================================
#  Sombrilla (dos superficies: lona / mástil y herrajes)
# =============================================================================

## Malla de la sombrilla del esquema pedido (0 coral, 1 azul, 2 amarilla).
## Lona cónica de 12 paños con borde ondulado y falda, 12 varillas por debajo
## del borde, mástil central con placa de base y remate.
static func malla_sombrilla(esquema: int) -> ArrayMesh:
	var clave := "sombrilla_%d" % esquema
	if _mallas.has(clave):
		return _mallas[clave]
	var color := [CORAL, AZUL, AMARILLO][clampi(esquema, 0, 2)] as Color
	var panos := 12
	var radio := 1.50
	var alto_cono := 2.52
	var alto_borde := 1.74
	# --- Superficie 0: lona -------------------------------------------------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in panos:
		var a0 := TAU * float(k) / float(panos)
		var a1 := TAU * float(k + 1) / float(panos)
		var r0 := radio + 0.04 * float(k % 2)
		var r1 := radio + 0.04 * float((k + 1) % 2)
		var y0 := alto_borde - 0.05 * float(k % 2)
		var y1 := alto_borde - 0.05 * float((k + 1) % 2)
		var v0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var v1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var cima := Vector3(0.0, alto_cono, 0.0)
		var col := color if (k % 2) == 0 else BLANCO_LONA
		_tri(st, v0, v1, cima, col)
	# Falda del borde (una banda corta hacia abajo, da grosor a la lona).
	for k in panos:
		var a0 := TAU * float(k) / float(panos)
		var a1 := TAU * float(k + 1) / float(panos)
		var r0 := radio + 0.04 * float(k % 2)
		var r1 := radio + 0.04 * float((k + 1) % 2)
		var y0 := alto_borde - 0.05 * float(k % 2)
		var y1 := alto_borde - 0.05 * float((k + 1) % 2)
		var v0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var v1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var s0 := v0 - Vector3(0.0, 0.13, 0.0)
		var s1 := v1 - Vector3(0.0, 0.13, 0.0)
		var col := color if (k % 2) == 0 else BLANCO_LONA
		_cuad2(st, v0, v1, s1, s0, col)
	st.generate_normals()
	var malla := st.commit()
	# --- Superficie 1: mástil, base, varillas y remate -----------------------
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Mástil: del suelo al remate, pasando por el vértice de la lona.
	_cilindro(st, 0.035, 0.035, Vector3.ZERO, Vector3(0.0, 2.58, 0.0), 8, METAL)
	_esfera(st, 0.06, Vector3(0.0, 2.62, 0.0), 4, 8, METAL)
	# Placa de base (para que se vea clavada en la arena) y casquillo.
	_cilindro(st, 0.26, 0.20, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.06, 0.0), 10, METAL)
	_cilindro(st, 0.10, 0.09, Vector3(0.0, 0.06, 0.0), Vector3(0.0, 0.20, 0.0), 8, METAL)
	# 12 varillas por debajo de la lona, del centro al borde.
	for k in panos:
		var a := TAU * float(k) / float(panos)
		var borde := Vector3(cos(a) * (radio - 0.06), alto_borde - 0.03, sin(a) * (radio - 0.06))
		var inicio := Vector3(0.0, alto_cono - 0.12, 0.0)
		var dir_v := (borde - inicio).normalized()
		_caja_girada(st, Vector3(0.022, 0.022, (borde - inicio).length()), Vector3.ZERO,
				(inicio + borde) * 0.5, dir_v, METAL)
	st.generate_normals()
	malla = st.commit(malla)
	malla.surface_set_material(0, material_lona())
	malla.surface_set_material(1, material_metal())
	_mallas[clave] = malla
	return malla


# =============================================================================
#  Reposera (dos superficies: tela / bastidor)
# =============================================================================

## Malla de la reposera: variante 0 tumbada (20°), 1 reclinada (40°).
## 1,95 m de largo por 0,66 de ancho, con listones de tela, cabecera y patas
## con travesaño. Largo en Z con los PIES hacia +Z: al orientarla, +Z mira al mar.
static func malla_reposera(variante: int) -> ArrayMesh:
	var clave := "reposera_%d" % variante
	if _mallas.has(clave):
		return _mallas[clave]
	var incl := deg_to_rad(20.0 if variante == 0 else 40.0)
	var sep := 0.31                 # semiancho entre largueros
	var y_tabla := 0.345            # cara superior del lecho
	var z_quiebre := -0.06          # quiebre entre lecho y respaldo
	var z_pies := 1.02
	var largo_respaldo := 0.92
	var dir := Vector3(0.0, sin(incl), -cos(incl))
	# --- Superficie 0: tela (listones y cabecera) ---------------------------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_lecho := 7
	for k in n_lecho:
		var z := lerpf(z_quiebre + 0.08, z_pies - 0.08, float(k) / float(n_lecho - 1))
		_caja_malla(st, Vector3(sep * 2.0 - 0.015, 0.035, 0.125), Vector3(0.0, y_tabla, z), TELA)
	var n_resp := 6
	for k in n_resp:
		var t := 0.10 + 0.78 * float(k) / float(n_resp - 1)
		var p := Vector3(0.0, y_tabla, z_quiebre) + dir * (largo_respaldo * t)
		_caja_girada(st, Vector3(sep * 2.0 - 0.015, 0.035, 0.125), Vector3.ZERO, p, dir, TELA)
	# Cabecera (almohadilla) en lo alto del respaldo.
	var p_cab := Vector3(0.0, y_tabla, z_quiebre) + dir * (largo_respaldo * 0.86)
	_caja_girada(st, Vector3(0.50, 0.10, 0.26), Vector3(0.0, 0.035, -0.02), p_cab, dir, TELA)
	st.generate_normals()
	var malla := st.commit()
	# --- Superficie 1: bastidor ----------------------------------------------
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Largueros del lecho (dos barras a lo largo).
	for s in [-1.0, 1.0]:
		_caja_malla(st, Vector3(0.05, 0.05, z_pies - z_quiebre),
				Vector3(s * sep, y_tabla - 0.035, (z_pies + z_quiebre) * 0.5), METAL)
	# Largueros del respaldo, inclinados.
	var centro_r := Vector3(0.0, y_tabla, z_quiebre) + dir * (largo_respaldo * 0.5)
	for s in [-1.0, 1.0]:
		_caja_girada(st, Vector3(0.05, 0.05, largo_respaldo), Vector3(s * sep, 0.0, 0.0),
				centro_r, dir, METAL)
	# Patas: dos pares, casi verticales, con travesaño de rigidez.
	for sz in [z_pies - 0.14, z_quiebre - 0.46]:
		var y := (y_tabla - 0.16) * 0.5 + 0.02
		for s in [-1.0, 1.0]:
			_caja_malla(st, Vector3(0.045, y_tabla - 0.09, 0.045), Vector3(s * sep, y, sz), METAL)
	_caja_malla(st, Vector3(sep * 2.0, 0.04, 0.04),
			Vector3(0.0, 0.14, z_quiebre - 0.46), METAL)
	st.generate_normals()
	malla = st.commit(malla)
	malla.surface_set_material(0, material_lona())
	malla.surface_set_material(1, material_metal())
	_mallas[clave] = malla
	return malla


# =============================================================================
#  Piezas geométricas (todas con color de vértice)
# =============================================================================

## Triángulo suelto.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


## Cuadrilátero a-b-c-d (dos triángulos), con un color por extremo.
static func _cuad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col_a: Color, col_b: Color) -> void:
	st.set_color(col_a)
	st.add_vertex(a)
	st.set_color(col_b)
	st.add_vertex(b)
	st.set_color(col_b)
	st.add_vertex(c)
	st.set_color(col_a)
	st.add_vertex(a)
	st.set_color(col_b)
	st.add_vertex(c)
	st.set_color(col_a)
	st.add_vertex(d)


## Cuadrilátero con un solo color.
static func _cuad2(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color) -> void:
	_cuad(st, a, b, c, d, col, col)


## Cilindro (o cono truncado) entre dos puntos, con tapas.
static func _cilindro(st: SurfaceTool, r0: float, r1: float, c0: Vector3, c1: Vector3,
		lados: int, col: Color) -> void:
	var eje := c1 - c0
	if eje.length_squared() < 0.000001:
		return
	var b := Basis(Quaternion(Vector3.UP, eje.normalized()))
	for k in lados:
		var a0 := TAU * float(k) / float(lados)
		var a1 := TAU * float(k + 1) / float(lados)
		var d0 := b * Vector3(cos(a0), 0.0, sin(a0))
		var d1 := b * Vector3(cos(a1), 0.0, sin(a1))
		_cuad2(st, c0 + d0 * r0, c0 + d1 * r0, c1 + d1 * r1, c1 + d0 * r1, col)
		_tri(st, c1, c1 + d1 * r1, c1 + d0 * r1, col)
		_tri(st, c0, c0 + d0 * r0, c0 + d1 * r0, col)


## Esfera de pocos segmentos.
static func _esfera(st: SurfaceTool, r: float, centro: Vector3, anillos: int, lados: int,
		col: Color) -> void:
	for i in anillos:
		var t0 := PI * float(i) / float(anillos)
		var t1 := PI * float(i + 1) / float(anillos)
		for k in lados:
			var a0 := TAU * float(k) / float(lados)
			var a1 := TAU * float(k + 1) / float(lados)
			var p00 := centro + Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)) * r
			var p01 := centro + Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)) * r
			var p10 := centro + Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0)) * r
			var p11 := centro + Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)) * r
			_cuad2(st, p00, p01, p11, p10, col)


## Caja alineada a los ejes (centro + tamaño).
static func _caja_malla(st: SurfaceTool, tam: Vector3, centro: Vector3, col: Color) -> void:
	var h := tam * 0.5
	for s: Vector3 in [Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)]:
		var e := s * h
		if s.x > 0.0:
			_cuad2(st, centro + e + Vector3(0, -h.y, -h.z), centro + e + Vector3(0, h.y, -h.z),
					centro + e + Vector3(0, h.y, h.z), centro + e + Vector3(0, -h.y, h.z), col)
		else:
			_cuad2(st, centro + e + Vector3(0, -h.y, h.z), centro + e + Vector3(0, h.y, h.z),
					centro + e + Vector3(0, h.y, -h.z), centro + e + Vector3(0, -h.y, -h.z), col)
	for s2: Vector3 in [Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0)]:
		var e2 := s2 * h
		if s2.y > 0.0:
			_cuad2(st, centro + e2 + Vector3(-h.x, 0, -h.z), centro + e2 + Vector3(h.x, 0, -h.z),
					centro + e2 + Vector3(h.x, 0, h.z), centro + e2 + Vector3(-h.x, 0, h.z), col)
		else:
			_cuad2(st, centro + e2 + Vector3(-h.x, 0, h.z), centro + e2 + Vector3(h.x, 0, h.z),
					centro + e2 + Vector3(h.x, 0, -h.z), centro + e2 + Vector3(-h.x, 0, -h.z), col)
	for s3: Vector3 in [Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0)]:
		var e3 := s3 * h
		if s3.z > 0.0:
			_cuad2(st, centro + e3 + Vector3(-h.x, -h.y, 0), centro + e3 + Vector3(h.x, -h.y, 0),
					centro + e3 + Vector3(h.x, h.y, 0), centro + e3 + Vector3(-h.x, h.y, 0), col)
		else:
			_cuad2(st, centro + e3 + Vector3(-h.x, h.y, 0), centro + e3 + Vector3(h.x, h.y, 0),
					centro + e3 + Vector3(h.x, -h.y, 0), centro + e3 + Vector3(-h.x, -h.y, 0), col)


## Caja girada: el eje Z local sigue a `dir` (para los listones y largueros del
## respaldo, que van inclinados). `desplaz` se suma al centro en el espacio girado.
static func _caja_girada(st: SurfaceTool, tam: Vector3, desplaz: Vector3, centro: Vector3,
		dir: Vector3, col: Color) -> void:
	var z_local := dir.normalized()
	var x_local := Vector3.UP.cross(z_local)
	if x_local.length_squared() < 0.0001:
		x_local = Vector3.RIGHT
	x_local = x_local.normalized()
	var y_local := z_local.cross(x_local).normalized()
	var b := Basis(x_local, y_local, z_local)
	var h := tam * 0.5
	var c := centro + b * desplaz
	# Se construyen las 6 caras en el espacio girado.
	for sx in [-1.0, 1.0]:
		var e := b * Vector3(sx * h.x, 0.0, 0.0)
		var e2 := b * Vector3(0.0, h.y, 0.0)
		var e3 := b * Vector3(0.0, 0.0, h.z)
		_cuad2(st, c + e - e2 - e3, c + e + e2 - e3, c + e + e2 + e3, c + e - e2 + e3, col)
	for sy in [-1.0, 1.0]:
		var e := b * Vector3(0.0, sy * h.y, 0.0)
		var e1 := b * Vector3(h.x, 0.0, 0.0)
		var e3 := b * Vector3(0.0, 0.0, h.z)
		_cuad2(st, c + e - e1 - e3, c + e + e1 - e3, c + e + e1 + e3, c + e - e1 + e3, col)
	for sz in [-1.0, 1.0]:
		var e := b * Vector3(0.0, 0.0, sz * h.z)
		var e1 := b * Vector3(h.x, 0.0, 0.0)
		var e2 := b * Vector3(0.0, h.y, 0.0)
		_cuad2(st, c + e - e1 - e2, c + e + e1 - e2, c + e + e1 + e2, c + e - e1 + e2, col)