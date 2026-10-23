class_name EnemigoTanque
extends "res://Enemigos Prueba/Scripts/base/enemigo_base.gd"

## Enemigo TANQUE - Fase 3 - Rol pesado
## - Mucha vida (150), lento (2.0 m/s), daño alto (20)
## - Rompe guardia, no se puede counterear normal (requiere counter perfecto)
## - Usa 2 tokens (bloquea a 2 enemigos)
## - Resiste knockback 50%, solo recibe mitad empuje
## - Ataque especial: pisotón en área 3.5m

const CLIPS_TANQUE := [&"golpe_1", &"golpe_2", &"golpe_fuerte"]
const FRACCION_IMPACTO_TANQUE := [0.44, 0.44, 0.28]
const CombatVFX_T = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_vfx.gd")

@export_group("Tanque")
@export var alcance_golpe: float = 2.8
@export var arco_golpe: float = 0.1
@export var alcance_vertical: float = 2.2
@export var pausa_entre_golpes: float = 0.35
@export var recuperacion_combo: float = 1.4
@export var espera_min: float = 1.0
@export var espera_max: float = 2.2
@export var resistencia_empuje: float = 0.5
@export var radio_pisoton: float = 3.5
@export var dano_pisoton: float = 25.0
@export var usa_dos_tokens: bool = true

var _indice_golpe: int = 0
var _golpe_aplicado: bool = false
var _t_resto: float = 0.0

func _ready() -> void:
	super()
	vida_max = 150.0
	_vida = vida_max
	velocidad = 2.0
	danio_base = 20.0
	_actualizar_barra()

func get_resistencia_empuje() -> float:
	return resistencia_empuje

func _pensar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	# Si está asustado, más defensivo
	if esta_asustado():
		_espera = maxf(_espera, 0.5)
	match _estado:
		Estado.ATACAR:
			_fase_atacar(delta, jugador, stats, jugador_vivo)
		Estado.RECUPERAR:
			_fase_recuperar(delta)
		_:
			_fase_cerco(delta, jugador, jugador_vivo)

func _fase_cerco(delta: float, jugador: Node3D, jugador_vivo: bool) -> void:
	var destino := _punto_de_cerco()
	var hacia := destino - global_position
	hacia.y = 0.0
	var dir := Vector3.ZERO
	if hacia.length() > radio_parada:
		dir = hacia.normalized()
	dir = _con_separacion(_dir_con_esquiva(delta, dir))
	_fisica(delta, dir, _velocidad_propia)

	var distancia := _distancia_plana(jugador)
	if jugador_vivo and distancia <= alcance_golpe and _en_arco(jugador, arco_golpe) \
			and _en_alcance_vertical(jugador) \
			and _espera <= 0.0 and _con_linea_de_vision(jugador, altura_pecho):
		if _pedir_turno_tanque():
			_iniciar_golpe(0)
	elif _tiene_turno():
		_soltar_turno_tanque()

func _en_alcance_vertical(jugador: Node3D) -> bool:
	return absf(jugador.global_position.y - global_position.y) <= alcance_vertical

func _iniciar_golpe(indice: int) -> void:
	_indice_golpe = indice
	_golpe_aplicado = false
	_estado = Estado.ATACAR
	var clip: StringName = CLIPS_TANQUE[indice]
	_animar_una_vez(clip)
	var dur := _duracion_clip(clip)
	var impacto := maxf(0.08, dur * float(FRACCION_IMPACTO_TANQUE[indice]))
	_t_fase = impacto
	_t_resto = maxf(0.05, dur - impacto) + pausa_entre_golpes
	_registrar_amenaza(_t_fase + _t_resto, "heavy")

func _fase_atacar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if not _golpe_aplicado and _t_fase <= 0.0:
		_golpe_aplicado = true
		_t_fase = _t_resto
		if jugador_vivo and stats != null \
				and _distancia_plana(jugador) <= alcance_golpe + 0.5 \
				and _en_arco(jugador, -0.2) \
				and _en_alcance_vertical(jugador) \
				and _con_linea_de_vision(jugador, altura_pecho):
			var dano := danio_base * randf_range(1.0 - varianza_dano, 1.0 + varianza_dano)
			if _indice_golpe == 2:
				_pisoton_area(stats)
			else:
				stats.recibir_danio(dano)
		return
	if _t_fase <= 0.0:
		if _indice_golpe < CLIPS_TANQUE.size() - 1:
			_iniciar_golpe(_indice_golpe + 1)
		else:
			_limpiar_amenaza()
			_soltar_turno_tanque()
			_estado = Estado.RECUPERAR
			_t_fase = recuperacion_combo

func _fase_recuperar(delta: float) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if _t_fase <= 0.0:
		_espera = randf_range(espera_min, espera_max)
		_estado = Estado.CERCO

func _pisoton_area(stats: EstadisticasJugador) -> void:
	print("[Tanque] ¡PISOTÓN! area %.1fm" % radio_pisoton)
	# Daño directo si está cerca
	var jugador := _obtener_jugador()
	if jugador != null and _distancia_plana(jugador) <= radio_pisoton + 0.5:
		stats.recibir_danio(dano_pisoton)
	# VFX
	var vfx_parent := get_tree().current_scene as Node3D
	if vfx_parent == null:
		vfx_parent = get_parent() as Node3D
	if vfx_parent != null:
		CombatVFX_T.spawn_hit_vfx(vfx_parent, global_position, "heavy", true, 0)

func _pedir_turno_tanque() -> bool:
	var gestor := _gestor_combate()
	if gestor == null:
		return true
	var tokens: Variant = gestor.get("tokens")
	if tokens == null:
		return true
	# Tanque intenta tomar token; si usa_dos_tokens, verifica que haya al menos 1 slot libre extra
	if usa_dos_tokens:
		# Si ya hay max_attackers-1 ocupados, no puede tomar 2
		if tokens.has_method("count_available"):
			if tokens.count_available() < 2 and not tokens.has_token(self):
				return false
	return bool(tokens.request(self))

func _soltar_turno_tanque() -> void:
	_soltar_turno()

func on_countered(stun: float) -> void:
	if stun >= 1.9:
		_estado = Estado.ATURDIDO
		_t_fase = stun
		print("[Tanque] ¡Counter perfecto! Stuneado %.1fs" % stun)
	else:
		_t_fase = stun * 0.3
		print("[Tanque] Counter normal resistido: %.1fs" % _t_fase)
