class_name FuerzaVfx
extends RefCounted

## =============================================================================
##  Vfx.gd — efectos visuales reutilizables (polvo, escombros, chispas)
## =============================================================================
##  Todo se construye POR CÓDIGO: no hace falta ningún asset ni escena extra.
##  Cada función devuelve el nodo ya montado; sólo hay que añadirlo al árbol
##  (o usar las funciones lanzar_*(), que además lo colocan y lo autolimpian).
##
##  Los tres ingredientes de un buen impacto:
##    · polvo      -> nube marrón que se abre y se desvanece
##    · escombros  -> piedras que saltan con gravedad y giran
##    · chispas    -> puntos de luz/energía que salen disparados
## =============================================================================


## Libera un nodo cuando pasen `segundos`. Evita dejar basura acumulada.
static func liberar_mas_tarde(nodo: Node, segundos: float) -> void:
	if nodo == null or nodo.get_tree() == null:
		return
	nodo.get_tree().create_timer(maxf(segundos, 0.05)).timeout.connect(nodo.queue_free)


## Material sencillo para partículas y efectos.
static func material(color: Color, emite: bool = false, sin_luz: bool = false) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if sin_luz:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emite:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	return m


## Desvanecido: opaco al nacer, transparente al morir (lo usan todas las nubes).
static func _degradado(desde: Color, hasta: Color) -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([desde, hasta])
	var t: GradientTexture1D = GradientTexture1D.new()
	t.gradient = g
	return t


## Motor común de todos los efectos: monta un GPUParticles3D de un solo disparo.
static func _sistema(padre: Node3D, pos: Vector3, malla: Mesh, mat: Material,
		cantidad: int, vida: float, vel_min: float, vel_max: float,
		direccion: Vector3, dispersion: float, gravedad: Vector3,
		escala_min: float, escala_max: float, giro_max: float,
		amortiguacion: float, color_inicio: Color, color_fin: Color) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = maxi(cantidad, 1)
	p.lifetime = maxf(vida, 0.05)
	p.one_shot = true
	p.explosiveness = 1.0
	p.draw_pass_1 = malla
	p.material_override = mat

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = direccion
	pm.spread = dispersion
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = gravedad
	pm.scale_min = escala_min
	pm.scale_max = escala_max
	pm.angular_velocity_min = -giro_max
	pm.angular_velocity_max = giro_max
	pm.damping_min = amortiguacion * 0.5
	pm.damping_max = amortiguacion
	pm.color_ramp = _degradado(color_inicio, color_fin)
	p.process_material = pm

	padre.add_child(p)
	p.global_position = pos
	p.emitting = true
	liberar_mas_tarde(p, vida + 0.35)
	return p


## Nube de polvo: se abre hacia los lados y se desvanece.
static func polvo(padre: Node3D, pos: Vector3, radio: float, cantidad: int = 26,
		color: Color = Color(0.62, 0.55, 0.45), vida: float = 1.3,
		fuerza: float = 3.2) -> GPUParticles3D:
	var malla: SphereMesh = SphereMesh.new()
	malla.radius = 0.5
	malla.height = 1.0
	malla.radial_segments = 6
	malla.rings = 3
	var mat: StandardMaterial3D = material(color, false)
	var s: GPUParticles3D = _sistema(padre, pos, malla, mat, cantidad, vida,
		fuerza * 0.25, fuerza, Vector3.UP, 75.0, Vector3(0.0, 1.6, 0.0),
		radio * 0.10, radio * 0.34, 60.0, 1.6,
		Color(color.r, color.g, color.b, 0.55), Color(color.r, color.g, color.b, 0.0))
	# Las partículas nacen repartidas por el radio del impacto, no todas del centro.
	var pm: ParticleProcessMaterial = s.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radio * 0.35, 0.05)
	return s


## Escombros: piedras que saltan hacia arriba, giran y caen.
static func escombros(padre: Node3D, pos: Vector3, radio: float, cantidad: int = 22,
		color: Color = Color(0.34, 0.30, 0.26), vida: float = 1.8,
		fuerza: float = 7.0) -> GPUParticles3D:
	var malla: BoxMesh = BoxMesh.new()
	malla.size = Vector3(0.18, 0.14, 0.18)
	var s: GPUParticles3D = _sistema(padre, pos, malla, material(color), cantidad, vida,
		fuerza * 0.45, fuerza, Vector3.UP, 70.0, Vector3(0.0, -22.0, 0.0),
		0.45, 1.5, 420.0, 0.7,
		Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 1.0))
	var pm: ParticleProcessMaterial = s.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radio * 0.3, 0.05)
	return s


## Chispas de energía (sin luz, brillantes): el golpe "mágico" del pisotón.
static func chispas(padre: Node3D, pos: Vector3, radio: float, cantidad: int = 30,
		color: Color = Color(1.0, 0.82, 0.42), vida: float = 0.7,
		fuerza: float = 9.0) -> GPUParticles3D:
	var malla: SphereMesh = SphereMesh.new()
	malla.radius = 0.09
	malla.height = 0.18
	malla.radial_segments = 5
	malla.rings = 3
	var s: GPUParticles3D = _sistema(padre, pos, malla, material(color, true, true),
		cantidad, vida, fuerza * 0.4, fuerza, Vector3.UP, 180.0, Vector3(0.0, -6.0, 0.0),
		0.5, 1.6, 0.0, 2.4,
		Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.0))
	var pm: ParticleProcessMaterial = s.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radio * 0.3, 0.05)
	return s
