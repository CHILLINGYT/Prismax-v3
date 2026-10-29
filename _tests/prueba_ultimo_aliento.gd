extends Node3D
## PRUEBA de "ÚLTIMO ALIENTO": con la vida en el 10 % o menos de su máximo, el
## jugador recibe la MITAD del daño que llega a la vida.
##   godot --headless --path . res://_tests/prueba_ultimo_aliento.tscn
##
## Se comprueba sobre el ÚNICO punto de entrada de daño (EstadisticasJugador.
## recibir_danio), con los perfiles REALES de vida de cada forma (los del jugador):
##   (a) daño normal por encima del umbral;
##   (b) daño reducido en el umbral y por debajo;
##   (c) un golpe que CRUZA el umbral reduce sólo la parte que cae en la zona;
##   (d) la muerte sigue ocurriendo (un golpe grande y una lluvia de golpes chicos);
##   (e) sin doble reducción ni doble daño (una llamada = un descuento, una señal);
##   + el daño reducido nunca es 0, la curación saca del efecto, el escudo sigue
##     absorbiendo igual, y la integración con un PROYECTIL ENEMIGO real.

const PROYECTIL := preload("res://Enemigos Prueba/Scenes/proyectil_enemigo.tscn")
const FORMAS: Array[StringName] = [&"humano", &"velocista", &"pes", &"tanque", &"combate", &"aguila"]
const EPS := 0.0001

var _ok: int = 0
var _fallos: int = 0

@onready var jugador: CharacterBody3D = $Jugador


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var real: EstadisticasJugador = jugador.get_node("Estadisticas") as EstadisticasJugador
	# Estadísticas aisladas con la MISMA configuración que el jugador (perfiles y
	# valores exportados), para poder llevarlas a la muerte sin disparar la secuencia
	# de muerte del controlador.
	var stats: EstadisticasJugador = EstadisticasJugador.new()
	stats.perfiles = real.perfiles.duplicate(true)
	stats.absorcion = real.absorcion
	stats.ultimo_aliento_umbral = real.ultimo_aliento_umbral
	stats.ultimo_aliento_reduccion = real.ultimo_aliento_reduccion
	stats.set_process(false)  # sin regeneración durante la medición
	add_child(stats)
	stats.set_process(false)
	await get_tree().process_frame

	_check(is_equal_approx(real.ultimo_aliento_umbral, 0.10), "configuración: umbral 10 %% (%.2f)" % real.ultimo_aliento_umbral)
	_check(is_equal_approx(real.ultimo_aliento_reduccion, 0.50), "configuración: reducción 50 %% (%.2f)" % real.ultimo_aliento_reduccion)

	for forma: StringName in FORMAS:
		_casos_de_forma(stats, forma)
	_caso_escudo(stats)
	_caso_curacion(stats)
	_caso_muerte_lluvia(stats)
	await _caso_proyectil_real(real)

	print("==================== ULTIMO ALIENTO: %d OK / %d FALLO ====================" % [_ok, _fallos])
	get_tree().quit()


