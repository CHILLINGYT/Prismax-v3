class_name FuerzaRockAim
extends Node3D

## =============================================================================
##  RockAimIndicator.gd — indicador de apuntado del lanzamiento de roca (Q)
## =============================================================================
##  Mientras la roca está preparada dibuja:
##    · una TRAYECTORIA de puntos que sigue la parábola real del tiro (misma
##      velocidad y gravedad que tendrá la roca), y
##    · una RETÍCULA (anillo) justo en el punto al que apunta la cámara.
##
##  Así queda claro: "la roca se lanzará hacia este punto".
##
##  Todo se construye POR CÓDIGO: no hace falta ningún asset ni escena extra.
##  El nodo es puramente visual y efímero: Player.gd lo crea al empezar a
##  apuntar, llama a mostrar() cada fotograma y lo libera al lanzar o cancelar.
## =============================================================================

## Cuántos puntos forman la trayectoria (más = línea más continua).
const PUNTOS: int = 30
## Radio de cada punto de la trayectoria (unidades del mundo).
const RADIO_PUNTO: float = 0.075
const COLOR_TRAYECTORIA: Color = Color(1.0, 0.72, 0.28)
const COLOR_RETICULA: Color = Color(1.0, 0.93, 0.55)

var _puntos: MultiMeshInstance3D
var _anillo: MeshInstance3D


func _ready() -> void:
	# --- trayectoria: ristra de bolitas brillantes ----------------------------
	var esfera: SphereMesh = SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 2.0
	esfera.radial_segments = 8
	esfera.rings = 4

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = esfera
	multimesh.instance_count = PUNTOS
	multimesh.visible_instance_count = 0

	_puntos = MultiMeshInstance3D.new()
	_puntos.name = "Trayectoria"
	_puntos.multimesh = multimesh
	_puntos.material_override = _material(COLOR_TRAYECTORIA)
	_puntos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puntos)

	# --- retícula: anillo en el punto objetivo --------------------------------
	var anillo: TorusMesh = TorusMesh.new()
	anillo.inner_radius = 0.20
	anillo.outer_radius = 0.30
	anillo.rings = 24
	anillo.ring_segments = 8

	_anillo = MeshInstance3D.new()
	_anillo.name = "Reticula"
	_anillo.mesh = anillo
	_anillo.material_override = _material(COLOR_RETICULA)
	_anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_anillo)

	# Nada visible hasta que mostrar() lo pida (evita un anillo suelto en el
	# origen del mundo durante el primer fotograma).
	visible = false


func _material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.6
	# La roca va sujeta DELANTE del pecho y tapa justo el centro de la pantalla:
	# sin esto, la trayectoria y la retícula quedarían escondidas detrás de ella
	# y no se vería nada. Dibujándolo por encima del resto del mundo, el jugador
	# siempre ve hacia dónde va a salir la roca.
	m.no_depth_test = true
	m.render_priority = 1
	return m


## Dibuja la trayectoria y la retícula para el apuntado actual.
##   desde     -> de dónde sale la roca (las manos, en coordenadas del mundo)
##   velocidad -> vector de lanzamiento completo (dirección * velocidad)
##   objetivo  -> punto por el que pasa el CENTRO de la roca (donde acaba la
##                ristra de puntos: va subido el radio, ver Player._punto_vuelo)
##   gravedad  -> gravedad efectiva de la roca (unidades/segundo²)
##   reticula  -> punto que marca el anillo (el sitio apuntado de verdad; suele
##                ser el objetivo bajado el radio de la roca)
func mostrar(desde: Vector3, velocidad: Vector3, objetivo: Vector3,
		gravedad: float, reticula: Vector3) -> void:
	visible = true
	var veloz: float = maxf(velocidad.length(), 0.5)
	var g: Vector3 = Vector3(0.0, -maxf(gravedad, 0.0), 0.0)

	# Tiempo de vuelo hasta cruzar el plano del objetivo: así el último punto
	# cae prácticamente sobre la retícula. Si el objetivo está casi encima, se
	# usa el tiempo que tarda en recorrer la distancia total.
	var plano: Vector2 = Vector2(objetivo.x - desde.x, objetivo.z - desde.z)
	var vel_plano: float = Vector2(velocidad.x, velocidad.z).length()
	var t_fin: float = desde.distance_to(objetivo) / veloz
	if plano.length() > 0.5 and vel_plano > 0.5:
		t_fin = plano.length() / vel_plano
	t_fin = clampf(t_fin, 0.15, 4.0)

	var mm: MultiMesh = _puntos.multimesh
	mm.visible_instance_count = PUNTOS
	for i: int in PUNTOS:
		var u: float = float(i) / float(PUNTOS - 1)
		var t: float = t_fin * u
		var p: Vector3 = desde + velocidad * t + 0.5 * g * t * t
		# Los últimos puntos se encogen un poco: da sensación de profundidad.
		var escala: float = RADIO_PUNTO * lerpf(1.2, 0.8, u)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * escala), p))

	# Retícula en el punto apuntado, orientada hacia quien lanza.
	var hacia_mi: Vector3 = desde - reticula
	var posicion: Vector3 = reticula + Vector3.UP * 0.03
	if hacia_mi.length_squared() > 0.0001:
		var arriba: Vector3 = Vector3.UP
		if absf(hacia_mi.normalized().dot(Vector3.UP)) > 0.98:
			arriba = Vector3.FORWARD
		var base: Basis = Basis.looking_at(hacia_mi, arriba)
		# El agujero del toro va sobre su eje Y: se gira para que mire a quien
		# lanza (queda como una diana de frente).
		global_transform = Transform3D(
			base * Basis(Vector3.RIGHT, -PI / 2.0), posicion)
	else:
		global_position = posicion


## Deja de dibujar (el nodo lo libera quien lo creó).
func ocultar() -> void:
	visible = false
	if _puntos != null:
		_puntos.multimesh.visible_instance_count = 0