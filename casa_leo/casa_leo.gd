class_name CasaLeo
extends Node3D
## =============================================================================
##  INTERIOR DE LA CASA DE LEO
## =============================================================================
##  Escena propia (res://casa_leo/casa_leo.tscn) con el modelo de interior
##  importado, sus colisiones reales, el cielo y la ciudad de verdad fuera de las
##  ventanas, y el JUGADOR DE VERDAD dentro (la misma escena de Leo, con sus
##  transformaciones, su HUD y sus controles).
##
##  Todo lo que depende del modelo se saca del MODELO MEDIDO, no de números
##  puestos a mano:
##   · ESCALA: el modelo se agranda de forma UNIFORME (1,2) y se centra solo: el
##     suelo queda a y = 0 y el techo pasa de 2,51 m a ~3,01 m. Nada se deforma
##     (la escala es la misma en los tres ejes) y el personaje no se toca;
##   · COLISIONES: una malla de colisión por cada malla del modelo
##     (`create_trimesh_collision()`): las paredes, las puertas y los MUEBLES
##     frenan a Leo exactamente donde los ves. Los vanos (puertas y ventanas) del
##     modelo están ABIERTOS y se siguen pasando a pie. Los tres vanos EXTERIORES
##     llevan un cristal invisible: se ve la ciudad, pero no se sale por la ventana;
##   · a los puntos del modelo (el vano del dormitorio, el pasillo) los convierte
##     con `_de_modelo()`: si algún día cambia la escala, todo sigue encajando.
##
##  El interior vive A LA MISMA HORA que la calle: al entrar hereda la fase del
##  `CicloDiaNoche` de la ciudad y al salir se la devuelve. No hay un segundo
##  reloj: es la única cifra que viaja (ver `EstadoCasaLeo`).
##
##  Los puntos del modelo (medidos con res://_tests/sonda_casa.gd sobre
##  res://modelos 3d casa leo/appartement.glb):
##   · la caja mide 7,05 × 2,51 × 10,66 m y el suelo está a y = -0,01;
##   · el PASILLO va de x = -4,96 a x = -3,91 (1,05 m de ancho), en z de -5,1 a 0,3;
##   · el VANO del dormitorio (el de la primera captura: la puerta por la que se ve
##     la cama) está en la pared este del pasillo, en x ≈ -3,76 | z ≈ -3,00.

## Escala UNIFORME del modelo (el techo pasa de 2,51 m a ~3,01 m).
const ESCALA := 1.2
## --- Tarea 2 (cámara) -------------------------------------------------------
## El brazo de la cámara venía SIN volumen (solo un rayo de un píxel) y con el
## margen por defecto (0,01 m): la cámara quedaba pegada a la pared y su plano
## cercano la atravesaba, así que se veía el interior desde fuera. Con volumen y
## margen se acerca al personaje en cuanto hay pared, marco, mueble o ventana de
## por medio. La máscara es la capa del mundo (1), la de las paredes.
const CAMARA_RADIO := 0.16      ## m: volumen de la cámara
const CAMARA_MARGEN := 0.22     ## m: separación mínima a cualquier superficie
## --- Tarea 3 (paso por las puertas) -----------------------------------------
## Los vanos reales del piso miden ~0,85 m y la cápsula del jugador (radio 0,40 =
## 0,80 m de ancho) los pasaba rozando: el dormitorio, el cuarto del norte y casi
## todo el salón quedaban sin acceso. DENTRO DE LA CASA se le da a Leo una cápsula
## más estrecha (0,50 m de ancho, como una persona) y al salir se le devuelve la
## suya. No se toca el modelo, ni las animaciones, ni el personaje: solo su radio
## de choque mientras está en casa (aquí no hay combate ni enemigos).
const RADIO_EN_CASA := 0.25
## Grosor (m) del suelo y del techo de la caja de seguridad.
const GROSOR := 0.4
const LUZ_CALIDA := Color(1.0, 0.94, 0.86)

# --- Puntos REALES del modelo (coordenadas del GLB) --------------------------
## Tarea 1: Puerta principal de entrada/salida del apartamento (la puerta cerrada
## en la pared derecha/este del pasillo, junto a la entrada del salón, que da al
## exterior del piso: x = -3,805, z ∈ [-0,159, +0,601], centro z = +0,221).
const VANO := Vector3(-3.805, 0.0, 0.221)
## Vano interior del dormitorio principal (abierto y transitable a pie).
const VANO_DORMITORIO := Vector3(-3.76, 0.0, -2.91)
## Dónde aparece Leo: en el pasillo, JUNTO a la puerta principal (la única puerta
## cerrada del modelo, la de la foto), pero un paso hacia el salón y MIRANDO HACIA
## LA VIVIENDA, no de narices contra la hoja.
## Por qué así (medido, no supuesto):
##   · `_tests/sonda_casa_lado_puerta.gd`: al OTRO lado del plano de la puerta
##     (x > -0,69 de la escena) hay suelo libre, pero `_tests/sonda_casa_paso.gd`
##     demuestra que es un BOLSILLO CERRADO (5 celdas alcanzables, cercado por
##     Object_10 al norte y Object_12 al sur): aparecer ahí dejaba a Leo encerrado;
##   · mirando a la puerta, la cámara se iba contra la pared del baño (el pasillo
##     mide 1,05 m): mirando al salón, detrás queda el pasillo libre y la cámara
##     respira. El cartel de salida sigue a mano (0,68 m del Area3D, radio 1,1 m).
const PASILLO := Vector3(-4.441, 0.0, -0.111)
## Hacia dónde mira al aparecer: hacia el salón (sur del pasillo), con la puerta
## a su espalda, que es como se entra de verdad en una casa.
const MIRA := Vector3(-4.441, 0.0, 1.722)
## La salida: EN LA PUERTA PRINCIPAL, un palmo hacia el pasillo.
## Al estar en el plano de la puerta, el radio y el lado (`normal`) cubren justo el
## pasillo de delante: el aviso se ofrece ahí y sólo ahí.
const SALIDA := Vector3(-3.98, 0.0, 0.221)

