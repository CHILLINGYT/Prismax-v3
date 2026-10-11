class_name CicloDiaNoche
extends Node3D
## =============================================================================
##  CICLO AUTOMÁTICO DE DÍA Y NOCHE (mapa de la ciudad)
## =============================================================================
##  Funciona solo al iniciar la partida: no hace falta que el jugador lo active.
##
##  Controla de forma coordinada:
##    * la posición, la energía y el color de la luz direccional que representa
##      al sol (la misma luz que el shader del cielo usa para dibujar el sol, la
##      luna, las estrellas y para mezclar día/atardecer/noche),
##    * la iluminación ambiental y el color de la niebla del WorldEnvironment,
##    * el color de las nubes del cielo.
##
##  El cielo (res://Cielo/cielo_ciudad.tres -> Cielo/shader/main.gdshader) deriva
##  su mezcla de día/noche del `LIGHT0_DIRECTION` de ESTA luz, así que cielo e
##  iluminación quedan siempre en fase sin sincronizar nada a mano.
##
##  Tiempos (fáciles de ajustar, ver el grupo "Tiempos"): día y noche se reparten
##  media vuelta de la órbita del sol cada uno. Por defecto, 900 s (15 min) de día
##  y 900 s de noche: a los 15 minutos de partida el sol se pone y llega la noche.
## =============================================================================

@export_group("Tiempos")
## Segundos de juego que dura el día (amanecer -> atardecer). 900 = 15 min.
@export var duracion_dia_segundos: float = 900.0
## Segundos de juego que dura la noche (atardecer -> amanecer).
@export var duracion_noche_segundos: float = 900.0
## Fase de arranque en [0, 1): 0.25 amanecer, 0.5 mediodía, 0.75 atardecer,
## 0.0/1.0 medianoche. Por defecto arranca poco después del amanecer.
@export_range(0.0, 1.0, 0.001) var fase_inicial: float = 0.28

@export_group("Referencias")
## Luz direccional que hace de sol (la que ve el shader del cielo).
@export var sol: DirectionalLight3D
## WorldEnvironment del mapa (su Environment y su Sky se ajustan aquí).
@export var entorno: WorldEnvironment

@export_group("Órbita del sol")
## Inclinación (grados) de la órbita alrededor del eje Z: reparte el amanecer y
## el atardecer hacia los lados en vez de por el eje Z. No cambia los tiempos.
@export_range(0.0, 45.0, 0.5) var inclinacion_orbita: float = 18.0
## Energía de la luz del sol con el sol en lo más alto.
@export var energia_sol_dia: float = 1.25
@export var color_sol_dia: Color = Color(1.0, 0.96, 0.9, 1.0)
## Color cálido de la luz al amanecer/atardecer.
@export var color_sol_atardecer: Color = Color(1.0, 0.55, 0.28, 1.0)

@export_group("Ambiente y niebla")
## Energía de la luz ambiental (día / noche).
@export var ambiente_energia_dia: float = 1.0
@export var ambiente_energia_noche: float = 1.1
## Cuánto del ambiente proviene del cielo (1) frente a un color plano (0).
@export var ambiente_contribucion_cielo_dia: float = 1.0
@export var ambiente_contribucion_cielo_noche: float = 0.35
## Color ambiental nocturno: mantiene la ciudad visible, sin quedar negra.
@export var ambiente_color_noche: Color = Color(0.18, 0.22, 0.36, 1.0)
@export var niebla_color_dia: Color = Color(0.73, 0.76, 0.81, 1.0)
@export var niebla_color_noche: Color = Color(0.05, 0.07, 0.12, 1.0)

@export_group("Nubes del cielo")
@export var nube_color_dia: Color = Color(0.9, 0.92, 0.95, 1.0)
@export var nube_color_noche: Color = Color(0.32, 0.34, 0.44, 1.0)

# Fase actual del ciclo en [0, 1). Avanza sola cada frame.
var _fase: float = 0.0


func _ready() -> void:
	_fase = fase_inicial
	if sol == null:
		push_warning("CicloDiaNoche: falta la referencia a la luz del sol.")
	if entorno == null:
		push_warning("CicloDiaNoche: falta la referencia al WorldEnvironment.")
	# Aplica ya el estado inicial para que el primer frame sea coherente.
	_aplicar()


