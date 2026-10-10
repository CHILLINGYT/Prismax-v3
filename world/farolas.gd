class_name Farolas
extends Node3D
## =============================================================================
##  FAROLAS DE LA CIUDAD (decoración + luz nocturna)
## =============================================================================
##  Coloca farolas de acera por TODO el trazado urbano real (no por una rejilla
##  inventada): lee la trama que ha calculado el generador de ciudad (paso entre
##  calles, ancho de calzada y de acera, centros de manzana) y las pone
##    * a media manzana en las aceras de todos los viales (seis por línea),
##    * en las esquinas de cada cruce,
##    * y en los parques.
##  Siempre a 0,45 m del bordillo, mirando hacia la calzada, así que no estorban
##  el paso ni el recorrido del velocista (no llevan colisión: son decoración).
##
##  El modelo es geométrico (poste, brazo y cabeza) con una placa de vidrio, y se
##  dibuja con MultiMeshInstance3D: un solo dibujado para todas las farolas.
##
##  La luz la da UNA OmniLight3D por farola con DESVANECIDO POR DISTANCIA, de
##  forma que sólo las luces cerca de la cámara cuestan; el resto ni se calculan.
##
##  El encendido va enganchado al ciclo de día y noche que ya tiene el juego: se
##  lee su fase (`_fase`) y se calcula el factor de encendido; no hay ningún
##  temporizador propio. El día las farolas están apagadas (ni luz ni emisión) y
##  a partir del minuto 13 de juego empiezan a subir hasta estar del todo
##  encendidas al minuto 15 (cuando llega la noche), siguen toda la noche y se
##  apagan al amanecer. Todo se repite cada ciclo.
## =============================================================================

const Y_ACERA := 0.0            ## cota de las aceras (donde apoyan las farolas)
const ALTO_POSTE := 4.05        ## altura del poste antes del brazo
const BRAZO := 1.25             ## longitud del brazo
const INCLINACION := -60.0      ## grados: cuánto se tumba el brazo hacia la calzada
const ALTURA_BRAZO := 0.62      ## altura del centrado del brazo
const RADIO_LUZ := 17.0         ## alcance de la luz de cada farola
const ENERGIA_MAX := 2.4        ## energía de la luz con la farola del todo encendida
const EMISION_MAX := 2.6        ## brillo del vidrio encendido

## Fases del ciclo (0 arranque, 0.25 amanecer, 0.5 mediodía, 0.75 atardecer):
## minuto 13 de juego = 780 s = 0.25 + 0.5 * 780/900 = 0.6833 (empieza a subir)
## minuto 15 = 900 s = 0.75 (atardecer: ya encendidas del todo)
## amanecer = 0.25 (se apagan en los 126 s anteriores, es decir desde 0.18).
const ENCENDIDO_INICIO := 0.68333
const ATARDECER := 0.75
const APAGADO_INICIO := 0.18
const AMANECER := 0.25

@export_group("Referencias")
## Nodo del generador de ciudad (para leer su trazado y sus parques).
@export var ciudad: Node
## Nodo del ciclo de día y noche (su `_fase` manda sobre el encendido).
@export var ciclo: Node

@export_group("Colocación")
## Separación (m) entre las farolas de una misma acera de manzana a manzana.
@export var separacion := 24.0
## Distancia (m) al bordillo: pegadas a la calzada, como en la calle.
@export var borde := 0.45
## Farolas en las esquinas de los cruces.
@export var farolas_esquina := true
## Farolas en los parques.
@export var farolas_parque := true
## Luces reales (si se apaga, quedan sólo como decoración).
@export var con_luz := true

var _metal: StandardMaterial3D
var _vidrio: StandardMaterial3D
var _luces: Array[OmniLight3D] = []
var _construido := false
var _t_espera := 0.0
var _factor := -1.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _construido:
		_t_espera += delta
		_construir()
		return
	_actualizar_luz(delta)