# --- Vanos EXTERIORES del modelo (sonda): cristal invisible -------------------
## [centro en el modelo, tamaño en metros del modelo]. Son los tres huecos que dan
## a la calle; el resto de la fachada del modelo es macizo y ya frena solo.
const VANOS := [
	[Vector3(-1.36, 1.20, 4.28), Vector3(3.95, 2.40, 0.20)],   # ventanal del salón (sur)
	[Vector3(0.26, 1.20, -1.35), Vector3(0.24, 2.40, 0.85)],   # ventana del dormitorio (este)
	[Vector3(-6.72, 1.20, -0.45), Vector3(0.24, 2.40, 1.30)],  # hueco oeste
]

# --- Ciudad que se ve por las ventanas ---------------------------------------
## Semilla fija: la misma ciudad siempre (nada de mapas distintos en cada carga).
const VISTA_SEMILLA := 20260214
const VISTA_SUELO_Y := -6.5          ## 2 pisos por debajo de la casa
const VISTA_ANILLO := Vector2(16.0, 80.0)
## Aire (m) que se le deja a la FACHADA: ningún edificio de la vista puede quedar
## a menos de (radio de la casa + su propia media diagonal + este margen).
## CAUSA RAÍZ del "muro azul" que tapaba las ventanas del salón/comedor: el anillo
## empezaba a 16 m del CENTRO y los edificios miden hasta 22 × 22 m, así que uno
## de 22 m de lado colocado a 16 m metía su esquina a 5 m del centro, o sea DENTRO
## de la casa (la caja mide 8,46 × 12,79 m). No era una pared ni un viewport: era
## un edificio del paisaje atravesando el salón.
const VISTA_AIRE_FACHADA := 12.0
const VISTA_EDIFICIOS := 40
const VISTA_LADO := Vector2(9.0, 22.0)
const VISTA_ALTO := Vector2(7.0, 30.0)
const VISTA_MATERIALES := 3
const VISTA_ALTO_VENTANA := 1.9      ## separación vertical entre ventanas
const VISTA_ANCHO_VENTANA := 1.7     ## separación horizontal entre ventanas
const VISTA_LUZ_VENTANA := Color(1.0, 0.85, 0.55)

var _jugador: CharacterBody3D
var _caja := AABB()                  ## caja REAL de la malla, ya centrada (unidades de la escena)
var _centro := Vector3.ZERO          ## centro del modelo SIN escalar (coordenadas del GLB)
var _listo := false
var _ciclo: CicloDiaNoche
var _sol: DirectionalLight3D
var _luz: DirectionalLight3D
var _lampara: OmniLight3D
var _mat_ventana: StandardMaterial3D
var _mat_edificios: Array[StandardMaterial3D] = []
var _noche01 := 0.0
var _cuerpos_malla := 0
var _cristales := 0
var _cristales_datos: Array = []
var _vista_posiciones: Array[Vector3] = []
var _vista_empujados := 0                    ## edificios de la vista corridos fuera de la casa
var _vista_min_dist := 0.0                   ## m del centro a la cara más cercana de un edificio
var _edificios := 0
var _ventanas := 0
var _radio_original := -1.0                  ## radio de cápsula del jugador fuera de casa
var _capsula_jugador: CapsuleShape3D
var _caras_dobles := 0                       ## materiales puestos a doble cara
var _hojas_abiertas := 0                     ## hojas interiores abiertas por pivote/rotación


func _ready() -> void:
	_modelo_a_escala()
	_hojas_abiertas = _abrir_puertas_interiores()
	_caja = _medir_modelo()
	_colisiones()
	_cristales = _cristales_de_vanos()
	_colisiones_malla()
	_vista()
	_entorno()
	_luces()
	_jugador = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_hora_del_ciclo()
	_marcadores()
	_colocar_jugador()
	_paso_del_jugador()
	_camara()
	_caras_dobles = _modelo_completo()
	set_process(true)
	_listo = true
	print("[casa] interior listo | modelo %.2f × %.2f × %.2f m (escala ×%.2f, techo a %.2f m) | colisiones de malla: %d | hojas abiertas: %d | cristales: %d | ciudad: %d edificios y %d ventanas" % [
			_caja.size.x, _caja.size.y, _caja.size.z, ESCALA,
			_caja.position.y + _caja.size.y, _cuerpos_malla, _hojas_abiertas, _cristales,
			_edificios, _ventanas])


