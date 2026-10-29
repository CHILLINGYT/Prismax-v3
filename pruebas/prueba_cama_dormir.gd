extends Node
## PRUEBA de "dormir en la cama" (casa de Leo → ciudad real), con fin automático.
##   godot --path . res://pruebas/prueba_cama_dormir.tscn   (con timeout externo)

const CASA := "res://mundo/casa_leo/casa_leo.tscn"
const CFG := "user://ajustes_graficos.cfg"
var _ok := 0
var _fallos := 0
var _copia := PackedByteArray()


func _ready() -> void:
	call_deferred("_correr")


func _correr() -> void:
	_copia = FileAccess.get_file_as_bytes(CFG) if FileAccess.file_exists(CFG) else PackedByteArray()
	AjustesGraficos.poner_modo_ambiente(0)
	var vieja := get_tree().current_scene
	reparent(get_tree().root)
	var casa := (load(CASA) as PackedScene).instantiate()
	get_tree().root.add_child(casa)
	get_tree().current_scene = casa
	if vieja != null and vieja != self:
		vieja.queue_free()
	await _fisica(20)
	var cama := casa.get_node_or_null("CamaDormir") as CamaDormir
	var ciclo := get_tree().get_first_node_in_group("ciclo_dia_noche")
	var jug := casa.call("jugador") as Node3D
	_check(cama != null and ciclo != null and jug != null, "hay cama, ciclo y jugador en la casa")
	_check(bool(ciclo.call("es_de_dia")), "la casa arranca de DÍA")
	# Lejos de la cama: sin aviso.
	_check(String(jug.call("texto_interaccion")) != CamaDormir.TEXTO, "en el pasillo NO se ofrece dormir")
	# A los pies de la cama (lado norte = −Z local), mirando a la cama.
	var pie := cama.to_global(Vector3(0.0, 0.05, -cama.semiejes.y - 0.45))
	jug.call("colocar_en", pie, cama.global_position)
	await _fisica(10)
	await _foto_cama(jug, cama)
	_check(String(jug.call("texto_interaccion")) == CamaDormir.TEXTO,
			"junto a la cama aparece el aviso ('%s')" % String(jug.call("texto_interaccion")))
	# --- 1) Dormir de día → noche, intentando interrumpir -------------------
	var pos0 := jug.global_position
	await _pulsar("interactuar")
	await _fisica(3)
	_check(cama.durmiendo(), "al pulsar E empieza a dormir")
	_check(jug.process_mode == Node.PROCESS_MODE_DISABLED, "durante el sueño Leo queda congelado")
	Input.action_press("mover_adelante")
	await _pulsar("atacar")
	await _pulsar("interactuar")
	await _esperar(0.9)
	await _foto("cama_durmiendo")
	await _esperar_despertar(cama)
	Input.action_release("mover_adelante")
	_check(cama.veces_dormido() == 1, "la E repetida durante el sueño no lo duerme dos veces (%d)" % cama.veces_dormido())
	_check(jug.global_position.distance_to(pos0) < 0.05, "moverse/atacar durante el sueño no hace nada (%.3f m)" % jug.global_position.distance_to(pos0))
	_check(jug.process_mode != Node.PROCESS_MODE_DISABLED, "al despertar Leo vuelve a responder")
	_check(not bool(ciclo.call("es_de_dia")), "dormir de día → es de NOCHE (fase %.3f)" % float(ciclo.call("fase_actual")))
	_check(get_tree().root.find_children("SuenoLeo", "", true, false).is_empty(), "la capa negra se retira sola")
	_check(not cama.en_rango(), "justo al despertar la cama no se ofrece (bloqueo breve)")
	# --- 2) Dormir de noche → mañana, en modo PS2 ---------------------------
	AjustesGraficos.poner_modo_ambiente(1)
	await _esperar_cama_libre(cama)
	_check(cama.en_rango(), "pasado el bloqueo se puede volver a dormir")
	await _pulsar("interactuar")
	await _esperar_despertar(cama)
	_check(bool(ciclo.call("es_de_dia")), "PS2: dormir de noche → es de DÍA (fase %.3f)" % float(ciclo.call("fase_actual")))
	# --- 3) Otra vez (de día → noche) y SALIR a la ciudad --------------------
	var libre2 := await _esperar_cama_libre(cama)
	_check(libre2 > 0.0 and libre2 < 2.0, "tras despertar la cama vuelve a ofrecerse en %.2f s reales" % libre2)
	await _pulsar("interactuar")
	await _esperar_despertar(cama)
	_check(not bool(ciclo.call("es_de_dia")), "tercera vez: de nuevo de NOCHE")
	AjustesGraficos.poner_modo_ambiente(0)
	var fase_casa := float(ciclo.call("fase_actual"))
	var salida := casa.call("salida") as SalidaInterior
	EstadoCasaLeo.marcar_vuelta(Vector3(0, 1, 4), Vector3.FORWARD)
	EstadoCasaLeo.salir(salida)
	# Espera a la ciudad real (pantalla de carga de por medio).
	var mundo: Node = null
	for i in 3000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path == EstadoCasaLeo.MUNDO:
			mundo = cs
			break
	_check(mundo != null, "se sale a la ciudad")
	await _fisica(30)
	var ciclo2 := get_tree().get_first_node_in_group("ciclo_dia_noche")
	_check(ciclo2 != null and absf(float(ciclo2.call("fase_actual")) - fase_casa) < 0.02,
			"la ciudad continúa la hora de la casa (%.3f ≈ %.3f)" % [float(ciclo2.call("fase_actual")) if ciclo2 else -1.0, fase_casa])
	_check(ciclo2 != null and not bool(ciclo2.call("es_de_dia")), "en la ciudad es de NOCHE")
	var sol := ciclo2.get("sol") as DirectionalLight3D if ciclo2 else null
	_check(sol != null and sol.light_energy < 0.01, "el sol está apagado (energía %.2f)" % (sol.light_energy if sol else -1.0))
	var far := mundo.find_child("Farolas", true, false) if mundo else null
	var resumen := String(far.call("resumen")) if far != null and far.has_method("resumen") else "sin farolas"
	_check("encendidas=true" in resumen, "las farolas están encendidas (%s)" % resumen)
	await _foto("cama_salida_noche")
	print("==================== CAMA DORMIR: %d OK / %d FALLO ====================" % [_ok, _fallos])
	_restaurar()
	get_tree().quit()


