extends Node3D
## PRUEBAS DE PASOS por el INTERIOR DE LA CASA DE LEO (Tareas 1, 1B, 2, 3 y 4).
##
## No coloca al jugador a mano: lo hace ANDAR de verdad (pulsando los mandos del
## juego, con la cámara que le puso la entrada) sobre la escena REAL, y comprueba
## con medidas dónde acaba cada tramo. Los tramos terminan al LLEGAR (o al agotar
## los fotogramas), así que la prueba no depende de la velocidad exacta de la
## marcha ni de la geometría del modelo.
##
## Comprueba:
##   1. aparece delante del vano del dormitorio (el de la captura) y la salida está
##      a mano: el HUD recibe el aviso exacto;
##   2. el modelo se agrandó de forma UNIFORME y el techo está a ~3,0 m;
##   3. hay colisión real por malla y tres cristales en los vanos exteriores;
##   4. se PASA A PIE por el vano del dormitorio (las puertas están abiertas) y se
##      camina dentro del dormitorio sin caerse;
##   5. desde el DORMITORIO la salida NO se ofrece (está al otro lado del muro) y
##      vuelve a ofrecerse al regresar al pasillo;
##   6. caminando por el pasillo llega al salón y el muro sur lo frena, sin salirse
##      ni caerse a la calle;
##   7. los tres vanos exteriores están CERRADOS por un cristal invisible (rayos);
##   8. fuera hay ciudad de verdad: edificios delante de cada ventana.

const CASA := "res://casa_leo/casa_leo.tscn"
const TEXTO_SALIDA := "Presiona E para salir a la ciudad"

var _ok := 0
var _fallos := 0
var _casa: CasaLeo
var _jug: CharacterBody3D
## Nombre del cuerpo que frenó el último tramo (para informar del tope real).
var _tope := ""


