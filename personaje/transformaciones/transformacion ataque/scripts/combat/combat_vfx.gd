class_name CombatVFX
## VFX de combate - Fase 2 - Genera chispas, ondas y efectos por tipo de golpe

static func spawn_hit_vfx(parent: Node3D, pos: Vector3, attack_type: String, is_finisher: bool, combo_count: int) -> void:
	if parent == null:
		return
	
	match attack_type:
		"light":
			_spawn_chispa(parent, pos, combo_count)
		"medium":
			_spawn_onda(parent, pos, 1.2, Color(1, 1, 1, 0.8))
		"heavy":
			_spawn_onda(parent, pos, 1.8, Color(1, 0.8, 0.3, 0.9))
	
	if is_finisher:
		_spawn_onda(parent, pos, 2.5, Color(1, 0.3, 0.2, 1.0))
		_spawn_chispa_grande(parent, pos)

static func _spawn_chispa(parent: Node3D, pos: Vector3, combo_count: int) -> void:
	# Chispa pequeña - usa MeshInstance3D con material emissive
	var mesh := SphereMesh.new()
	mesh.radius = 0.08 + float(combo_count) * 0.02
	mesh.height = mesh.radius * 2.0
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.9, 0.4, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.8, 0.2)
	mat.emission_energy_multiplier = 2.0
	
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.global_position = pos + Vector3(randf_range(-0.1, 0.1), randf_range(0.0, 0.3), randf_range(-0.1, 0.1))
	parent.add_child(inst)
	
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(inst, "scale", Vector3.ONE * 2.0, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.chain().tween_callback(inst.queue_free)

static func _spawn_onda(parent: Node3D, pos: Vector3, radio: float, color: Color) -> void:
	# Onda expansiva - anillo que crece
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.1
	mesh.height = 0.05
	mesh.radial_segments = 16
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.global_position = pos
	inst.global_position.y += 0.05
	parent.add_child(inst)
	
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "top_radius", radio, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(mesh, "bottom_radius", radio, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(inst.queue_free)

static func _spawn_chispa_grande(parent: Node3D, pos: Vector3) -> void:
	# Para finisher - varias chispas
	for i in range(6):
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.24
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 0.4, 0.2, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.3, 0.1)
		mat.emission_energy_multiplier = 3.0
		
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = mat
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
		inst.global_position = pos + dir * 0.2
		parent.add_child(inst)
		
		var tween := parent.create_tween()
		tween.set_parallel(true)
		tween.tween_property(inst, "global_position", inst.global_position + dir * 1.5 + Vector3.UP * 0.5, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tween.chain().tween_callback(inst.queue_free)

static func spawn_counter_vfx(parent: Node3D, pos: Vector3, is_perfect: bool) -> void:
	var color := Color(0.3, 0.8, 1.0, 0.9) if is_perfect else Color(1, 1, 0.5, 0.7)
	var radio := 2.0 if is_perfect else 1.2
	_spawn_onda(parent, pos, radio, color)
	if is_perfect:
		_spawn_chispa_grande(parent, pos)
