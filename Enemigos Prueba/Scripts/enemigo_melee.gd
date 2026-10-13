class_name EnemigoMelee
# Se extiende por RUTA a propósito: no depende de la caché de clases global del
# editor (el mismo motivo por el que el gerente resuelve su enemigo con preload).
extends "res://Enemigos Prueba/Scripts/base/enemigo_base.gd"

## Enemigo cuerpo a cuerpo con esqueleto: persigue al jugador por el anillo de
## cerco del CombatFormation y, cuando lo tiene cerca y de frente, encadena un
## combo FIJO de tres golpes (golpe_1 -> golpe_2 -> golpe_3) y lo repite.
## Un solo daño por golpe, en el fotograma de impacto de cada clip: la cadencia
## resultante es perseguir (CERCO) -> parar y golpear (ATACAR) -> recuperar.
##
## Todo el contrato de daño/registro/barra/animation viene de EnemigoBase.

const CLIPS := [&"golpe_1", &"golpe_2", &"golpe_3"]
## Fracción del clip en la que cae el impacto (medida sobre la duración real del
## clip horneado, no un valor fijo en segundos): golpe_1/2 pegan a media
## animación y golpe_3 (el fuerte, más largo) algo antes.
const FRACCION_IMPACTO := [0.44, 0.44, 0.32]

@export_group("Combo")
## Alcance del golpe (m, entre centros). Debe ser >= el radio del anillo de cerco
## (2.5 m en combat_config), si no el enemigo se quedaría en el anillo sin pegar.
@export var alcance_golpe: float = 2.8
## Arco frontal mínimo (dot) para que el golpe conecte.
@export var arco_golpe: float = 0.2
## Alcance VERTICAL (m, entre orígenes): si el jugador está más alto que esto
## (p. ej. volando con el águila), este enemigo terrestre no arranca el combo
## ni conecta el impacto. Antes, con el jugador justo encima, golpeaba el aire.
@export var alcance_vertical: float = 2.2
## Pausa (s) entre un golpe del combo y el siguiente.
@export var pausa_entre_golpes: float = 0.16
## Recuperación (s) tras el tercer golpe, antes de volver a perseguir.
@export var recuperacion_combo: float = 0.9
## Espera entre combos propios (aleatoria): desincroniza a varios enemigos.
@export var espera_min: float = 0.5
@export var espera_max: float = 1.6

var _indice_golpe: int = 0
var _golpe_aplicado: bool = false
var _t_resto: float = 0.0

func _pensar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	match _estado:
		Estado.ATACAR:
			_fase_atacar(delta, jugador, stats, jugador_vivo)
		Estado.RECUPERAR:
			_fase_recuperar(delta)
		_:
			_fase_cerco(delta, jugador, jugador_vivo)

# =============================================================== Persecución
func _fase_cerco(delta: float, jugador: Node3D, jugador_vivo: bool) -> void:
	var destino := _punto_de_cerco()
	var hacia := destino - global_position
	hacia.y = 0.0
	var dir := Vector3.ZERO
	if hacia.length() > radio_parada:
		dir = hacia.normalized()
	# Bordea obstáculos y se separa de sus compañeros antes de moverse.
	dir = _con_separacion(_dir_con_esquiva(delta, dir))
	_fisica(delta, dir, _velocidad_propia)

	# Para ARRANCAR el combo hace falta rango, arco y LÍNEA DE VISIÓN (si una
	# pared tapa al jugador, sigue moviéndose para rodearla en vez de golpear aire).
	var distancia := _distancia_plana(jugador)
	if jugador_vivo and distancia <= alcance_golpe and _en_arco(jugador, arco_golpe) \
			and _en_alcance_vertical(jugador) \
			and _espera <= 0.0 and _con_linea_de_vision(jugador, altura_pecho):
		if _pedir_turno():
			_iniciar_golpe(0)
	elif _tiene_turno():
		# Ya no puede o no quiere atacar: suelta el turno para no bloquear la cola.
		_soltar_turno()

## ¿El jugador está dentro del alcance VERTICAL del enemigo? Los dos orígenes
## están a la altura de los pies de cada cuerpo: si el jugador vuela por encima
## (parte delantera = más alto que alcance_vertical), este enemigo no ataca.
func _en_alcance_vertical(jugador: Node3D) -> bool:
	return absf(jugador.global_position.y - global_position.y) <= alcance_vertical

# =============================================================== Combo
func _iniciar_golpe(indice: int) -> void:
	_indice_golpe = indice
	_golpe_aplicado = false
	_estado = Estado.ATACAR
	var clip: StringName = CLIPS[indice]
	_animar_una_vez(clip)
	var dur := _duracion_clip(clip)
	var impacto := maxf(0.08, dur * float(FRACCION_IMPACTO[indice]))
	_t_fase = impacto
	_t_resto = maxf(0.05, dur - impacto) + pausa_entre_golpes
	# Amenaza registrada para el contraataque contextual del FreeFlow (opcional).
	_registrar_amenaza(_t_fase + _t_resto, "melee")

## ATACAR: se detiene, espera al fotograma de impacto y aplica UN daño; al acabar
## el clip encadena el siguiente golpe o pasa a recuperación.
func _fase_atacar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if not _golpe_aplicado and _t_fase <= 0.0:
		_golpe_aplicado = true
		_t_fase = _t_resto
		# El impacto sólo conecta si el jugador sigue cerca, delante y VISIBLE:
		# si se alejó o una pared se interpone, el golpe no hace daño.
		if jugador_vivo and stats != null \
				and _distancia_plana(jugador) <= alcance_golpe + 0.35 \
				and _en_arco(jugador, -0.1) \
				and _en_alcance_vertical(jugador) \
				and _con_linea_de_vision(jugador, altura_pecho):
			var dano := danio_base * randf_range(1.0 - varianza_dano, 1.0 + varianza_dano)
			stats.recibir_danio(dano)
		return
	if _t_fase <= 0.0:
		if _indice_golpe < CLIPS.size() - 1:
			_iniciar_golpe(_indice_golpe + 1)
		else:
			_limpiar_amenaza()
			_soltar_turno()
			_estado = Estado.RECUPERAR
			_t_fase = recuperacion_combo

func _fase_recuperar(delta: float) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if _t_fase <= 0.0:
		_espera = randf_range(espera_min, espera_max)
		_estado = Estado.CERCO