## Al abandonar el interior se le devuelve la HORA a la calle: la fase vivida
## dentro viaja con Leo (el ciclo de la ciudad la recoge al volver).
func _exit_tree() -> void:
	if _ciclo != null:
		EstadoCasaLeo.guardar_fase(_ciclo.fase_actual())
	# El radio de choque de Leo se devuelve al suyo: la casa no deja secuelas.
	if _capsula_jugador != null and _radio_original >= 0.0:
		_capsula_jugador.radius = _radio_original


## El interior arranca a la hora que tenía la calle al entrar (una sola cifra: no
## se crea ningún reloj nuevo). Sin fase guardada, el ciclo arranca como siempre.
func _hora_del_ciclo() -> void:
	_ciclo = get_node_or_null("CicloDiaNoche") as CicloDiaNoche
	if _ciclo == null or not _ciclo.has_method("poner_fase"):
		return
	var f := EstadoCasaLeo.fase_guardada()
	if f < 0.0:
		return
	_ciclo.poner_fase(f)
	print("[casa] interior a la hora de la calle (fase %.3f)" % f)


## Escala UNIFORME y centrado del modelo. Se mide en el espacio del GLB (con la
## transformación del nodo puesta a identidad) y de ahí salen el centro y la
## colocación: el suelo del piso queda a y = 0 y la casa centrada en el origen.
func _modelo_a_escala() -> void:
	var modelo := get_node_or_null("Modelo") as Node3D
	if modelo == null:
		push_warning("CasaLeo: falta el nodo Modelo.")
		return
	modelo.transform = Transform3D.IDENTITY
	var caja := _caja_de_malla(modelo, Transform3D.IDENTITY)
	if caja.size.length() < 0.001:
		return
	_centro = Vector3(
			(caja.position.x + caja.end.x) * 0.5,
			caja.position.y,
			(caja.position.z + caja.end.z) * 0.5)
	modelo.scale = Vector3.ONE * ESCALA
	modelo.position = -_centro * ESCALA


## Convierte un punto del MODELO (coordenadas del GLB) a esta escena.
func _de_modelo(p: Vector3) -> Vector3:
	return (p - _centro) * ESCALA


## Coloca los marcadores y la salida en los puntos REALES del modelo (los del
## sondeo): el punto de entrada con su mirada, y la salida justo delante del vano.
## Así no hay coordenadas inventadas en la escena: si cambia la escala o el modelo,
## los tres puntos se recalculan solos.
func _marcadores() -> void:
	var punto := get_node_or_null("PuntoEntrada") as Node3D
	if punto != null:
		punto.position = _de_modelo(PASILLO)
	var destino := get_node_or_null("MiraEntrada") as Node3D
	if destino != null:
		destino.position = _de_modelo(MIRA)
	var nodo_salida := get_node_or_null("SalidaInterior") as SalidaInterior
	if nodo_salida == null:
		return
	nodo_salida.position = _de_modelo(SALIDA)
	# Hacia dónde queda el pasillo (el lado desde el que se sale): la salida sólo
	# se ofrece de ESE lado, nunca desde el dormitorio ni desde el otro lado del muro.
	nodo_salida.normal = (_de_modelo(SALIDA) - _de_modelo(VANO)).normalized()


## Tarea 2: la cámara del jugador, con volumen y margen, para que NO atraviese
## las paredes, los marcos, los muebles ni los cristales de las ventanas. El
## comportamiento es el de siempre (misma distancia máxima, mismo apuntado): lo
## único que cambia es que se acerca al personaje cuando hay algo en medio.
func _camara() -> void:
	if _jugador == null:
		return
	var pivote := _jugador.get_node_or_null("PivoteCamara")
	var brazo := pivote.get_node_or_null("Brazo") as SpringArm3D if pivote != null else null
	if brazo == null:
		push_warning("CasaLeo: no se encontró el brazo de la cámara del jugador.")
		return
	# TODOS los brazos de cámara del jugador (el normal y los de las formas
	# acuática y de vuelo): ninguno puede asomarse fuera de las paredes de casa.
	var brazos := 0
	for nodo in _jugador.find_children("*", "SpringArm3D", true, false):
		var b := nodo as SpringArm3D
		if b == null:
			continue
		var esfera := SphereShape3D.new()
		esfera.radius = CAMARA_RADIO
		b.shape = esfera
		b.margin = maxf(b.margin, CAMARA_MARGEN)
		b.collision_mask = b.collision_mask | 1
		b.add_excluded_object(_jugador.get_rid())
		var dueno := b.get_parent()
		while dueno != null and dueno != _jugador:
			if dueno is CollisionObject3D:
				b.add_excluded_object((dueno as CollisionObject3D).get_rid())
			dueno = dueno.get_parent()
		brazos += 1
	print("[casa] %d brazos de cámara con volumen dentro de casa" % brazos)
	if pivote != null and pivote.has_method("forzar_ajuste_inmediato"):
		pivote.call("forzar_ajuste_inmediato")
	print("[casa] cámara con volumen (r %.2f m) y margen %.2f m: no atraviesa paredes ni ventanas" % [
			CAMARA_RADIO, CAMARA_MARGEN])


