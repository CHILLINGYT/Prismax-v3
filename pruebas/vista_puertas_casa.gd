extends Node
## VISTA (no suite): fotos del pasillo de la casa de Leo desde varios puntos, con
## la cámara real del jugador, para identificar la puerta de la foto de referencia.
## Coordenadas en el espacio del MODELO (GLB); se convierten con la escala de la casa.

const CASA := "res://mundo/casa_leo/casa_leo.tscn"
const CARPETA := "res://pruebas/capturas"

## [nombre, dónde se planta Leo (GLB), hacia dónde mira (GLB)]
const VISTAS := [
	["A_spawn_actual", Vector3(-4.48, 0, 0.221), Vector3(-3.805, 0, 0.221)],
	["B_pasillo_mirando_sur", Vector3(-4.45, 0, -3.6), Vector3(-4.45, 0, 0.6)],
	["C_pasillo_mirando_norte", Vector3(-4.45, 0, -0.6), Vector3(-4.45, 0, -5.0)],
	["D_antesala_mirando_oeste", Vector3(-4.45, 0, -4.4), Vector3(-6.7, 0, -4.4)],
	["E_salon_mirando_pasillo", Vector3(-4.45, 0, 1.6), Vector3(-4.45, 0, -3.0)],
	["F_como_la_foto", Vector3(-5.45, 0, -4.35), Vector3(-6.75, 0, -4.75)],
]

var _casa: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	_casa = (load(CASA) as PackedScene).instantiate()
	add_child(_casa)
	for i in 20:
		await get_tree().physics_frame
	var jug: Node3D = null
	for n in get_tree().get_nodes_in_group("player"):
		if n.has_method("colocar_en"):
			jug = n
	for v in VISTAS:
		var donde: Vector3 = _casa.call("_de_modelo", v[1])
		var mira: Vector3 = _casa.call("_de_modelo", v[2])
		jug.call("colocar_en", donde + Vector3.UP * 0.05, mira)
		for k in 45:
			await get_tree().physics_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.resize(int(img.get_width() * 0.5), int(img.get_height() * 0.5))
		var ruta := "%s/casa_%s.png" % [CARPETA, v[0]]
		img.save_png(ProjectSettings.globalize_path(ruta))
		print("[vista] %s → %s" % [v[0], ruta])
	print("[vista] FIN")
