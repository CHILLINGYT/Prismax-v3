extends Node3D
## PRUEBAS de LA PUERTA DE LA CASA DE LEO EN LA CIUDAD, sobre la escena REAL
## (PuertaCasaLeo) con una ciudad de mentira que trae PORTALES como los del
## generador, más el jugador de verdad para probar el canal del HUD y la marcha.
##
## Comprueba:
##   1. la puerta se marca en un portal REAL de la ciudad y elige el MÁS CERCANO a
##      donde aparece Leo, por la cara exterior (a la calle);
##   2. la puerta elegida se RECUERDA: aunque se cargue el mundo con Leo en la otra
##      punta, la casa sigue teniendo la MISMA puerta (una sola, para siempre);
##   3. la flecha amarilla de la puerta está montada, encima del portal y apuntando
##      hacia abajo (el aviso de la calle);
##   4. el aviso llega al HUD con el TEXTO EXACTO, sólo dentro del radio, y se
##      retira al alejarse;
##   5. `puede_usar()` sólo dice sí con Leo cerca y sin el bloqueo anti-bucle;
##   6. al volver de la casa, Leo aparece en el punto de vuelta ORIENTADO a la calle
##      y andando hacia adelante va RECTO a la calle (raíz sin girar: ni diagonales
##      ni desplazamientos raros), y la vuelta se consume;
##   7. además, justo al volver la puerta no se ofrece hasta que Leo se aleja.

const TEXTO_ENTRADA := "Presiona E para entrar a la casa de Leo"

var _ok := 0
var _fallos := 0
var _ciudad: CiudadPortales
var _puerta: PuertaCasaLeo
var _jug: CharacterBody3D