## Tarea 3: abre las puertas interiores semicerradas del modelo (los dos baños
## del pasillo en Object_4) separando sus hojas como nodos `MeshInstance3D` con
## pivote en sus bisagras reales y girándolas a 90° abiertas, conservando intactos
## los marcos, las paredes y la puerta exterior cerrada del pasillo.
func _abrir_puertas_interiores() -> int:
	var modelo := get_node_or_null("Modelo") as Node3D
	if modelo == null:
		return 0
	var mi4 := modelo.find_child("Object_4", true, false) as MeshInstance3D
	if mi4 == null or mi4.mesh == null or mi4.mesh.get_surface_count() == 0:
		return 0
	var t4 := _transform_hasta(mi4, modelo)
	var arr := mi4.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		return 0
	var mat4 := mi4.get_active_material(0)
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx_pared := PackedInt32Array()
	var idx_b2 := PackedInt32Array()
	var idx_b3 := PackedInt32Array()
	var n := int(idx.size() / 3.0)
	for k in range(n):
		var i0 := idx[k * 3]
		var i1 := idx[k * 3 + 1]
		var i2 := idx[k * 3 + 2]
		var v0: Vector3 = t4 * verts[i0]
		var v1: Vector3 = t4 * verts[i1]
		var v2: Vector3 = t4 * verts[i2]
		var tmin := v0.min(v1.min(v2))
		var tmax := v0.max(v1.max(v2))
		if _es_hoja_bano2(tmin, tmax):
			idx_b2.append(i0); idx_b2.append(i1); idx_b2.append(i2)
		elif _es_hoja_bano3(tmin, tmax):
			idx_b3.append(i0); idx_b3.append(i1); idx_b3.append(i2)
		else:
			idx_pared.append(i0); idx_pared.append(i1); idx_pared.append(i2)
	mi4.mesh = _construir_malla_superficie(verts, norms, uvs, idx_pared, mat4)
	var abiertas := 0
	var padre := mi4.get_parent() as Node3D
	if padre != null:
		if not idx_b2.is_empty():
			_crear_nodo_hoja_abierta(padre, "HojaPuertaBano2", verts, norms, uvs, idx_b2, mat4,
					Vector3(-5.02, 0.0, -1.880) - t4.origin, deg_to_rad(120.0))
			abiertas += 1
		if not idx_b3.is_empty():
			_crear_nodo_hoja_abierta(padre, "HojaPuertaBano3", verts, norms, uvs, idx_b3, mat4,
					Vector3(-5.02, 0.0, -0.022) - t4.origin, deg_to_rad(120.0))
			abiertas += 1
	print("[casa] puertas interiores abiertas por pivote/rotación: %d hojas (marcos y paredes intactos)" % abiertas)
	return abiertas


func _construir_malla_superficie(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array, mat: Material) -> ArrayMesh:
	var nuevo := []
	nuevo.resize(Mesh.ARRAY_MAX)
	nuevo[Mesh.ARRAY_VERTEX] = verts
	if not norms.is_empty():
		nuevo[Mesh.ARRAY_NORMAL] = norms
	if not uvs.is_empty():
		nuevo[Mesh.ARRAY_TEX_UV] = uvs
	nuevo[Mesh.ARRAY_INDEX] = indices
	var malla := ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nuevo)
	if mat != null:
		malla.surface_set_material(0, mat)
	return malla


func _crear_nodo_hoja_abierta(padre: Node3D, nombre: String, verts_orig: PackedVector3Array,
		norms: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		mat: Material, pivote_local: Vector3, giro_y: float) -> void:
	var mapa_v := {}
	var verts_compactos := PackedVector3Array()
	var norms_compactos := PackedVector3Array()
	var uvs_compactos := PackedVector2Array()
	var idx_compactos := PackedInt32Array()
	for idx_v in indices:
		if not mapa_v.has(idx_v):
			var nuevo_i := verts_compactos.size()
			mapa_v[idx_v] = nuevo_i
			verts_compactos.append(verts_orig[idx_v] - pivote_local)
			if not norms.is_empty():
				norms_compactos.append(norms[idx_v])
			if not uvs.is_empty():
				uvs_compactos.append(uvs[idx_v])
		idx_compactos.append(int(mapa_v[idx_v]))
	var nodo := MeshInstance3D.new()
	nodo.name = nombre
	nodo.mesh = _construir_malla_superficie(verts_compactos, norms_compactos, uvs_compactos, idx_compactos, mat)
	nodo.position = pivote_local
	nodo.rotation.y = giro_y
	padre.add_child(nodo)


func _es_hoja_bano2(tmin: Vector3, tmax: Vector3) -> bool:
	if tmax.z > -1.875 or tmin.z < -2.560:
		return false
	if tmin.x < -5.009 or tmax.x > -4.590:
		return false
	if tmax.x <= -4.980 and tmin.z >= -1.891:
		return false
	return true


func _es_hoja_bano3(tmin: Vector3, tmax: Vector3) -> bool:
	if tmax.z > -0.015 or tmin.z < -0.700:
		return false
	if tmin.x < -5.009 or tmax.x > -4.590:
		return false
	if tmax.x <= -4.980 and tmin.z >= -0.033:
		return false
	return true


