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
##
##  LAS TRANSICIONES TIENEN DURACIÓN PROPIA (7 min por defecto, ver
##  `duracion_amanecer_segundos` / `duracion_anochecer_segundos`). No son la
##  sinusoide de la órbita: el sol recorre su órbita como siempre, pero su ALTURA
##  sigue un perfil de mesetas (día y noche) y rampas de duración fija. Así el
##  anochecer y el amanecer duran minutos exactos de juego y la noche queda CERRADA
##  al terminar el anochecer (no a medianoche), sin saltos ni parpadeos: cada rampa
##  arranca y termina con pendiente nula.
## =============================================================================

@export_group("Tiempos")
## Segundos de juego que dura la MITAD DIURNA del ciclo (0.25 -> 0.75), que incluye
## el amanecer, la meseta de DÍA PLENO y el anochecer. 600 = 90 s de amanecer +
## 420 s (7 min) de día pleno + 90 s de anochecer.
@export var duracion_dia_segundos: float = 600.0
## Segundos de juego que dura la MITAD NOCTURNA (0.75 -> 0.25), que incluye la
## meseta de NOCHE y el amanecer. 420 = 7 min de noche plena + 90 s de amanecer.
@export var duracion_noche_segundos: float = 420.0
## Duración REAL (s de juego) de la transición del AMANECER: del sol asomando al
## día pleno. 90 = 1,5 min.
@export var duracion_amanecer_segundos: float = 90.0
## Duración REAL (s de juego) de la transición del ANOCHECER: de la luz de día a la
## noche cerrada. 90 = 1,5 min. Termina en el atardecer (fase 0.75), que es donde los
## faroles acaban de encenderse y la noche queda completa.
@export var duracion_anochecer_segundos: float = 90.0
## Fase de arranque en [0, 1): 0.25 amanecer, 0.5 mediodía, 0.75 atardecer,
## 0.0/1.0 medianoche. Sólo se usa si `arrancar_en_dia` está apagado.
@export_range(0.0, 1.0, 0.001) var fase_inicial: float = 0.25
## ¿La partida arranca a PLENO DÍA? Es lo que se quiere en una PARTIDA NUEVA: el
## sol ya está alto y la iluminación es diurna; a partir de ahí el ciclo corre solo
## (7 min de día, 1,5 min de anochecer, 7 min de noche, 1,5 min de amanecer...) y se
## repite indefinidamente. Se calcula desde las duraciones de arriba, así que
## sigue siendo correcto si se cambian los tiempos. NO reinicia el ciclo cada vez
## que se carga una escena: sólo se lee al entrar en el mapa.
@export var arrancar_en_dia: bool = true

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

# --- Perfil de altura del sol -------------------------------------------------
# Altura = componente Y de la dirección hacia el sol ANTES de inclinar la órbita
# (la inclinación de 18° la deja en ~0.95 de ese valor). Con estas tres cotas el
# día y la noche son MESETAS y el amanecer/el anochecer son rampas de duración
# fija: es lo que hace que la transición dure minutos exactos en lugar de depender
# de lo deprisa que suba una sinusoide.
## Meseta de DÍA: el sol en lo más alto.
const ALTURA_DIA := 1.0
## Altura a la que la noche está CERRADA (fin del anochecer / principio del
## amanecer). El sol queda bien por debajo del horizonte (unos 33°), así que el
## cielo está oscuro de verdad aunque no sea medianoche.
const ALTURA_NOCHE := -0.55
## Punto más bajo de la noche (medianoche). La oscuridad no cambia —ya está al
## máximo—, pero la luna gana altura y recorre el cielo en vez de quedarse fija.
const ALTURA_MEDIANOCHE := -0.90

# Fase actual del ciclo en [0, 1). Avanza sola cada frame.
var _fase: float = 0.0
# Fase con la que arrancó ESTA partida (para el diagnóstico de minutos).
var _fase_arranque: float = 0.25


func _ready() -> void:
	add_to_group("ciclo_dia_noche")
	_fase_arranque = fase_dia_pleno() if arrancar_en_dia else fase_inicial
	_fase = _fase_arranque
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
## Fase actual del ciclo en [0, 1). La leen los sitios que tienen que ir A LA HORA
## DEL CICLO sin crear un segundo reloj (por ejemplo el interior de la casa, que
## arranca con la fase que tenía la calle al entrar). No se llama `fase()` porque
## media clase usa ese nombre para sus parámetros.
func fase_actual() -> float:
	return _fase


## Coloca el ciclo en una fase concreta (y aplica ya su estado). Sólo lo usan los
## cambios de escena que CONTINÚAN el tiempo real: entrar y salir de la casa. Si no
## se llama, el ciclo arranca como siempre (en DÍA, o en `fase_inicial`).
func poner_fase(f: float) -> void:
	_fase = fposmod(f, 1.0)
	_aplicar()


