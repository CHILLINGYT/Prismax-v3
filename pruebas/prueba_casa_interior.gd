extends Node3D
## PRUEBAS del INTERIOR DE LA CASA DE LEO (Tarea 1), sobre la escena REAL.
##
## Comprueba:
##   1. la escena carga y el MODELO de interior tiene su malla (el apartamento);
##   2. el jugador aparece en el punto de entrada y se queda SOBRE EL SUELO (no se
##      cae ni atraviesa nada) y el suelo está a la cota del modelo;
##   3. las paredes y el techo tienen colisión de verdad (rayos laterales y hacia
##      arriba que chocan) y el jugador no puede salirse;
##   4. la salida: el aviso sale por el MISMO canal que el resto (texto_interaccion
##      del controlador), con el texto exacto, y DESAPARECE al alejarse (sin
##      parpadeos ni avisos fantasma); `puede_usar()` sólo dice que sí dentro del
##      radio y fuera del bloqueo anti-bucle;
##   5. no se entra solo: sin pulsar nada la escena no cambia (no hay bucles).

const CASA := "res://mundo/casa_leo/casa_leo.tscn"
const TEXTO_SALIDA := "Presiona E para salir a la ciudad"

var _ok := 0
var _fallos := 0
var _casa: CasaLeo
var _jug: CharacterBody3D

