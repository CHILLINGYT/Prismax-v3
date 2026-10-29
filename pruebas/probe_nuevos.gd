extends SceneTree

## SONDA de los recursos importados NUEVOS (casa de Leo + los tres vehículos).
## Mide lo que hace falta para integrarlos sin inventar nada:
##   · nº de mallas/superficies y VÉRTICES (peso real del modelo),
##   · caja envolvente COMPUESTA (componiendo la cadena de padres),
##   · si traen esqueleto/animaciones y nombres de las piezas grandes (ruedas),
##   · las dimensiones de la carrocería, que es lo que decide escala y colisión.
##
##   Godot --headless --path . --script res://pruebas/probe_nuevos.gd

const MODELOS := {
	"CASA": "res://mundo/casa_leo/modelo/appartement.glb",
	"MOTO": "res://modelos 3d autos/vespa.glb",
	"AUTO": "res://modelos 3d autos/free_1972_datsun_240k_gt.glb",
	"CAMIONETA": "res://modelos 3d autos/free_zuk_3d_model.glb",
}

func _init() -> void:
	for etiqueta in MODELOS.keys():
		_medir(etiqueta, MODELOS[etiqueta])
	quit()

func _medir(etiqueta: String, ruta: String) -> void:
	print("=".repeat(72))
	var t0 := Time.get_ticks_msec()
	var ps := load(ruta) as PackedScene
	if ps == null:
		print("[%s] NO CARGA: %s" % [etiqueta, ruta])
		return
	var raiz := ps.instantiate() as Node3D
	var t_carga := Time.get_ticks_msec() - t0
	var mallas := raiz.find_children("*", "MeshInstance3D", true, false)
	var vertices := 0
	var superficies := 0
	var con_material := 0
	var caja := AABB()
	var hay := false
	var piezas: Array = []
	for n in mallas:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			superficies += 1
			vertices += mi.mesh.surface_get_array_len(s)
			if mi.get_active_material(s) != null:
				con_material += 1
		var a: AABB = _compuesta(mi, mi.get_aabb())
		caja = a if not hay else caja.merge(a)
		hay = true
		piezas.append([String(mi.name), a])
	print("[%s] %s" % [etiqueta, ruta])
	print("   carga en %d ms | mallas=%d | superficies=%d | VÉRTICES=%d | con material=%d" % [
			t_carga, mallas.size(), superficies, vertices, con_material])
	var esqueletos := raiz.find_children("*", "Skeleton3D", true, false)
	var animaciones := raiz.find_children("*", "AnimationPlayer", true, false)
	print("   Skeleton3D=%d | AnimationPlayer=%d" % [esqueletos.size(), animaciones.size()])
	if hay:
		print("   AABB min=%v max=%v" % [caja.position.snapped(Vector3(0.001, 0.001, 0.001)),
				(caja.position + caja.size).snapped(Vector3(0.001, 0.001, 0.001))])
		print("   TAMAÑO (X,Y,Z) = %v" % caja.size.snapped(Vector3(0.001, 0.001, 0.001)))
		# Piezas más grandes (por volumen de su caja): suelen ser carrocería y ruedas.
		piezas.sort_custom(func(a: Array, b: Array) -> bool:
			var va: float = (a[1] as AABB).size.x * (a[1] as AABB).size.y * (a[1] as AABB).size.z
			var vb: float = (b[1] as AABB).size.x * (b[1] as AABB).size.y * (b[1] as AABB).size.z
			return va > vb)
		print("   piezas mayores:")
		for i in mini(8, piezas.size()):
			var p: Array = piezas[i]
			var a: AABB = p[1]
			print("     · %-34s tam=%v  min.y=%.3f" % [String(p[0]).substr(0, 34),
					a.size.snapped(Vector3(0.01, 0.01, 0.01)), a.position.y])
	raiz.free()

## Caja de una malla en el espacio de la RAÍZ de su escena (compone TODA la cadena de
## padres: los modelos traen nodos intermedios con escala y giro).
func _compuesta(n: Node3D, caja: AABB) -> AABB:
	var t := n.transform
	var p := n.get_parent() as Node3D
	while p != null:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t * caja