func _avanzar(delta: float) -> void:
	var es_dia: bool = _fase >= 0.25 and _fase < 0.75
	var duracion: float = duracion_dia_segundos if es_dia else duracion_noche_segundos
	if duracion <= 0.001:
		return
	_fase = fposmod(_fase + delta * 0.5 / duracion, 1.0)


func _aplicar() -> void:
	var direccion_sol: Vector3 = _direccion_sol()
	if sol != null:
		_orientar_sol(direccion_sol)
		# La LUZ del sol sigue su altura real (se apaga al ponerse), pero la
		# oscuridad del ambiente, la niebla y las nubes la manda `_oscuridad()`, que
		# llega a su valor de noche justo al terminar el anochecer.
		_ajustar_luz_sol(direccion_sol.y)
	_ajustar_entorno()


## Tramo de fase que ocupa cada transición dentro de la mitad diurna (0.25 -> 0.75),
## que se recorre en `duracion_dia_segundos`. Si los dos tramos no caben en esa
## mitad se reparten en proporción, de modo que nunca se solapan.
func _tramos() -> Vector2:
	var a: float = maxf(duracion_amanecer_segundos, 0.0) * 0.5 / maxf(duracion_dia_segundos, 0.001)
	var o: float = maxf(duracion_anochecer_segundos, 0.0) * 0.5 / maxf(duracion_dia_segundos, 0.001)
	var suma: float = a + o
	if suma > 0.5:
		var k: float = 0.5 / suma
		a *= k
		o *= k
	return Vector2(a, o)


## Primera fase de la MESETA DE DÍA PLENO: justo cuando acaba de terminar el
## amanecer. Es la fase con la que arranca una partida nueva (`arrancar_en_dia`), de
## modo que el juego empieza con el sol ya alto y la iluminación de día, sin
## atravesar una transición.
func fase_dia_pleno() -> float:
	return fposmod(0.25 + _tramos().x, 1.0)


## Fases de referencia del alumbrado público, para que las farolas NO tengan su
## propio horario y sigan siempre al ciclo:
##   x = fase en la que empiezan a encenderse (principio del anochecer),
##   y = fase en la que están del todo encendidas (noche cerrada, 0.75),
##   z = fase en la que empiezan a apagarse (principio del amanecer),
##   w = fase en la que están del todo apagadas (día pleno).
func fases_farolas() -> Vector4:
	var tramos := _tramos()
	return Vector4(0.75 - tramos.y, 0.75, 0.25, 0.25 + tramos.x)


## Altura del sol (-1..1) en esa fase: rampas de duración fija en el amanecer y el
## anochecer, y mesetas planas en el día y la noche. Cada rampa empieza y acaba con
## pendiente NULA (smoothstep), así que no hay cambios bruscos de brillo.
func _perfil_altura(fase: float) -> float:
	var tramos := _tramos()
	var amanecer: float = tramos.x
	var anochecer: float = tramos.y
	var fin_amanecer: float = 0.25 + amanecer
	var inicio_anochecer: float = 0.75 - anochecer
	if amanecer > 0.0001 and fase >= 0.25 and fase < fin_amanecer:
		var u: float = (fase - 0.25) / amanecer
		return lerpf(ALTURA_NOCHE, ALTURA_DIA, smoothstep(0.0, 1.0, u))
	if fase >= fin_amanecer and fase < inicio_anochecer:
		return ALTURA_DIA
	if anochecer > 0.0001 and fase >= inicio_anochecer and fase < 0.75:
		var u: float = (fase - inicio_anochecer) / anochecer
		return lerpf(ALTURA_DIA, ALTURA_NOCHE, smoothstep(0.0, 1.0, u))
	# Noche: el sol sigue bajando hasta medianoche y vuelve a subir, de forma que la
	# luna recorra el cielo. La oscuridad NO cambia (ya está al máximo).
	var s: float = clampf(fposmod(fase - 0.75, 1.0) / 0.5, 0.0, 1.0)
	return lerpf(ALTURA_NOCHE, ALTURA_MEDIANOCHE, 0.5 - 0.5 * cos(TAU * s))


## Oscuridad del cielo: 0 = día pleno, 1 = noche cerrada. Sale del MISMO perfil de
## altura, así que vale 0 en la meseta de día, sube 0 -> 1 durante el anochecer y
## baja 1 -> 0 durante el amanecer: la iluminación, la niebla y las nubes llegan a
## su valor de noche exactamente cuando el anochecer termina.
func _oscuridad() -> float:
	var recorrido: float = ALTURA_DIA - ALTURA_NOCHE
	if recorrido <= 0.0001:
		return 0.0
	return clampf((ALTURA_DIA - _perfil_altura(_fase)) / recorrido, 0.0, 1.0)


