extends Node
## PRUEBA corta (headless) del selector "Modo de ambiente":
##  · las dos escenas de menú cargan y tienen su fila;
##  · cambiar desde el menú de pausa / principal cambia AjustesGraficos y el texto;
##  · se GUARDA en user://ajustes_graficos.cfg y se vuelve a LEER al cargar.
## La preferencia real del jugador se copia antes y se restaura al terminar.
##   godot --headless --path . res://pruebas/prueba_menu_ambiente.tscn

const CFG := "user://ajustes_graficos.cfg"
var _ok := 0
var _fallos := 0


func _ready() -> void:
	call_deferred("_correr")


func _correr() -> void:
	var copia := FileAccess.get_file_as_bytes(CFG) if FileAccess.file_exists(CFG) else PackedByteArray()
	var previo: int = AjustesGraficos.modo_ambiente
	AjustesGraficos.poner_modo_ambiente(AjustesGraficos.Ambiente.REALISTA)

	var pausa := (load("res://ui/scenes/PauseMenu.tscn") as PackedScene).instantiate()
	add_child(pausa)
	await get_tree().process_frame
	var valor := pausa.get_node_or_null("%AmbienteValor") as Label
	_check(valor != null, "menú de pausa: existe la fila MODO DE AMBIENTE")
	pausa.call("_on_ambiente_paso", 1)
	await get_tree().process_frame
	_check(AjustesGraficos.es_ps2(), "pausa: la flecha cambia a PS2")
	_check(valor != null and valor.text == "PS2", "pausa: la fila muestra PS2 (%s)" % (valor.text if valor else "-"))
	var cf := ConfigFile.new()
	cf.load(CFG)
	_check(int(cf.get_value("graficos", "modo_ambiente", -1)) == 1, "se guardó en %s" % CFG)
	AjustesGraficos.modo_ambiente = 0
	AjustesGraficos.call("_cargar")
	_check(AjustesGraficos.modo_ambiente == 1, "al cargar la configuración vuelve PS2")
	pausa.call("_on_ambiente_paso", -1)
	_check(not AjustesGraficos.es_ps2() and valor.text == "REALISTA", "pausa: vuelve a REALISTA")
	pausa.queue_free()

	var menu := (load("res://ui/scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var fila := menu.find_child("AmbienteOption", true, false)
	_check(fila != null and int(fila.get("action")) == 11, "menú principal: fila con acción AMBIENTE")
	menu.call("_actualizar_calidad")
	var et := fila.get_node("Label") as Label if fila != null else null
	_check(et != null and et.text == "MODO DE AMBIENTE: REALISTA", "menú principal: texto (%s)" % (et.text if et else "-"))
	AjustesGraficos.pasar_modo_ambiente(1)
	menu.call("_actualizar_calidad")
	_check(et != null and et.text == "MODO DE AMBIENTE: PS2", "menú principal: refleja PS2")
	var calidad := menu.find_child("CalidadOption", true, false)
	_check(calidad != null and int(calidad.get("action")) == 6,
			"la fila CALIDAD conserva su acción (enum ampliado al final)")
	menu.queue_free()

	# Restaurar la preferencia real.
	AjustesGraficos.modo_ambiente = previo
	if copia.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(copia)
		f.close()
	print("==================== MENU AMBIENTE: %d OK / %d FALLO ====================" % [_ok, _fallos])
	get_tree().quit()


func _check(c: bool, t: String) -> void:
	if c:
		_ok += 1
		print("[ambiente-menu] OK   ", t)
	else:
		_fallos += 1
		print("[ambiente-menu] FALLO ", t)
