extends Node3D

# Suite automática (se ejecuta como ESCENA) de la MUERTE de la forma VUELO (águila)
# con el sistema REAL de muerte del ControladorLeo:
#   1. al transformar a águila, su reproductor recibe `muerte` y `morido`
#      RETARGETEADOS (Mixamo -> rig del maniquí, por el mapa de huesos);
#   2. la muerte se dispara UNA vez en la condición real (vida y escudo agotados);
#   3. `muerte` se reproduce COMPLETA (no se corta a mitad) sobre el cuerpo;
#   4. al terminar pasa a `morido`, que queda EN BUCLE con el cuerpo en el suelo
#      (la cadera baja de ~0.9 m a la altura del cadáver);
#   5. la entrada del jugador (movimiento, ataque, C de volar) no interrumpe la
#      secuencia ni mueve el cuerpo;
#   6. muriendo EN EL AIRE, el cuerpo desciende con física hasta el suelo;
#   7. la pantalla final existe y el fundido sigue su curso (sin tocarlo).
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta como ESCENA:
#   godot --headless --path . res://pruebas/prueba_muerte_vuelo.tscn
# También se puede abrir y ejecutar desde el editor (F6).

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const FORMA_VUELO := 5
const ESC_MUERTE := "res://personaje/transformaciones/Muerte.fbx"

var _pasadas := 0
var _falladas := 0

func _ready() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _esperar_seg(s: float) -> void:
	await _esperar(int(ceil(s * 60.0)))

func _crear_jugador(pos: Vector3, nombre: String) -> ControladorLeo:
	var j := JUGADOR.instantiate() as ControladorLeo
	j.name = nombre
	j.position = pos
	add_child(j)
	return j

