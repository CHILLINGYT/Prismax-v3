extends Node

## LANZADOR DE LA PRUEBA DEL CARTEL DE OBJETIVO.
##
## Rehace el flujo normal del menú: fija `LoadingScreen.destino` (igual que hace
## main_menu.gd) y cambia a la pantalla de carga, de modo que el mundo se cargue y se
## genere EXACTAMENTE como en una partida real. El monitor que hace las comprobaciones
## se cuelga de la raíz del árbol, así sobrevive al cambio de escena.

const ESCENA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const ESCENA_CARGA := "res://ui/scenes/LoadingScreen.tscn"
const RUTA_MONITOR := "res://.backup_cartel_objetivo/_monitor_cartel.gd"


func _ready() -> void:
	var guion: GDScript = load(RUTA_MONITOR) as GDScript
	if guion == null:
		push_error("[PruebaCartel] No se pudo cargar el monitor %s" % RUTA_MONITOR)
		get_tree().quit(1)
		return
	var monitor: Node = guion.new()
	if monitor == null:
		push_error("[PruebaCartel] No se pudo crear el monitor")
		get_tree().quit(1)
		return
	monitor.name = "MonitorCartel"
	# Diferido a propósito: la raíz del árbol está ocupada montando la escena actual
	# mientras corre este `_ready`, así que un `add_child` directo fallaría ("parent is
	# busy"). Con `call_deferred` el monitor entra al árbol al final de este fotograma y
	# sigue vivo cuando cambiemos de escena (la pantalla de carga y luego el mundo).
	get_tree().root.add_child.call_deferred(monitor)
	await get_tree().process_frame
	print("[PruebaCartel] monitor dentro del arbol: %s" % str(monitor.is_inside_tree()))
	LoadingScreen.destino = ESCENA_MUNDO
	get_tree().change_scene_to_file(ESCENA_CARGA)