func _ready() -> void:
	_casa = (load(CASA) as PackedScene).instantiate() as CasaLeo
	add_child(_casa)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_jug = _casa.jugador() as CharacterBody3D
	_check(_casa.listo() and _jug != null, "el interior carga con el jugador dentro")
	if _jug == null:
		_resumen()
		return
	var caja := _casa.caja_interior()
	var techo := caja.position.y + caja.size.y
	_check(is_equal_approx(_casa.escala(), 1.2), "el modelo se agrandó ×%.2f (uniforme)" % _casa.escala())
	_check(absf(techo - 3.01) < 0.06, "el techo queda a %.2f m (antes 2,51: la casa es más holgada)" % techo)
	_check(_casa.cuerpos_de_malla() == 6, "colisión REAL por malla del modelo (%d mallas)" % _casa.cuerpos_de_malla())
	_check(_casa.cristales() == 3, "cristales invisibles en los %d vanos exteriores" % _casa.cristales())
	_check(_casa.edificios() == 40 and _casa.ventanas() > 500,
			"ciudad fuera de las ventanas: %d edificios y %d ventanas" % [_casa.edificios(), _casa.ventanas()])

	# --- 1) PRUEBA A: Aparece delante de la puerta principal cerrada (foto 1) --
	var puerta := _casa.puerta_interior()
	var d0 := Vector2(_jug.global_position.x - puerta.x, _jug.global_position.z - puerta.z).length()
	_check(d0 < 1.3, "aparece delante de la puerta principal del pasillo (a %.2f m de la puerta)" % d0)
	_check(absf(puerta.z - 1.40) < 0.15 and absf(puerta.x - (-0.69)) < 0.15,
			"la puerta está en la ubicación de la foto (pared derecha del pasillo: %s)" % str(puerta))
	_check(_jug.global_position.x > -2.15 and _jug.global_position.x < -0.70,
			"aparece DENTRO del pasillo (x %.2f; el pasillo va de -2,07 a -0,81)" % _jug.global_position.x)
	var salida := _casa.salida()
	_check(salida != null and bool(salida.call("en_rango")), "la salida está a mano al aparecer")
	var texto := String(_jug.call("texto_interaccion"))
	_check(texto == TEXTO_SALIDA, "el HUD recibe el aviso exacto ('%s')" % texto)

	# --- 2) PRUEBA B y D: Cámara segura + Geometría completa a doble cara ------
	_check(_casa.caras_dobles() >= 5, "geometría completa con %d materiales a doble cara (sin recortes)" % _casa.caras_dobles())
	_check(_casa.hojas_abiertas() == 2, "las %d hojas interiores de los baños se abrieron por pivote/rotación" % _casa.hojas_abiertas())
	_check(is_equal_approx(_casa.radio_del_jugador(), _casa.paso_en_casa()) and is_equal_approx(_casa.radio_de_fuera(), 0.40),
			"radio de cápsula en casa %.2f m (fuera %.2f m guardado para restaurar)" % [_casa.radio_del_jugador(), _casa.radio_de_fuera()])
	var pivote_cam := _jug.get_node_or_null("PivoteCamara") as Node3D
	var brazo_cam := _jug.get_node_or_null("PivoteCamara/Brazo") as SpringArm3D
	var cam := _jug.get_node_or_null("PivoteCamara/Brazo/Camara") as Camera3D
	_check(brazo_cam != null and brazo_cam.shape is SphereShape3D and brazo_cam.margin >= 0.18,
			"el SpringArm3D tiene forma esférica y margen (%.2f m)" % (brazo_cam.margin if brazo_cam != null else -1.0))
	if pivote_cam != null and cam != null:
		var yaw_orig := pivote_cam.rotation.y
		var cam_dentro := true
		for i in range(8):
			pivote_cam.rotation.y = yaw_orig + TAU * float(i) / 8.0
			if pivote_cam.has_method("forzar_ajuste_inmediato"):
				pivote_cam.call("forzar_ajuste_inmediato")
			var pc := cam.global_position
			if pc.x < caja.position.x - 0.05 or pc.x > caja.end.x + 0.05 or pc.z < caja.position.z - 0.05 or pc.z > caja.end.z + 0.05:
				cam_dentro = false
		pivote_cam.rotation.y = yaw_orig
		if pivote_cam.has_method("forzar_ajuste_inmediato"):
			pivote_cam.call("forzar_ajuste_inmediato")
		_check(cam_dentro, "la cámara gira 360° en el pasillo sin salirse nunca de las paredes")

	# --- 3) PRUEBA C: Puertas interiores transitables (dormitorio y baño) -----
	await _ir_a(Vector2(-1.45, -1.75), 180)
	await _ir_a(Vector2(-2.60, -1.75), 140)
	var p_bano := _jug.global_position
	_check(p_bano.x < -2.15, "entró A PIE al baño interior cuya puerta estaba cerrada (x %.2f)" % p_bano.x)
	await _ir_a(Vector2(-1.45, -1.75), 140)
	await _ir_a(Vector2(-1.45, -2.45), 120)
	await _ir_a(Vector2(1.8, -2.45), 200)
	var p1 := _jug.global_position
	_check(p1.x > 0.2, "pasó A PIE por el vano del dormitorio (x %.2f; el vano está en -0,63)" % p1.x)
	_check(p1.y > -0.3 and p1.y < 0.6, "cruzó el vano sin caerse ni colarse por el suelo (y %.2f)" % p1.y)
	_check(not bool(salida.call("en_rango")), "desde el DORMITORIO la salida NO se ofrece (otro lado del muro)")
	var texto_dentro := String(_jug.call("texto_interaccion"))
	_check(texto_dentro != TEXTO_SALIDA, "el aviso de SALIDA desapareció dentro del dormitorio (ahora: '%s')" % texto_dentro)
	# Y dentro del dormitorio no se cae: sigue apoyado.
	_check(_jug.is_on_floor(), "sigue apoyado en el suelo del dormitorio")

	# --- 4) Vuelve al pasillo y a la puerta principal: la salida se ofrece ----
	await _ir_a(Vector2(-1.45, -2.45), 220)
	var p2 := _jug.global_position
	_check(p2.x < -0.85, "regresó al pasillo andando (x %.2f)" % p2.x)
	await _ir_a(Vector2(-1.45, 1.40), 220)
	_check(bool(salida.call("en_rango")), "delante de la puerta principal la salida se ofrece otra vez")

	# --- 5) Por el pasillo hasta el salón y freno en el mobiliario ------------
	await _ir_a(Vector2(-1.45, 2.2), 160)
	var p3 := _jug.global_position
	_check(p3.z > 1.8, "bajó por el pasillo hasta el salón (z %.2f)" % p3.z)
	await _ir_a(Vector2(-1.45, 6.4), 260)
	var p4 := _jug.global_position
	# La marcha recta hacia el ventanal se topa con el MOBILIARIO del modelo (la
	# cocina-comedor, Object_13): es la prueba de que los muebles tienen colisión
	# de verdad y no se atraviesan. La contención del ventanal se comprueba aparte,
	# con rayos (más abajo), que es una medida exacta y no depende de la ruta.
	_check(p4.z > 2.2 and p4.z < 6.7,
			"avanzó por el salón y lo frenó el mobiliario del modelo (z %.2f)" % p4.z)
	_check(_tope.begins_with("Object_"),
			"el tope es mobiliario REAL del modelo con colisión (%s)" % _tope)
	_check(p4.y > -0.4, "sigue dentro de la casa, sin caerse a la calle (y %.2f)" % p4.y)

	# --- 5) La vista sigue al CICLO real: de día a plena luz, de noche cerrada y
	#         con las ventanas de los edificios encendidas. ---------------------
	var ciclo := _casa.get_node_or_null("CicloDiaNoche") as CicloDiaNoche
	_check(ciclo != null, "el interior usa el ciclo del juego (sin reloj propio)")
	if ciclo != null:
		ciclo.poner_fase(ciclo.fase_dia_pleno())
		await get_tree().physics_frame
		await get_tree().process_frame
		_check(_casa.noche01() < 0.10, "de DÍA la ciudad de fuera está a plena luz (noche %.2f)" % _casa.noche01())
		ciclo.poner_fase(0.98)
		await get_tree().physics_frame
		await get_tree().process_frame
		_check(_casa.noche01() > 0.90, "de NOCHE la vista pasa a noche cerrada (noche %.2f)" % _casa.noche01())
		var ventanas := _casa.get_node_or_null("CiudadVista/Ventanas") as MultiMeshInstance3D
		var mat := ventanas.material_override as StandardMaterial3D if ventanas != null else null
		_check(mat != null and mat.emission_energy_multiplier > 1.0,
				"y se encienden las ventanas de los edificios (emisión %.2f)" % (mat.emission_energy_multiplier if mat != null else -1.0))
		ciclo.poner_fase(ciclo.fase_dia_pleno())
		await get_tree().physics_frame
		await get_tree().process_frame

	# --- 6) Los vanos exteriores no se cruzan (rayos) ------------------------
	_rayos_de_cristales()
	# --- 6) Detrás de cada ventana hay ciudad --------------------------------
	_ciudad_tras_las_ventanas()
	_check(EstadoCasaLeo.hay_vuelta() == false, "no queda ninguna vuelta pendiente colgada")
	_resumen()