func _transform_hasta(nodo: Node, tope: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := nodo
	while cur != null and cur != tope:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Tarea 3: el radio de choque de Leo DENTRO de la casa (ver RADIO_EN_CASA). Al
## salir se devuelve el suyo, así que la calle no cambia en nada.
func _paso_del_jugador() -> void:
	if _jugador == null:
		return
	var colision := _jugador.get_node_or_null("Colision") as CollisionShape3D
	if colision == null or not (colision.shape is CapsuleShape3D):
		return
	var caps := colision.shape as CapsuleShape3D
	_radio_original = caps.radius
	_capsula_jugador = caps
	caps.radius = RADIO_EN_CASA
	print("[casa] paso por las puertas: radio de Leo %.2f m dentro de casa (fuera %.2f m, se devuelve al salir)" % [
			caps.radius, _radio_original])


## Tarea 4: la casa entera también vista desde fuera. El modelo importado tiene
## las caras de un solo lado: desde fuera (cuando la cámara se salía) las paredes
## se veían transparentes y parecía que faltaban trozos de la vivienda. NO se borra
## ni se oculta nada: se duplican los materiales EN ESTA INSTANCIA y se ponen a
## doble cara, así la casa se ve maciza desde cualquier ángulo. El recurso
## importado (.glb) no se toca.
func _modelo_completo() -> int:
	var modelo := get_node_or_null("Modelo")
	if modelo == null:
		return 0
	var caras := 0
	for mi in _mallas_bajo(modelo):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var original := mi.get_active_material(i) as BaseMaterial3D
			if original == null or original.cull_mode == BaseMaterial3D.CULL_DISABLED:
				continue
			var copia := original.duplicate() as BaseMaterial3D
			if copia == null:
				continue
			copia.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(i, copia)
			caras += 1
	print("[casa] casa completa: %d materiales a doble cara (maciza desde fuera; no se ocultó nada)" % caras)
	return caras


## Coloca a Leo en el punto de entrada, mirando por el vano. Se usa la colocación
## del controlador (`colocar_en`), que orienta cuerpo y cámara SIN girar la raíz del
## jugador: girarla era lo que dejaba el modelo descolocado en el ángulo de giro.
func _colocar_jugador() -> void:
	if _jugador == null:
		push_warning("CasaLeo: no hay jugador en la escena.")
		return
	var punto := get_node_or_null("PuntoEntrada") as Node3D
	var destino := get_node_or_null("MiraEntrada") as Node3D
	if punto == null or destino == null:
		return
	if _jugador.has_method("colocar_en"):
		_jugador.call("colocar_en", punto.global_position + Vector3.UP * 0.05, destino.global_position)
	else:
		_jugador.global_position = punto.global_position + Vector3.UP * 0.05
	print("[casa] Leo aparece junto a la puerta principal, mirando a la vivienda (%s)" % str(punto.global_position))


## Cielo y entorno: los MISMOS del juego (el material del cielo del asset Sky 3D
## se lo pone `Sky3DPuente`, igual que en la ciudad, y el ciclo ajusta ambiente y
## niebla). Aquí sólo se deja un respaldo por si la escena se abriera a pelo.
func _entorno() -> void:
	var we := get_node_or_null("Entorno") as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		we.name = "Entorno"
		add_child(we)
	if we.environment == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = load("res://Cielo/cielo_ciudad.tres") as Sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ssao_enabled = true
		env.fog_enabled = true
		env.fog_light_color = Color(0.73, 0.76, 0.81)
		env.fog_density = 0.00035
		env.fog_sky_affect = 0.0
		we.environment = env


## Luces del interior: la del sol de verdad (la mueve el ciclo) entra por las
## ventanas; la de relleno y la lámpara cálida se ajustan en `_actualizar_luz`.
func _luces() -> void:
	_sol = get_node_or_null("Sol") as DirectionalLight3D
	_luz = get_node_or_null("Luz") as DirectionalLight3D
	_lampara = get_node_or_null("LuzCalida") as OmniLight3D


## Colisiones de SEGURIDAD: piso y techo de la caja real (las paredes ya las ponen
## los triángulos del modelo). Así Leo no se cae ni salta fuera ni por los vanos.
func _colisiones() -> void:
	if _caja.size.length() < 0.001:
		return
	var cuerpo := get_node_or_null("Colision") as StaticBody3D
	if cuerpo == null:
		cuerpo = StaticBody3D.new()
		cuerpo.name = "Colision"
		add_child(cuerpo)
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	var minimo := _caja.position
	var maximo := _caja.position + _caja.size
	var centro_y := minimo.y + _caja.size.y * 0.5
	var alto := _caja.size.y + GROSOR * 2.0
	# Debajo del suelo real y por encima del techo real: no estorban a nada.
	_caja_colision(cuerpo, "Piso", Vector3(_caja.size.x + GROSOR * 2.0, GROSOR, _caja.size.z + GROSOR * 2.0),
			Vector3(minimo.x + _caja.size.x * 0.5, minimo.y - GROSOR * 0.5, minimo.z + _caja.size.z * 0.5))
	_caja_colision(cuerpo, "Techo", Vector3(_caja.size.x + GROSOR * 2.0, GROSOR, _caja.size.z + GROSOR * 2.0),
			Vector3(minimo.x + _caja.size.x * 0.5, maximo.y + GROSOR * 0.5, minimo.z + _caja.size.z * 0.5))
	# Contención perimetral invisible por fuera de la fachada (no tapa visualmente
	# ninguna ventana, pero garantiza que ni jugador ni cámara salgan del edificio).
	_caja_colision(cuerpo, "ParedOeste", Vector3(GROSOR, alto, _caja.size.z + GROSOR * 2.0),
			Vector3(minimo.x - GROSOR * 0.5 - 0.15, centro_y, minimo.z + _caja.size.z * 0.5))
	_caja_colision(cuerpo, "ParedEste", Vector3(GROSOR, alto, _caja.size.z + GROSOR * 2.0),
			Vector3(maximo.x + GROSOR * 0.5 + 0.15, centro_y, minimo.z + _caja.size.z * 0.5))
	_caja_colision(cuerpo, "ParedNorte", Vector3(_caja.size.x + GROSOR * 2.0, alto, GROSOR),
			Vector3(minimo.x + _caja.size.x * 0.5, centro_y, minimo.z - GROSOR * 0.5 - 0.15))
	_caja_colision(cuerpo, "ParedSur", Vector3(_caja.size.x + GROSOR * 2.0, alto, GROSOR),
			Vector3(minimo.x + _caja.size.x * 0.5, centro_y, maximo.z + GROSOR * 0.5 + 0.15))


func _caja_colision(cuerpo: StaticBody3D, nombre: String, tam: Vector3, centro: Vector3) -> void:
	var forma := CollisionShape3D.new()
	forma.name = nombre
	var caja := BoxShape3D.new()
	caja.size = tam
	forma.shape = caja
	forma.position = centro
	cuerpo.add_child(forma)


## Cristal invisible en los vanos EXTERIORES: la ciudad se ve por ellos y no se
## puede salir a la calle por la ventana. Los vanos INTERIORES (las puertas del
## modelo) no llevan nada: se pasan a pie.
func _cristales_de_vanos() -> int:
	var cuerpo := get_node_or_null("Colision") as StaticBody3D
	if cuerpo == null:
		return 0
	var n := 0
	for vano in VANOS:
		var centro: Vector3 = _de_modelo(vano[0])
		var tam: Vector3 = vano[1] * ESCALA
		_caja_colision(cuerpo, "Cristal%d" % n, tam, centro)
		_cristales_datos.append([centro, tam])
		n += 1
	return n


## Colisión REAL del modelo: una malla de triángulos por cada malla del GLB. Las
## paredes, los vanos y los muebles quedan exactos (los vanos siguen abiertos
## porque son huecos de la geometría). Medido: ~102 ms para las seis mallas.
func _colisiones_malla() -> void:
	var modelo := get_node_or_null("Modelo") as Node3D
	if modelo == null:
		return
	for mi in _mallas_bajo(modelo):
		if String(mi.name).begins_with("HojaPuerta"):
			continue
		mi.create_trimesh_collision()
		var t_glb := _transform_hasta(mi, modelo)
		for forma_nodo in mi.find_children("*", "CollisionShape3D", true, false):
			var cs := forma_nodo as CollisionShape3D
			if cs == null or not (cs.shape is ConcavePolygonShape3D):
				continue
			var concavo := cs.shape as ConcavePolygonShape3D
			concavo.backface_collision = true
			var nombre := String(mi.name)
			if nombre == "Object_10" or nombre == "Object_12" or nombre == "Object_13":
				var caras_filtradas := _filtrar_caras_colision(nombre, concavo.get_faces(), t_glb)
				concavo.set_faces(caras_filtradas)
	_cuerpos_malla = 0
	for hijo in modelo.find_children("*", "StaticBody3D", true, false):
		var cuerpo := hijo as StaticBody3D
		if cuerpo == null:
			continue
		cuerpo.collision_layer = 1
		cuerpo.collision_mask = 0
		_cuerpos_malla += 1


func _filtrar_caras_colision(nombre: String, caras: PackedVector3Array, t_glb: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := int(caras.size() / 3.0)
	for k in range(n):
		var l0: Vector3 = caras[k * 3]
		var l1: Vector3 = caras[k * 3 + 1]
		var l2: Vector3 = caras[k * 3 + 2]
		var v0: Vector3 = t_glb * l0
		var v1: Vector3 = t_glb * l1
		var v2: Vector3 = t_glb * l2
		var tmin := v0.min(v1.min(v2))
		var tmax := v0.max(v1.max(v2))
		var omitir := false
		if nombre == "Object_10":
			# Hojas interiores abiertas de los 2 dormitorios y sus pomos (los marcos quedan en x <= -3.725).
			if tmin.x >= -3.726 and tmax.x <= -2.955 and tmax.y <= 2.10:
				if (tmin.z >= -3.340 and tmax.z <= -3.215) or (tmin.z >= -5.060 and tmax.z <= -4.935):
					omitir = true
			# Escalón milimétrico de alfombras (el piso ya tiene colisión continua a y = 0).
			if tmax.y <= 0.085 and tmin.x >= -3.65 and tmax.x <= -0.04 and tmin.z >= -6.15 and tmax.z <= -0.44:
				omitir = true
		elif nombre == "Object_12" or nombre == "Object_13":
			# Alfombra del salón y estrechamiento esquina mostrador-sofá para paso al ala oeste.
			if tmax.y <= 0.040 and tmin.x >= -6.10 and tmax.x <= -0.40 and tmin.z >= 0.30 and tmax.z <= 4.20:
				omitir = true
			elif tmax.y > 0.040 and tmax.y < 1.20 and tmax.x >= -5.18 and tmin.x <= -4.48 and tmax.z >= 1.25 and tmin.z <= 1.82:
				omitir = true
		if not omitir:
			out.append(l0)
			out.append(l1)
			out.append(l2)
	return out


func _mallas_bajo(nodo: Node) -> Array[MeshInstance3D]:
	var lista: Array[MeshInstance3D] = []
	if nodo is MeshInstance3D:
		lista.append(nodo as MeshInstance3D)
	for c in nodo.get_children():
		lista.append_array(_mallas_bajo(c))
	return lista


## CIUDAD de fuera: suelo + edificios de verdad colocados alrededor, con ventanas
## encendidas que se iluminan de noche. Es determinista (semilla fija) y barato
## (los edificios son cajas y todas las ventanas son UNA sola MultiMesh).
func _vista() -> void:
	var raiz := Node3D.new()
	raiz.name = "CiudadVista"
	add_child(raiz)
	# Suelo de la ciudad, dos pisos por debajo de la casa.
	var suelo := MeshInstance3D.new()
	suelo.name = "Suelo"
	var plano := PlaneMesh.new()
	plano.size = Vector2(420.0, 420.0)
	suelo.mesh = plano
	suelo.material_override = _mat_plano()
	suelo.position = Vector3(0.0, VISTA_SUELO_Y, 0.0)
	raiz.add_child(suelo)
	# Edificios alrededor y sus ventanas (una sola MultiMesh para todas).
	var rng := RandomNumberGenerator.new()
	rng.seed = VISTA_SEMILLA
	var rejilla: Array[Transform3D] = []
	# Radio de la casa en planta: ningún edificio puede entrar en este círculo.
	var radio_casa := Vector2(
			maxf(absf(_caja.position.x), absf(_caja.end.x)),
			maxf(absf(_caja.position.z), absf(_caja.end.z))).length()
	_vista_empujados = 0
	_vista_min_dist = 1e9
	for i in VISTA_EDIFICIOS:
		var angulo := TAU * float(i) / float(VISTA_EDIFICIOS) + rng.randf_range(-0.07, 0.07)
		var dist := rng.randf_range(VISTA_ANILLO.x, VISTA_ANILLO.y)
		var ancho := rng.randf_range(VISTA_LADO.x, VISTA_LADO.y)
		var fondo := rng.randf_range(VISTA_LADO.x, VISTA_LADO.y)
		var alto := rng.randf_range(VISTA_ALTO.x, VISTA_ALTO.y)
		# Fuera de la casa SIEMPRE: la media diagonal del edificio es lo que puede
		# asomar hacia el centro por mucho que gire la esquina.
		var minima := radio_casa + Vector2(ancho, fondo).length() * 0.5 + VISTA_AIRE_FACHADA
		if dist < minima:
			dist = minima
			_vista_empujados += 1
		_vista_min_dist = minf(_vista_min_dist, dist - Vector2(ancho, fondo).length() * 0.5)
		var centro := Vector3(cos(angulo) * dist, VISTA_SUELO_Y + alto * 0.5, sin(angulo) * dist)
		var edificio := MeshInstance3D.new()
		edificio.name = "Edificio%d" % i
		var caja := BoxMesh.new()
		caja.size = Vector3(ancho, alto, fondo)
		edificio.mesh = caja
		edificio.material_override = _mat_edificio(i)
		edificio.position = centro
		raiz.add_child(edificio)
		_vista_posiciones.append(centro)
		_ventanas_de(rejilla, centro, ancho, alto, fondo, rng)
	_edificios = VISTA_EDIFICIOS
	_ventanas = rejilla.size()
	print("[casa] vista de la ciudad: %d edificios, %d corridos fuera de la casa | la cara más cercana queda a %.1f m del centro (la casa llega a %.1f m)" % [
			_edificios, _vista_empujados, _vista_min_dist, radio_casa])
	if rejilla.is_empty():
		return
	_mat_ventana = _mat_nueva_ventana()
	var multi := MultiMeshInstance3D.new()
	multi.name = "Ventanas"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var hoja := BoxMesh.new()
	hoja.size = Vector3(0.85, 1.1, 0.14)
	mm.mesh = hoja
	mm.instance_count = rejilla.size()
	for j in rejilla.size():
		mm.set_instance_transform(j, rejilla[j])
	multi.multimesh = mm
	multi.material_override = _mat_ventana
	raiz.add_child(multi)


## Ventanas encendidas de un edificio: rejilla sobre las DOS caras que miran a la
## casa (esas son las que se ven desde dentro). Nada de ventanas en la cara de atrás.
func _ventanas_de(destino: Array[Transform3D], centro: Vector3, ancho: float, alto: float,
		fondo: float, rng: RandomNumberGenerator) -> void:
	var hacia := Vector3(-centro.x, 0.0, -centro.z)
	if hacia.length_squared() < 0.001:
		return
	hacia = hacia.normalized()
	var por_x := absf(hacia.x) >= absf(hacia.z)
	var caras: Array[float] = [1.0, -1.0]
	for signo in caras:
		var normal := Vector3(signo, 0.0, 0.0) if por_x else Vector3(0.0, 0.0, signo)
		if normal.dot(hacia) <= 0.1:
			continue   # esta cara no se ve desde la casa
		var media := ancho * 0.5 if por_x else fondo * 0.5
		var largo := fondo if por_x else ancho
		var x0 := 1.6 - largo * 0.5
		var y := VISTA_SUELO_Y + 2.2
		while y < VISTA_SUELO_Y + alto - 1.6:
			var x := x0
			while x < largo * 0.5 - 1.4:
				if rng.randf() > 0.32:
					var p := centro + normal * (media + 0.08)
					if por_x:
						p.z += x
					else:
						p.x += x
					p.y = y
					destino.append(Transform3D(Basis(), p))
				x += VISTA_ANCHO_VENTANA
			y += VISTA_ALTO_VENTANA


func _mat_plano() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.19)
	m.roughness = 1.0
	return m


func _mat_edificio(i: int) -> StandardMaterial3D:
	while _mat_edificios.size() <= i % VISTA_MATERIALES:
		var m := StandardMaterial3D.new()
		m.roughness = 0.95
		m.albedo_color = [Color(0.42, 0.43, 0.46), Color(0.35, 0.34, 0.36), Color(0.5, 0.47, 0.44)][_mat_edificios.size() % 3]
		_mat_edificios.append(m)
	return _mat_edificios[i % VISTA_MATERIALES]


func _mat_nueva_ventana() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.14)
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = VISTA_LUZ_VENTANA
	m.emission_energy_multiplier = 0.0
	return m


