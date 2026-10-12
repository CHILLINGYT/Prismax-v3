extends Node
## Sonda temporal de rendimiento: carga el juego real y lo deja correr para medir FPS
## con los modelos nuevos. No toca nada del juego.

func _ready() -> void:
	var juego: Node = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	add_child(juego)
	print("[FPS2] juego cargado (52 ciudadanos Mixamo)")


func _process(_delta: float) -> void:
	var f := Engine.get_frames_per_second()
	if f > 0 and int(Engine.get_process_frames()) % 300 == 0:
		print("[FPS2] %d fps · objetos %d" % [f, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])