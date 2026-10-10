class_name EstadisticasJugador
extends Node

## Estadísticas del jugador: VIDA y RESISTENCIA (escudo).
##
## - La VIDA es la salud real del personaje.
## - La RESISTENCIA funciona como escudo: mientras tenga carga absorbe el 80 %
##   del daño entrante y sólo el 20 % restante llega a la vida. Cuando la
##   resistencia está agotada, el 100 % del daño va a la vida.
## - La resistencia NO depende del número de golpes: cada golpe consume una
##   cantidad de resistencia proporcional a su daño.
## - La resistencia se regenera progresivamente tras un tiempo de espera
##   (5 s por defecto) sin recibir daño y sin atacar. El movimiento normal NO
##   interrumpe la regeneración; atacar SÍ la cancela y reinicia la espera.
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

@export_group("Vida")
@export var vida_max: float = 100.0

@export_group("Resistencia (escudo)")
@export var resistencia_max: float = 100.0
## Fracción del daño que absorbe la resistencia mientras tenga carga (0.8 = 80 %).
@export_range(0.0, 1.0, 0.01) var absorcion: float = 0.8
## Segundos sin daño ni ataques antes de empezar a regenerar resistencia.
@export var espera_regeneracion: float = 5.0
## Puntos de resistencia recuperados por segundo.
@export var velocidad_regeneracion: float = 18.0

## Perfiles opcionales por transformación: id (StringName) -> {"vida_max", "resistencia_max"}.
## Vacío por defecto: todas las formas comparten los mismos máximos. Añadir una
## entrada sólo cuando una transformación necesite estadísticas propias; el HUD
## no necesita cambios para ello.
@export var perfiles: Dictionary = {}

var vida: float = 0.0
var resistencia: float = 0.0
var muerto: bool = false

var _t_desde_dano: float = 0.0
var _regenerando: bool = false

func _ready() -> void:
	vida = vida_max
	resistencia = resistencia_max
	# Se emite en diferido para que el HUD (hermano en la escena) ya esté conectado
	# a las señales cuando llegue el primer valor.
	_emitir_todo.call_deferred()

func _process(delta: float) -> void:
	if muerto:
		return
	# Fase de espera tras el último daño/ataque.
	if _t_desde_dano < espera_regeneracion:
		_t_desde_dano += delta
		return
	if resistencia < resistencia_max:
		_fijar_regenerando(true)
		resistencia = minf(resistencia_max, resistencia + velocidad_regeneracion * delta)
		resistencia_cambiada.emit(resistencia, resistencia_max)
	elif _regenerando:
		_fijar_regenerando(false)

# =============================================================== Daño
## Aplica daño al personaje. Reparte el daño entre resistencia (escudo) y vida
## según `absorcion`. Reinicia la espera de regeneración.
func recibir_danio(cantidad: float) -> void:
	if muerto or cantidad <= 0.0:
		return
	danio_recibido.emit(cantidad)

	var a_vida := cantidad
	if resistencia > 0.0:
		var absorbe := minf(resistencia, cantidad * absorcion)
		resistencia -= absorbe
		a_vida = cantidad - absorbe
		resistencia_cambiada.emit(resistencia, resistencia_max)

	vida = maxf(0.0, vida - a_vida)
	vida_cambiada.emit(vida, vida_max)

	_t_desde_dano = 0.0
	_fijar_regenerando(false)

	if vida <= 0.0:
		muerto = true
		murio.emit()

## Cura vida (no afecta a la resistencia).
func curar(cantidad: float) -> void:
	if muerto or cantidad <= 0.0:
		return
	vida = minf(vida_max, vida + cantidad)
	vida_cambiada.emit(vida, vida_max)

## Llamado cuando el jugador ataca: cancela la regeneración y reinicia la espera.
## La señal de combate `golpe_realizado` entrega el índice del combo (1..4); este
## sistema no necesita ese dato, así que lo acepta y lo ignora (antes no aceptaba
## ningún argumento y Godot rechazaba la llamada en cada golpe).
func notificar_ataque(_indice: int = 0) -> void:
	if muerto:
		return
	_t_desde_dano = 0.0
	_fijar_regenerando(false)

# =============================================================== Formas / utilidades
## Aplica, si existe, el perfil de estadísticas de una transformación.
## Sin perfil definido la forma comparte los máximos actuales (comportamiento actual).
func aplicar_forma(id: StringName) -> void:
	if not perfiles.has(id):
		return
	var p: Dictionary = perfiles[id]
	if p.has("vida_max"):
		vida_max = float(p["vida_max"])
	if p.has("resistencia_max"):
		resistencia_max = float(p["resistencia_max"])
	vida = clampf(vida, 0.0, vida_max)
	resistencia = clampf(resistencia, 0.0, resistencia_max)
	_emitir_todo()

## Devuelve el personaje al estado inicial a tope (p. ej. NEW GAME).
func reiniciar() -> void:
	muerto = false
	vida = vida_max
	resistencia = resistencia_max
	_t_desde_dano = espera_regeneracion
	_fijar_regenerando(false)
	_emitir_todo()

func _fijar_regenerando(v: bool) -> void:
	if v != _regenerando:
		_regenerando = v
		regenerando_cambiado.emit(v)

func _emitir_todo() -> void:
	vida_cambiada.emit(vida, vida_max)
	resistencia_cambiada.emit(resistencia, resistencia_max)