class_name EnemigoJefe
extends "res://Enemigos Prueba/Scripts/base/enemigo_base.gd"

## Enemigo JEFE - Fase 3 - Rol jefe
## - Vida 300, velocidad 3.2, daño 25
## - Usa tokens dobles pero ataca aunque no tenga token (jefe no respeta cola)
## - Tiene fases: 100-60% vida = fase 1 (melee), 60-30% = fase 2 (mezcla melee + proyectiles), <30% = fase 3 (enfurecido)
## - Puede hacer feint (windup falso) para baitear counter
## - Sistema de miedo: si matas 3 enemigos cerca, jefe se pone defensivo

const CLIPS_JEFE := [&"golpe_1", &"golpe_2", &"golpe_3", &"golpe_fuerte", &"disparar"]
const FRACCION_JEFE := [0.44, 0.44, 0.32, 0.25, 0.5]

@export_group("Jefe")
@export var alcance_golpe: float = 3.2
@export var danio_fase2: float = 15.0
@export var prob_feint: float = 0.25 # 25% de hacer feint
@export var vida_fase2: float = 0.6 # 60% vida entra fase 2
@export var vida_fase3: float = 0.3 # 30% vida entra fase 3

var _indice_golpe: int = 0
var _golpe_aplicado: bool = false
var _t_resto: float = 0.0
var _fase_jefe: int = 1
var _en_feint: bool = false

func _ready() -> void:
	super()
	vida_max = 300.0
	_vida = vida_max
	velocidad = 3.2
	danio_base = 25.0
	_actualizar_barra()

func _pensar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	_actualizar_fase()
	
	match _estado:
		Estado.ATACAR:
			_fase_atacar(delta, jugador, stats, jugador_vivo)
		Estado.RECUPERAR:
			_fase_recuperar(delta)
		_:
			_fase_cerco(delta, jugador, jugador_vivo)

func _actualizar_fase() -> void:
	var pct := _vida / vida_max
	if pct < vida_fase3:
		_fase_jefe = 3
	elif pct < vida_fase2:
		_fase_jefe = 2
	else:
		_fase_jefe = 1

func _fase_cerco(delta: float, jugador: Node3D, jugador_vivo: bool) -> void:
	var destino := _punto_de_cerco()
	var hacia := destino - global_position
	hacia.y = 0.0
	var dir := Vector3.ZERO
	if hacia.length() > radio_parada:
		dir = hacia.normalized()
	# Jefe no se separa tanto, es imponente
	dir = _dir_con_esquiva(delta, dir)
	_fisica(delta, dir, _velocidad_propia * (1.3 if _fase_jefe == 3 else 1.0))

	var distancia := _distancia_plana(jugador)
	var en_rango_melee := distancia <= alcance_golpe and _en_arco(jugador, 0.15) and _en_alcance_vertical(jugador)
	var en_rango_tiro := distancia <= 18.0 and distancia > alcance_golpe
	
	if jugador_vivo and _espera <= 0.0 and _con_linea_de_vision(jugador, altura_pecho):
		if _fase_jefe == 1 and en_rango_melee:
			if _pedir_turno_jefe():
				_iniciar_golpe(0)
		elif _fase_jefe == 2:
			if en_rango_melee and randf() < 0.6:
				if _pedir_turno_jefe():
					_iniciar_golpe(randi() % 3)
			elif en_rango_tiro:
				if _pedir_turno_jefe():
					_iniciar_golpe(4) # disparar
		elif _fase_jefe == 3:
			# Fase 3: siempre ataca, sin respetar tokens
			_iniciar_golpe(randi() % 4)

