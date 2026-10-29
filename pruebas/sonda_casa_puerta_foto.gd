extends Node
## SONDA (sólo fotografía): reconstruye puntos de vista del SALÓN de la casa de Leo
## para identificar la puerta de la foto de referencia. Marca con esferas de color
## las puertas conocidas del modelo (coordenadas del GLB), sin tocar la casa.

const CASA := "res://mundo/casa_leo/casa_leo.tscn"
const CARPETA := "res://pruebas/capturas"

## [nombre, posición de cámara (escena), punto mirado (escena)]
const VISTAS := [
	["F1_salon_ne", Vector3(-1.5, 1.60, 4.6), Vector3(2.0, 1.10, 1.2)],
	["F2_salon_n", Vector3(-1.8, 1.60, 4.6), Vector3(-0.4, 1.10, 0.6)],
	["F3_salon_centro", Vector3(-0.6, 1.60, 4.0), Vector3(1.6, 1.10, 1.0)],
	["F4_comedor_o", Vector3(1.6, 1.60, 2.6), Vector3(-1.6, 1.10, 1.2)],
	# Encuadre de la FOTO del usuario (salón mirando al este-noreste: cocina a la
	# izquierda, pared azul a la derecha, puerta de madera en el borde izquierdo).
	["G1_como_la_foto", Vector3(-1.5, 1.60, 4.6), Vector3(2.5, 1.10, 3.0)],
	# La puerta principal actual, centrada y de cerca.
	["G2_puerta_centrada", Vector3(-1.5, 1.60, 4.6), Vector3(-0.69, 1.10, 1.4)],
]

var _casa: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	_casa = (load(CASA) as PackedScene).instantiate() as Node3D
	add_child(_casa)
	for i in 600:
		await get_tree().process_frame
		if bool(_casa.call("listo")):
			break
	for i in 10:
		await get_tree().process_frame
	# Puertas conocidas del modelo (GLB) → escena, con el mismo convertidor de la casa.
	var puertas := {
		"principal_actual": Vector3(-3.805, 1.0, 0.221),
		"bano_2": Vector3(-4.80, 1.0, -2.21),
		"bano_3": Vector3(-4.80, 1.0, -0.36),
		"dormitorio_1": Vector3(-3.34, 1.0, -3.28),
		"dormitorio_2": Vector3(-3.34, 1.0, -4.99),
	}
	var colores := {
		"principal_actual": Color(1, 0, 0), "bano_2": Color(1, 1, 0), "bano_3": Color(0, 1, 1),
		"dormitorio_1": Color(0, 0.4, 1), "dormitorio_2": Color(1, 0, 1),
	}
	for k in puertas:
		var p: Vector3 = _a_escena(puertas[k])
		_marca(p, colores[k])
		print("[foto] puerta %s → escena %s" % [k, str(p.snapped(Vector3.ONE * 0.01))])
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.current = true
	for v in VISTAS:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.resize(int(img.get_width() * 0.6), int(img.get_height() * 0.6))
		var ruta: String = "%s/casa_%s.png" % [CARPETA, String(v[0])]
		img.save_png(ProjectSettings.globalize_path(ruta))
		print("[foto] %s desde %s → %s" % [String(v[0]), str(v[1]), ruta])
	print("[foto] FIN")


## Mismo convertidor que casa_leo.gd: (p - centro) * ESCALA, con el centro medido
## a partir de los puntos que la casa ya expone.
func _a_escena(p_modelo: Vector3) -> Vector3:
	var centro := Vector3(-3.233, 0.0, -0.9442)
	var r: Vector3 = (p_modelo - centro) * 1.2
	r.y = p_modelo.y
	return r


func _marca(p: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 0.12
	esfera.height = 0.24
	mi.mesh = esfera
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	mi.material_override = m
	mi.position = p
	add_child(mi)
