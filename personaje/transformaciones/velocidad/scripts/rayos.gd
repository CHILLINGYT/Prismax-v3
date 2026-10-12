class_name RayosVelocidad
extends MeshInstance3D

# Rayos electricos procedimentales billboardeados alrededor del personaje.
# intensidad 0 = invisibles. Se regeneran cada frame para dar sensacion dinamica.

var intensidad: float = 0.0:
	set(v):
		intensidad = clampf(v, 0.0, 1.0)
		visible = intensidad > 0.002

var radio: float = 0.9
var altura_min: float = -0.1
var altura_max: float = 1.2
var largo_min: float = 0.5
var largo_max: float = 1.3
# Cantidad de rayos para intensidad minima/maxima. Los valores por defecto
# conservan el comportamiento existente de dash/carga; los ataques usan su
# propia instancia con un rango mayor para que la progresion del combo se lea.
var rayos_min: int = 3
var rayos_max: int = 9
var color_nucleo: Color = Color(0.8, 1.0, 1.0, 0.55)
var color_brillo: Color = Color(0.3, 0.6, 1.0, 0.45)

var _mesh: ImmediateMesh
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	material_override = _crear_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.randomize()
	visible = false

func _crear_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta * 24.0
	_reconstruir()

func _reconstruir() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d()
	var cam_local := Vector3(0.0, 0.0, 5.0)
	if cam != null:
		cam_local = to_local(cam.global_position)

	var cantidad := int(lerpf(float(rayos_min), float(rayos_max), intensidad))
	var largo := lerpf(largo_min, largo_max, intensidad)
	var ancho := lerpf(0.008, 0.022, intensidad)
	for i in cantidad:
		var inicio := Vector3(
			_rng.randf_range(-radio, radio),
			_rng.randf_range(altura_min, altura_max),
			_rng.randf_range(-radio, radio)
		)
		var pts := PackedVector3Array([inicio])
		var actual := inicio
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-0.4, 0.6),
			_rng.randf_range(-1.0, 1.0)
		).normalized()
		var segs := 5
		for s in segs:
			dir = (dir + Vector3(
				_rng.randf_range(-0.8, 0.8),
				_rng.randf_range(-0.5, 0.5),
				_rng.randf_range(-0.8, 0.8)
			)).normalized()
			actual += dir * (largo / float(segs))
			pts.append(actual)
		var c: Color = color_nucleo.lerp(color_brillo, _rng.randf())
		_agregar_ribbon(pts, cam_local, ancho, c)
	_mesh.surface_end()

func _agregar_ribbon(pts: PackedVector3Array, cam_local: Vector3, ancho: float, c: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		if seg.length() < 0.0001:
			continue
		var medio := (a + b) * 0.5
		var hacia_cam := cam_local - medio
		if hacia_cam.length() < 0.0001:
			hacia_cam = Vector3(0.0, 0.0, 1.0)
		var lado := seg.cross(hacia_cam).normalized() * ancho
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(a + lado)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(a - lado)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(b + lado)

		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(b + lado)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(a - lado)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(b - lado)