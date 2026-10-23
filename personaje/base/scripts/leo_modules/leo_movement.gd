## leo_movement.gd - Fase 3 - Movimiento humano y utilidades
## Extraído de controlador_leo.gd (6066 líneas) para modularización

class_name LeoMovement

static func direccion_entrada(leo: CharacterBody3D) -> Vector3:
	var input_dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1.0
	if Input.is_action_pressed("move_back"):
		input_dir.z += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if input_dir.length_squared() > 0.001:
		input_dir = input_dir.normalized()
		# Relativo a cámara si existe
		var cam := leo.get_node_or_null("PivoteCamara") as Node3D
		if cam != null:
			var cam_basis := cam.global_transform.basis
			var forward := cam_basis.z
			forward.y = 0.0
			forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
			var right := cam_basis.x
			right.y = 0.0
			right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
			input_dir = (forward * input_dir.z + right * input_dir.x).normalized()
	return input_dir

static func intentar_escalon(leo: CharacterBody3D, dir_mov: Vector3, col: KinematicCollision3D) -> bool:
	if col == null:
		return false
	var normal := col.get_normal()
	if absf(normal.y) >= 0.7:
		return false
	var altura := LeoConstants.ALTURA_ESCALON
	var avance := LeoConstants.AVANCE_ESCALON
	if leo.test_move(leo.global_transform, Vector3.UP * altura):
		return false
	var elevado := leo.global_transform
	elevado.origin.y += altura
	if leo.test_move(elevado, dir_mov * avance):
		return false
	var mundo := leo.get_world_3d()
	if mundo == null:
		return false
	var desde := elevado.origin + dir_mov * avance + Vector3.UP * 0.05
	var q := PhysicsRayQueryParameters3D.create(desde, desde + Vector3.DOWN * (altura + 0.25))
	q.collision_mask = leo.collision_mask
	q.exclude = []
	if leo is CollisionObject3D:
		q.exclude = [(leo as CollisionObject3D).get_rid()]
	var hit := mundo.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var punto: Vector3 = hit.position
	var dif_y := punto.y - leo.global_position.y
	if dif_y < LeoConstants.DESNIVEL_MINIMO or dif_y > altura + LeoConstants.MARGEN_ESCALON:
		return false
	leo.global_position.y = punto.y
	return true

static func normal_pared(leo: CharacterBody3D) -> Vector3:
	var col := leo.get_last_slide_collision()
	if col == null:
		return Vector3.ZERO
	var n := col.get_normal()
	if absf(n.y) >= 0.7:
		return Vector3.ZERO
	return n

static func radio_capsula(leo: CharacterBody3D) -> float:
	var col := leo.get_node_or_null("Colision") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		return (col.shape as CapsuleShape3D).radius
	return 0.4

static func rayo_suelo(leo: CharacterBody3D, desde: Vector3, largo: float) -> Dictionary:
	var mundo := leo.get_world_3d()
	if mundo == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(desde, desde + Vector3.DOWN * largo)
	q.collision_mask = leo.collision_mask
	q.exclude = []
	if leo is CollisionObject3D:
		q.exclude = [(leo as CollisionObject3D).get_rid()]
	return mundo.direct_space_state.intersect_ray(q)
