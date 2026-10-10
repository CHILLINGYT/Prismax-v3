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

@export_group("Referencias")
## Luz direccional que hace de sol (la misma que mueve `CicloDiaNoche`).
@export var sol: DirectionalLight3D
## WorldEnvironment del mapa (sólo se le cambia el material del cielo).
@export var entorno: WorldEnvironment

@export_group("Luna")
## Energía máxima de la luz de la luna, con la luna en lo más alto. Es luz
## ambiente nocturna: baja a propósito para que la noche siga siendo noche.
@export var luna_energia_max: float = 0.22
@export var luna_color: Color = Color(0.60, 0.72, 0.98, 1.0)

@export_group("Cielo")
## Brillo del disco solar en el cielo.
@export var brillo_disco_solar: float = 16.0
## Tamaño del disco solar (fracción del cielo).
@export var tamano_disco_solar: float = 0.03

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


## Luz de la luna: opuesta al sol, sin sombras (no se abusa del coste) y apagada
## mientras no haga falta.
func _crear_luna() -> void:
	_luna = DirectionalLight3D.new()
	_luna.name = "Luna3D"
	_luna.light_color = luna_color
	_luna.light_energy = 0.0
	_luna.light_specular = 0.1
	_luna.light_angular_distance = 1.0
	_luna.shadow_enabled = false
	_luna.visible = false
	# Se cuelga del mapa (no del puente) para que su transformación sea global.
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
	_domo.sun_disk_intensity = brillo_disco_solar
	_domo.sun_disk_size = tamano_disco_solar
	# Nubes del asset suavizadas: con sus valores por defecto el cielo diurno
	# quedaba casi tapado y no se veía ni el disco del sol.
	_domo.cumulus_coverage = 0.40
	_domo.cirrus_coverage = 0.34
	# Arranque en el estado que marca la luz del sol de verdad.
	_aplicar_sol(true)


## Lee la dirección del sol de la luz `Sol` y con ella actualiza el cielo y la
## luna. `forzar` lo hace aunque el sol no se haya movido (arranque).
func _aplicar_sol(forzar: bool) -> void:
	if _domo == null or sol == null:
		return
	# La base de la luz guarda, en su eje +Z, la dirección de la escena al sol.
	var hacia_sol: Vector3 = sol.global_transform.basis.z.normalized()
	if not forzar and hacia_sol.distance_to(_ultimo_sol) < 0.0002:
		return
	_ultimo_sol = hacia_sol
	# Ángulos del asset: `altitude` es el ángulo polar (0 = cenit, PI/2 = horizonte).
	_domo.sun_altitude = acos(clampf(hacia_sol.y, -1.0, 1.0))
	_domo.sun_azimuth = atan2(hacia_sol.x, hacia_sol.z)
	# La luna va opuesta al sol: sale cuando él se pone y es llena en su cenit.
	var hacia_luna: Vector3 = -hacia_sol
	_domo.moon_altitude = acos(clampf(hacia_luna.y, -1.0, 1.0))
	_domo.moon_azimuth = atan2(hacia_luna.x, hacia_luna.z)
	# La luz de la luna sólo existe mientras la luna esté sobre el horizonte.
	var alto: float = clampf(hacia_luna.y, 0.0, 1.0)
	var energia: float = alto * luna_energia_max
	_luna.light_energy = energia
	_luna.visible = energia > 0.002


## Resumen del estado del cielo (para las comprobaciones del juego).
func resumen() -> String:
	if _domo == null:
		return "cielo sin montar"
	var hacia_sol: Vector3 = sol.global_transform.basis.z.normalized()
	return "sol(y=%.2f alt=%.1f° az=%.1f°) luna(energia=%.2f visible=%s) dia=%s" % [
		hacia_sol.y, rad_to_deg(_domo.sun_altitude), rad_to_deg(_domo.sun_azimuth),
		_luna.light_energy, str(_luna.visible), str(_domo.is_day())]