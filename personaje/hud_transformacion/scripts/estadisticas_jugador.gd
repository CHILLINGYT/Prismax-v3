class_name EstadisticasJugador
extends Node

## Estadísticas de los PERSONAJES jugables (las cinco formas del jugador): VIDA y
## RESISTENCIA (escudo) INDEPENDIENTES para cada uno, más su regeneración.
##
## - La VIDA es la salud real del personaje.
## - La RESISTENCIA funciona como escudo: mientras tenga carga absorbe el 80 %
##   del daño entrante y sólo el 20 % restante llega a la vida. Cuando la
##   resistencia está agotada, el 100 % del daño va a la vida.
## - La resistencia NO depende del número de golpes: cada golpe consume una
##   cantidad de resistencia proporcional a su daño.
## - MUERTE: sólo cuando la vida Y la resistencia llegan a cero. Con la
##   resistencia en positivo el personaje no muere (última reserva defensiva):
##   puede quedar a 0 de vida y recuperarse si deja de recibir daño. La señal
##   `murio` se emite UNA vez, en el golpe que agota las dos.
##
## RECURSOS POR PERSONAJE (no se comparten):
##   · Cada forma (humano, velocista, pes, tanque, combate) guarda su propia vida
##     y su propio escudo en `_estados`.
##   · Cambiar de personaje NO restaura nada: se guardan los valores del que sale
##     y se recuperan los del que entra, tal como quedaron.
##   · `vida`, `resistencia`, `vida_max`, `resistencia_max` y `muerto` publican
##     SIEMPRE los del personaje ACTIVO, así el HUD y los enemigos no cambian.
##   · Todas las formas usan los máximos base salvo que exista un perfil propio
##     en `perfiles` (id -> {"vida_max", "resistencia_max"}).
##
## REGENERACIÓN (medida en tiempo, nunca por fotogramas):
##   · Regeneran TODOS los personajes, el activo y los inactivos.
##   · El ACTIVO usa la velocidad normal (`velocidad_regen_vida` para la vida y
##     `velocidad_regeneracion` para el escudo); cada INACTIVO usa exactamente el
##     50 % (`factor_inactivo`).
##   · Se respeta el retraso existente (`espera_regeneracion`) tras recibir daño
##     o atacar, y ningún valor supera su máximo.
##   · Un personaje muerto no regenera ni revive solo (regla actual del juego).
##   · Hay UN solo bucle de regeneración: el de este nodo, para todas las formas.
##
## Es un componente puramente lógico, sin UI: el HUD se suscribe a sus señales
## y lee `vida`, `resistencia`, `vida_max`, `resistencia_max`.

signal vida_cambiada(actual: float, maxima: float)
signal resistencia_cambiada(actual: float, maxima: float)
## Verdadero mientras la resistencia se está regenerando (para animar el HUD).
signal regenerando_cambiado(regenerando: bool)
## Daño total entrante recibido en un golpe (antes de repartirlo entre escudo y vida).
signal danio_recibido(cantidad: float)
signal murio

## Personaje con el que arranca la partida (coincide con la forma inicial del
## controlador).
const FORMA_INICIAL := &"humano"

@export_group("Vida")
@export var vida_max: float = 100.0
## Puntos de VIDA por segundo que recupera el personaje ACTIVO. Los inactivos
## usan esta misma tasa multiplicada por `factor_inactivo`.
@export var velocidad_regen_vida: float = 3.0

@export_group("Resistencia (escudo)")
@export var resistencia_max: float = 100.0
## Fracción del daño que absorbe la resistencia mientras tenga carga (0.8 = 80 %).
@export_range(0.0, 1.0, 0.01) var absorcion: float = 0.8
## Segundos sin daño ni ataques antes de empezar a regenerar resistencia.
@export var espera_regeneracion: float = 5.0
## Puntos de RESISTENCIA por segundo que recupera el personaje ACTIVO.
@export var velocidad_regeneracion: float = 18.0
## Fracción de la velocidad de regeneración que usan los personajes INACTIVOS:
## 0.5 = exactamente la mitad (regla de diseño).
@export_range(0.0, 1.0, 0.01) var factor_inactivo: float = 0.5

## Perfiles por transformación: id (StringName) -> {"vida_max", "resistencia_max"}.
## Es donde vive la tabla de máximos de cada personaje; el HUD no necesita cambios
## para ello. Una forma sin perfil usa los máximos base del nodo.
## Acepta claves String o StringName (se normalizan al arrancar).
@export var perfiles: Dictionary = {}