# =============================================================================
#  Construcción (una sola vez, cuando el generador ya tiene su trazado)
# =============================================================================
func _construir() -> void:
	if ciudad == null:
		return
	var trazado: Dictionary = ciudad.get("_trazado")
	if trazado.is_empty():
		return
	# Las manzanas, los parques y el mobiliario del generador se montan por
	# etapas en los primeros fotogramas: se espera a que estén para no dejar
	# farolas sin parque. El informe del generador marca los parques al crear la
	# manzana-parque, así que con 3 (o con 4 s de espera) ya está.
	var est: Dictionary = ciudad.get("_est")
	var parques_listos: bool = int(est.get("parques", 0)) >= 3
	if not parques_listos and _t_espera < 4.0:
		return

	_metal = _material_metal()
	_vidrio = _material_vidrio()
	var malla_metal := _malla_farola()
	var malla_vidrio := _malla_vidrio()

	var pistas: Array[Transform3D] = []
	var calzada: float = trazado["calzada"]
	var acera: float = trazado["acera"]
	var hw: float = trazado["hw"]
	var paso: float = trazado["paso"]
	var ext: Vector2 = trazado["ext"]
	var off: Vector2 = trazado["off"]
	var n_x: int = int(round(ext.x / paso))
	var n_z: int = int(round(ext.y / paso))
	# Cota donde termina el bordillo de la acera exterior.
	var lat := calzada * 0.5 + acera - borde

	# --- Farolas a media manzana, alternando de acera en cada vial -----------
	for i in n_x + 1:
		var p: float = off.x + float(i) * paso
		var lado: float = 1.0 if (i % 2 == 0) else -1.0
		var d: float = off.y + 6.0
		while d < off.y + ext.y - 6.0:
			if _lejos_de_cruce(d, off.y, paso, hw + 1.0):
				pistas.append(_fila(p + lado * lat, d, -lado, 0.0, true))
			d += separacion
	for j in n_z + 1:
		var p2: float = off.y + float(j) * paso
		var lado2: float = -1.0 if (j % 2 == 0) else 1.0
		var d2: float = off.x + 6.0
		while d2 < off.x + ext.x - 6.0:
			if _lejos_de_cruce(d2, off.x, paso, hw + 1.0):
				pistas.append(_fila(d2, p2 + lado2 * lat, -lado2, 0.0, false))
			d2 += separacion

	# --- Esquinas: una farola por cruce, en la acera que mira al cruce -------
	if farolas_esquina:
		for i in n_x + 1:
			for j in n_z + 1:
				var cx: float = off.x + float(i) * paso
				var cz: float = off.y + float(j) * paso
				var sx: float = 1.0 if ((i + j) % 2 == 0) else -1.0
				var sz: float = 1.0 if ((i * 3 + j) % 2 == 0) else -1.0
				pistas.append(_esquina(cx + sx * (calzada * 0.5 + borde + 0.4),
						cz + sz * (calzada * 0.5 + borde + 0.4), sx, sz))

	# --- Parques ------------------------------------------------------------
	if farolas_parque:
		for t: Transform3D in _parques(ciudad):
			pistas.append(t)

	if pistas.is_empty():
		return
	_construido = true
	_volcar(pistas, malla_metal, malla_vidrio)
	print("[farolas] %d farolas colocadas (%s)" % [pistas.size(),
			"con luz" if con_luz else "sólo decoración"])


## Farola de acera a lo largo de un vial. `vertical` = el vial corre en Z.
## La farola apoya en (x, z) y su brazo mira hacia la calzada.
func _fila(x: float, z: float, hacia: float, _sin_uso: float, vertical: bool) -> Transform3D:
	var giro: float
	if vertical:
		giro = PI if hacia > 0.0 else 0.0
	else:
		giro = PI * 0.5 if hacia > 0.0 else -PI * 0.5
	return Transform3D(Basis(Vector3.UP, giro), Vector3(x, Y_ACERA, z))


## Farola de esquina: en la acera del cruce, mirando al cruce (hacia dentro).
func _esquina(x: float, z: float, sx: float, sz: float) -> Transform3D:
	# El brazo apunta hacia el centro del cruce, que está en (-sx, -sz).
	var dir := Vector3(-sx, 0.0, -sz).normalized()
	var giro := atan2(-dir.z, dir.x)
	return Transform3D(Basis(Vector3.UP, giro), Vector3(x, Y_ACERA, z))