func _iniciar_golpe(indice: int) -> void:
	_indice_golpe = indice
	_golpe_aplicado = false
	_en_feint = false
	_estado = Estado.ATACAR
	
	# Feint: 25% probabilidad en fase 2-3
	if _fase_jefe >= 2 and randf() < prob_feint and indice < 3:
		_en_feint = true
		var clip: StringName = CLIPS_JEFE[indice]
		_animar_una_vez(clip)
		_t_fase = 0.2 # windup falso corto
		_t_resto = 0.0
		print("[Jefe] ¡FEINT! Bait de counter")
		return
	
	var clip: StringName = CLIPS_JEFE[indice]
	_animar_una_vez(clip)
	var dur := _duracion_clip(clip)
	var impacto := maxf(0.08, dur * float(FRACCION_JEFE[indice]))
	_t_fase = impacto
	_t_resto = maxf(0.05, dur - impacto) + (0.2 if _fase_jefe == 3 else 0.5)
	var tipo := "heavy" if indice >= 3 else "melee"
	_registrar_amenaza(_t_fase + _t_resto, tipo)

func _fase_atacar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	
	if _en_feint:
		if _t_fase <= 0.0:
			print("[Jefe] Feint cancelado, vuelve a cerco - si hiciste counter, quedas vulnerable")
			_limpiar_amenaza()
			_estado = Estado.CERCO
			_espera = 0.3
		return
	
	if not _golpe_aplicado and _t_fase <= 0.0:
		_golpe_aplicado = true
		_t_fase = _t_resto
		if jugador_vivo and stats != null:
			if _indice_golpe == 4:
				_disparar_proyectil(jugador)
			else:
				if _distancia_plana(jugador) <= alcance_golpe + 0.6 and _en_arco(jugador, -0.2) and _con_linea_de_vision(jugador, altura_pecho):
					var dano := danio_base * (1.5 if _fase_jefe == 3 else 1.0) * randf_range(0.9, 1.1)
					stats.recibir_danio(dano)
		return
	
	if _t_fase <= 0.0:
		_limpiar_amenaza()
		_soltar_turno()
		_estado = Estado.RECUPERAR
		_t_fase = 0.4 if _fase_jefe == 3 else 0.9

func _fase_recuperar(delta: float) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if _t_fase <= 0.0:
		_espera = randf_range(0.3, 0.8) if _fase_jefe == 3 else randf_range(0.6, 1.4)
		_estado = Estado.CERCO

func _disparar_proyectil(jugador: Node3D) -> void:
	print("[Jefe] ¡Disparo fase %d!" % _fase_jefe)
	# Reusa lógica de tirador
	var escena_proyectil := preload("res://Enemigos Prueba/Scenes/proyectil_enemigo.tscn")
	var padre := get_parent()
	if padre == null:
		return
	var boca := global_position + Vector3.UP * 1.2 + (-global_transform.basis.z) * 0.5
	var dir := (jugador.global_position + Vector3.UP * 1.0 - boca).normalized()
	var p := escena_proyectil.instantiate()
	if "radio" in p:
		p.set("radio", 0.2)
	if "velocidad" in p:
		p.set("velocidad", 28.0)
	if "dano" in p:
		p.set("dano", danio_fase2)
	padre.add_child(p)
	if p.has_method("lanzar"):
		p.call("lanzar", boca, dir, self, 28.0, danio_fase2)

# Jefe no respeta tokens en fase 3, y usa 2 tokens en fase 1-2
func _pedir_turno_jefe() -> bool:
	if _fase_jefe == 3:
		return true # fase 3: ataca siempre
	return _pedir_turno()

func on_countered(stun: float) -> void:
	if _en_feint:
		print("[Jefe] ¡Counter en FEINT! Jugador vulnerable 0.5s")
		# Aquí el jugador debería quedar vulnerable - se maneja en player.gd
		_estado = Estado.CERCO
		_espera = 0.1
		_en_feint = false
		_limpiar_amenaza()
		return
	
	# Jefe resiste stun 50% en fase 1-2, 30% en fase 3
	var resistencia := 0.5 if _fase_jefe < 3 else 0.7
	var stun_real := stun * (1.0 - resistencia)
	if stun >= 1.9: # counter perfecto sí lo stunea más
		stun_real = stun * 0.7
	
	_estado = Estado.ATURDIDO
	_t_fase = stun_real
	print("[Jefe] Stuneado %.1fs (fase %d, resistencia %.0f%%)" % [stun_real, _fase_jefe, resistencia*100])

func _en_alcance_vertical(jugador: Node3D) -> bool:
	return absf(jugador.global_position.y - global_position.y) <= 3.0 # jefe alcanza más alto
