extends Node
## Arnés de captura/inspección del menú de pausa (P10-B2). Instancia SOLO el
## PauseMenu (sin cargar el mundo) y abre CONFIGURACIÓN -> GRÁFICOS para poder
## revisar la maquetación del panel negro. No toca nada del juego.

func _ready() -> void:
	var pm := (load("res://ui/scenes/PauseMenu.tscn") as PackedScene).instantiate()
	add_child(pm)
	await get_tree().process_frame
	await get_tree().process_frame
	pm.call("abrir")
	var cfg := pm.get_node("Root/MenuPanel/Content/OptionsList/ConfigItems") as VBoxContainer
	var graf := cfg.get_child(2) as MenuOption
	pm.call("_toggle_categoria", 2, graf)
	await get_tree().process_frame
	await get_tree().process_frame
	_medir(pm)


func _medir(pm: Node) -> void:
	var vp := get_viewport().get_visible_rect().size
	print("[MED] viewport=", vp)
	for ruta: String in [
			"Root/ConfigPanel", "Root/ConfigPanel/PanelBG",
			"Root/ConfigPanel/ConfigScroll",
			"Root/ConfigPanel/ConfigScroll/ConfigContent",
			"Root/ConfigPanel/ConfigScroll/ConfigContent/CalidadFila",
			"Root/ConfigPanel/ConfigScroll/ConfigContent/CalidadFila/Etiqueta",
			"Root/ConfigPanel/ConfigScroll/ConfigContent/CalidadFila/CalidadDer",
			"Root/ConfigPanel/ConfigScroll/ConfigContent/DistanciaFila",
			"Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionFila",
			"Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionDependientes"]:
		var n := pm.get_node_or_null(ruta) as Control
		if n == null:
			print("[MED] ", ruta, " = (no existe)")
			continue
		var g := n.get_global_rect()
		print("[MED] ", ruta, " pos=", g.position, " size=", g.size,
				" (der=", g.position.x + g.size.x, ", abajo=", g.position.y + g.size.y, ")")