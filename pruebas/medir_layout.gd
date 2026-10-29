extends Node
## Medición de la maquetación de los paneles de ajustes (P10-B2), headless.
## Imprime los rectángulos de los contenedores clave de AMBOS menús para
## diagnosticar el desalineamiento sin depender de estimaciones visuales.

func _ready() -> void:
	await _medir_pausa()
	await _medir_menu_principal()
	get_tree().quit()


func _medir_pausa() -> void:
	var pm := (load("res://ui/scenes/PauseMenu.tscn") as PackedScene).instantiate()
	add_child(pm)
	await get_tree().process_frame
	pm.call("abrir")
	var cfg := pm.get_node("Root/MenuPanel/Content/OptionsList/ConfigItems") as VBoxContainer
	pm.call("_toggle_categoria", 2, cfg.get_child(2) as MenuOption)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[MED-PAUSA] viewport=", get_viewport().get_visible_rect().size)
	_volcar(pm, [
		"Root/ConfigPanel",
		"Root/ConfigPanel/PanelBG",
		"Root/ConfigPanel/ConfigContent",
		"Root/ConfigPanel/ConfigContent/CalidadFila",
		"Root/ConfigPanel/ConfigContent/CalidadFila/Etiqueta",
		"Root/ConfigPanel/ConfigContent/DistanciaFila",
		"Root/ConfigPanel/ConfigContent/OptimizacionFila",
		"Root/ConfigPanel/ConfigContent/OptimizacionFila/Etiqueta"])
	pm.queue_free()
	await get_tree().process_frame


func _medir_menu_principal() -> void:
	var mm := (load("res://ui/scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(mm)
	await get_tree().process_frame
	mm.call("_entrar_ajustes")
	var cfg := mm.get_node("MenuPanel/Content/OptionsList/ConfigItems") as VBoxContainer
	mm.call("_toggle_categoria", 0, cfg.get_child(0) as MenuOption)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[MED-MENU] viewport=", get_viewport().get_visible_rect().size)
	_volcar(mm, [
		"ConfigPanel",
		"ConfigPanel/PanelBG",
		"ConfigPanel/ConfigContent",
		"ConfigPanel/ConfigContent/SeccionGraficos",
		"ConfigPanel/ConfigContent/SeccionGraficos/CalidadOption",
		"ConfigPanel/ConfigContent/SeccionGraficos/CalidadOption/Label"])
	mm.queue_free()


func _volcar(nodo: Node, rutas: Array) -> void:
	for ruta: String in rutas:
		var n := nodo.get_node_or_null(ruta) as Control
		if n == null:
			print("[MED] ", ruta, " (no existe)")
			continue
		var g := n.get_global_rect()
		print("[MED] ", ruta, " pos=", g.position, " size=", g.size,
				" der=", g.position.x + g.size.x, " min=", n.get_combined_minimum_size())