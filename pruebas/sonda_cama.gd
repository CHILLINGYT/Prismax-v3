extends Node3D
## SONDA (headless): mapa de alturas de la casa de Leo para ubicar la CAMA.
## Rayos verticales cada 0,1 m; la altura de lo primero que tocan bajo el techo.
##   '.' suelo (<0,12)  'b' superficie de cama/mueble bajo (0,30–0,75)
##   'm' mueble medio (0,12–0,30)  '#' alto (>0,75)
const CASA := "res://mundo/casa_leo/casa_leo.tscn"

func _ready() -> void:
	var casa := (load(CASA) as PackedScene).instantiate() as Node3D
	add_child(casa)
	for i in 4:
		await get_tree().physics_frame
	var esp := get_world_3d().direct_space_state
	var excl: Array[RID] = []
	for n in get_tree().get_nodes_in_group("player"):
		if n is CollisionObject3D:
			excl.append((n as CollisionObject3D).get_rid())
	var caja: AABB = casa.call("caja_interior")
	print("[cama] caja ", caja)
	var paso := 0.1
	var z := caja.position.z + 0.05
	while z < caja.end.z:
		var linea := "%+6.2f " % z
		var x := caja.position.x + 0.05
		while x < caja.end.x:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2.4, z), Vector3(x, -0.5, z), 1, excl)
			var r := esp.intersect_ray(q)
			var y := float((r["position"] as Vector3).y) if not r.is_empty() else -9.0
			var c := "."
			if y > 0.75: c = "#"
			elif y >= 0.30: c = "b"
			elif y >= 0.12: c = "m"
			linea += c
			x += paso
		print(linea)
		z += paso * 2.0
	print("[cama] x de %.2f a %.2f, paso %.1f" % [caja.position.x, caja.end.x, paso])
	get_tree().quit()
