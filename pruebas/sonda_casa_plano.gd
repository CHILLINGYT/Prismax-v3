extends Node
## SONDA (sólo mide y fotografía): plano CENITAL de la casa de Leo con los puntos
## conocidos marcados, para identificar puertas y ventanas sin adivinar.
##   · esferas ROJAS   = puerta principal actual (VANO) y punto de aparición
##   · esferas VERDES  = vanos exteriores (ventanas) declarados en casa_leo.gd
##   · esfera AZUL     = vano del dormitorio
## Además imprime la correspondencia píxel ↔ (x, z) del plano.

const CASA := "res://mundo/casa_leo/casa_leo.tscn"
const CARPETA := "res://pruebas/capturas"
const TAM := 14.0        ## tamaño ortográfico (m) del plano

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
	var caja: AABB = _casa.call("caja_interior")
	print("[plano] caja de la casa: pos %s size %s" % [str(caja.position), str(caja.size)])
	print("[plano] puerta actual (VANO) %s | spawn %s | mira %s | dormitorio %s" % [
			str(_casa.call("puerta_interior")), str(_casa.call("spawn")),
			str(_casa.call("mira")), str(_casa.call("vano_dormitorio"))])
	_marca(_casa.call("puerta_interior"), Color(1, 0, 0), 0.18)
	_marca(_casa.call("spawn"), Color(1, 0.5, 0), 0.14)
	_marca(_casa.call("vano_dormitorio"), Color(0, 0.3, 1), 0.14)
	for d in _casa.call("cristales_datos"):
		_marca((d[0] as Vector3) + Vector3.UP * 0.2, Color(0, 1, 0), 0.16)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TAM
	cam.near = 7.6          ## recorta el techo: se ve la planta
	cam.far = 40.0
	cam.position = Vector3(0, 10.0, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	add_child(cam)
	cam.current = true
	for i in 10:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var ruta: String = "%s/casa_plano.png" % CARPETA
	img.save_png(ProjectSettings.globalize_path(ruta))
	var w: int = img.get_width()
	var h: int = img.get_height()
	print("[plano] imagen %dx%d | ortho alto %.1f m → ancho %.1f m" % [w, h, TAM, TAM * float(w) / float(h)])
	print("[plano] centro de la imagen = (x 0, z 0). x crece a la DERECHA, z crece hacia ABAJO.")
	print("[plano] m por píxel: %.4f" % (TAM / float(h)))
	print("[plano] → %s" % ruta)
	print("[plano] FIN")


func _marca(p: Vector3, c: Color, r: float) -> void:
	var mi := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = r
	esfera.height = r * 2.0
	mi.mesh = esfera
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = p + Vector3.UP * 1.2
	add_child(mi)
