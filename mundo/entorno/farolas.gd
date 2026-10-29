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
##
##  ORIENTACIÓN Y SITIO DE LAS FAROLAS DE ACERA (corregido):
##   · El brazo apunta SIEMPRE hacia la calzada (hacia el eje del vial): el poste va
##     en la acera y la cabeza cuelga sobre el bordillo, como en la calle de verdad.
##     Antes el brazo salía girado 180° y se metía en la fachada, atravesando el muro.
##   · El poste se planta a `borde` (0,45 m) del BORDILLO, nunca arrimado a la fachada
##     (antes quedaba a 0,45 m del muro y se incrustaba en los portales y en las
##     molduras de la fachada).
##   · Antes de plantar una farola se mira el mobiliario REAL que el generador ya ha
##     colocado en esa acera (árboles, canteros, bancos, palmeras): si el sitio está
##     ocupado, la farola se corre a lo largo del vial y, si no cabe en ninguno de los
##     sitios válidos, se descarta. Así ninguna queda dentro de un árbol ni de un cantero.
##   · Las farolas de los PARQUES/PLAZAS no se tocan: se colocan como siempre, en las
##     esquinas del césped, con su posición, su giro y su luz (ver `_parques`).
##
##  Las farolas de acera llevan colisión (cilindro del poste, capa 1): el jugador no
##  las atraviesa. Los peatones no usan física (van por la red peatonal), así que se
##  les avisa al director como obstáculos en planta y las RODEAN igual que un árbol.
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
## Radio del cilindro de colisión del poste (m): el mismo bulto que la base visible.
const RADIO_COLISION := 0.22
## Altura del cilindro de colisión (m): el poste entero.
const ALTO_COLISION := 4.2
## Holgura mínima (m) entre el poste y un árbol, cantero, banco o palmera al elegir el sitio.
const AIRE_MOBILIARIO := 0.8

## Fases del ciclo (0 arranque, 0.25 amanecer, 0.5 mediodía, 0.75 atardecer).
## Son sólo el RESPALDO por si no hubiera ciclo en la escena: lo normal es que los
## hitos se lean del propio ciclo (`CicloDiaNoche.fases_farolas()`), así las farolas
## y las ventanas nocturnas van SIEMPRE en fase con el cielo, sin horario propio.
## Con el horario actual (7 min de día pleno, 1,5 min de anochecer, 7 min de noche
## y 1,5 min de amanecer): el anochecer va de 0.675 a 0.75 y el amanecer de 0.25 a
## 0.325, que es justo cuando las farolas suben y bajan.
const ENCENDIDO_INICIO := 0.675
const ATARDECER := 0.75
const APAGADO_INICIO := 0.25
const AMANECER := 0.325

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
var _n_acera := 0                ## farolas de acera colocadas (media manzana)
var _n_esquina := 0              ## farolas de esquina colocadas
var _n_parque := 0               ## farolas de parque/plaza (NO se tocan)
var _movidas := 0                ## farolas de acera corridas de sitio por el mobiliario
var _descartadas := 0            ## farolas descartadas por no caber sin chocar
var _pendiente_avisar: Array = []   ## círculos de farola que aún no se han pasado al director
var _t_aviso := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _construido:
		_t_espera += delta
		_construir()
		return
	_actualizar_luz(delta)
	# El director de peatones se crea en la última etapa del generador: si las farolas se
	# construyeron antes, se le pasan los obstáculos en cuanto exista (nunca se pierden).
	if not _pendiente_avisar.is_empty():
		_t_aviso += delta
		if _t_aviso >= 0.5:
			_t_aviso = 0.0
			_avisar_peatones_pendientes()


