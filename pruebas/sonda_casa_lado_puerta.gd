extends Node
## SONDA (sólo mide): a cada lado de la ÚNICA puerta cerrada del modelo
## (Object_4, x_modelo -3.805, z -0.21..0.65) comprueba si cabe Leo de pie
## (cápsula r 0.25 h 1.9, la que usa dentro de casa) y qué hay en el suelo.
## Sirve para decidir de qué lado va el punto de aparición y el Area3D.

const CASA := "res://mundo/casa_leo/casa_leo.tscn"

var _casa: Node3D


func _ready() -> void:
	_casa = (load(CASA) as PackedScene).instantiate() as Node3D
	add_child(_casa)
	for i in 600:
		await get_tree().physics_frame
		if bool(_casa.call("listo")):
			break
	for i in 20:
		await get_tree().physics_frame
	var puerta: Vector3 = _casa.call("puerta_interior")
	print("[lado] puerta (escena) %s" % str(puerta))
	# Barrido en X a ambos lados del plano de la puerta, en varias z.
	for dz in [-0.9, -0.6, -0.45, -0.2, 0.0, 0.45]:
		for dx in [0.3, 0.5, 0.8, 1.1, 1.4, 1.8, 2.2]:
			var p: Vector3 = puerta + Vector3(dx, 0.0, dz)
			print("[lado] dx %+.2f dz %+.2f → %s | cámara libre %.2f m" % [
					dx, dz, _informe(p), _camara_libre(p, puerta)])
	print("[lado] FIN")


## Espacio libre (m, máx 2,6) detrás del jugador: la cámara va en la dirección
## opuesta a la puerta, a 1,55 m de altura.
func _camara_libre(p: Vector3, puerta: Vector3) -> float:
	var atras: Vector3 = (p - puerta)
	atras.y = 0.0
	atras = atras.normalized()
	var esp: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var desde: Vector3 = p + Vector3.UP * 1.55
	var q := PhysicsRayQueryParameters3D.create(desde, desde + atras * 2.6, 1)
	var hit: Dictionary = esp.intersect_ray(q)
	if hit.is_empty():
		return 2.6
	return desde.distance_to(hit["position"] as Vector3)


func _informe(p: Vector3) -> String:
	var esp: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, 2.5, p.z), Vector3(p.x, -1.5, p.z), 1)
	var suelo := esp.intersect_ray(rq)
	var y: float = float((suelo["position"] as Vector3).y) if not suelo.is_empty() else -99.0
	var caps := CapsuleShape3D.new()
	caps.radius = 0.25
	caps.height = 1.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = caps
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), Vector3(p.x, y + 0.97, p.z))
	var golpes: Array = []
	for r in esp.intersect_shape(q, 8):
		var c := r.get("collider") as Node
		golpes.append(String(c.name) if c != null else "?")
	return "suelo y %.2f | %s" % [y, ("LIBRE" if golpes.is_empty() else str(golpes))]