## La luz del interior sigue al SOL de verdad (la altura de la luz que mueve el
## ciclo): de día entra luz por las ventanas y de noche manda la lámpara y se
## encienden las ventanas de los edificios. Sin relojes propios ni parpadeos.
func _actualizar_luz(_delta: float) -> void:
	var y := 0.0
	if _sol != null:
		y = _sol.global_transform.basis.z.normalized().y
	_noche01 = 1.0 - clampf(smoothstep(-0.05, 0.22, y), 0.0, 1.0)
	var dia := 1.0 - _noche01
	if _luz != null:
		_luz.light_energy = lerpf(0.10, 0.45, dia)
		_luz.light_color = Color(1.0, 0.97, 0.92).lerp(LUZ_CALIDA, _noche01)
	if _lampara != null:
		_lampara.light_energy = lerpf(2.0, 0.9, dia)
	if _mat_ventana != null:
		_mat_ventana.emission_energy_multiplier = _noche01 * 2.4


func _process(delta: float) -> void:
	_actualizar_luz(delta)


## Caja REAL de la malla del modelo (sólo MeshInstance3D), en el espacio de esta
## escena: es la referencia de suelo, techo y paredes.
func _medir_modelo() -> AABB:
	var modelo := get_node_or_null("Modelo") as Node3D
	if modelo == null:
		return AABB()
	return _caja_de_malla(modelo, modelo.transform)


