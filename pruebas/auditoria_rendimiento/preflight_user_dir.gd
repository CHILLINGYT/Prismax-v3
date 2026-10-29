extends SceneTree
## Sonda de AISLAMIENTO (solo lectura: no carga escenas, no escribe NADA).
##
## Responde a una única pregunta antes de medir: ¿a qué ruta real apunta
## `user://` en este proceso, y se instancian los autoloads del proyecto?
## Se ejecuta con `godot --headless -s`, por lo que NO debería abrir ventana.
##
## Uso:
##   XDG_DATA_HOME=/tmp/prismax_audit/xdg \
##     godot --path . --headless -s res://pruebas/auditoria_rendimiento/preflight_user_dir.gd

func _init() -> void:
	var user_dir := OS.get_user_data_dir()
	print("PROBE user_data_dir=", user_dir)
	print("PROBE xdg_data_home=", OS.get_environment("XDG_DATA_HOME"))
	print("PROBE home=", OS.get_environment("HOME"))
	# ¿Godot instanció los autoloads del proyecto en una corrida con -s?
	var hijos: Array[String] = []
	for c in root.get_children():
		hijos.append(String(c.name))
	print("PROBE root_children=", hijos)
	# El proyecto NO define use_custom_user_dir ni custom_user_dir_name:
	print("PROBE use_custom_user_dir=", ProjectSettings.get_setting("application/config/use_custom_user_dir", "<no definido>"))
	print("PROBE custom_user_dir_name=", ProjectSettings.get_setting("application/config/custom_user_dir_name", "<no definido>"))
	quit()