extends Node

## Banco enfocado: monta SÓLO el globo de diálogo (sin ciudad), compila el .dialogue con
## el compilador del addon y prueba tres formas de inyectar el clic hasta que el botón
## «Entendido» lo reciba. Registra también los textos de los cuatro mensajes.

const RUTA_DIALOGO := "res://NPCs/Dialogues/ivan.dialogue"
const RUTA_SCENE := "res://ui/scenes/DialogueBalloon.tscn"
const LOG := "res://.backup_dialogo_ivan/log_globo.txt"

var _f: FileAccess = null
var _globo: Node = null


func _ready() -> void:
	_f = FileAccess.open(LOG, FileAccess.WRITE)
	var texto := FileAccess.get_file_as_string(RUTA_DIALOGO)
	var res: DMCompilerResult = DMCompiler.compile_string(texto, RUTA_DIALOGO)
	_log("compilación del .dialogue: %d error(es) %s" % [res.errors.size(), str(res.errors)])
	_log("cues: %s | primer cue: %s | personajes: %s" % [str(res.cues.keys()), res.first_cue, str(res.character_names)])
	var rec := DialogueResource.new()
	rec.using_states = res.using_states
	rec.cues = res.cues
	rec.first_cue = res.first_cue
	rec.character_names = res.character_names
	rec.lines = res.lines
	_globo = (load(RUTA_SCENE) as PackedScene).instantiate()
	add_child(_globo)
	await _frames(2)
	_globo.start(rec, "inicio", [])
	await _frames(3)
	_log("mensaje 1: \"%s\" | nombre \"%s\"" % [_texto(), _nombre()])
	for i in 3:
		await _clic_panel()
		_log("mensaje %d: \"%s\" | botón visible %s" % [i + 2, _texto(), str(_boton().visible)])
	var b := _boton()
	var rect := b.get_global_rect()
	var etiqueta := _globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Texto") as Control
	var marco := _globo.get_node("Catcher/PanelInferior/Marco") as Control
	_log("rect botón   %s -> centro %s" % [str(rect), str(rect.get_center())])
	_log("rect etiqueta %s (contiene el centro del botón: %s)" % [
			str(etiqueta.get_global_rect()), str(etiqueta.get_global_rect().has_point(rect.get_center()))])
	_log("rect marco   %s | tamaño de ventana %s | tamaño del viewport %s" % [
			str(marco.get_global_rect()), str(DisplayServer.window_get_size()), str(get_viewport().get_visible_rect().size)])
	# Tres formas de inyectar el clic sobre el botón.
	for modo in [1, 2, 3]:
		var disparos := [0]
		b.pressed.connect(func() -> void: disparos[0] += 1)
		await _clic(rect.get_center(), modo)
		_log("modo %d: señal pressed = %s | globo sigue = %s" % [
				modo, str(disparos[0] > 0), str(is_instance_valid(_globo))])
		if disparos[0] > 0:
			break
	if _f != null:
		_f.close()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _texto() -> String:
	return (_globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Texto") as RichTextLabel).text

func _nombre() -> String:
	return (_globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Nombre") as RichTextLabel).text

func _boton() -> Button:
	return _globo.get_node("Catcher/PanelInferior/Marco/Margen/Columna/Pie/Entendido") as Button

func _clic_panel() -> void:
	var marco := _globo.get_node("Catcher/PanelInferior/Marco") as Control
	await _clic(marco.get_global_rect().get_center(), 1)

func _clic(pos: Vector2, modo: int) -> void:
	for pulsado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pulsado else 0
		ev.pressed = pulsado
		ev.position = pos
		ev.global_position = pos
		match modo:
			1:
				Input.parse_input_event(ev)
			2:
				get_viewport().push_input(ev)
			3:
				get_viewport().push_input(ev, true)
		await _frames(2)

func _log(t: String) -> void:
	print(t)
	if _f != null:
		_f.store_line(t)
		_f.flush()