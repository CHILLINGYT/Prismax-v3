class_name Sky3DPuente
extends Node3D
## =============================================================================
##  CIELO "SKY 3D" ADAPTADO AL CICLO DE DÍA Y NOCHE QUE YA TENÍA EL JUEGO
## =============================================================================
##  El asset Sky 3D trae su propio ciclo horario (Sky3D.gd / TimeOfDay.gd) y sus
##  propias luces de sol y luna. Ese ciclo NO se usa aquí: el juego conserva su
##  `CicloDiaNoche` tal cual (mismas duraciones, mismos horarios, misma luz `Sol`
##  y mismo WorldEnvironment). Lo que se aprovecha del asset es su CIELO: el
##  material `SkyMaterial.gdshader` (atmósfera, disco solar, luna con textura,
##  estrellas, Vía Láctea y nubes) y su nodo `SkyDome`, que ajusta todo eso.
##
##  El puente hace tres cosas y ninguna más:
##    1. Pone el material del cielo del asset en el Sky del WorldEnvironment de
##       siempre (el entorno, la niebla, el tonemap y el ambiente son los del
##       juego, no se duplican).
##    2. Alimenta a `SkyDome` con la posición REAL del sol, leída de la luz `Sol`
##       que mueve `CicloDiaNoche`, y con la de la luna (su opuesta). El shader
##       del asset toma las direcciones de las dos luces direccionales de la
##       escena (LIGHT0 = `Sol`, LIGHT1 = la luna de este puente), así que el sol
##       y la luna que dibuja el cielo son exactamente los del ciclo.
##    3. Enciende una luz de luna (la única luz que se añade, sin sombras y de
##       energía baja) sólo cuando la luna está sobre el horizonte: es la luz
##       direccional nocturna natural. Al ir opuesta al sol no gasta nada de día.
##
##  Nada de esto toca la duración, la lógica, las variables ni los horarios del
##  ciclo: si el ciclo cambia de ritmo, el cielo y la luna lo siguen solos.
## =============================================================================

const RUTA_SKYDOME := "res://addons/sky_3d/src/SkyDome.gd"
const RUTA_SHADER := "res://addons/sky_3d/shaders/SkyMaterial.gdshader"

## Color del disco solar según la altura del sol (de mayor a menor elevación):
## blanco cálido en lo alto, dorado al bajar, naranja y rojizo al ponerse. La
## elevación es la componente Y de la dirección hacia el sol (-1..1); se mezcla de
## forma continua, así que la transición no tiene saltos.
const COLOR_DISCO := [
	[0.55, Color(1.0, 0.98, 0.94)],
	[0.25, Color(1.0, 0.95, 0.82)],
	[0.10, Color(1.0, 0.88, 0.66)],
	[0.03, Color(1.0, 0.72, 0.44)],
	[-0.01, Color(1.0, 0.53, 0.26)],
	[-0.06, Color(0.96, 0.38, 0.21)],
]

## Color cálido del horizonte (tinte del amanecer/atardecer): de un dorado suave a
## naranja, rojo y por último rosado/lila cuando el sol ya se ha puesto.
const COLOR_HORIZONTE := [
	[0.55, Color(1.0, 0.88, 0.74)],
	[0.20, Color(1.0, 0.80, 0.58)],
	[0.06, Color(1.0, 0.66, 0.42)],
	[0.01, Color(1.0, 0.52, 0.32)],
	[-0.04, Color(0.98, 0.44, 0.34)],
	[-0.09, Color(0.80, 0.38, 0.42)],
	[-0.16, Color(0.45, 0.28, 0.40)],
	[-0.30, Color(0.30, 0.24, 0.34)],
]

@export_group("Referencias")
## Luz direccional que hace de sol (la misma que mueve `CicloDiaNoche`).
@export var sol: DirectionalLight3D
## WorldEnvironment del mapa (sólo se le cambia el material del cielo).
@export var entorno: WorldEnvironment

@export_group("Sol y luna")
## Diámetro angular del sol en grados. El real mide ~0,53°: algo más para que se
## distinga con claridad sin parecer de dibujos animados.
@export var diametro_sol_grados: float = 1.05
## Diámetro angular de la luna en grados. La real mide ~0,52°: aquí unas tres veces
## más, para que se lean su textura y su fase sin dejar de ser una luna natural
## (antes eran 8°: quince veces la real, y llenaba el cielo).
@export var diametro_luna_grados: float = 1.60
## Brillo del disco solar con el sol alto.
@export var brillo_disco_solar: float = 18.0
## Cuánto se refuerza el disco solar al acercarse al horizonte.
@export var refuerzo_disco_horizonte: float = 1.5
## Energía máxima de la luz de la luna, con la luna en lo más alto. Es luz ambiente
## nocturna: baja a propósito para que la noche siga siendo noche.
@export var luna_energia_max: float = 0.22
@export var luna_color: Color = Color(0.60, 0.72, 0.98, 1.0)