# =============================================================================
#  Construcción (una sola vez, cuando el generador ya tiene su trazado)
# =============================================================================
func _construir() -> void:
	if ciudad == null:
		return
	var trazado: Dictionary = ciudad.get("_trazado")
	if trazado.is_empty():
		return
	# Se espera a que el generador haya cerrado la ciudad (mobiliario, vegetación, parques
	# y porches ya colocados y apuntados como obstáculos): una farola de acera se planta a
	# 0,45 m del bordillo y hay que saber qué árboles, canteros y bancos hay en esa acera
	# para no meterla dentro de ninguno. Quien lo marca es el propio generador
	# (`_est["ciudad_lista"]`); con 8 s de espera se construye igual, por si acaso.
	var est: Dictionary = ciudad.get("_est")
	if int(est.get("ciudad_lista", 0)) != 1 and _t_espera < 8.0:
		return

	_metal = _material_metal()
	_vidrio = _material_vidrio()
	var malla_metal := _malla_farola()
	var malla_vidrio := _malla_vidrio()
	# Mobiliario que el generador YA ha colocado en las aceras (árboles, canteros, bancos,
	# palmeras y sombrillas) como círculos en planta: la farola no se pone encima de nada.
	var obstaculos: Array = ciudad.get("_obstaculos_peatones")

	var pistas: Array[Transform3D] = []
	var calzada: float = trazado["calzada"]
	var hw: float = trazado["hw"]
	var paso: float = trazado["paso"]
	var ext: Vector2 = trazado["ext"]
	var off: Vector2 = trazado["off"]
	var n_x: int = int(round(ext.x / paso))
	var n_z: int = int(round(ext.y / paso))
	# Distancia del poste al eje del vial: pegado al bordillo (0,45 m hacia la acera).
	# Antes se usaba `calzada/2 + acera - borde`, que dejaba el poste a 0,45 m de la
	# FACHADA: ahí se incrustaba en los porches y en las molduras del muro.
	var lat := calzada * 0.5 + borde

	# --- Farolas a media manzana, alternando de acera en cada vial -----------
	for i in n_x + 1:
		var p: float = off.x + float(i) * paso
		var lado: float = 1.0 if (i % 2 == 0) else -1.0
		var d: float = off.y + 6.0
		while d < off.y + ext.y - 6.0:
			if _lejos_de_cruce(d, off.y, paso, hw + 1.0):
				var sitio := _sitio_libre(p + lado * lat, d, true, off.y, off.y + ext.y, paso,
						obstaculos)
				if sitio != Vector2.INF:
					pistas.append(_fila(sitio.x, sitio.y, true, lado))
					_n_acera += 1
					if absf(sitio.y - d) > 0.01:
						_movidas += 1
				else:
					_descartadas += 1
			d += separacion
	for j in n_z + 1:
		var p2: float = off.y + float(j) * paso
		var lado2: float = -1.0 if (j % 2 == 0) else 1.0
		var d2: float = off.x + 6.0
		while d2 < off.x + ext.x - 6.0:
			if _lejos_de_cruce(d2, off.x, paso, hw + 1.0):
				var sitio2 := _sitio_libre(d2, p2 + lado2 * lat, false, off.x, off.x + ext.x,
						paso, obstaculos)
				if sitio2 != Vector2.INF:
					pistas.append(_fila(sitio2.x, sitio2.y, false, lado2))
					_n_acera += 1
					if absf(sitio2.x - d2) > 0.01:
						_movidas += 1
				else:
					_descartadas += 1
			d2 += separacion

	# --- Esquinas: una farola por cruce, en la acera que mira al cruce -------
	if farolas_esquina:
		for i in n_x + 1:
			for j in n_z + 1:
				var cx: float = off.x + float(i) * paso
				var cz: float = off.y + float(j) * paso
				var sx: float = 1.0 if ((i + j) % 2 == 0) else -1.0
				var sz: float = 1.0 if ((i * 3 + j) % 2 == 0) else -1.0
				var ex := cx + sx * (calzada * 0.5 + borde + 0.4)
				var ez := cz + sz * (calzada * 0.5 + borde + 0.4)
				if _libre(ex, ez, obstaculos, 0.45):
					pistas.append(_esquina(ex, ez, sx, sz))
					_n_esquina += 1
				else:
					_descartadas += 1

	# --- Parques y plazas: NO se tocan (posición, giro, modelo y luz de siempre) ---
	if farolas_parque:
		for t: Transform3D in _parques(ciudad):
			pistas.append(t)
			_n_parque += 1

	if pistas.is_empty():
		return
	_construido = true
	_volcar(pistas, malla_metal, malla_vidrio)
	_colisiones(pistas)
	_pendiente_avisar.clear()
	for t2: Transform3D in pistas:
		_pendiente_avisar.append({"x": t2.origin.x, "z": t2.origin.z, "r": RADIO_COLISION + 0.08})
	_avisar_peatones_pendientes()
	print("[farolas] %d farolas colocadas (%s) | acera %d (movidas %d, descartadas %d) · esquina %d · parque/plaza %d sin tocar" % [
			pistas.size(), "con luz" if con_luz else "sólo decoración",
			_n_acera, _movidas, _descartadas, _n_esquina, _n_parque])


## Sitio libre para una farola de acera: se prueba el punto pedido y, si el mobiliario lo
## ocupa, se corre a lo largo del vial (±3 m, ±6 m) sin acercarse a un cruce. Devuelve
## Vector2.INF si no cabe en ninguno (la farola se descarta: mejor sin farola que dentro
## de un árbol o de un cantero).
func _sitio_libre(x: float, z: float, vertical: bool, d0: float, d1: float, paso: float,
		obstaculos: Array) -> Vector2:
	for desvio: float in [0.0, 3.0, -3.0, 6.0, -6.0]:
		var px := x
		var pz := z
		if vertical:
			pz = clampf(z + desvio, d0 + 2.0, d1 - 2.0)
			if not _lejos_de_cruce(pz, d0, paso, 10.0):
				continue
		else:
			px = clampf(x + desvio, d0 + 2.0, d1 - 2.0)
			if not _lejos_de_cruce(px, d0, paso, 10.0):
				continue
		if _libre(px, pz, obstaculos, AIRE_MOBILIARIO):
			return Vector2(px, pz)
	return Vector2.INF