## Recursos del personaje ACTIVO (espejo de `_estados[_forma_actual]`): es lo que
## leen el HUD y los enemigos, así que su significado público no cambia.
var vida: float = 0.0
var resistencia: float = 0.0
var muerto: bool = false

var _forma_actual: StringName = FORMA_INICIAL
## id (StringName) -> {"vida", "resistencia", "t_desde_dano", "muerto"}.
## Cada personaje jugable guarda aquí SUS propios recursos.
var _estados: Dictionary = {}
## Máximos base del nodo (los de los exports), copiados al arrancar: desde
## entonces `vida_max`/`resistencia_max` publican los del personaje ACTIVO.
var _vida_max_base: float = 0.0
var _resistencia_max_base: float = 0.0
## Copia de `perfiles` con las claves ya en StringName (una sola vez al arrancar).
var _perfiles_norm: Dictionary = {}
var _regenerando: bool = false

func _ready() -> void:
	# Los exports quedan como máximos BASE: las propiedades públicas pasan a
	# publicar los del personaje activo.
	_vida_max_base = vida_max
	_resistencia_max_base = resistencia_max
	for k in perfiles.keys():
		_perfiles_norm[StringName(k)] = perfiles[k]
	_estados[FORMA_INICIAL] = _estado_nuevo(FORMA_INICIAL)
	_forma_actual = FORMA_INICIAL
	_sincronizar_activa()
	# Se emite en diferido para que el HUD (hermano en la escena) ya esté conectado
	# a las señales cuando llegue el primer valor.
	_emitir_todo.call_deferred()

func _process(delta: float) -> void:
	# Regeneran TODOS los personajes: el activo a ritmo normal y cada inactivo al
	# 50 %. Un único bucle para todos evita procesos de regeneración duplicados.
	for id in _estados.keys():
		_regenerar_forma(id, delta)

# =============================================================== Daño
## Aplica daño al personaje ACTIVO. Reparte el daño entre resistencia (escudo) y
## vida según `absorcion`. Reinicia la espera de regeneración de ESE personaje.
## Los recursos de los demás personajes no se tocan.
func recibir_danio(cantidad: float) -> void:
	var est: Dictionary = _estados[_forma_actual]
	if bool(est["muerto"]) or cantidad <= 0.0:
		return
	danio_recibido.emit(cantidad)

	var res: float = float(est["resistencia"])
	var a_vida := cantidad
	if res > 0.0:
		var absorbe := minf(res, cantidad * absorcion)
		res -= absorbe
		a_vida = cantidad - absorbe
		est["resistencia"] = res
		_sincronizar_activa()
		resistencia_cambiada.emit(resistencia, resistencia_max)

	est["vida"] = maxf(0.0, float(est["vida"]) - a_vida)
	_sincronizar_activa()
	vida_cambiada.emit(vida, vida_max)

	est["t_desde_dano"] = 0.0
	_fijar_regenerando(false)

	# CONDICIÓN DE MUERTE (regla del juego): el personaje muere únicamente cuando
	# la VIDA y la RESISTENCIA están agotadas las dos. Mientras quede reserva
	# defensiva (resistencia > 0), el golpe mortal lo deja en pie a 0 de vida: es
	# su ÚLTIMA RESERVA y puede recuperarse si deja de recibir daño (la
	# regeneración sigue funcionando: no está muerto). El golpe que termina de
	# vaciar la resistencia lo mata.
	if vida <= 0.0 and resistencia <= 0.0:
		est["muerto"] = true
		_sincronizar_activa()
		murio.emit()

## Cura vida del personaje ACTIVO (no afecta a la resistencia).
func curar(cantidad: float) -> void:
	var est: Dictionary = _estados[_forma_actual]
	if bool(est["muerto"]) or cantidad <= 0.0:
		return
	est["vida"] = minf(_vida_max_de(_forma_actual), float(est["vida"]) + cantidad)
	_sincronizar_activa()
	vida_cambiada.emit(vida, vida_max)

## Llamado cuando el jugador ataca: cancela la regeneración y reinicia la espera.
## La señal de combate `golpe_realizado` entrega el índice del combo (1..4); este
## sistema no necesita ese dato, así que lo acepta y lo ignora (antes no aceptaba
## ningún argumento y Godot rechazaba la llamada en cada golpe).
func notificar_ataque(_indice: int = 0) -> void:
	var est: Dictionary = _estados[_forma_actual]
	if bool(est["muerto"]):
		return
	est["t_desde_dano"] = 0.0
	_fijar_regenerando(false)