func _cambiar_forma(jug: ControladorLeo, id: StringName, forma: int) -> bool:
	jug._on_transformacion_elegida(id)
	var t := 0
	while (int(jug.forma) != forma or jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(jug.forma) == forma

func _vuelo_de(jug: ControladorLeo) -> Node3D:
	return jug.get_node_or_null("Vuelo") as Node3D

func _anim_muerte_de(jug: ControladorLeo) -> AnimationPlayer:
	return jug.call("_animador_forma", _vuelo_de(jug)) as AnimationPlayer

## Altura MUNDIAL de la cadera según la pose actual del esqueleto del águila.
func _altura_cadera(jug: ControladorLeo) -> float:
	var sk := jug.call("_esqueleto_de", _vuelo_de(jug)) as Skeleton3D
	if sk == null:
		return -1.0
	var i := sk.find_bone("Hips")
	if i < 0:
		return -1.0
	return (sk.global_transform * sk.get_bone_global_pose(i).origin).y

func _correr() -> void:
	print("=== PRUEBA: muerte del personaje VUELO (águila) ===")

	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(200.0, 1.0, 200.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	var jug := _crear_jugador(Vector3(0.0, 0.1, 0.0), "JugadorSuelo")
	var stats := jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar(20)
	if stats == null:
		_check("jugador y estadísticas listos", false)
		_resumen()
		return
	_check("jugador y estadísticas listos", true)

	# ------------------------------------------------- 1. transformar a águila
	# Vuelo está BLOQUEADO hasta completar la misión de Iván: se completa para poder
	# probar aquí la muerte del águila (el bloqueo no es objeto de esta suite).
	Misiones.marcar_completada(Misiones.MISION_PROFUGOS)
	var ok := await _cambiar_forma(jug, &"aguila", FORMA_VUELO)
	_check("1. La transformación a águila entra", ok, "forma=%d" % int(jug.forma))
	var anim := _anim_muerte_de(jug)
	_check("1. El águila tiene reproductor para la muerte", anim != null)

	# ------------------------------------------------- 2. condición real
	stats.recibir_danio(9999.0)
	await _esperar(4)
	_check("2. La muerte se dispara con vida y escudo agotados",
			int(jug._muerte_estado) == 1, "estado=%d" % int(jug._muerte_estado))

	if anim == null:
		_resumen()
		return

	# ------------------------------------- 3. `muerte` presente y REPRODUCIÉNDOSE
	var hay_muerte := anim.has_animation(&"muerte")
	var hay_morido := anim.has_animation(&"morido")
	var pistas := 0
	if hay_muerte:
		pistas = anim.get_animation(&"muerte").get_track_count()
	_check("3. El clip `muerte` fue RETARGETEADO al rig del águila",
			hay_muerte and pistas >= 40, "pistas=%d" % pistas)
	_check("3. El clip `morido` fue retargeteado al rig del águila", hay_morido)
	_check("3. `muerte` se está reproduciendo sobre el modelo del águila",
			hay_muerte and anim.current_animation == &"muerte" and anim.is_playing(),
			"clip=%s" % String(anim.current_animation))

	# La cadera arranca arriba (de pie) y debe caer con el clip.
	var cadera0 := _altura_cadera(jug)
	await _esperar_seg(1.0)
	_check("3. `muerte` sigue en curso 1 s después (no se corta a mitad)",
			int(jug._muerte_estado) == 1 and anim.current_animation == &"muerte",
			"clip=%s" % String(anim.current_animation))

	# ---------------------- 5. la entrada NO interrumpe la secuencia
	var pos_antes := _vuelo_de(jug).global_position
	Input.action_press(&"saltar")
	Input.action_press(&"atacar")
	Input.action_press(&"toggle_flight")
	await _esperar_seg(0.6)
	Input.action_release(&"saltar")
	Input.action_release(&"atacar")
	Input.action_release(&"toggle_flight")
	_check("5. Ataque/salto/volar durante la muerte no cambian la secuencia",
			int(jug._muerte_estado) == 1 and anim.current_animation == &"muerte")
	_check("5. El cuerpo no se mueve durante la secuencia",
			_vuelo_de(jug).global_position.distance_to(pos_antes) < 0.35,
			"delta=%.2f" % _vuelo_de(jug).global_position.distance_to(pos_antes))

	# ------------------------------------- 4. paso a `morido` (en bucle)
	var paso := false
	var t := 0.0
	while t < 5.0 and not paso:
		await _esperar_seg(0.25)
		t += 0.25
		paso = anim.current_animation == &"morido"
	_check("4. Al terminar `muerte` pasa a `morido`", paso, "t=%.2fs" % t)
	var cadera_fin := _altura_cadera(jug)
	_check("4. El cadáver queda EN EL SUELO (cadera de pie ~0.9 m -> suelo)",
			cadera_fin > 0.0 and cadera_fin < 0.45,
			"cadera %.2f -> %.2f" % [cadera0, cadera_fin])
	_check("4. `morido` está EN BUCLE (loop lineal)",
			anim.get_animation(&"morido").loop_mode == Animation.LOOP_LINEAR)
	# Sigue en bucle: 1.5 s después, todavía `morido`, con el cuerpo abajo.
	await _esperar_seg(1.5)
	_check("4. `morido` sigue en bucle indefinidamente",
			anim.current_animation == &"morido" and anim.is_playing(),
			"clip=%s" % String(anim.current_animation))
	_check("4. El cadáver sigue en el suelo tras el bucle",
			absf(_altura_cadera(jug) - cadera_fin) < 0.1,
			"cadera=%.2f" % _altura_cadera(jug))

	# ------------------------------------- 7. pantalla final en curso
	var pantalla: Variant = jug.get("_pantalla_muerte")
	_check("7. La pantalla final de muerte existe (fundido en curso)",
			pantalla != null and is_instance_valid(pantalla))

	# --------------------------- 6. muerte EN EL AIRE: el cuerpo baja al suelo
	var jug2 := _crear_jugador(Vector3(40.0, 0.1, 0.0), "JugadorAire")
	var stats2 := jug2.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar(20)
	var ok2 := await _cambiar_forma(jug2, &"aguila", FORMA_VUELO)
	_check("6. El segundo jugador también se transforma", ok2)
	var cuerpo2 := _vuelo_de(jug2)
	# Se aparca a 8 m de altura (como muriendo en pleno vuelo).
	cuerpo2.set_physics_process(false)
	cuerpo2.global_position = jug2.global_position + Vector3.UP * 8.0
	var y0 := cuerpo2.global_position.y
	stats2.recibir_danio(9999.0)
	await _esperar(6)
	var bajo := false
	var t2 := 0.0
	while t2 < 4.0 and not bajo:
		await _esperar_seg(0.25)
		t2 += 0.25
		bajo = cuerpo2.global_position.y < 0.9
	var y1 := cuerpo2.global_position.y
	_check("6. Muriendo en el aire el cuerpo DESCIENDE hasta el suelo",
			bajo, "y %.1f -> %.2f (%.1fs)" % [y0, y1, t2])
	var paso2 := false
	var t3 := 0.0
	while t3 < 4.0 and not paso2:
		await _esperar_seg(0.25)
		t3 += 0.25
		paso2 = _anim_muerte_de(jug2).current_animation == &"morido"
	_check("6. Ya en el suelo, la secuencia sigue hasta `morido`",
			paso2, "clip=%s (%.1fs)" % [String(_anim_muerte_de(jug2).current_animation), t3])

	_resumen()

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")