## PILOTO AUTOMÁTICO de la prueba: lleva a Leo hasta un objetivo (x, z) pulsando
## los mandos del juego que más le acercan, corrigiendo la deriva en cada
## fotograma (como un joystick). Se para al llegar (± 0,35 m) o al agotar los
## fotogramas (tramo taponado por un muro). Así los tramos no dependen de la
## velocidad de la marcha ni de pequeños desvíos.
func _ir_a(destino: Vector2, max_frames: int) -> void:
	var mandos := ["mover_adelante", "mover_atras", "mover_izquierda", "mover_derecha"]
	for m in mandos:
		Input.action_release(m)
	var usados := 0
	while usados < max_frames:
		var pos := Vector2(_jug.global_position.x, _jug.global_position.z)
		var falta := destino - pos
		if falta.length() < 0.35:
			break
		# Dirección de mundo que da cada mando ahora mismo, según la cámara real.
		var base: Basis = (_jug.get("pivote") as Node3D).global_transform.basis
		var direcciones := [
			Vector3(-base.z.x, 0.0, -base.z.z).normalized(),
			Vector3(base.z.x, 0.0, base.z.z).normalized(),
			Vector3(-base.x.x, 0.0, -base.x.z).normalized(),
			Vector3(base.x.x, 0.0, base.x.z).normalized(),
		]
		var deseo := falta.normalized()
		for i in mandos.size():
			var d := Vector2(direcciones[i].x, direcciones[i].z)
			var peso := d.dot(deseo)
			var pulsado := Input.is_action_pressed(mandos[i])
			if peso > 0.35 and not pulsado:
				Input.action_press(mandos[i])
			elif peso <= 0.35 and pulsado:
				Input.action_release(mandos[i])
		await get_tree().physics_frame
		usados += 1
	for m in mandos:
		Input.action_release(m)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Si no llegó, se informa del TOPE exacto: qué tiene delante y a qué altura está
	# el suelo. (Es lo que dice si el tapón es un mueble, una pared o un escalón.)
	var final := Vector2(_jug.global_position.x, _jug.global_position.z)
	if final.distance_to(destino) >= 0.35:
		var mundo := get_world_3d().direct_space_state
		var mira := Vector3(destino.x - final.x, 0.0, destino.y - final.y).normalized()
		var pecho := _jug.global_position + Vector3.UP * 1.0
		var rayo := PhysicsRayQueryParameters3D.create(pecho, pecho + mira * 1.6, 1)
		var golpe := mundo.intersect_ray(rayo)
		var suelo := PhysicsRayQueryParameters3D.create(
				pecho + mira * 0.8, pecho + mira * 0.8 - Vector3.UP * 3.0, 1)
		var piso := mundo.intersect_ray(suelo)
		_tope = String(golpe.get("collider").name) if not golpe.is_empty() else "nada"
		print("[casa-pasos] TOPE en %s (faltaban %.2f m) | delante: %s | suelo a y %s" % [
				str(final), final.distance_to(destino),
				str(golpe.get("collider")) if not golpe.is_empty() else "nada",
				"%.2f" % (piso["position"] as Vector3).y if not piso.is_empty() else "nada"])


