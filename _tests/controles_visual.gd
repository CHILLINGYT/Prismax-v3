extends Node

## Escena de COMPROBACIÓN VISUAL del panel CONTROLES (no forma parte del juego).
##
## Abre el menú de pausa directamente en la pantalla de CONFIGURACIÓN para poder
## pulsar las categorías con el ratón y ver el panel real. No modifica nada del
## juego: sólo instancia el menú existente.

const PauseMenuScene := preload("res://ui/scenes/PauseMenu.tscn")

func _ready() -> void:
	var menu: CanvasLayer = PauseMenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.abrir()
	await get_tree().process_frame
	menu._entrar_config()