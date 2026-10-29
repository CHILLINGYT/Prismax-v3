extends Node
## PRUEBA de compilación: recorre TODOS los .gd del proyecto (salvo addons de
## terceros, copias de respaldo y carpetas ocultas) y comprueba que compilan con
## los autoloads cargados (por eso es una ESCENA y no un --script).
##   godot --headless --path . res://pruebas/prueba_compilacion_scripts.tscn

## Carpetas que no son código del juego (respaldos y addons de terceros).
const EXCLUIR := ["res://addons", "res://_revisar"]

var _ok: int = 0
var _fallos: int = 0


func _ready() -> void:
	call_deferred("_correr")


func _correr() -> void:
	var pila: Array[String] = ["res://"]
	while not pila.is_empty():
		var dir_ruta: String = pila.pop_back()
		var d: DirAccess = DirAccess.open(dir_ruta)
		if d == null:
			continue
		for sub: String in d.get_directories():
			var completa: String = dir_ruta.path_join(sub)
			if sub.begins_with(".") or sub.begins_with("_backup") or sub.begins_with("backup") \
					or completa in EXCLUIR:
				continue
			pila.append(completa)
		for f: String in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var ruta: String = dir_ruta.path_join(f)
			var s: GDScript = ResourceLoader.load(ruta, "", ResourceLoader.CACHE_MODE_REUSE) as GDScript
			if s != null and s.can_instantiate():
				_ok += 1
			else:
				_fallos += 1
				print("[compilacion] FALLO ", ruta)
	print("==================== COMPILACION: %d OK / %d FALLO ====================" % [_ok, _fallos])
	get_tree().quit()