func _caja_de_malla(nodo: Node, t: Transform3D) -> AABB:
	var caja := AABB()
	var primero := true
	if nodo is MeshInstance3D:
		var mi := nodo as MeshInstance3D
		if mi.mesh != null:
			caja = _transformar_aabb(mi.get_aabb(), t)
			primero = false
	for c in nodo.get_children():
		var hijo := c as Node3D
		if hijo == null:
			continue
		var caja_hijo := _caja_de_malla(hijo, t * hijo.transform)
		if caja_hijo.size.length() < 0.0001:
			continue
		caja = caja_hijo if primero else caja.merge(caja_hijo)
		primero = false
	return caja


func _transformar_aabb(caja: AABB, t: Transform3D) -> AABB:
	var r := AABB(t * caja.position, Vector3.ZERO)
	for i in range(1, 8):
		r = r.expand(t * caja.get_endpoint(i))
	return r


## --- Lecturas para las pruebas ----------------------------------------------
func listo() -> bool:
	return _listo


func caja_interior() -> AABB:
	return _caja


func jugador() -> Node3D:
	return _jugador


func salida() -> SalidaInterior:
	return get_node_or_null("SalidaInterior") as SalidaInterior


func escala() -> float:
	return ESCALA


func cuerpos_de_malla() -> int:
	return _cuerpos_malla