func _process(delta: float) -> void:
	_avanzar(delta)
	_aplicar()


## Avanza la fase. El día y la noche ocupan media vuelta (0.5) cada uno, y cada
## mitad avanza a su propio ritmo, así que se pueden ajustar por separado.
func _avanzar(delta: float) -> void:
	var es_dia: bool = _fase >= 0.25 and _fase < 0.75
	var duracion: float = duracion_dia_segundos if es_dia else duracion_noche_segundos
	if duracion <= 0.001:
		return
	_fase = fposmod(_fase + delta * 0.5 / duracion, 1.0)


func _aplicar() -> void:
	var direccion_sol: Vector3 = _direccion_sol()
	var elevacion: float = direccion_sol.y
	if sol != null:
		_orientar_sol(direccion_sol)
		_ajustar_luz_sol(elevacion)
	_ajustar_entorno(elevacion)


## Dirección normalizada DESDE la escena HACIA el sol. Su componente Y es la
## elevación: > 0 de día, <= 0 de noche.
func _direccion_sol() -> Vector3:
	var angulo: float = (_fase - 0.25) * TAU
	var dir: Vector3 = Vector3(0.0, sin(angulo), -cos(angulo))
	# Girar sobre Z inclina la órbita sin cambiar cuándo cruza el horizonte.
	return dir.rotated(Vector3(0.0, 0.0, 1.0), deg_to_rad(inclinacion_orbita)).normalized()


## Orienta la luz para que emita DESDE el sol hacia la escena (hacia abajo con el
## sol alto). Godot pasa al shader del cielo esa misma dirección, que es la que el
## asset usa para día/noche y para dibujar sol y luna.
func _orientar_sol(direccion_sol: Vector3) -> void:
	var adelante: Vector3 = -direccion_sol
	var arriba: Vector3 = Vector3.UP
	if absf(adelante.dot(arriba)) > 0.999:
		arriba = Vector3.FORWARD
	var eje_z: Vector3 = -adelante
	var eje_x: Vector3 = arriba.cross(eje_z).normalized()
	if eje_x.length_squared() < 0.0001:
		eje_x = Vector3.RIGHT
	var eje_y: Vector3 = eje_z.cross(eje_x)
	sol.global_transform = Transform3D(Basis(eje_x, eje_y, eje_z), sol.global_position)


func _ajustar_luz_sol(elevacion: float) -> void:
	var alto: float = clampf(elevacion, 0.0, 1.0)
	# Se apaga al bajar del horizonte: nunca ilumina desde abajo.
	var energia: float = 0.0
	if elevacion > 0.0:
		energia = energia_sol_dia * pow(alto, 0.6)
	sol.light_energy = energia
	# Color cálido cerca del horizonte, blanco en lo alto.
	var calidez: float = clampf(1.0 - alto / 0.4, 0.0, 1.0)
	sol.light_color = color_sol_dia.lerp(color_sol_atardecer, calidez)


func _ajustar_entorno(elevacion: float) -> void:
	if entorno == null or entorno.environment == null:
		return
	var env: Environment = entorno.environment
	var dia: float = clampf(elevacion, 0.0, 1.0)
	var noche: float = clampf(-elevacion, 0.0, 1.0)
	# El ambiente viene del cielo de día; de noche se mezcla con un azul frío para
	# que los edificios y calles sigan leyéndose sin quedar en negro.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = lerpf(ambiente_energia_noche, ambiente_energia_dia, dia)
	env.ambient_light_sky_contribution = lerpf(
		ambiente_contribucion_cielo_noche, ambiente_contribucion_cielo_dia, dia)
	env.ambient_light_color = ambiente_color_noche
	env.fog_light_color = niebla_color_dia.lerp(niebla_color_noche, noche)
	_ajustar_nubes(noche)


## Oscurece las nubes del cielo de noche (el asset usa un solo color de nube).
func _ajustar_nubes(noche: float) -> void:
	var material: ShaderMaterial = _material_cielo()
	if material != null:
		material.set_shader_parameter("cloud_color", nube_color_dia.lerp(nube_color_noche, noche))


func _material_cielo() -> ShaderMaterial:
	if entorno == null or entorno.environment == null or entorno.environment.sky == null:
		return null
	return entorno.environment.sky.sky_material as ShaderMaterial