@export_group("Cielo")
## Nubes del asset: bajadas respecto a sus valores por defecto porque el cielo
## diurno quedaba casi tapado y no se veía el disco del sol.
@export var nubes_cumulos: float = 0.40
@export var nubes_cirros: float = 0.34

var _material: ShaderMaterial
var _domo: SkyDome
var _luna: DirectionalLight3D
var _env: Environment
# Dirección de la escena hacia el sol en el último ajuste (para no rehacer el
# cielo cuando el sol no se ha movido de forma apreciable).
var _ultimo_sol: Vector3 = Vector3(9.0, 9.0, 9.0)


func _ready() -> void:
	if sol == null or entorno == null or entorno.environment == null:
		push_warning("Sky3DPuente: faltan la luz del sol o el WorldEnvironment.")
		return
	_env = entorno.environment
	_crear_cielo()
	_crear_luna()
	_crear_domo()
	set_process(true)
	_aplicar_sol(true)
	print("[cielo] Sky 3D montado en el entorno del juego: %s" % resumen())


func _process(_delta: float) -> void:
	_aplicar_sol(false)


## Material del cielo del asset dentro del Sky del entorno de siempre. Se
## conserva el Sky (y su `radiance_size` reducido, porque el ambiente del juego
## proviene del cielo y así no cuesta de más) y se cambia sólo su material.
func _crear_cielo() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load(RUTA_SHADER)
	# El cielo del asset se dibuja antes que nada (prioridad negativa), como en
	# su propio demo.
	_material.render_priority = -128
	var cielo: Sky = _env.sky
	if cielo == null:
		cielo = Sky.new()
		_env.sky = cielo
	cielo.sky_material = _material
	cielo.radiance_size = Sky.RADIANCE_SIZE_128


## Luz de la luna: opuesta al sol, sin sombras (no se abusa del coste). Su energía
## se calcula cada fotograma; la luz se mantiene SIEMPRE visible (con energía 0 de
## día) para que su dirección nunca desaparezca de la escena.
func _crear_luna() -> void:
	_luna = DirectionalLight3D.new()
	_luna.name = "Luna3D"
	_luna.light_color = luna_color
	_luna.light_energy = 0.0
	_luna.light_specular = 0.1
	_luna.light_angular_distance = 1.0
	_luna.shadow_enabled = false
	# El cielo ya no lee las luces direccionales (usa los uniformes del puente), así
	# que las dos luces se limitan a iluminar la escena.
	_luna.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	if sol != null:
		sol.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_luna)


## `SkyDome` del asset, con el cielo ya montado. No se le da luz de sol (la del
## ciclo manda) y sí la de la luna, para que él la coloque y oriente la textura
## lunar. Su niebla de pantalla se apaga: la niebla del juego es la única.
func _crear_domo() -> void:
	_domo = load(RUTA_SKYDOME).new()
	_domo.name = "DomoSky3D"
	_domo.environment = _env
	add_child(_domo)
	_domo.sun_light_path = NodePath("")
	_domo.moon_light_path = _domo.get_path_to(_luna)
	# La energía y las sombras de la luna las lleva este puente, no el domo.
	_domo.moon_light_enabled = false
	_domo.fog_visible = false
	# Tamaños angulares NATURALES (ver la cabecera): el disco solar se mide como
	# cuerda en un círculo unidad y la luna como radio de esfera a distancia 1.
	_domo.sun_disk_size = 2.0 * sin(deg_to_rad(diametro_sol_grados) * 0.25)
	_domo.moon_size = sin(deg_to_rad(diametro_luna_grados) * 0.5)
	_domo.moon_color = Color.WHITE
	_domo.sun_disk_intensity = brillo_disco_solar
	_domo.cumulus_coverage = nubes_cumulos
	_domo.cirrus_coverage = nubes_cirros
	# Arranque en el estado que marca la luz del sol de verdad.
	_aplicar_sol(true)