func cristales() -> int:
	return _cristales


## [centro, tamaño] de cada cristal invisible, en unidades de la escena: con esto
## las pruebas comprueban con rayos que las ventanas NO se cruzan.
func cristales_datos() -> Array:
	return _cristales_datos


## Centros de los edificios de la ciudad que se ve por las ventanas.
func vista_posiciones() -> Array[Vector3]:
	return _vista_posiciones


func edificios() -> int:
	return _edificios


## Edificios de la vista que hubo que correr para que no entraran en la casa.
func vista_empujados() -> int:
	return _vista_empujados


## Distancia (m) del centro de la casa a la CARA más cercana de cualquier edificio
## de la vista: tiene que ser mayor que el radio de la casa (si no, tapa ventanas).
func vista_distancia_minima() -> float:
	return _vista_min_dist


func ventanas() -> int:
	return _ventanas


func noche01() -> float:
	return _noche01


## --- Lecturas de las correcciones (para las pruebas) ------------------------
func camara_radio() -> float:
	return CAMARA_RADIO


func camara_margen() -> float:
	return CAMARA_MARGEN


func paso_en_casa() -> float:
	return RADIO_EN_CASA


func radio_del_jugador() -> float:
	return _capsula_jugador.radius if _capsula_jugador != null else -1.0


func radio_de_fuera() -> float:
	return _radio_original


func caras_dobles() -> int:
	return _caras_dobles


func hojas_abiertas() -> int:
	return _hojas_abiertas


func vano_dormitorio() -> Vector3:
	return _de_modelo(VANO_DORMITORIO)


func puerta_interior() -> Vector3:
	return _de_modelo(VANO)


func spawn() -> Vector3:
	return _de_modelo(PASILLO)


func mira() -> Vector3:
	return _de_modelo(MIRA)