## Dirección normalizada DESDE la escena HACIA el sol. El recorrido horizontal es el
## de siempre (el sol cruza el cielo de un horizonte al otro) y su componente Y es
## la del perfil: > 0 de día, <= 0 de noche.
func _direccion_sol() -> Vector3:
	var angulo: float = (_fase - 0.25) * TAU
	var horizontal: float = -cos(angulo)
	var altura: float = _perfil_altura(_fase)
	var dir: Vector3 = Vector3(0.0, altura, horizontal * sqrt(maxf(1.0 - altura * altura, 0.0)))
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


func _ajustar_entorno() -> void:
	if entorno == null or entorno.environment == null:
		return
	var env: Environment = entorno.environment
	# La oscuridad la manda el perfil de transiciones (rampas de duración fija), no
	# la altura instantánea del sol: así la noche llega completa al terminar el
	# anochecer y no a medianoche.
	var oscuridad: float = _oscuridad()
	var dia: float = 1.0 - oscuridad
	# El ambiente viene del cielo de día; de noche se mezcla con un azul frío para
	# que los edificios y calles sigan leyéndose sin quedar en negro.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = lerpf(ambiente_energia_noche, ambiente_energia_dia, dia)
	env.ambient_light_sky_contribution = lerpf(
		ambiente_contribucion_cielo_noche, ambiente_contribucion_cielo_dia, dia)
	env.ambient_light_color = ambiente_color_noche
	env.fog_light_color = niebla_color_dia.lerp(niebla_color_noche, oscuridad)
	_ajustar_nubes(oscuridad)


## Oscurece las nubes del cielo de noche (el asset usa un solo color de nube).
func _ajustar_nubes(oscuridad: float) -> void:
	var material: ShaderMaterial = _material_cielo()
	if material != null:
		material.set_shader_parameter("cloud_color", nube_color_dia.lerp(nube_color_noche, oscuridad))


func _material_cielo() -> ShaderMaterial:
	if entorno == null or entorno.environment == null or entorno.environment.sky == null:
		return null
	return entorno.environment.sky.sky_material as ShaderMaterial


## Resumen del horario para las comprobaciones del juego: fase, minutos de juego
## desde el arranque, altura del sol, oscuridad y las fases en las que empiezan y
## acaban las dos transiciones. También la duración real de cada rampa en segundos.
func resumen_horario() -> String:
	var tramos := _tramos()
	var fin_amanecer: float = 0.25 + tramos.x
	var inicio_anochecer: float = 0.75 - tramos.y
	return ("fase=%.4f min=%.2f altura=%.3f oscuridad=%.2f | amanecer 0.25->%.4f (%.0f s) "
			+ "anochecer %.4f->0.75 (%.0f s)") % [
		_fase, minutos_desde_arranque(_fase), _perfil_altura(_fase), _oscuridad(),
		fin_amanecer, duracion_amanecer_segundos,
		inicio_anochecer, duracion_anochecer_segundos]


## Minutos de juego transcurridos desde el arranque (`fase_inicial`) hasta esa fase,
## avanzando por el ciclo. Es una comprobación del horario: sirve para saber en qué
## minuto de partida cae cada hito.
func minutos_desde_arranque(fase: float) -> float:
	return segundos_entre(_fase_arranque, fase) / 60.0


## Segundos de juego entre dos fases avanzando por el ciclo. La mitad diurna
## (0.25 -> 0.75) avanza a 0.5 de fase por `duracion_dia_segundos` y la nocturna a
## 0.5 por `duracion_noche_segundos`, así que se integra por tramos exactos.
func segundos_entre(desde: float, hasta: float) -> float:
	var f: float = fposmod(desde, 1.0)
	var objetivo: float = fposmod(hasta, 1.0)
	if objetivo <= f + 0.000001:
		objetivo += 1.0
	var total: float = 0.0
	# Se corta en los hitos de las mitades (0.25 y 0.75) que caigan por delante.
	for hito_base in [0.25, 0.75]:
		var hito: float = hito_base
		while hito <= f + 0.000001:
			hito += 1.0
		if hito < objetivo:
			total += _segundos_tramo(f, hito)
			f = hito
	total += _segundos_tramo(f, objetivo)
	return total


func _segundos_tramo(desde: float, hasta: float) -> float:
	var duracion: float = duracion_dia_segundos if _es_de_dia((desde + hasta) * 0.5) else duracion_noche_segundos
	return (hasta - desde) * 2.0 * maxf(duracion, 0.001)


## ¿Se VE de día ahora? (oscuridad < 0,5: el atardecer temprano cuenta como día y
## el amanecer avanzado también). Lectura pública para quien tenga que decidir
## según la hora visible, p. ej. dormir en la casa de Leo.
func es_de_dia() -> bool:
	return _oscuridad() < 0.5


func _es_de_dia(fase: float) -> bool:
	var f: float = fposmod(fase, 1.0)
	return f >= 0.25 and f < 0.75
