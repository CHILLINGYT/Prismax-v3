extends Node
## VISTA (no suite): carga el MUNDO real y fotografía CADA vehículo con Leo de pie
## justo a su lado, con la cámara perpendicular al costado del vehículo y a la
## altura de los ojos. Sirve para juzgar la PROPORCIÓN (no la colocación).
## Las fotos quedan en res://_tests/capturas/escala_*.png

const MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const CARPETA := "res://_tests/capturas"

var _mundo: Node
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	_mundo = (load(MUNDO) as PackedScene).instantiate()
	add_child(_mundo)
	var veh: Node = _mundo.get_node("Vehiculos")
	for i in 2400:
		await get_tree().process_frame
		if bool(veh.call("listo")):
			break
	var ciclo: Node = get_tree().get_first_node_in_group("ciclo_dia_noche")
	if ciclo != null and ciclo.has_method("poner_fase") and ciclo.has_method("fase_dia_pleno"):
		ciclo.call("poner_fase", ciclo.call("fase_dia_pleno"))
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_mundo.add_child(_cam)
	var jug: Node3D = null
	for n in get_tree().get_nodes_in_group("player"):
		if n.has_method("colocar_en"):
			jug = n as Node3D
			break
	for p in veh.call("puestos"):
		var nodo: Node3D = p["nodo"] as Node3D
		var vertical: bool = p["vertical"]
		var centro: Vector3 = nodo.global_position
		var largo: float = float(p["largo"])
		var ancho: float = float(p["ancho"])
		# Costado del vehículo = perpendicular a su eje largo.
		var lado_v: Vector3 = Vector3(1, 0, 0) if vertical else Vector3(0, 0, 1)
		var eje_v: Vector3 = Vector3(0, 0, 1) if vertical else Vector3(1, 0, 0)
		var lado: float = float(p["lado"])
		if jug != null:
			# Leo pegado al morro del vehículo, sobre su mismo suelo.
			var punto: Vector3 = centro + eje_v * (largo * 0.5 + 0.8) + lado_v * (lado * ancho * 0.25)
			punto.y = centro.y + 0.3
			jug.call("colocar_en", punto, punto + lado_v * -lado * 5.0)
			for k in 20:
				await get_tree().physics_frame
		_cam.global_position = centro + lado_v * (-lado * 10.0) + eje_v * (largo * 0.35) + Vector3.UP * 1.7
		_cam.look_at(centro + eje_v * largo * 0.25 + Vector3.UP * 0.9, Vector3.UP)
		_cam.current = true
		for k in 12:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.resize(int(img.get_width() * 0.6), int(img.get_height() * 0.6))
		var ruta: String = "%s/escala_%s.png" % [CARPETA, String(p["tipo"])]
		img.save_png(ProjectSettings.globalize_path(ruta))
		print("[escala] %s | largo %.2f alto %.2f | Leo en %s → %s" % [
				String(p["tipo"]), largo, (nodo as VehiculoAparcado).alto_m(),
				str(jug.global_position.snapped(Vector3.ONE * 0.01)) if jug != null else "-", ruta])
	print("[escala] FIN")
