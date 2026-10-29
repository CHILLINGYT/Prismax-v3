extends Node
## VISTA (no suite): carga el MUNDO real y guarda una foto de cada vehículo
## aparcado, desde la acera y en diagonal, para ver el cordón, las ruedas y los
## edificios de alrededor. Las fotos quedan en res://pruebas/capturas/.

const MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const CARPETA := "res://pruebas/capturas"

var _mundo: Node
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	_mundo = (load(MUNDO) as PackedScene).instantiate()
	add_child(_mundo)
	var veh := _mundo.get_node("Vehiculos")
	for i in 2400:
		await get_tree().process_frame
		if bool(veh.call("listo")):
			break
	# Ciclo a pleno día para que las fotos se lean bien.
	var ciclo := get_tree().get_first_node_in_group("ciclo_dia_noche")
	if ciclo != null and ciclo.has_method("poner_fase") and ciclo.has_method("fase_dia_pleno"):
		ciclo.call("poner_fase", ciclo.call("fase_dia_pleno"))
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_mundo.add_child(_cam)
	for p in veh.call("puestos"):
		var nodo := p["nodo"] as Node3D
		var vertical: bool = p["vertical"]
		var lado: float = p["lado"]
		# La acera queda del lado del cordón: el vehículo está a +lado del eje del vial.
		var hacia_acera := (Vector3(lado, 0, 0) if vertical else Vector3(0, 0, lado))
		var a_lo_largo := (Vector3(0, 0, 1) if vertical else Vector3(1, 0, 0))
		var centro := nodo.global_position
		# Leo de pie en la vereda, al costado del vehículo, para comparar tamaños.
		# El grupo "player" incluye más de un nodo (p. ej. el cuerpo de vuelo): se
		# usa el que es el jugador de verdad, el que sabe colocarse.
		var jug: Node3D = null
		for n in get_tree().get_nodes_in_group("player"):
			if n.has_method("colocar_en"):
				jug = n as Node3D
				break
		if jug == null:
			print("[vista] grupo player: %s" % str(get_tree().get_nodes_in_group("player").map(func(n: Node) -> String: return str(n.get_path()))))
		if jug != null and jug.has_method("colocar_en"):
			var ancho: float = p["ancho"]
			jug.call("colocar_en", centro + hacia_acera * (ancho * 0.5 + 0.9) + Vector3.UP * 0.3,
					centro + hacia_acera * 5.0)
			for k in 30:
				await get_tree().physics_frame
			var vis := 0
			for mi in jug.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).is_visible_in_tree():
					vis += 1
			print("[vista] Leo %s en %s (pedido %s) | mallas visibles %d | visible %s" % [
					jug.get_path(), str(jug.global_position.snapped(Vector3.ONE * 0.01)),
					str((centro + hacia_acera * (float(p["ancho"]) * 0.5 + 0.9)).snapped(Vector3.ONE * 0.01)),
					vis, jug.is_visible_in_tree()])
		# Sobre la VEREDA (que mide 3 m desde el cordón): a 2,5 m del vehículo hacia
		# ella, nunca dentro de la manzana.
		_cam.global_position = centro + hacia_acera * 2.5 + a_lo_largo * 7.0 + Vector3.UP * 3.6
		if String(p["tipo"]) == "auto":
			# En esa vereda hay un árbol justo detrás: se mira desde la calzada.
			_cam.global_position = centro - hacia_acera * 6.0 + a_lo_largo * 5.0 + Vector3.UP * 3.0
		_cam.look_at(centro + Vector3.UP * 0.6, Vector3.UP)
		_cam.current = true
		for k in 12:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.resize(int(img.get_width() * 0.5), int(img.get_height() * 0.5))
		var ruta := "%s/vehiculo_%s.png" % [CARPETA, String(p["tipo"])]
		img.save_png(ProjectSettings.globalize_path(ruta))
		print("[vista] foto de %s en %s → %s" % [p["tipo"], str(centro), ruta])
	print("[vista] FIN")
