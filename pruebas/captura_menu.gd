extends Node
## Arnés de captura del menú principal (P10-B2): abre AJUSTES -> GRÁFICOS.
## Asigna las variables DIRECTAMENTE (sin guardar) para no tocar las preferencias
## reales. Cambia OPT para ver el estado con la optimización apagada o encendida.

const OPT := true

func _ready() -> void:
	AjustesGraficos.optimizacion_agresiva = OPT
	AjustesGraficos.distancia_carga = 6
	AjustesGraficos.distancia_precarga = 4
	AjustesGraficos.modo_diagnostico_stream = OPT
	var mm := (load("res://ui/scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	mm.call("_entrar_ajustes")
	var cfg := mm.get_node("MenuPanel/Content/OptionsList/ConfigItems") as VBoxContainer
	mm.call("_toggle_categoria", 0, cfg.get_child(0) as MenuOption)