## ¿Está `d` lejos de todos los cruces del vial? (no se pone farola en el paso
## de peatones).
func _lejos_de_cruce(d: float, d0: float, paso: float, margen: float) -> bool:
	var k := int(round((d - d0) / paso))
	var cruce: float = d0 + float(k) * paso
	return absf(d - cruce) > margen


## Farolas de los parques: dos, en esquinas opuestas del césped.
func _parques(gen: Node) -> Array[Transform3D]:
	var salida: Array[Transform3D] = []
	var suelo := gen.get_node_or_null("CiudadGenerada/Suelo")
	if suelo == null:
		return salida
	for n: Node in suelo.get_children():
		if not n.name.begins_with("Parque_"):
			continue
		var cuerpo := n as StaticBody3D
		if cuerpo == null:
			continue
		var tam := Vector2.ZERO
		var y := Y_ACERA
		for c: Node in cuerpo.get_children():
			var mi := c as MeshInstance3D
			if mi != null and mi.mesh is BoxMesh:
				tam = Vector2((mi.mesh as BoxMesh).size.x, (mi.mesh as BoxMesh).size.z)
				y = cuerpo.position.y + (mi.mesh as BoxMesh).size.y * 0.5
				break
		if tam == Vector2.ZERO:
			continue
		var c2 := Vector2(cuerpo.position.x, cuerpo.position.z)
		for s: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, 1.0)]:
			var p := c2 + s * (tam * 0.5 - Vector2(2.0, 2.0))
			salida.append(Transform3D(Basis(Vector3.UP, atan2(-s.x, -s.y)), Vector3(p.x, y, p.y)))
	return salida


# =============================================================================
#  Modelo
# =============================================================================
func _material_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.18)
	m.metallic = 0.55
	m.roughness = 0.55
	return m


## Vidrio de la farola: apagado es gris claro; encendido, la emisión (que sube
## con el factor de noche) lo hace brillar.
func _material_vidrio() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.72, 0.68)
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(1.0, 0.88, 0.66)
	m.emission_energy_multiplier = 0.0
	return m


## Malla de la farola: basa + poste + brazo + cabeza, en un solo dibujado.
## Local: el brazo apunta hacia +X.
func _malla_farola() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basa := CylinderMesh.new()
	basa.top_radius = 0.12
	basa.bottom_radius = 0.17
	basa.height = 0.5
	basa.radial_segments = 10
	st.append_from(basa, 0, Transform3D(Basis(), Vector3(0.0, 0.25, 0.0)))
	var poste := CylinderMesh.new()
	poste.top_radius = 0.07
	poste.bottom_radius = 0.10
	poste.height = ALTO_POSTE - 0.5
	poste.radial_segments = 10
	st.append_from(poste, 0, Transform3D(Basis(), Vector3(0.0, 0.5 + (ALTO_POSTE - 0.5) * 0.5, 0.0)))
	var brazo := CylinderMesh.new()
	brazo.top_radius = 0.05
	brazo.bottom_radius = 0.06
	brazo.height = BRAZO
	brazo.radial_segments = 8
	var b_brazo := Basis(Vector3.BACK, deg_to_rad(INCLINACION))
	var dir := b_brazo * Vector3.UP
	st.append_from(brazo, 0, Transform3D(b_brazo, Vector3(0.0, ALTO_POSTE, 0.0) + dir * (BRAZO * 0.5)))
	var cabeza := BoxMesh.new()
	cabeza.size = Vector3(0.52, 0.20, 0.30)
	var punta := Vector3(0.0, ALTO_POSTE, 0.0) + dir * BRAZO
	st.append_from(cabeza, 0, Transform3D(b_brazo, punta + Vector3(0.06, 0.10, 0.0)))
	st.generate_tangents()
	return st.commit()


## Placa de vidrio, justo debajo de la cabeza.
func _malla_vidrio() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b_brazo := Basis(Vector3.BACK, deg_to_rad(INCLINACION))
	var dir := b_brazo * Vector3.UP
	var punta := Vector3(0.0, ALTO_POSTE, 0.0) + dir * BRAZO
	var placa := BoxMesh.new()
	placa.size = Vector3(0.44, 0.05, 0.24)
	st.append_from(placa, 0, Transform3D(b_brazo, punta + Vector3(0.06, -0.02, 0.0)))
	st.generate_tangents()
	return st.commit()