## Espera (reloj REAL, tope 4 s) a que la cama vuelva a ofrecerse; devuelve los
## segundos reales que tardó (−1 si no).
func _esperar_cama_libre(cama: CamaDormir) -> float:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		if cama.en_rango():
			return float(Time.get_ticks_msec() - t0) / 1000.0
	return -1.0


func _esperar_despertar(cama: CamaDormir) -> void:
	for i in 600:
		await get_tree().process_frame
		if not cama.durmiendo():
			return


func _pulsar(accion: String) -> void:
	Input.action_press(accion)
	await _fisica(2)
	Input.action_release(accion)


func _fisica(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _foto(nombre: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://pruebas/capturas/%s.png" % nombre))


## Vista de la cama desde los pies, alta, para compararla con la foto.
func _foto_cama(jug: Node3D, cama: CamaDormir) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	cam.look_at_from_position(cama.to_global(Vector3(0.3, 2.1, -cama.semiejes.y - 1.1)),
			cama.to_global(Vector3(0.0, 0.5, 0.4)))
	cam.current = true
	await _fisica(4)
	await _foto("cama_vista")
	cam.queue_free()
	await _fisica(2)


func _restaurar() -> void:
	if _copia.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(_copia)
		f.close()


func _check(c: bool, t: String) -> void:
	if c:
		_ok += 1
		print("[cama] OK   ", t)
	else:
		_fallos += 1
		print("[cama] FALLO ", t)