func _ready() -> void:
	EstadoCasaLeo.olvidar_portal()
	_piso()
	# El jugador PRIMERO (la puerta lo busca para saber de dónde parte Leo).
	_jug = (load("res://personaje/base/escenas/leo_jugador.tscn") as PackedScene).instantiate() as CharacterBody3D
	_jug.position = Vector3(0.0, 0.2, 0.0)
	add_child(_jug)
	_ciudad = CiudadPortales.new()
	add_child(_ciudad)
	await get_tree().physics_frame
	_puerta = PuertaCasaLeo.new()
	_puerta.name = "PuertaCasaLeo"
	_puerta.ciudad = _ciudad
	add_child(_puerta)
	var t := 0
	while _puerta.portal() == Vector3.ZERO and t < 300:
		await get_tree().physics_frame
		t += 1
	await get_tree().physics_frame

	# 1. Portal elegido: el más cercano (8 m), por la cara exterior (a la calle).
	_check(_puerta.portal().distance_to(Vector3(8.0, 0.0, 0.0)) < 0.01,
			"elige el portal MÁS CERCANO de la ciudad (%s)" % str(_puerta.portal()))
	_check(EstadoCasaLeo.portal_guardado() == 0,
			"y lo RECUERDA para siempre (portal %d guardado)" % EstadoCasaLeo.portal_guardado())
	var portal := _puerta.portal()
	var hacia_calle := _puerta.global_position - portal
	_check(hacia_calle.normalized().dot(Vector3.LEFT) > 0.9,
			"se marca por la CARA EXTERIOR (a %.2f m del portal, hacia la calle)" % hacia_calle.length())
	_check(_puerta.texto_prompt() == TEXTO_ENTRADA,
			"el texto del aviso es el pedido ('%s')" % _puerta.texto_prompt())

	# 2. La flecha amarilla, encima del portal y apuntando hacia abajo.
	var flecha := _puerta.flecha()
	_check(flecha != null, "la puerta tiene su flecha de aviso")
	if flecha != null:
		# Marcador DoorMarker (estilo GTA SA): la punta flota sobre el portal.
		var marcador := flecha as DoorMarker
		_check(marcador != null, "la flecha es el marcador reutilizable DoorMarker")
		if marcador != null:
			var y0 := marcador.altura_flecha()
			_check(y0 > 2.0 and y0 < 3.2, "la punta va encima del portal (y %.2f)" % y0)
			var malla := (marcador.get_node("_DMPivote/_DMFlecha") as MeshInstance3D).mesh
			var caja := malla.get_aabb()
			_check(caja.position.y > -0.01 and caja.position.y < 0.05 and caja.end.y > 0.8,
					"apunta hacia abajo (punta en la base de su malla, cola arriba: %.2f..%.2f)" % [caja.position.y, caja.end.y])
			var c := marcador.color
			_check(c.r > 0.9 and c.g > 0.6 and c.b < 0.2 and c.s > 0.9, "amarillo saturado (%s)" % str(c))
			var g0 := marcador.giro_flecha()
			var alturas := [y0]
			for k in 40:
				await get_tree().process_frame
				alturas.append(marcador.altura_flecha())
			var g1 := marcador.giro_flecha()
			_check(absf(wrapf(g1 - g0, -PI, PI)) > 0.01, "gira sobre su eje vertical (%.3f → %.3f rad)" % [g0, g1])
			_check(alturas.max() - alturas.min() > 0.005, "sube y baja (vaivén %.3f m)" % (alturas.max() - alturas.min()))

	# 3. Radio: lejos no hay aviso; cerca sí, por el canal del HUD.
	_jug.global_position = Vector3(0.0, 0.2, 12.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _puerta.en_rango(), "de lejos no oferta la entrada")
	_check(String(_jug.call("texto_interaccion")) == "", "de lejos el HUD no muestra nada")
	_check(not _puerta.puede_usar(), "de lejos no se puede entrar")
	_jug.global_position = portal + Vector3(-1.5, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_puerta.en_rango(), "de cerca ofrece la entrada")
	_check(String(_jug.call("texto_interaccion")) == TEXTO_ENTRADA,
			"el HUD recibe el aviso EXACTO ('%s')" % String(_jug.call("texto_interaccion")))
	_check(_puerta.puede_usar(), "de cerca la E entra en la casa")

	# 4. Bloqueo anti-bucle: recién vuelto de la casa, no se entra otra vez.
	EstadoCasaLeo.bloquear(600)
	_check(not _puerta.puede_usar(), "con el bloqueo anti-bucle puesto NO se entra (nada de bucles)")
	_check(EstadoCasaLeo.bloqueado(), "el bloqueo está activo de verdad")
	# Se espera por FOTOGRAMAS, no con temporizador: los temporizadores del banco
	# de pruebas se disparan antes de tiempo (0,7 s ≈ 45 fotogramas a 60 Hz).
	for i in 80:
		await get_tree().physics_frame
	_check(_puerta.puede_usar(), "pasado el bloqueo vuelve a ofrecerse")

	# 5. Punto de vuelta: delante de la puerta, mirando a la calle.
	var salida := _puerta.punto_de_salida()
	var fuera := salida - _puerta.global_position
	_check(fuera.length() > 1.0 and fuera.normalized().dot(Vector3.LEFT) > 0.9,
			"el punto de vuelta queda delante de la puerta, a la calle (%.2f m)" % fuera.length())

	# 6. Volver de la casa: aparece en ese punto, mirando a la calle (mira = -X).
	EstadoCasaLeo.marcar_vuelta(salida, Vector3.LEFT)
	_check(EstadoCasaLeo.hay_vuelta(), "queda una vuelta pendiente al salir de la casa")
	var otra := PuertaCasaLeo.new()
	otra.name = "PuertaCasaLeo2"
	otra.ciudad = _ciudad
	add_child(otra)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_jug.global_position.distance_to(salida) < 0.6,
			"al volver, Leo aparece delante de su puerta (a %.2f m del punto)" % _jug.global_position.distance_to(salida))
	_check(not EstadoCasaLeo.hay_vuelta(), "la vuelta se consume (no queda colgando)")
	_check(otra.portal().distance_to(Vector3(8.0, 0.0, 0.0)) < 0.01,
			"el mundo recargado usa la MISMA puerta de siempre (%s), no otra" % str(otra.portal()))

	# 7. La puerta no se ofrece hasta que Leo se aleja.
	_jug.global_position = _puerta.global_position + Vector3(-1.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# La vuelta la consume la puerta que la encuentra pendiente (la segunda, que es
	# la que se creó después de marcar la vuelta): es ELLA la que espera a que Leo
	# se aleje. Las dos están en el mismo portal, así que el efecto es el mismo.
	_check(otra.esperando_alejarse(), "justo al volver, la puerta espera a que Leo se aleje")
	_check(not otra.puede_usar(), "y por eso no vuelve a entrar sin querer (sin bucles)")

	# 8. La ORIENTACIÓN al volver: raíz sin girar y marcha RECTA hacia la calle.
	var raiz := _jug.rotation.y
	_check(absf(raiz) < 0.02, "la raíz del jugador se queda sin girar (yaw %.3f)" % raiz)
	var pivote := _jug.get("pivote") as Node3D
	_check(pivote != null and absf(angle_difference(pivote.rotation.y, PI * 0.5)) < 0.2,
			"la cámara mira a la calle (-X: %.3f rad)" % (pivote.rotation.y if pivote != null else 0.0))
	var antes := _jug.global_position
	Input.action_press("mover_adelante")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("mover_adelante")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var paso := _jug.global_position - antes
	_check(paso.x < -1.5 and absf(paso.z) < 0.5,
			"andando hacia adelante va RECTO a la calle, sin diagonales (dx %.2f, dz %.2f)" % [paso.x, paso.z])
	_check(not otra.esperando_alejarse(), "al alejarse, la puerta vuelve a estar disponible")
	# PRUEBA E (regresión): en la calle, sin nada detrás, la cámara conserva su
	# distancia de siempre (la corrección anti-paredes no la acerca sin motivo).
	var piv_cam := _jug.get_node_or_null("PivoteCamara")
	if piv_cam != null and piv_cam.has_method("distancia_actual"):
		for i in 30:
			await get_tree().process_frame
		var dist := float(piv_cam.call("distancia_actual"))
		_check(dist > 2.3, "fuera de casa la cámara sigue a su distancia normal (%.2f m de 2,6)" % dist)
	_jug.global_position = _puerta.global_position + Vector3(-1.5, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_puerta.puede_usar(), "de vuelta delante de la puerta se puede entrar otra vez")

	# 8b. El BUG de la semilla fija: el portal más cercano da a un edificio vecino
	# (delante hay una pared). La casa NO puede quedarse con ese: tiene que elegir
	# el más cercano de los que se pueden pisar.
	var muro := StaticBody3D.new()
	muro.collision_layer = 1
	var forma_muro := CollisionShape3D.new()
	var caja_muro := BoxShape3D.new()
	caja_muro.size = Vector3(4.0, 3.0, 4.0)
	forma_muro.shape = caja_muro
	muro.add_child(forma_muro)
	muro.position = Vector3(8.0 - 2.2, 1.5, 0.0)   # tapa el frente del portal 0 (da a -X)
	add_child(muro)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var portal_antes := EstadoCasaLeo.portal_guardado()
	EstadoCasaLeo.olvidar_portal()
	var tapada := PuertaCasaLeo.new()
	tapada.name = "PuertaCasaLeoTapada"
	tapada.ciudad = _ciudad
	add_child(tapada)
	for i in 10:
		await get_tree().physics_frame
	_check(tapada.portal().distance_to(Vector3(30.0, 0.0, 0.0)) < 0.01,
			"con el portal más cercano TAPADO por un edificio, elige el siguiente accesible (%s)" % str(tapada.portal()))
	# Se deja todo como estaba para el resto de la prueba.
	tapada.queue_free()
	muro.queue_free()
	EstadoCasaLeo.olvidar_portal()
	EstadoCasaLeo.guardar_portal(portal_antes)
	await get_tree().physics_frame

	# 9. La E arranca la carga del INTERIOR de verdad: se comprueba el destino que
	# queda puesto (la pantalla de carga es la del juego, la de siempre). Se hace al
	# final a propósito: el cambio de escena se lanza al terminar este fotograma, así
	# que primero se leen el destino y el punto de vuelta (y se imprime el resumen).
	var uso := _puerta.intentar_usar()
	_check(uso, "la E en la puerta arranca la entrada a la casa")
	_check(LoadingScreen.destino == EstadoCasaLeo.CASA,
			"y carga el INTERIOR por la pantalla de carga del juego ('%s')" % LoadingScreen.destino)
	_check(EstadoCasaLeo.hay_vuelta(), "dejando el punto de vuelta ya marcado para el regreso")
	_resumen()


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[puerta-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[puerta-suite] FALLO ", texto)


func _resumen() -> void:
	print("==================== PUERTA CASA: %d OK / %d FALLO ====================" % [_ok, _fallos])


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(400, 1.0, 400)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 4.0, 18.0)
	cam.rotation = Vector3(-0.2, 0.0, 0.0)
	cam.current = true
	add_child(cam)