# =============================================================== Formas / utilidades
## Cambia el personaje ACTIVO: guarda los recursos del que sale y recupera los del
## que entra, SIN restaurarlos. Emite las señales para que el HUD se actualice al
## instante con los valores del nuevo personaje. Lo llama el controlador al
## terminar cada transformación (`_entrar_*`).
func aplicar_forma(id: StringName) -> void:
	if not _estados.has(id):
		# Primera vez que se usa este personaje: arranca a tope.
		_estados[id] = _estado_nuevo(id)
	_forma_actual = id
	_sincronizar_activa()
	_emitir_todo()

## Recursos de UN personaje (copia; para pruebas/diagnóstico).
func estado_de_forma(id: StringName) -> Dictionary:
	if not _estados.has(id):
		return {}
	var e: Dictionary = _estados[id]
	return {
		"vida": float(e["vida"]),
		"resistencia": float(e["resistencia"]),
		"vida_max": _vida_max_de(id),
		"resistencia_max": _resistencia_max_de(id),
		"muerto": bool(e["muerto"]),
	}

## Personajes con recursos registrados (el activo siempre está).
func formas() -> Array:
	return _estados.keys()

## Personaje activo ahora mismo.
func forma_actual() -> StringName:
	return _forma_actual

## Devuelve TODOS los personajes al estado inicial a tope (p. ej. NEW GAME).
func reiniciar() -> void:
	for id in _estados.keys():
		_estados[id] = _estado_nuevo(id)
	_regenerando = false
	_sincronizar_activa()
	_emitir_todo()

func _fijar_regenerando(v: bool) -> void:
	if v != _regenerando:
		_regenerando = v
		regenerando_cambiado.emit(v)

func _emitir_todo() -> void:
	vida_cambiada.emit(vida, vida_max)
	resistencia_cambiada.emit(resistencia, resistencia_max)

# =============================================================== Interno
## Estado inicial de un personaje: a tope, sin daño reciente y vivo.
func _estado_nuevo(id: StringName) -> Dictionary:
	return {
		"vida": _vida_max_de(id),
		"resistencia": _resistencia_max_de(id),
		"t_desde_dano": espera_regeneracion,
		"muerto": false,
	}

## Copia los recursos del personaje activo a las propiedades públicas.
func _sincronizar_activa() -> void:
	if not _estados.has(_forma_actual):
		return
	var e: Dictionary = _estados[_forma_actual]
	vida = float(e["vida"])
	resistencia = float(e["resistencia"])
	muerto = bool(e["muerto"])
	vida_max = _vida_max_de(_forma_actual)
	resistencia_max = _resistencia_max_de(_forma_actual)

## Perfil de un personaje (vacío si no tiene).
func _perfil_de(id: StringName) -> Dictionary:
	return _perfiles_norm.get(id, {})

func _vida_max_de(id: StringName) -> float:
	var p := _perfil_de(id)
	if p.has("vida_max"):
		return float(p["vida_max"])
	return _vida_max_base

func _resistencia_max_de(id: StringName) -> float:
	var p := _perfil_de(id)
	if p.has("resistencia_max"):
		return float(p["resistencia_max"])
	return _resistencia_max_base

## Regeneración de UN personaje. `factor` es 1.0 para el activo y `factor_inactivo`
## (0.5) para los inactivos; el retraso y los topes son los mismos para todos.
func _regenerar_forma(id: StringName, delta: float) -> void:
	var e: Dictionary = _estados[id]
	if bool(e["muerto"]):
		return
	var activo := id == _forma_actual
	var factor := 1.0 if activo else factor_inactivo
	var t: float = float(e["t_desde_dano"])
	if t < espera_regeneracion:
		e["t_desde_dano"] = minf(espera_regeneracion, t + delta)
		return
	if factor <= 0.0:
		return

	var v_max := _vida_max_de(id)
	var r_max := _resistencia_max_de(id)
	var v: float = float(e["vida"])
	var r: float = float(e["resistencia"])
	var cambio := false
	if v < v_max:
		v = minf(v_max, v + velocidad_regen_vida * factor * delta)
		e["vida"] = v
		cambio = true
	if r < r_max:
		r = minf(r_max, r + velocidad_regeneracion * factor * delta)
		e["resistencia"] = r
		cambio = true
	if not cambio:
		if activo and _regenerando:
			_fijar_regenerando(false)
		return
	if activo:
		# Señales sólo del personaje que se ve: el HUD no necesita saber de los demás.
		_sincronizar_activa()
		vida_cambiada.emit(vida, vida_max)
		resistencia_cambiada.emit(resistencia, resistencia_max)
		_fijar_regenerando(resistencia < resistencia_max)