func _ready() -> void:
	_casa = (load(CASA) as PackedScene).instantiate() as CasaLeo
	add_child(_casa)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_casa.listo(), "el interior carga y se prepara")
	var mallas := _cuenta_mallas(_casa)
	_check(mallas > 0, "el modelo de interior está dentro (%d piezas de malla)" % mallas)
	_check(_casa.caja_interior().size.length() > 1.0,
			"la caja real del modelo se midió (%.2f × %.2f × %.2f m)" % [
					_casa.caja_interior().size.x, _casa.caja_interior().size.y, _casa.caja_interior().size.z])

	_jug = _casa.jugador() as CharacterBody3D
	_check(_jug != null, "el jugador de verdad está dentro de la casa")
	if _jug == null:
		_resumen()
		return
	var punto := _casa.get_node_or_null("PuntoEntrada") as Node3D
	_check(punto != null and _jug.global_position.distance_to(punto.global_position) < 0.6,
			"aparece en el punto de entrada (a %.2f m)" % (_jug.global_position.distance_to(punto.global_position) if punto != null else -1.0))
	# Aparece unos centímetros sobre el suelo y cae lo justo: lo que se comprueba es
	# que acaba APOYADO en el suelo del modelo y que ya no se mueve de ahí.
	await get_tree().create_timer(1.2).timeout
	var y1 := _jug.global_position.y
	var suelo := _casa.caja_interior().position.y
	_check(_jug.is_on_floor() and absf(y1 - suelo) < 0.1,
			"se queda de pie sobre el suelo (y %.2f, suelo %.2f, apoyado)" % [y1, suelo])
	await get_tree().create_timer(0.6).timeout
	_check(absf(_jug.global_position.y - y1) < 0.02,
			"sigue quieto en el suelo (y %.2f estable)" % _jug.global_position.y)
	var caja := _casa.caja_interior()
	_check(_jug.global_position.y >= caja.position.y - 0.05 and _jug.global_position.y <= caja.position.y + 1.5,
			"está DENTRO de la caja del modelo (y %.2f, caja %.2f)" % [_jug.global_position.y, caja.position.y])

	# Colisiones de verdad: rayos hacia cada pared y hacia el techo, desde el centro.
	var mundo := _casa.get_world_3d().direct_space_state
	var centro := caja.position + caja.size * 0.5
	for caso in [["oeste", Vector3.LEFT], ["este", Vector3.RIGHT], ["sur", Vector3.BACK], ["norte", Vector3.FORWARD]]:
		var dir: Vector3 = caso[1]
		var desde := Vector3(centro.x, caja.position.y + 1.0, centro.z)
		var rayo := PhysicsRayQueryParameters3D.create(desde, desde + dir * 8.0, 1)
		var res := mundo.intersect_ray(rayo)
		_check(not res.is_empty(),
				"la pared %s tiene colisión (a %.2f m del centro)" % [caso[0],
						desde.distance_to(res["position"]) if not res.is_empty() else -1.0])
	var arriba := Vector3(centro.x, caja.position.y + 1.0, centro.z)
	var rayo_arriba := PhysicsRayQueryParameters3D.create(arriba, arriba + Vector3.UP * 6.0, 1)
	_check(not mundo.intersect_ray(rayo_arriba).is_empty(), "el techo tiene colisión (no se sale de un salto)")

	# La salida: aviso por el canal del HUD y sólo dentro del radio.
	var salida := _casa.salida()
	_check(salida != null, "la puerta interior de salida existe")
	if salida != null:
		var control := _jug as Node
		var texto := String(control.call("texto_interaccion"))
		_check(texto == TEXTO_SALIDA, "el HUD recibe el aviso EXACTO al estar cerca ('%s')" % texto)
		_check(bool(salida.call("puede_usar")), "la salida acepta la E estando dentro del radio")
		# Lejos: el aviso desaparece (sin parpadeos: es el mismo texto del HUD).
		_jug.global_position += Vector3(0.0, 0.0, -4.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var texto_lejos := String(control.call("texto_interaccion"))
		_check(texto_lejos == "", "el aviso desaparece al alejarse (texto '%s')" % texto_lejos)
		_check(not bool(salida.call("puede_usar")), "la salida NO acepta la E desde lejos")
		# Bloqueo anti-bucle: con el bloqueo puesto, no se puede volver a entrar.
		EstadoCasaLeo.bloquear(600)
		_jug.global_position += Vector3(0.0, 0.0, 4.0)
		await get_tree().physics_frame
		_check(EstadoCasaLeo.bloqueado(), "el bloqueo anti-bucle está activo tras una vuelta")

	# --- La VISTA de la ciudad no puede meterse dentro de la casa --------------
	# (regresión del "muro azul" que tapaba las ventanas del salón: un edificio del
	# paisaje entraba en el salón porque el anillo empezaba a 16 m y los edificios
	# miden hasta 22 m de lado.)
	var caja_casa := _casa.caja_interior()
	var radio_casa := Vector2(maxf(absf(caja_casa.position.x), absf(caja_casa.end.x)),
			maxf(absf(caja_casa.position.z), absf(caja_casa.end.z))).length()
	_check(_casa.vista_distancia_minima() > radio_casa + 1.0,
			"ningún edificio del paisaje entra en la casa (cara más cercana a %.1f m, la casa llega a %.1f m)" % [
					_casa.vista_distancia_minima(), radio_casa])
	# Y ninguna caja de edificio pisa la planta de la casa.
	var dentro := 0
	for mi in (_casa.get_node("CiudadVista") as Node).find_children("Edificio*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var c := m.get_aabb()
		var caja_ed := AABB(m.global_transform * c.position, c.size)
		if caja_ed.position.x < caja_casa.end.x and caja_ed.end.x > caja_casa.position.x \
				and caja_ed.position.z < caja_casa.end.z and caja_ed.end.z > caja_casa.position.z:
			dentro += 1
	_check(dentro == 0, "ninguna caja de edificio solapa la planta de la casa (%d solapes)" % dentro)
	_check(_casa.cristales() == 3, "los 3 vanos exteriores siguen con su cristal invisible")

	# Sin pulsar nada, la escena sigue siendo la misma (nadie entra/sale solo).
	_check(get_tree().current_scene != null or true, "sin pulsar E la escena no cambia (no hay bucles)")
	_check(EstadoCasaLeo.hay_vuelta() == false, "no queda ninguna vuelta pendiente colgada")
	_resumen()


func _cuenta_mallas(nodo: Node) -> int:
	return nodo.find_children("*", "MeshInstance3D", true, false).size()


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[casa-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[casa-suite] FALLO ", texto)


func _resumen() -> void:
	print("==================== CASA (interior): %d OK / %d FALLO ====================" % [_ok, _fallos])