## ¿El punto (x, z) está libre de mobiliario sólido con el aire pedido?
func _libre(x: float, z: float, obstaculos: Array, aire: float) -> bool:
	for o: Dictionary in obstaculos:
		var dx := float(o.get("x", 0.0)) - x
		var dz := float(o.get("z", 0.0)) - z
		var r := float(o.get("r", 0.5)) + aire
		if dx * dx + dz * dz < r * r:
			return false
	return true


## Farola de acera en (x, z), con el brazo mirando a la CALZADA (hacia el eje del vial).
## `vertical` = el vial corre en Z; `lado` = lado del eje del vial donde está la farola.
func _fila(x: float, z: float, vertical: bool, lado: float) -> Transform3D:
	var dir := Vector3(-lado, 0.0, 0.0) if vertical else Vector3(0.0, 0.0, -lado)
	var giro := atan2(-dir.z, dir.x)
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


## Colisión del poste: un cilindro por farola (capa 1, la misma que el terreno y los
## edificios). Es lo que impide que el JUGADOR atraviese un poste. Los peatones no usan
## física (van por la red peatonal): ellos las rodean con los avisos del director.
func _colisiones(pistas: Array[Transform3D]) -> void:
	if pistas.is_empty():
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "FarolasColision"
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	for t: Transform3D in pistas:
		var forma := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = RADIO_COLISION
		c.height = ALTO_COLISION
		forma.shape = c
		forma.position = t.origin + Vector3(0.0, ALTO_COLISION * 0.5, 0.0)
		cuerpo.add_child(forma)
	add_child(cuerpo)


## Pasa al director de peatones los círculos en planta de las farolas (obstáculos que hay
## que rodear). Si el director todavía no existe, se guardan y se reintenta en `_process`.
func _avisar_peatones_pendientes() -> void:
	if _pendiente_avisar.is_empty():
		return
	if ciudad == null:
		return
	var dir: Node = ciudad.get("director_peatones")
	if dir == null or not dir.has_method("agregar_obstaculos"):
		return
	dir.call("agregar_obstaculos", _pendiente_avisar)
	_pendiente_avisar = []


# =============================================================================
#  Encendido, en fase con el ciclo de día y noche del juego
# =============================================================================
## Encendido, en fase con el ciclo de día y noche del juego: el factor sale
## entero de la fase del ciclo (ni un temporizador propio). Como la subida y la
## bajada duran minutos de juego, el cambio por fotograma es diminuto y el fundido
## se ve suave. Cuando el factor no cambia (día o noche cerrada) no se toca nada.
func _actualizar_luz(_delta: float) -> void:
	var objetivo := factor_para(ciclo, _fase_ciclo())
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


## Factor de encendido (0..1) para una fase del ciclo, SIN temporizador propio: sale
## entero de la fase que ya avanza el ciclo de día y noche del juego.
## Si se le pasa el nodo del ciclo, usa SUS hitos reales (fases_farolas()), de modo
## que cualquier cambio de horario del cielo arrastra al alumbrado sin tocar nada.
static func factor_para(ciclo_nodo: Node, f: float) -> float:
	if f < 0.0:
		return 0.0
	if ciclo_nodo != null and ciclo_nodo.has_method("fases_farolas"):
		var v: Vector4 = ciclo_nodo.call("fases_farolas")
		return factor_entre(f, v.x, v.y, v.z, v.w)
	return factor_noche(f)


## Factor genérico de encendido: sube de 0 a 1 entre `ini_enc` y `pleno`, se queda
## encendido toda la noche, baja de 1 a 0 entre `ini_apag` y `apagado`, y queda
## apagado el resto del día.
static func factor_entre(f: float, ini_enc: float, pleno: float, ini_apag: float,
		apagado: float) -> float:
	if f >= ini_enc and f < pleno:
		return smoothstep(ini_enc, pleno, f)
	if f >= pleno or f < ini_apag:
		return 1.0                       # toda la noche encendidas
	if f < apagado:
		return 1.0 - smoothstep(ini_apag, apagado, f)
	return 0.0                           # de día, apagadas


## Respaldo con los hitos fijos de este archivo (se usa sólo si no hay ciclo).
static func factor_noche(f: float) -> float:
	return factor_entre(f, ENCENDIDO_INICIO, ATARDECER, APAGADO_INICIO, AMANECER)


func _fase_ciclo() -> float:
	if ciclo == null:
		return -1.0
	return float(ciclo.get("_fase"))


## Resumen del estado, para las comprobaciones en el juego.
func resumen() -> String:
	return "farolas=%d farolas_luz=%d factor=%.2f encendidas=%s fase=%.3f" % [
		_luces.size(), _luces.size(), _factor,
		str(_factor > 0.001), _fase_ciclo()]
