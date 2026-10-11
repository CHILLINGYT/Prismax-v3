class_name BarcoExplorable
extends Node3D
## =============================================================================
##  BARCO GRANDE, EXPLORABLE (buque de suministro)
## =============================================================================
##  Un ÚNICO barco en medio del océano. Se construye con geometría nativa de
##  Godot (sin modelos externos): el casco es una superficie alargada generada por
##  estaciones (afinada en proa y popa), y el resto son cajas y cilindros.
##
##  PUNTOS CLAVE DEL DISEÑO
##   * El origen local está en la LÍNEA DE FLOTACIÓN: el nodo se coloca con su Y a
##     la altura del mar, así el casco queda medio sumergido de forma natural (no
##     "flota" sobre el agua ni se hunde).
##   * La cubierta es una superficie PLANA y AMPLIA, con colisión propia: se puede
##     caminar por ella (base para futuras oleadas de enemigos).
##   * Cada parte travesable tiene SU colisión; NO hay una única caja gigante que
##     bloquee la cubierta: el casco macizo va por debajo, la cubierta por encima y
##     el castillo es una sala hueca con puerta.
##   * La escalera (EscaleraBarco) es el único punto de subida, y sólo la usa la
##     forma acuática (ver controlador_leo.gd).
## =============================================================================

# --- Medidas (m, en coordenadas locales; y=0 es la línea de flotación) ---
const ESLORA := 62.0
const MANGA := 13.0
const SEMI_L := ESLORA * 0.5
const SEMI_M := MANGA * 0.5
## Cota local de la cara superior de la cubierta (transitable).
const CUBIERTA := 2.6
## Cota local del fondo del casco (obra viva).
const QUILLA := -5.6

## Contorno de una cuaderna (u: -1..1 media manga, v: 0..1 del fondo a cubierta).
## El tramo del último punto al primero es la boca de cubierta: no se genera.
const SECCION := [
	Vector2(1.0, 1.0), Vector2(1.0, 0.55), Vector2(0.78, 0.14),
	Vector2(0.0, 0.0), Vector2(-0.78, 0.14), Vector2(-1.0, 0.55), Vector2(-1.0, 1.0)]

# --- Oscilación (vaivén) muy leve, opcional ---
const VAIVEN_ALTURA := 0.045
const VAIVEN_INCLINA := 0.006
const VAIVEN_VELOCIDAD := 0.55

var _cuerpo: StaticBody3D
var _base_y: float = 0.0
var _t: float = 0.0

var _mat_casco: StandardMaterial3D
var _mat_cubierta: StandardMaterial3D
var _mat_super: StandardMaterial3D
var _mat_ventana: StandardMaterial3D
var _mat_barandilla: StandardMaterial3D
var _mat_aro: StandardMaterial3D
var _mat_mastil: StandardMaterial3D
var _mat_contenedor: Array[StandardMaterial3D] = []


func _ready() -> void:
	_base_y = position.y
	_preparar_materiales()
	_cuerpo = StaticBody3D.new()
	_cuerpo.name = "Cuerpo"
	add_child(_cuerpo)
	_construir_casco()
	_construir_cubierta()
	_construir_castillo()
	_construir_contenedores()
	_construir_mastil()
	_construir_barandillas()
	_construir_aros()
	_construir_escalera()


func _process(delta: float) -> void:
	_t += delta
	var s := sin(_t * VAIVEN_VELOCIDAD)
	position.y = _base_y + s * VAIVEN_ALTURA
	rotation.z = sin(_t * VAIVEN_VELOCIDAD * 0.72) * VAIVEN_INCLINA
	rotation.x = sin(_t * VAIVEN_VELOCIDAD * 0.53) * VAIVEN_INCLINA * 0.6


