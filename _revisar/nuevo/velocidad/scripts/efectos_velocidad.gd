extends Node3D

# RayosVelocidad del modulo (preload, sin class_name global para evitar colisiones).
const RayosV := preload("res://velocidad/scripts/rayos.gd")

# Orquesta todos los efectos visuales de supervelocidad:
# rayos, particulas, siluetas residuales y distorsion de pantalla.
# Las siluetas son instancias efimeras del modelo que se desvanecen rapido
# (imagenes residuales, nunca personajes independientes).

var _jugador: Node3D
var _capa: CanvasLayer
var _rayos: RayosV
var _rayos_carga: RayosV
# Rayos exclusivos de los golpes del combo: acompañan visualmente el ataque sin
# tocar su animacion. Su intensidad escala con el indice del combo.
var _rayos_ataque: RayosV
var _particulas: GPUParticles3D
var _part_mat: ParticleProcessMaterial
var _estela_particulas: GPUParticles3D
var _estela_mat: ParticleProcessMaterial
var _mat_fantasma: StandardMaterial3D

var _nivel_rayos: float = 0.0
var _nivel_rayos_obj: float = 0.0
var _nivel_carga: float = 0.0
var _nivel_carga_obj: float = 0.0
# Nivel de los rayos de ataque: sube con cada golpe y decae solo rapidamente.
var _nivel_ataque: float = 0.0
var _nivel_ataque_obj: float = 0.0
var _t_ataque_rayos: float = 0.0

# Intensidad por golpe del combo (1..4): moderada, media, alta, maxima.
const RAYOS_ATAQUE_MIN := 0.30
const RAYOS_ATAQUE_MAX := 1.00
const DURACION_RAYOS_ATAQUE := 0.24  # los rayos viven solo el momento del golpe
var _t_silueta: float = 0.0
var _intervalo_silueta: float = 0.05
var _en_dash: bool = false
var _en_ejecucion: bool = false

func _ready() -> void:
	_jugador = get_parent() as Node3D
	_capa = get_node_or_null("../CapaVelocidad")
	_mat_fantasma = _crear_mat_fantasma()

	_rayos = RayosV.new()
	_rayos.radio = 0.8
	_rayos.altura_min = -0.1
	_rayos.altura_max = 1.1
	add_child(_rayos)

	_rayos_carga = RayosV.new()
	_rayos_carga.radio = 0.85
	_rayos_carga.altura_min = -0.2
	_rayos_carga.altura_max = 1.4
	_rayos_carga.largo_max = 1.1
	add_child(_rayos_carga)

	# Rayos de los golpes: rango de cantidad amplio para que la progresion del
	# combo (1..4) se perciba claramente. Solo visuales.
	_rayos_ataque = RayosV.new()
	_rayos_ataque.radio = 0.9
	_rayos_ataque.altura_min = -0.1
	_rayos_ataque.altura_max = 1.2
	_rayos_ataque.largo_max = 1.5
	_rayos_ataque.rayos_min = 4
	_rayos_ataque.rayos_max = 20
	add_child(_rayos_ataque)

	var p := _crear_particulas(90, 0.05, 0.35)
	_particulas = p[0]
	_part_mat = p[1]
	add_child(_particulas)

	var e := _crear_particulas(180, 0.08, 0.5)
	_estela_particulas = e[0]
	_estela_mat = e[1]
	add_child(_estela_particulas)

func _crear_mat_fantasma() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.45, 0.8, 1.0, 0.4)
	return m

func _crear_particulas(cantidad: int, espesor: float, vida: float) -> Array:
	var p := GPUParticles3D.new()
	p.amount = cantidad
	p.lifetime = vida
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-10.0, -10.0, -10.0), Vector3(20.0, 20.0, 20.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.7
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 70.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.04
	mat.scale_max = 0.12
	p.process_material = mat
	var q := QuadMesh.new()
	q.size = Vector2(espesor, espesor)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.6, 0.9, 1.0, 0.4)
	q.material = m
	p.draw_pass_1 = q
	return [p, mat]

# ---- Dash ----
func iniciar_dash(dir: Vector3) -> void:
	_en_dash = true
	_nivel_rayos_obj = 1.0
	_intervalo_silueta = 0.05
	if dir.length() > 0.001:
		_part_mat.direction = -dir
	_particulas.emitting = true
	if _capa != null:
		_capa.set_intensidad(0.18)
	_emitir_silueta()

func terminar_dash() -> void:
	_en_dash = false
	_nivel_rayos_obj = 0.0
	_particulas.emitting = false
	if _capa != null:
		_capa.set_intensidad(0.0)

func iniciar_caida_dash() -> void:
	_nivel_rayos_obj = 0.6
	_particulas.emitting = true
	if _capa != null:
		_capa.set_intensidad(0.2)

