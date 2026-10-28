extends Node3D
## PRUEBAS de las VOCES DE ENEMIGOS MÁS GRAVES (Tarea 4).
##
## Comprueba sobre el proyecto REAL (no sobre una copia):
##   1. existe el bus propio de voces de enemigos y lleva el efecto de tono;
##   2. el tono pedido está en la banda 0,90–0,95 (0,92) y el efecto está activo;
##   3. el bus desemboca en "Efectos", así el volumen de efectos del jugador sigue
##      mandando por encima (y el filtro subacuático también las alcanza);
##   4. una voz de aparición de verdad se crea EN ESE bus;
##   5. el resto del audio NO cambia: los demás buses siguen igual y el arma sigue
##      en "Efectos" con su volumen;
##   6. la regla de UNA voz por grupo de aparición sigue intacta.

const BUS := &"VocesEnemigos"
const BUS_PADRE := &"Efectos"
const TONO_MIN := 0.90
const TONO_MAX := 0.95
const ESCENA_ARMA := "res://Enemigos Prueba/Scenes/arma_ak_tirador.tscn"

var _ok := 0
var _fallos := 0

func _ready() -> void:
	_piso()
	var idx := AudioServer.get_bus_index(BUS)
	_check(idx >= 0, "existe el bus propio de voces de enemigos (%s)" % BUS)
	if idx < 0:
		_resumen()
		return
	_check(AudioServer.get_bus_effect_count(idx) >= 1,
			"el bus lleva %d efecto(s) de audio" % AudioServer.get_bus_effect_count(idx))
	var efecto := AudioServer.get_bus_effect(idx, 0) as AudioEffectPitchShift
	_check(efecto != null, "el efecto del bus es un AudioEffectPitchShift (cambia el tono)")
	if efecto != null:
		var tono := efecto.pitch_scale
		print("[voces-suite] tono del bus: ", tono, " | fft_size: ", efecto.fft_size)
		_check(tono >= TONO_MIN and tono <= TONO_MAX,
				"el tono está en la banda pedida 0,90–0,95 (%.2f): suenan un poco más graves" % tono)
	_check(not AudioServer.is_bus_bypassing_effects(idx), "el efecto está ACTIVO (el bus no lo saltea)")
	var padre := AudioServer.get_bus_send(idx)
	_check(padre == BUS_PADRE, "el bus de voces desemboca en '%s' (volumen de efectos sigue mandando)" % padre)

	# Una voz REAL de aparición: se crea en el bus nuevo.
	VocesAparicion.reiniciar_grupos()
	var enemigo := Node3D.new()
	add_child(enemigo)
	await get_tree().process_frame
	var voz: VocesAparicion = VocesAparicion.anunciar_aparicion(enemigo)
	_check(voz != null, "una aparición real crea su voz")
	if voz != null:
		_check(voz.bus == BUS, "la voz se reproduce por el bus de voces de enemigos ('%s')" % voz.bus)
		_check(absf(voz.volume_db - VocesAparicion.VOLUMEN_DB) < 0.01,
				"conserva su volumen propio (%.1f dB)" % voz.volume_db)
		_check(voz.max_distance > 0.0 and voz.unit_size > 0.0,
				"conserva el audio 3D posicional (alcance %.0f m)" % voz.max_distance)

	# UNA voz por grupo: los siguientes del mismo grupo no añaden voz.
	var segundo := Node3D.new()
	add_child(segundo)
	await get_tree().process_frame
	var voz2: VocesAparicion = VocesAparicion.anunciar_aparicion(segundo)
	_check(voz2 == null and VocesAparicion.grupos_anunciados() == 1,
			"el mismo grupo sigue sonando UNA sola vez (%d grupo)" % VocesAparicion.grupos_anunciados())

	# El resto del audio no se toca.
	_check(AudioServer.get_bus_count() == 5,
			"los buses del juego siguen siendo 5 (Master + música + efectos + diálogos + voces)")
	for nombre in [&"Efectos", &"Musica", &"Dialogos"]:
		var i := AudioServer.get_bus_index(nombre)
		_check(i >= 0 and AudioServer.get_bus_send(i) == &"Master",
				"el bus '%s' no se tocó (sigue enviando a Master)" % nombre)
	var arma := (load(ESCENA_ARMA) as PackedScene).instantiate() as Node3D
	add_child(arma)
	await get_tree().process_frame
	var disparo := arma.get_node_or_null("SonidoDisparo") as AudioStreamPlayer3D
	var bus_arma := String(disparo.bus) if disparo != null else "?"
	_check(disparo != null and bus_arma == String(BUS_PADRE),
			"el sonido del ARMA sigue en '%s' (no se le cambió el tono)" % bus_arma)
	_resumen()


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[voces-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[voces-suite] FALLO ", texto)


func _resumen() -> void:
	print("==================== VOCES GRAVES: %d OK / %d FALLO ====================" % [_ok, _fallos])


func _piso() -> void:
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)