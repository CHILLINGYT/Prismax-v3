extends Node
## SONDA (sólo fotografía y mide): mira por CADA vano exterior de la casa de Leo
## desde dentro, a la altura de los ojos, para ver si detrás del cristal hay
## paisaje urbano o algo tapándolo. Una foto por ventana, de día y de noche.

const CASA := "res://casa_leo/casa_leo.tscn"
const CARPETA := "res://pruebas/capturas"

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
	print("[ventana] edificios corridos fuera de la casa: %d | cara más cercana a %.1f m" % [
			int(_casa.call("vista_empujados")), float(_casa.call("vista_distancia_minima"))])
	var caja: AABB = _casa.call("caja_interior")
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	var datos: Array = _casa.call("cristales_datos")
	var ciclo: Node = _casa.get_node_or_null("CicloDiaNoche")
	for momento in ["dia", "noche"]:
		if ciclo != null and ciclo.has_method("poner_fase"):
			ciclo.call("poner_fase", 0.325 if momento == "dia" else 0.85)
			for i in 30:
				await get_tree().process_frame
		for n in datos.size():
			var centro: Vector3 = datos[n][0]
			var tam: Vector3 = datos[n][1]
			# Hacia fuera = desde el centro de la casa hacia el vano, por el eje fino.
			var afuera: Vector3 = Vector3(signf(centro.x), 0.0, 0.0) if tam.x < tam.z else Vector3(0.0, 0.0, signf(centro.z))
			var ojo: Vector3 = centro - afuera * 1.6
			ojo.y = 1.55
			cam.global_position = ojo
			cam.look_at(centro + afuera * 12.0 + Vector3.UP * 0.2, Vector3.UP)
			for i in 8:
				await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			img.resize(int(img.get_width() * 0.6), int(img.get_height() * 0.6))
			var ruta: String = "%s/ventana_%d_%s.png" % [CARPETA, n, momento]
			img.save_png(ProjectSettings.globalize_path(ruta))
			print("[ventana] %d (%s) centro %s tam %s | ojo %s → %s" % [
					n, momento, str(centro.snapped(Vector3.ONE * 0.01)), str(tam.snapped(Vector3.ONE * 0.01)),
					str(ojo.snapped(Vector3.ONE * 0.01)), ruta])
	print("[ventana] caja de la casa %s / %s" % [str(caja.position), str(caja.end)])
	print("[ventana] FIN")
