extends Control
## VISTA (no suite): el HUD rediseñado sobre fondos REALES del juego (una captura
## de día y otra de noche) para juzgar contraste y jerarquía. Usa los componentes
## de verdad (AvisoInteraccion, PanelMision.tscn, JuiceCombate) y una réplica del
## cartel del objetivo con los mismos nodos/variantes que ziba_prototipo.tscn.
## Fotos → res://pruebas/capturas/hud_dia.png y hud_noche.png

const TEMA := preload("res://ui/tema/tema_juego.tres")
const FONDOS := {
	"dia": "res://pruebas/capturas/vehiculo_auto.png",
	"noche": "res://pruebas/capturas/ventana_0_noche.png",
}

var _fondo: TextureRect


func _ready() -> void:
	_fondo = TextureRect.new()
	_fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_fondo)
	# Cartel del objetivo (réplica de la estructura de ziba_prototipo.tscn).
	var capa_cartel := CanvasLayer.new()
	capa_cartel.layer = 70
	add_child(capa_cartel)
	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	margen.theme = TEMA
	margen.add_theme_constant_override("margin_top", 18)
	capa_cartel.add_child(margen)
	var cartel := PanelContainer.new()
	cartel.theme_type_variation = &"HudVelo"
	cartel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cartel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margen.add_child(cartel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	cartel.add_child(col)
	var et := Label.new()
	et.theme_type_variation = &"HudEtiqueta"
	et.text = "OBJETIVO"
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(et)
	var acento := Panel.new()
	acento.theme_type_variation = &"HudAcento"
	acento.custom_minimum_size = Vector2(46, 2)
	acento.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(acento)
	var tx := Label.new()
	tx.theme_type_variation = &"HudObjetivo"
	tx.text = "habla con el hombre en la plaza"
	tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tx)
	# Panel de misión real, forzado visible con un progreso de ejemplo.
	var panel := (load("res://ui/scenes/PanelMision.tscn") as PackedScene).instantiate()
	add_child(panel)
	# Avisos reales (los tres formatos de texto que tiene el juego).
	var capa := CanvasLayer.new()
	capa.layer = 80
	add_child(capa)
	var textos := ["Presiona E para entrar a la casa de Leo", "E — Hablar con Iván",
			"Solo puedes ingresar al agua con el personaje acuatico"]
	var margenes := [132.0, 200.0, 268.0]
	for i in textos.size():
		var a := AvisoInteraccion.new()
		capa.add_child(a)
		a.anclar_abajo_centro(margenes[i])
		a.mostrar(textos[i])
	# Contador de combo real (JuiceCombate sin jugador: sólo su UI).
	var juice := JuiceCombate.new()
	add_child(juice)
	await get_tree().process_frame
	for i in 7:
		juice.call("_sumar_combo")
	await get_tree().create_timer(0.6).timeout
	(panel.get_node("Raiz") as Control).visible = true
	(panel.get_node("Raiz/Panel/Fila/Columna/Estado") as Label).text = "7 / 20"
	for nombre in FONDOS:
		_fondo.texture = load(FONDOS[nombre]) as Texture2D
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://pruebas/capturas/hud_%s.png" % nombre))
		print("[vista-hud] %s → hud_%s.png" % [nombre, nombre])
	print("[vista-hud] FIN")
	get_tree().quit()