# ============================================================ MATERIALES
func _preparar_materiales() -> void:
	_mat_casco = _mat(Color(0.14, 0.18, 0.24))
	_mat_casco.cull_mode = BaseMaterial3D.CULL_DISABLED      # casco de doble cara
	_mat_cubierta = _mat(Color(0.42, 0.43, 0.40))            # gris antideslizante
	_mat_super = _mat(Color(0.88, 0.89, 0.9))               # blanco del castillo
	_mat_ventana = _mat(Color(0.05, 0.12, 0.16))
	_mat_ventana.metallic = 0.6
	_mat_ventana.roughness = 0.15
	_mat_barandilla = _mat(Color(0.85, 0.7, 0.12))          # amarillo seguridad
	_mat_aro = _mat(Color(0.95, 0.42, 0.08))                # naranja salvavidas
	_mat_cubierta.roughness = 0.9
	_mat_mastil = _mat(Color(0.6, 0.6, 0.62))
	_mat_contenedor = [
		_mat(Color(0.75, 0.22, 0.16)), _mat(Color(0.15, 0.35, 0.6)),
		_mat(Color(0.2, 0.5, 0.3)), _mat(Color(0.8, 0.65, 0.15))]


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


# ============================================================ CASCO
func _construir_casco() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ns := 28
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

	# Colisión del casco: caja principal (maciza, no travesable) + caja de proa
	# más estrecha, para no dejar una caja gigante que sobresalga del pico.
	_colision(Vector3(0.0, (CUBIERTA + QUILLA) * 0.5 - 0.2, -2.0),
			Vector3(MANGA - 0.5, CUBIERTA - QUILLA - 0.4, ESLORA - 12.0))
	_colision(Vector3(0.0, -1.4, SEMI_L - 7.5), Vector3(6.5, 3.4, 15.0))


func _manga_factor(t: float) -> float:
	if t < 0.12:
		return lerpf(0.66, 1.0, t / 0.12)
	if t > 0.78:
		var s := (t - 0.78) / 0.22
		return lerpf(1.0, 0.05, s * s)
	return 1.0


func _quilla(t: float) -> float:
	if t > 0.70:
		var s := (t - 0.70) / 0.30
		return lerpf(QUILLA, -0.6, s * s)
	if t < 0.05:
		var s := (0.05 - t) / 0.05
		return lerpf(QUILLA, -4.4, s)
	return QUILLA


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
	# Cubierta principal: superficie plana y amplia, con colisión propia para
	# poder caminar por ella.
	_caja("Cubierta", Vector3(0.0, CUBIERTA - 0.2, -7.0),
			Vector3(MANGA - 0.4, 0.4, 46.0), _mat_cubierta, true)
	# Cubierta de proa (más estrecha, sigue la afinación del casco).
	_caja("CubiertaProa", Vector3(0.0, CUBIERTA - 0.2, 21.5),
			Vector3(8.0, 0.4, 11.0), _mat_cubierta, true)
	_caja("CubiertaPico", Vector3(0.0, CUBIERTA - 0.2, 28.0),
			Vector3(4.0, 0.4, 4.0), _mat_cubierta, true)
	# Borda (peto) a lo largo de los costados: sube un escalón desde la cubierta.
	# SIN colisión a propósito: es más alta que el escalón máximo del controlador
	# (0,26 m), así que si bloqueara, encerraría al jugador en la cubierta sin forma
	# de bajar. Decorativa: se puede salir andando por el borde y caer al agua.
	_caja("BordaBabor", Vector3(-SEMI_M + 0.35, CUBIERTA + 0.35, -7.0),
			Vector3(0.5, 0.9, 46.0), _mat_super, false)
	_caja("BordaEstribor", Vector3(SEMI_M - 0.35, CUBIERTA + 0.35, -7.0),
			Vector3(0.5, 0.9, 46.0), _mat_super, false)