## Un rayo desde dentro hacia fuera en cada cristal: tiene que chocar con el
## cristal invisible (la ventana se ve, pero no se cruza).
func _rayos_de_cristales() -> void:
	var mundo := _casa.get_world_3d().direct_space_state
	var datos := _casa.cristales_datos()
	for i in datos.size():
		var centro: Vector3 = (datos[i] as Array)[0]
		var tam: Vector3 = (datos[i] as Array)[1]
		var eje := 0
		if tam.y < tam.x and tam.y < tam.z:
			eje = 1
		elif tam.z < tam.x and tam.z < tam.y:
			eje = 2
		var dir := Vector3.ZERO
		match eje:
			0:
				dir = Vector3(signf(centro.x), 0.0, 0.0)
			1:
				dir = Vector3(0.0, signf(centro.y), 0.0)
			_:
				dir = Vector3(0.0, 0.0, signf(centro.z))
		var desde := centro - dir * 0.6
		var rayo := PhysicsRayQueryParameters3D.create(desde, desde + dir * 1.8, 1)
		var golpe := mundo.intersect_ray(rayo)
		var d := desde.distance_to(golpe["position"]) if not golpe.is_empty() else -1.0
		_check(not golpe.is_empty() and d < 0.9,
				"el vano exterior %d está cerrado: el rayo choca a %.2f m (no se sale)" % [i + 1, d])


## Cada ventana tiene que dar a la ciudad: cuenta los edificios que están DELANTE
## de cada vano (en su lado de fuera) y a menos de 90 m.
func _ciudad_tras_las_ventanas() -> void:
	var datos := _casa.cristales_datos()
	var posiciones := _casa.vista_posiciones()
	for i in datos.size():
		var centro: Vector3 = (datos[i] as Array)[0]
		var tam: Vector3 = (datos[i] as Array)[1]
		var eje := 0
		if tam.y < tam.x and tam.y < tam.z:
			eje = 1
		elif tam.z < tam.x and tam.z < tam.y:
			eje = 2
		var dir := Vector3.ZERO
		match eje:
			0:
				dir = Vector3(signf(centro.x), 0.0, 0.0)
			1:
				dir = Vector3(0.0, signf(centro.y), 0.0)
			_:
				dir = Vector3(0.0, 0.0, signf(centro.z))
		var delante := 0
		var mas_cerca := 1e9
		for p in posiciones:
			var v := p - centro
			if v.length() < 90.0 and v.normalized().dot(dir) > 0.25:
				delante += 1
				mas_cerca = minf(mas_cerca, v.length())
		_check(delante >= 3, "tras el vano %d hay ciudad: %d edificios (el más cerca a %.0f m)" % [
				i + 1, delante, mas_cerca])


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[casa-pasos] OK   ", texto)
	else:
		_fallos += 1
		print("[casa-pasos] FALLO ", texto)


func _resumen() -> void:
	print("==================== CASA (pasos): %d OK / %d FALLO ====================" % [_ok, _fallos])
