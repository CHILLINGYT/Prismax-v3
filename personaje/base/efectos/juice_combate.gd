class_name JuiceCombate
extends Node
## =============================================================================
##  CAPA DE PULIDO DEL COMBATE FREE FLOW ("juice")
## =============================================================================
##  Vive como hijo de `LeoJugador` (leo_jugador.tscn) y escucha las señales de
##  SOLO LECTURA del controlador (`golpe_lanzado`, `golpe_conectado`). No decide
##  nada del combate: sólo añade feedback encima de lo que ya pasa.
##
##  CADA mejora tiene su interruptor exportado (`*_activo`): se apagan en el
##  Inspector de LeoJugador > JuiceCombate para comparar antes/después. Con TODOS
##  apagados el combate se comporta exactamente como antes de esta capa.
##
##  Fuerza de cada golpe (índice de la cadena: 0 jab · 1 cros · 2 gancho) y el
##  "remate" (el golpe que deja al enemigo sin vida) escalan todos los efectos.

# --------------------------------------------------------------------- HITSTOP
@export_group("Hitstop")
## Congela el mundo unos milisegundos en cada impacto confirmado (Engine.time_scale).
@export var hitstop_activo := true
## Duración REAL (s) por eslabón: jab, cros, gancho. El gancho cierra la cadena.
@export var hitstop_por_golpe := PackedFloat32Array([0.045, 0.06, 0.085])
## Duración REAL (s) del golpe que deja al enemigo sin vida.
@export var hitstop_remate := 0.11
## Escala de tiempo durante el congelado (0 = parado del todo; 0,04 deja que se
## note el "temblor" de la pose sin parecer un corte).
@export_range(0.0, 0.5, 0.01) var hitstop_escala := 0.04

var _jugador: Node = null
## Fin (µs de reloj REAL) de cada efecto de tiempo. El reloj real no se ve
## afectado por Engine.time_scale, así que el efecto nunca se "estira" a sí mismo.
var _hitstop_hasta_us := 0
## Última escala que puso ESTA capa: si otro sistema cambia Engine.time_scale,
## no se le pisa (sólo se devuelve a 1 lo que esta capa bajó).
var _escala_puesta := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_jugador = get_parent()
	if _jugador == null:
		return
	if _jugador.has_signal("golpe_conectado"):
		_jugador.connect("golpe_conectado", _on_golpe_conectado)
	if _jugador.has_signal("golpe_lanzado"):
		_jugador.connect("golpe_lanzado", _on_golpe_lanzado)


func _exit_tree() -> void:
	# Nunca dejar el juego a cámara lenta si el jugador desaparece a mitad.
	if not is_equal_approx(_escala_puesta, 1.0) and is_equal_approx(Engine.time_scale, _escala_puesta):
		Engine.time_scale = 1.0
	_escala_puesta = 1.0


func _process(_delta: float) -> void:
	_actualizar_tiempo()


# ------------------------------------------------------------------ eventos
func _on_golpe_lanzado(_indice: int) -> void:
	pass


func _on_golpe_conectado(objetivo: Node3D, _dir: Vector3, indice: int, remate: bool) -> void:
	if objetivo == null:
		return
	if hitstop_activo:
		var dur := hitstop_remate if remate else _valor_por_golpe(hitstop_por_golpe, indice, 0.05)
		_hitstop(dur)


# ------------------------------------------------------------------ tiempo
func _hitstop(segundos: float) -> void:
	if segundos <= 0.0:
		return
	var fin := Time.get_ticks_usec() + int(segundos * 1_000_000.0)
	_hitstop_hasta_us = maxi(_hitstop_hasta_us, fin)
	_actualizar_tiempo()


## Escala de tiempo deseada AHORA según los efectos vivos (el más lento manda).
func _escala_deseada() -> float:
	var ahora := Time.get_ticks_usec()
	var escala := 1.0
	if ahora < _hitstop_hasta_us:
		escala = minf(escala, hitstop_escala)
	return escala


func _actualizar_tiempo() -> void:
	var deseada := _escala_deseada()
	# Si alguien más tocó Engine.time_scale (p. ej. una herramienta de depuración)
	# y esta capa no tiene nada activo, no se interfiere.
	if is_equal_approx(deseada, 1.0) and is_equal_approx(_escala_puesta, 1.0):
		return
	if not is_equal_approx(Engine.time_scale, _escala_puesta) and is_equal_approx(deseada, 1.0):
		_escala_puesta = 1.0
		return
	Engine.time_scale = deseada
	_escala_puesta = deseada


# ------------------------------------------------------------------ util
func _valor_por_golpe(tabla: PackedFloat32Array, indice: int, defecto: float) -> float:
	if tabla.is_empty():
		return defecto
	return tabla[clampi(indice, 0, tabla.size() - 1)]


## Lectura para pruebas: ¿hay un hitstop en curso?
func hitstop_en_curso() -> bool:
	return Time.get_ticks_usec() < _hitstop_hasta_us