# ============================================================ CASTILLO (sala)
func _construir_castillo() -> void:
	var z0 := -26.0   # popa
	var z1 := -12.0   # frente (hacia proa)
	var hz := 3.0
	var cy := CUBIERTA + hz * 0.5
	# Paredes: popa, dos costados y frente con HUECO DE PUERTA (dos tramos).
	_caja("CastilloPopa", Vector3(0.0, cy, z0), Vector3(9.0, hz, 0.35), _mat_super, true)
	_caja("CastilloBabor", Vector3(-4.5, cy, (z0 + z1) * 0.5),
			Vector3(0.35, hz, (z1 - z0)), _mat_super, true)
	_caja("CastilloEstribor", Vector3(4.5, cy, (z0 + z1) * 0.5),
			Vector3(0.35, hz, (z1 - z0)), _mat_super, true)
	_caja("CastilloFrenteIzq", Vector3(-2.7, cy, z1), Vector3(3.6, hz, 0.35), _mat_super, true)
	_caja("CastilloFrenteDer", Vector3(2.7, cy, z1), Vector3(3.6, hz, 0.35), _mat_super, true)
	# Dintel sobre la puerta (cierra el hueco por arriba).
	_caja("CastilloDintel", Vector3(0.0, CUBIERTA + hz - 0.45, z1),
			Vector3(1.8, 0.9, 0.35), _mat_super, true)
	# Techo.
	_caja("CastilloTecho", Vector3(0.0, CUBIERTA + hz, (z0 + z1) * 0.5),
			Vector3(10.0, 0.4, (z1 - z0) + 1.0), _mat_super, true)
	# Ventanas (decorativas) en los costados.
	_caja("VentanaBabor", Vector3(-4.72, CUBIERTA + 1.9, (z0 + z1) * 0.5),
			Vector3(0.06, 1.0, 11.0), _mat_ventana, false)
	_caja("VentanaEstribor", Vector3(4.72, CUBIERTA + 1.9, (z0 + z1) * 0.5),
			Vector3(0.06, 1.0, 11.0), _mat_ventana, false)
	_caja("VentanaProa", Vector3(0.0, CUBIERTA + 1.9, z1 - 0.02),
			Vector3(4.0, 1.0, 0.06), _mat_ventana, false)
	# Consola interior (detalle del puente de mando).
	_caja("Consola", Vector3(0.0, CUBIERTA + 0.6, -25.0), Vector3(3.0, 1.2, 0.7), _mat_cubierta, false)
	# Chimenea.
	_cilindro("Chimenea", Vector3(0.0, CUBIERTA + hz + 1.7, -22.0), 1.0, 3.4, _mat_super, false)


# ============================================================ CONTENEDORES
func _construir_contenedores() -> void:
	_contenedor(Vector3(-3.7, CUBIERTA + 1.3, 6.0), 0)
	_contenedor(Vector3(0.0, CUBIERTA + 1.3, 6.0), 1)
	_contenedor(Vector3(3.7, CUBIERTA + 1.3, 6.0), 2)
	_contenedor(Vector3(0.0, CUBIERTA + 3.9, 6.0), 3)


func _contenedor(centro: Vector3, i: int) -> void:
	var mat := _mat_contenedor[i % _mat_contenedor.size()]
	_caja("Contenedor%d" % i, centro, Vector3(2.5, 2.6, 6.0), mat, true)


# ============================================================ MÁSTIL Y ANTENAS
func _construir_mastil() -> void:
	var base := CUBIERTA + 3.0
	_cilindro("Mastil", Vector3(0.0, base + 4.5, -16.0), 0.22, 9.0, _mat_mastil, false)
	_cilindro("AntenaA", Vector3(-1.0, base + 3.0, -14.0), 0.06, 6.0, _mat_mastil, false)
	_cilindro("AntenaB", Vector3(1.0, base + 3.0, -14.0), 0.06, 6.0, _mat_mastil, false)
	# Travesaño del mástil.
	_caja("Cruceta", Vector3(0.0, base + 6.0, -16.0), Vector3(3.0, 0.1, 0.1), _mat_mastil, false)