# ------------------------------------------------------------------ casos por forma
func _casos_de_forma(stats: EstadisticasJugador, forma: StringName) -> void:
	stats.aplicar_forma(forma)
	var vmax: float = stats.vida_max
	var u: float = vmax * 0.10
	var etiqueta: String = "[%s vmax=%.0f]" % [forma, vmax]

	# (a) Por encima del umbral: daño íntegro.
	_poner(stats, forma, vmax * 0.5, 0.0)
	var golpe: float = vmax * 0.2
	var senales: Array = [0]
	var cb: Callable = func(_c: float) -> void: senales[0] += 1
	stats.danio_recibido.connect(cb)
	stats.recibir_danio(golpe)
	stats.danio_recibido.disconnect(cb)
	_check(_cerca(stats.vida, vmax * 0.5 - golpe), "%s (a) arriba del 10 %%: daño normal (%.2f -> %.2f)" % [etiqueta, vmax * 0.5, stats.vida])
	_check(senales[0] == 1, "%s (e) una llamada = UNA señal de daño (%d)" % [etiqueta, senales[0]])

	# (b) Justo EN el umbral: todo el golpe cae en la zona → mitad.
	_poner(stats, forma, u, 0.0)
	stats.recibir_danio(4.0)
	_check(_cerca(stats.vida, u - 2.0), "%s (b) en el 10 %% exacto: daño a la mitad (%.2f -> %.2f)" % [etiqueta, u, stats.vida])

	# (b) Por debajo del umbral.
	_poner(stats, forma, u * 0.5, 0.0)
	stats.recibir_danio(2.0)
	_check(_cerca(stats.vida, u * 0.5 - 1.0), "%s (b) debajo del 10 %%: daño a la mitad (%.2f -> %.2f)" % [etiqueta, u * 0.5, stats.vida])

	# (c) Cruza el umbral: de 15 % a la zona. Parte normal = 5 % del máximo.
	_poner(stats, forma, vmax * 0.15, 0.0)
	var cruce: float = vmax * 0.12
	var esperado: float = vmax * 0.15 - (vmax * 0.05 + (cruce - vmax * 0.05) * 0.5)
	stats.recibir_danio(cruce)
	_check(_cerca(stats.vida, esperado), "%s (c) golpe que cruza: sólo se reduce lo que cae en la zona (%.3f, esperado %.3f)" % [etiqueta, stats.vida, esperado])
	_check(stats.vida < u, "%s (c) un golpe grande no se salta el efecto: quedó dentro de la zona (%.2f < %.2f)" % [etiqueta, stats.vida, u])

	# Nunca 0: un golpe diminuto en la zona sigue quitando algo.
	_poner(stats, forma, u * 0.5, 0.0)
	var antes: float = stats.vida
	stats.recibir_danio(0.002)
	_check(stats.vida < antes, "%s el daño reducido nunca es 0 (%.6f -> %.6f)" % [etiqueta, antes, stats.vida])

	# (e) Dos golpes iguales seguidos: cada uno se reduce UNA vez, sin acumular.
	_poner(stats, forma, u * 0.8, 0.0)
	var v0: float = stats.vida
	stats.recibir_danio(1.0)
	var v1: float = stats.vida
	stats.recibir_danio(1.0)
	var v2: float = stats.vida
	_check(_cerca(v0 - v1, 0.5) and _cerca(v1 - v2, 0.5), "%s (e) sin doble reducción ni doble daño (%.3f y %.3f)" % [etiqueta, v0 - v1, v1 - v2])

	# (d) Muerte con un golpe grande dentro de la zona (sin escudo).
	_poner(stats, forma, u * 0.3, 0.0)
	var murio: Array = [0]
	var cbm: Callable = func() -> void: murio[0] += 1
	stats.murio.connect(cbm)
	stats.recibir_danio(vmax)
	stats.murio.disconnect(cbm)
	_check(stats.muerto and stats.vida <= 0.0 and murio[0] == 1, "%s (d) la muerte sigue ocurriendo (muerto=%s, señal x%d)" % [etiqueta, str(stats.muerto), murio[0]])


## El escudo absorbe lo MISMO que antes; la reducción sólo toca lo que llega a la vida.
func _caso_escudo(stats: EstadisticasJugador) -> void:
	var forma: StringName = &"humano"
	stats.aplicar_forma(forma)
	var u: float = stats.vida_max * 0.10
	_poner(stats, forma, u * 0.5, 50.0)
	var r0: float = stats.resistencia
	var v0: float = stats.vida
	stats.recibir_danio(10.0)
	var absorbe: float = minf(r0, 10.0 * stats.absorcion)
	_check(_cerca(r0 - stats.resistencia, absorbe), "escudo: absorbe igual que siempre (%.2f)" % (r0 - stats.resistencia))
	_check(_cerca(v0 - stats.vida, (10.0 - absorbe) * 0.5), "escudo: lo que pasa a la vida se reduce una sola vez (%.2f)" % (v0 - stats.vida))
	_check(not stats.muerto, "escudo: con reserva de escudo el jugador sigue en pie (regla del juego intacta)")


