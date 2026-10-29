extends Node3D

signal pico_alcanzado
signal terminado

@export var color: Color = Color(0.2, 0.7, 1.0)   # elige tu color
@export var diametro := 2.2
@export var cantidad_rayos := 24
@export var largo_rayos := 3.5
@export var tiempo_subida := 0.25
@export var tiempo_bajada := 0.45

var _nucleo: MeshInstance3D
var _halo: MeshInstance3D
var _luz: OmniLight3D
var _rayos: Array[Node3D] = []
var _tween: Tween

func _ready() -> void:
	_construir()
	visible = false

func _material(c: Color, energia: float, alfa := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alfa)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energia
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alfa < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _construir() -> void:
	# Núcleo: color claro, casi blanco
	_nucleo = MeshInstance3D.new()
	_nucleo.mesh = SphereMesh.new()  # radio 0.5 -> escala = diámetro
	_nucleo.material_override = _material(color.lightened(0.7), 3.0)
	add_child(_nucleo)

	# Halo: más grande y translúcido
	_halo = MeshInstance3D.new()
	_halo.mesh = SphereMesh.new()
	_halo.material_override = _material(color, 2.0, 0.35)
	add_child(_halo)

	# Luz
	_luz = OmniLight3D.new()
	_luz.light_color = color
	_luz.omni_range = 8.0
	_luz.light_energy = 0.0
	add_child(_luz)

	# Rayos: un pivote por rayo, con un cono hijo
	var cono := CylinderMesh.new()
	cono.top_radius = 0.0
	cono.bottom_radius = 0.07
	cono.height = 1.0
	cono.radial_segments = 6
	cono.rings = 1
	var mat_rayo := _material(color, 3.0, 0.8)

	for i in cantidad_rayos:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var pivote := Node3D.new()
		pivote.basis = Basis(Quaternion(Vector3.UP, dir))  # eje Y apunta a dir
		pivote.scale = Vector3(1, 0.001, 1)
		var malla := MeshInstance3D.new()
		malla.mesh = cono
		malla.material_override = mat_rayo
		malla.position.y = 0.5  # base en el centro, punta hacia afuera
		pivote.add_child(malla)
		add_child(pivote)
		_rayos.append(pivote)

func reproducir() -> void:
	if _tween:
		_tween.kill()
	visible = true
	var cero := Vector3.ONE * 0.001

	_tween = create_tween().set_parallel(true)

	# --- SUBIDA ---
	_tween.tween_property(_nucleo, "scale", Vector3.ONE * diametro, tiempo_subida)\
		.from(cero).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_halo, "scale", Vector3.ONE * diametro * 1.4, tiempo_subida)\
		.from(cero).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_luz, "light_energy", 8.0, tiempo_subida).from(0.0)
	for r in _rayos:
		_tween.tween_property(r, "scale:y", largo_rayos * randf_range(0.6, 1.2), tiempo_subida)\
			.from(0.001).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# --- PICO: aquí cambias de forma ---
	_tween.chain().tween_callback(pico_alcanzado.emit)

	# --- BAJADA (empieza junto al callback) ---
	_tween.tween_property(_nucleo, "scale", cero, tiempo_bajada).set_ease(Tween.EASE_IN)
	_tween.tween_property(_halo, "scale", Vector3.ONE * diametro * 2.0, tiempo_bajada)
	_tween.tween_property(_halo, "transparency", 1.0, tiempo_bajada)
	_tween.tween_property(_luz, "light_energy", 0.0, tiempo_bajada)
	for r in _rayos:
		_tween.tween_property(r, "scale:y", 0.001, tiempo_bajada)

	_tween.chain().tween_callback(_fin)

func _fin() -> void:
	visible = false
	_halo.transparency = 0.0
	terminado.emit()