# ============================================================ BARANDILLAS
func _construir_barandillas() -> void:
	var y := CUBIERTA
	var xb := -SEMI_M + 0.55
	var xe := SEMI_M - 0.55
	# Costado de babor (se interrumpe donde está la escalera, z≈6).
	_tramo_barandilla(Vector3(xb, y, -30.0), Vector3(xb, y, 2.0))
	_tramo_barandilla(Vector3(xb, y, 10.0), Vector3(xb, y, 16.0))
	# Costado de estribor completo.
	_tramo_barandilla(Vector3(xe, y, -30.0), Vector3(xe, y, 16.0))
	# Popa.
	_tramo_barandilla(Vector3(xb, y, -30.0), Vector3(xe, y, -30.0))
	# Proa (estrechándose hacia el pico).
	_tramo_barandilla(Vector3(xb + 1.5, y, 16.0), Vector3(-2.0, y, 27.0))
	_tramo_barandilla(Vector3(2.0, y, 27.0), Vector3(xe - 1.5, y, 16.0))
	_tramo_barandilla(Vector3(-2.0, y, 27.0), Vector3(2.0, y, 27.0))


func _tramo_barandilla(a: Vector3, b: Vector3) -> void:
	var largo := a.distance_to(b)
	var n := maxi(2, int(round(largo / 3.0)))
	# Postes.
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_caja("Poste", Vector3(p.x, p.y + 0.55, p.z), Vector3(0.08, 1.1, 0.08), _mat_barandilla, false)
	# Dos travesaños horizontales.
	for altura in [1.05, 0.6]:
		var centro := Vector3((a.x + b.x) * 0.5, a.y + altura, (a.z + b.z) * 0.5)
		var dir := b - a
		dir.y = 0.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(absf(dir.x), 0.08), 0.07, maxf(absf(dir.z), 0.08))
		mi.mesh = bm
		mi.material_override = _mat_barandilla
		mi.position = centro
		add_child(mi)


# ============================================================ AROS SALVAVIDAS
func _construir_aros() -> void:
	for z in [-28.0, -10.0, 12.0]:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.45
		tm.outer_radius = 0.65
		mi.mesh = tm
		mi.material_override = _mat_aro
		mi.position = Vector3(-SEMI_M + 0.55, CUBIERTA + 0.75, z)
		mi.rotation.x = PI * 0.5
		add_child(mi)


# ============================================================ ESCALERA
func _construir_escalera() -> void:
	var x := -SEMI_M - 0.4      # justo por fuera del casco (babor)
	var z := 6.0
	# Dos largueros verticales.
	for dz in [-0.35, 0.35]:
		_caja("Larguero", Vector3(x, -0.2, z + dz), Vector3(0.1, 6.0, 0.1), _mat_barandilla, false)
	# Peldaños.
	var n := 12
	for i in n:
		var y := lerpf(-3.0, 2.6, float(i) / float(n - 1))
		_caja("Peldano", Vector3(x, y, z), Vector3(0.12, 0.09, 0.75), _mat_barandilla, false)
	# Cartel "[E] Subir a bordo" mirando al agua.
	var etiqueta := Label3D.new()
	etiqueta.text = "[E]  Subir a bordo"
	etiqueta.font_size = 40
	etiqueta.pixel_size = 0.01
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.position = Vector3(x - 0.6, -1.6, z)
	add_child(etiqueta)
	# Nodo de agarre para la forma acuática.
	var esc := EscaleraBarco.new()
	esc.name = "Escalera"
	esc.position = Vector3(x - 0.5, -2.6, z)
	esc.cima_local = Vector3(4.0 - x, CUBIERTA + 2.6, 0.0)   # aterriza en la cubierta
	esc.mirada_local = Vector3(1.0, 0.0, 0.0)
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


func _colision(centro: Vector3, tam: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	cs.position = centro
	_cuerpo.add_child(cs)