## Curar por encima del umbral apaga el efecto: el siguiente golpe es íntegro.
func _caso_curacion(stats: EstadisticasJugador) -> void:
	var forma: StringName = &"velocista"
	stats.aplicar_forma(forma)
	var vmax: float = stats.vida_max
	_poner(stats, forma, vmax * 0.05, 0.0)
	_check(stats.en_ultimo_aliento(), "curación: con 5 % de vida el efecto está ACTIVO")
	stats.curar(vmax * 0.5)
	_check(not stats.en_ultimo_aliento(), "curación: al curar por encima del 10 % el efecto se DESACTIVA")
	var v: float = stats.vida
	stats.recibir_danio(5.0)
	_check(_cerca(v - stats.vida, 5.0), "curación: después el daño vuelve a ser normal (%.2f)" % (v - stats.vida))


## (d) Una lluvia de golpes pequeños también mata (la reducción es lineal, no
## asintótica): se cuenta cuántos hacen falta y se compara con el cálculo.
func _caso_muerte_lluvia(stats: EstadisticasJugador) -> void:
	var forma: StringName = &"tanque"
	stats.aplicar_forma(forma)
	var u: float = stats.vida_max * 0.10
	_poner(stats, forma, u, 0.0)
	var golpes: int = 0
	while not stats.muerto and golpes < 1000:
		stats.recibir_danio(1.0)
		golpes += 1
	var esperados: int = int(ceil(u / 0.5))
	_check(stats.muerto, "(d) una lluvia de golpes de 1 desde el 10 %% termina matando (%d golpes)" % golpes)
	_check(golpes == esperados, "(d) hacen falta exactamente los golpes calculados a mitad de daño (%d = %d)" % [golpes, esperados])
	var antes: float = stats.vida
	stats.recibir_danio(5.0)
	_check(stats.vida == antes, "(e) muerto: no recibe más daño")


## Integración: un PROYECTIL ENEMIGO real contra el jugador real con poca vida.
func _caso_proyectil_real(real: EstadisticasJugador) -> void:
	var forma: StringName = real.forma_actual()
	var u: float = real.vida_max * 0.10
	_poner(real, forma, u * 0.5, 0.0)
	var v0: float = real.vida
	var p: Node3D = PROYECTIL.instantiate() as Node3D
	add_child(p)
	var origen: Vector3 = Vector3(0.0, 1.0, 10.0)
	var destino: Vector3 = jugador.global_position + Vector3.UP * 1.0
	p.call("lanzar", origen, destino - origen, null, 20.0, 4.0)
	for i: int in 60:
		await get_tree().physics_frame
	_check(not is_instance_valid(p), "proyectil real: impactó y se destruyó")
	_check(_cerca(v0 - real.vida, 2.0), "proyectil real: con 5 %% de vida un disparo de 4 quita 2 (%.2f)" % (v0 - real.vida))


# ------------------------------------------------------------------ auxiliares
## Pone la vida y el escudo de UNA forma sin pasar por el daño (sólo pruebas).
func _poner(stats: EstadisticasJugador, forma: StringName, vida: float, resistencia: float) -> void:
	stats.aplicar_forma(forma)
	var est: Dictionary = stats._estados[forma]
	est["vida"] = vida
	est["resistencia"] = resistencia
	est["muerto"] = false
	est["t_desde_dano"] = 0.0
	stats._sincronizar_activa()


func _cerca(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


func _check(cond: bool, texto: String) -> void:
	if cond:
		_ok += 1
		print("[aliento] OK    ", texto)
	else:
		_fallos += 1
		print("[aliento] FALLO ", texto)