## Lee la dirección del sol de la luz `Sol` y con ella actualiza el cielo, la luna
## y la luz lunar. `forzar` lo hace aunque el sol no se haya movido (arranque).
func _aplicar_sol(forzar: bool) -> void:
	if _domo == null or sol == null or _material == null:
		return
	# La base de la luz guarda, en su eje +Z, la dirección de la escena al sol.
	var hacia_sol: Vector3 = sol.global_transform.basis.z.normalized()
	if not forzar and hacia_sol.distance_to(_ultimo_sol) < 0.0002:
		return
	_ultimo_sol = hacia_sol
	var y := hacia_sol.y
	# La luna va opuesta al sol: sale cuando él se pone y es llena en su cenit.
	var hacia_luna: Vector3 = -hacia_sol

	# --- Cielo: direcciones y fundidos ---------------------------------------
	_material.set_shader_parameter("sun_direction", hacia_sol)
	_material.set_shader_parameter("moon_direction", hacia_luna)
	# El sol se apaga al hundirse bajo el horizonte (~1,7°) y la luna se enciende
	# subiendo los primeros ~2°: ninguno aparece ni desaparece de golpe.
	_material.set_shader_parameter("sun_visibility", smoothstep(-0.03, 0.015, y))
	_material.set_shader_parameter("moon_visibility", smoothstep(-0.005, 0.035, hacia_luna.y))

	# --- Disco solar: color y brillo según su altura -------------------------
	_domo.sun_disk_color = _gradiente(y, COLOR_DISCO)
	_domo.sun_disk_intensity = brillo_disco_solar * lerpf(1.0,
			refuerzo_disco_horizonte, smoothstep(0.30, 0.0, y))
	# Tinte cálido del horizonte (amanecer/atardecer) y color de la luz del sol: el
	# asset tiñe con él las nubes, así que cielo e iluminación van en fase.
	_domo.atm_horizon_light_tint = _gradiente(y, COLOR_HORIZONTE)
	_material.set_shader_parameter("sun_light_color", sol.light_color)
	# Estrellas: sólo cuando el cielo está de verdad oscuro. El asset las dibuja en
	# cuanto el sol baja de 17° de altura (todavía hay luz), así que su brillo se
	# funde aquí con la oscuridad real del cielo. El alfa del mapa (0,855) se
	# conserva: el shader lo usa para el contraste del fondo estrellado.
	var noche: float = 1.0 - smoothstep(-0.16, -0.02, y)
	_domo.starmap_color = Color(0.71 * noche, 0.71 * noche, 0.71 * noche, 0.855)
	_domo.star_field_color = Color(noche, noche, noche)

	# --- Luna: posición (la coloca el domo) y luz ----------------------------
	# Ángulos del asset: `altitude` es el ángulo polar (0 = cenit, PI/2 = horizonte).
	_domo.sun_altitude = acos(clampf(y, -1.0, 1.0))
	_domo.sun_azimuth = atan2(hacia_sol.x, hacia_sol.z)
	_domo.moon_altitude = acos(clampf(hacia_luna.y, -1.0, 1.0))
	_domo.moon_azimuth = atan2(hacia_luna.x, hacia_luna.z)
	# La luz de la luna sube con su altura y se apaga con el mismo fundido que su
	# disco: nunca da un salto de iluminación.
	var alto: float = clampf(hacia_luna.y, 0.0, 1.0)
	var vis: float = smoothstep(-0.005, 0.035, hacia_luna.y)
	_luna.light_energy = alto * luna_energia_max * vis


## Interpola un color a lo largo de una lista de pares [elevación, color] ordenada de
## mayor a menor elevación. Devuelve un color CONTINUO para cualquier altura del sol,
## que es lo que hace graduales las transiciones del amanecer y del atardecer.
static func _gradiente(y: float, puntos: Array) -> Color:
	if puntos.is_empty():
		return Color.WHITE
	if y >= float(puntos[0][0]):
		return puntos[0][1] as Color
	for i in range(puntos.size() - 1):
		var a: Array = puntos[i]
		var b: Array = puntos[i + 1]
		if y >= float(b[0]):
			var t: float = clampf((y - float(b[0])) / (float(a[0]) - float(b[0])), 0.0, 1.0)
			return (b[1] as Color).lerp(a[1] as Color, t)
	return puntos[puntos.size() - 1][1] as Color


## Resumen del estado del cielo (para las comprobaciones del juego).
func resumen() -> String:
	if _domo == null:
		return "cielo sin montar"
	var hacia_sol: Vector3 = sol.global_transform.basis.z.normalized()
	return "sol(y=%.2f vis=%.2f brillo=%.1f) luna(y=%.2f luz=%.2f vis=%.2f) dia=%s" % [
		hacia_sol.y, float(_material.get_shader_parameter("sun_visibility")),
		_domo.sun_disk_intensity, -hacia_sol.y, _luna.light_energy,
		float(_material.get_shader_parameter("moon_visibility")), str(_domo.is_day())]