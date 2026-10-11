extends SceneTree

## Prueba headless del efecto de pantalla de daño y rotura de escudo
## (personaje/base/efectos/efecto_danio_pantalla.gd + shader efecto_danio.gdshader).
##
## Comprueba: pulso al recibir daño real, rotura de escudo SOLO en la rotura
## real y una sola vez, golpes con el escudo ya roto sin re-rotura, impactos
## seguidos sin parpadeos ni capas duplicadas, expiración del modo rotura (la
## regeneración no lo deja atascado) y el mismo efecto compartido en otra
## transformación. También: la viñeta cubre la ventana, no bloquea el ratón y
## queda por debajo del HUD.
##
## Ejecutar: godot --headless -s "res://ziba/test/prueba_efecto_danio.gd"

const ESCENA_PARTIDA := "res://ziba/escenas/ziba_prototipo.tscn"

var _fallos: int = 0
var _roturas: int = 0


func _initialize() -> void:
	await _run()
	if _fallos == 0:
		print("=== RESULTADO: TODAS LAS PRUEBAS PASAN ===")
		quit(0)
	else:
		print("=== RESULTADO: ", _fallos, " FALLOS ===")
		quit(1)


func _check(condicion: bool, mensaje: String) -> void:
	if condicion:
		print("  PASA:  ", mensaje)
	else:
		_fallos += 1
		print("  FALLA: ", mensaje)


func _run() -> void:
	var partida: Node = (load(ESCENA_PARTIDA) as PackedScene).instantiate()
	get_root().add_child(partida)
	for i in 2400:
		await process_frame
		if partida.find_child("CiudadGenerada", true, false) != null:
			break
	var jugador: CharacterBody3D = partida.get_node_or_null("Jugador") as CharacterBody3D
	if jugador == null:
		_check(false, "hay jugador en la partida")
		partida.queue_free()
		return
	var stats = jugador.estadisticas
	var efecto = jugador.get_node_or_null("EfectoDanioPantalla")

	print("--- 0) El overlay existe, está bien colocado y no bloquea nada")
	_check(efecto != null, "el efecto está instalado en el personaje")
	if efecto == null:
		partida.queue_free()
		return
	var vineta := efecto.get_node_or_null("Vineta") as ColorRect
	_check(vineta != null and vineta.anchor_right == 1.0 and vineta.anchor_bottom == 1.0,
			"la viñeta cubre toda la ventana (se adapta a cualquier resolución)")
	_check(vineta != null and vineta.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"la viñeta no captura el ratón (no bloquea los controles)")
	_check(efecto.layer < 10, "el efecto queda por debajo del HUD (layer %d < 10)" % efecto.layer)
	stats.escudo_roto.connect(func() -> void: _roturas += 1)

	print("--- 1) Daño normal: pulso visible sin rotura")
	stats.recibir_danio(25.0)
	await _esperar_frames(2)
	_check(_roturas == 0, "un golpe que no agota el escudo NO emite escudo_roto")
	_check(efecto._intensidad > 0.2, "el pulso de daño sube (intensidad %.2f)" % efecto._intensidad)
	await create_timer(1.6).timeout
	_check(efecto._intensidad < 0.05, "el pulso se desvanece solo sin intervención (%.2f)" % efecto._intensidad)

	print("--- 2) Rotura real: una sola vez, modo rojo con prioridad")
	# La resistencia quedó en 80. Tres golpes más (20 c/u) la dejan en 20: no rompen.
	for i in 3:
		stats.recibir_danio(25.0)
		await _esperar_frames(2)
	_check(_roturas == 0, "tres golpes más por encima de cero siguen sin ser rotura (resistencia %.0f)" % stats.resistencia)
	stats.recibir_danio(25.0)  # 20 -> 0: rotura real
	await _esperar_frames(2)
	_check(_roturas == 1, "el golpe que agota el escudo emite escudo_roto UNA vez (emitidas: %d)" % _roturas)
	_check(efecto._t_rotura > 0.0, "el efecto entra en modo rotura")
	var mezcla_rotura: float = efecto._material.get_shader_parameter("mezcla_azul")
	_check(mezcla_rotura < 0.2, "en la rotura la mezcla es predominantemente roja (azul %.2f)" % mezcla_rotura)
	stats.recibir_danio(25.0)
	stats.recibir_danio(25.0)
	await _esperar_frames(2)
	_check(_roturas == 1, "golpes con el escudo ya roto no repiten la rotura (emitidas: %d)" % _roturas)
	_check(_contar_capas(jugador) == 1, "exactamente 1 capa de efecto: nunca se duplica (hay %d)" % _contar_capas(jugador))

	print("--- 3) Impactos seguidos: actualización fluida, sin reinicios")
	var antes: float = efecto._intensidad
	stats.recibir_danio(5.0)
	await _esperar_frames(1)
	_check(efecto._intensidad >= antes - 0.05,
			"un impacto durante el efecto lo mantiene/refuerza (%.2f -> %.2f)" % [antes, efecto._intensidad])
	_check(efecto._t_rotura > 0.0, "la rotura conserva su prioridad con el impacto encima")

	print("--- 4) El modo rotura expira solo y la regeneración no lo atasca")
	await create_timer(2.6).timeout
	_check(efecto._t_rotura <= 0.0, "el intervalo de rotura terminó (no queda permanente)")
	_check(efecto._intensidad < 0.05, "el efecto se apagó solo (%.3f)" % efecto._intensidad)
	await create_timer(6.5).timeout
	_check(stats.resistencia > 0.0, "la resistencia se regeneró (%.0f)" % stats.resistencia)
	_check(efecto._intensidad < 0.05, "la regeneración no dejó el efecto encendido (%.3f)" % efecto._intensidad)
	stats.vida = stats.vida_max  # el test no debe morir por la acumulación de golpes
	stats.recibir_danio(stats.resistencia / 0.8 + 1.0)
	await _esperar_frames(2)
	_check(_roturas == 2, "tras regenerar, una rotura nueva vuelve a emitirse (emitidas: %d)" % _roturas)

	print("--- 5) Otra transformación usa el MISMO efecto (compartido)")
	jugador._on_transformacion_elegida(&"velocista")
	var llego := false
	for i in 1200:
		await physics_frame
		if jugador._id_forma(jugador.forma) == &"velocista":
			llego = true
			break
	_check(llego, "el personaje está en forma velocista")
	await _esperar_frames(40)
	stats.vida = stats.vida_max
	stats.resistencia = stats.resistencia_max
	await create_timer(2.6).timeout  # que expire la rotura anterior antes de medir
	stats.recibir_danio(25.0)
	await _esperar_frames(2)
	_check(efecto._intensidad > 0.2, "en velocista el daño también enciende el pulso (%.2f)" % efecto._intensidad)
	_check(efecto._t_rotura <= 0.0, "y no entra en rotura con un golpe que no agota el escudo")
	stats.recibir_danio(stats.resistencia / 0.8 + 1.0)
	await _esperar_frames(2)
	_check(_roturas == 3, "en velocista la rotura del escudo también se refleja (emitidas: %d)" % _roturas)
	_check(_contar_capas(jugador) == 1, "sigue habiendo una sola capa compartida (hay %d)" % _contar_capas(jugador))

	partida.queue_free()
	await _esperar_frames(3)


func _contar_capas(jugador: Node) -> int:
	var n := 0
	for h in jugador.get_children():
		if h is CanvasLayer and h.name == "EfectoDanioPantalla":
			n += 1
	return n


func _esperar_frames(n: int) -> void:
	for i in n:
		await physics_frame