# ---- Carga ----
func iniciar_carga() -> void:
	_nivel_carga = 0.0
	_nivel_carga_obj = 0.0
	if _capa != null:
		_capa.set_intensidad(0.12)

func actualizar_carga(t: float) -> void:
	var tt := clampf(t, 0.0, 1.0)
	_nivel_carga_obj = lerpf(0.25, 0.7, tt)
	if _capa != null:
		_capa.set_intensidad(lerpf(0.08, 0.22, tt))

func terminar_carga() -> void:
	_nivel_carga_obj = 0.0
	if _capa != null:
		_capa.set_intensidad(0.0)

# ---- Ejecucion de trayectoria ----
func iniciar_ejecucion() -> void:
	_en_ejecucion = true
	_nivel_rayos_obj = 1.0
	_intervalo_silueta = 0.03
	_estela_particulas.emitting = true
	_particulas.emitting = true
	if _capa != null:
		_capa.set_intensidad(0.32)
	_emitir_silueta()

func actualizar_ejecucion(_pos: Vector3, dir: Vector3) -> void:
	if dir.length() > 0.001:
		_estela_mat.direction = -dir
		_part_mat.direction = -dir

func terminar_ejecucion() -> void:
	_en_ejecucion = false
	_nivel_rayos_obj = 0.0
	_estela_particulas.emitting = false
	_particulas.emitting = false
	if _capa != null:
		_capa.set_intensidad(0.0)

# ---- Rayos de los golpes del combo ----
# Se invoca en cada golpe con el indice del combo (1..4). La intensidad objetivo
# escala con el indice (moderada -> media -> alta -> maxima) y decae sola, de modo
# que los rayos solo acompanan el momento del golpe. No hay rayos permanentes.
func golpe_ataque(indice: int) -> void:
	var t := clampf(float(indice - 1) / 3.0, 0.0, 1.0)
	_nivel_ataque_obj = lerpf(RAYOS_ATAQUE_MIN, RAYOS_ATAQUE_MAX, t)
	_t_ataque_rayos = DURACION_RAYOS_ATAQUE

# Detiene la generacion de nuevos rayos del golpe (p. ej. al cancelar por salto).
# Los rayos ya generados terminan su breve desvanecido natural.
func cancelar_ataque() -> void:
	_nivel_ataque_obj = 0.0
	_t_ataque_rayos = 0.0

func _process(delta: float) -> void:
	_nivel_rayos = move_toward(_nivel_rayos, _nivel_rayos_obj, delta * 4.0)
	_nivel_carga = move_toward(_nivel_carga, _nivel_carga_obj, delta * 3.0)
	_rayos.intensidad = _nivel_rayos
	_rayos_carga.intensidad = _nivel_carga
	# Rayos del golpe: suben rapido con el impacto y decaen solos al terminar.
	if _t_ataque_rayos > 0.0:
		_t_ataque_rayos -= delta
		if _t_ataque_rayos <= 0.0:
			_nivel_ataque_obj = 0.0
	_nivel_ataque = move_toward(_nivel_ataque, _nivel_ataque_obj, delta * 12.0)
	_rayos_ataque.intensidad = _nivel_ataque
	if _en_dash or _en_ejecucion:
		_t_silueta -= delta
		if _t_silueta <= 0.0:
			_t_silueta = _intervalo_silueta
			_emitir_silueta()

func _emitir_silueta() -> void:
	if _jugador == null:
		return
	var modelo := _jugador.get_node_or_null("Visual/Pose/Volteo/Modelo") as Node3D
	if modelo == null:
		return
	var padre := _jugador.get_parent()
	if padre == null:
		padre = get_tree().current_scene
	if padre == null:
		return
	var fantasma := modelo.duplicate() as Node3D
	if fantasma == null:
		return
	padre.add_child(fantasma)
	fantasma.global_transform = modelo.global_transform
	var mallas: Array[MeshInstance3D] = []
	_preparar_fantasma(fantasma, mallas)
	if mallas.is_empty():
		fantasma.queue_free()
		return
	var t := create_tween()
	t.tween_method(_set_transparencia.bind(mallas), 0.0, 1.0, 0.4)
	t.tween_callback(fantasma.queue_free)

func _preparar_fantasma(n: Node, mallas: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_override = _mat_fantasma
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mallas.append(mi)
	if n is AnimationPlayer:
		(n as AnimationPlayer).stop()
	for c in n.get_children():
		_preparar_fantasma(c, mallas)

func _set_transparencia(v: float, mallas: Array[MeshInstance3D]) -> void:
	for mi in mallas:
		if is_instance_valid(mi):
			mi.transparency = v
