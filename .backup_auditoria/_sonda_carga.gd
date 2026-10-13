extends Node

func _ready() -> void:
	var rutas := [
		"res://ziba/escenas/ziba_prototipo.tscn",
		"res://NPCs/Scenes/NPC_Estatico_Obrero.tscn",
		"res://ui/scenes/DialogueBalloon.tscn",
		"res://personaje/base/escenas/leo_jugador.tscn",
		"res://ui/scenes/LoadingScreen.tscn",
		"res://ui/scenes/MainMenu.tscn",
	]
	for r in rutas:
		var existe := FileAccess.file_exists(r)
		var reconocido := ResourceLoader.exists(r)
		var res: Resource = null
		if reconocido:
			res = ResourceLoader.load(r)
		print("[carga] %s | archivo=%s | reconocido=%s | cargado=%s | clase=%s" % [
			r, str(existe), str(reconocido), str(res != null),
			(res.get_class() if res != null else "-")])
		if res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			print("         instancia=%s | nodos=%d" % [str(inst != null), inst.get_child_count() if inst != null else -1])
			if inst != null:
				inst.free()
	await get_tree().process_frame
	get_tree().quit(0)
