extends Node

## Prueba BASE (sin diálogo): instancia el juego y sale a los 3 s para comparar los
## avisos de consola con los de la prueba del diálogo. Sirve para saber si un aviso es
## de estos cambios o ya venía del juego.

func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	print("[base] fin de la prueba base (el juego no se usó: ni diálogo ni interacción)")
	get_tree().quit(0)