## Dibuja todas las farolas (metal + vidrio) y crea sus luces.
func _volcar(pistas: Array[Transform3D], malla_metal: ArrayMesh, malla_vidrio: ArrayMesh) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malla_metal
	mm.instance_count = pistas.size()
	for i in pistas.size():
		mm.set_instance_transform(i, pistas[i])
	var cuerpo := MultiMeshInstance3D.new()
	cuerpo.name = "FarolasMetal"
	cuerpo.multimesh = mm
	cuerpo.material_override = _metal
	cuerpo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(cuerpo)

	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = malla_vidrio
	mm2.instance_count = pistas.size()
	for i in pistas.size():
		mm2.set_instance_transform(i, pistas[i])
	var vidrio := MultiMeshInstance3D.new()
	vidrio.name = "FarolasVidrio"
	vidrio.multimesh = mm2
	vidrio.material_override = _vidrio
	vidrio.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vidrio)

	if not con_luz:
		return
	# Una luz por farola, en la cabeza. Sin sombras (no se abusa del coste) y con
	# desvanecido por distancia: fuera de ese radio la luz no se calcula.
	var b_brazo := Basis(Vector3.BACK, deg_to_rad(INCLINACION))
	var local := (Vector3(0.0, ALTO_POSTE, 0.0) + b_brazo * Vector3.UP * BRAZO) + Vector3(0.06, -0.06, 0.0)
	for t: Transform3D in pistas:
		var luz := OmniLight3D.new()
		luz.name = "Luz"
		luz.light_color = Color(1.0, 0.87, 0.66)
		luz.light_energy = 0.0
		luz.light_specular = 0.2
		luz.omni_range = RADIO_LUZ
		luz.omni_attenuation = 1.2
		luz.shadow_enabled = false
		luz.distance_fade_enabled = true
		luz.distance_fade_begin = 42.0
		luz.distance_fade_length = 30.0
		luz.visible = false
		luz.transform = Transform3D(Basis(), t * local)
		add_child(luz)
		_luces.append(luz)


# =============================================================================
#  Encendido, en fase con el ciclo de día y noche del juego
# =============================================================================
## Encendido, en fase con el ciclo de día y noche del juego: el factor sale
## entero de la fase del ciclo (ni un temporizador propio). Como la subida y la
## bajada duran minutos de juego, el cambio por fotograma es diminuto y el fundido
## se ve suave. Cuando el factor no cambia (día o noche cerrada) no se toca nada.
func _actualizar_luz(_delta: float) -> void:
	var objetivo := factor_noche(_fase_ciclo())
	if not is_equal_approx(objetivo, _factor):
		_factor = objetivo
		_aplicar(_factor)


func _aplicar(factor: float) -> void:
	if _vidrio != null:
		_vidrio.emission_energy_multiplier = EMISION_MAX * factor
	var encendidas := factor > 0.001
	for luz: OmniLight3D in _luces:
		luz.visible = encendidas
		luz.light_energy = ENERGIA_MAX * factor


## Factor de encendido (0..1) para una fase del ciclo. Sin temporizadores: sale
## entero de la fase que ya avanza el ciclo de día y noche del juego.
static func factor_noche(f: float) -> float:
	if f >= ENCENDIDO_INICIO and f < ATARDECER:
		# Del minuto 13 al 15 de juego: suben poco a poco hasta el atardecer.
		return smoothstep(ENCENDIDO_INICIO, ATARDECER, f)
	if f >= ATARDECER and f < 1.0:
		return 1.0                       # toda la noche encendidas
	if f < AMANECER:
		# Pasada la medianoche: se apagan al amanecer, poco a poco.
		if f < APAGADO_INICIO:
			return 1.0
		return 1.0 - smoothstep(APAGADO_INICIO, AMANECER, f)
	return 0.0                           # de día, apagadas


func _fase_ciclo() -> float:
	if ciclo == null:
		return -1.0
	return float(ciclo.get("_fase"))


## Resumen del estado, para las comprobaciones en el juego.
func resumen() -> String:
	return "farolas=%d farolas_luz=%d factor=%.2f encendidas=%s fase=%.3f" % [
		_luces.size(), _luces.size(), _factor,
		str(_factor > 0.001), _fase_ciclo()]