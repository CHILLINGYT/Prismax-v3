extends Node
## VISTA (no suite) en el MUNDO REAL (ziba_prototipo, como en el juego):
##   1. al empezar: cartel del objetivo (estilo nuevo) → mundo_inicio.png
##   2. Leo delante de la puerta de su casa: aviso con keycap → mundo_puerta.png
##   3. la puerta vista desde la calle a 12 m (marcador de la puerta) → mundo_puerta_lejos.png
##   4. lo mismo de NOCHE → mundo_puerta_noche.png
## Se ejecuta con el binario: godot --path . res://pruebas/vista_hud_mundo.tscn

const MUNDO := "res://mundo/escena/ziba_prototipo.tscn"
const CARPETA := "res://pruebas/capturas"


func _ready() -> void:
	call_deferred("_arrancar")


func _arrancar() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	EstadoCasaLeo.olvidar_portal()
	var vieja := get_tree().current_scene
	reparent(get_tree().root)
	var mundo := (load(MUNDO) as PackedScene).instantiate()
	get_tree().root.add_child(mundo)
	get_tree().current_scene = mundo
	if vieja != null and vieja != self:
		vieja.queue_free()
	var puerta := mundo.get_node("PuertaCasaLeo") as PuertaCasaLeo
	for i in 3000:
		await get_tree().physics_frame
		if puerta.portal() != Vector3.ZERO:
			break
	var ciclo := get_tree().get_first_node_in_group("ciclo_dia_noche")
	if ciclo != null and ciclo.has_method("poner_fase") and ciclo.has_method("fase_dia_pleno"):
		ciclo.call("poner_fase", ciclo.call("fase_dia_pleno"))
	await _esperar(90)
	await _foto("mundo_inicio")
	var jug: Node3D = null
	for n in get_tree().get_nodes_in_group("player"):
		if n.has_method("colocar_en"):
			jug = n as Node3D
			break
	var afuera := (puerta.global_position - puerta.portal())
	afuera.y = 0.0
	afuera = afuera.normalized()
	# Delante de la puerta, mirándola: el aviso con keycap.
	jug.call("colocar_en", puerta.global_position + afuera * 0.4 + Vector3.UP * 0.1, puerta.portal())
	await _esperar(60)
	print("[vista-mundo] texto_interaccion = '%s'" % String(jug.call("texto_interaccion")))
	await _foto("mundo_puerta")
	# Desde la calle, a 12 m, con la cámara mirando la puerta.
	var lateral := afuera.cross(Vector3.UP).normalized()
	jug.call("colocar_en", puerta.global_position + afuera * 12.0 + lateral * 2.0 + Vector3.UP * 0.1, puerta.portal())
	# Cámara fija de calle (la del jugador quedaba detrás de un árbol de la vereda).
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	cam.look_at_from_position(puerta.global_position + afuera * 14.0 - lateral * 4.0 + Vector3.UP * 1.7,
			puerta.global_position + Vector3.UP * 2.2)
	cam.current = true
	await _esperar(60)
	await _foto("mundo_puerta_lejos")
	if ciclo != null and ciclo.has_method("poner_fase"):
		ciclo.call("poner_fase", 0.85)
	await _esperar(60)
	await _foto("mundo_puerta_noche")
	print("[vista-mundo] FIN")
	get_tree().quit()


func _esperar(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [CARPETA, nombre]))
	print("[vista-mundo] %s.png" % nombre)
