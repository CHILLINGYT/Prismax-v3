class_name CamaDormir
extends Node3D
## =============================================================================
##  DORMIR EN LA CAMA (casa de Leo)
## =============================================================================
##  Cerca de la cama aparece el aviso del juego ("Presiona E para dormir"), por el
##  MISMO canal que la puerta y la salida (`texto_prompt()` + `en_rango()` +
##  `intentar_usar()`, que pregunta el controlador). Al dormir:
##    fundido a negro → texto "Durmiendo…" → se pasa la hora → fundido de vuelta.
##  De día → noche cerrada; de noche → mañana (día pleno).
##
##  La hora se cambia con `CicloDiaNoche.poner_fase()` (ya existía: no hay reloj
##  nuevo). Las farolas, el cielo y la luz del interior SALEN de esa fase, y al
##  salir de la casa `casa_leo.gd` ya guarda la fase para la calle: no queda
##  ningún estado a medias (sol y farolas a la vez, etc.).
##
##  Casos borde: mientras se duerme el jugador queda congelado (no se mueve, no
##  ataca, no se transforma, no sale); la E no cuenta dos veces (bloqueo); dormir
##  varias veces seguidas alterna día/noche; no toca el render, así que funciona
##  igual en los modos de ambiente PS2 y REALISTA.

const TEXTO := "Presiona E para dormir"
const TEMA := preload("res://ui/tema/tema_juego.tres")

## Interruptor de la función (false = la cama no ofrece dormir).
@export var activa := true
## Semiejes (m, en planta) del colchón, en el espacio de este nodo. Los pone
## `casa_leo.gd` desde las medidas reales del modelo.
@export var semiejes := Vector2(1.15, 1.0)
## Distancia (m) al borde de la cama a la que se ofrece dormir.
@export var margen := 0.8
@export var fundido_segundos := 0.7
@export var negro_segundos := 1.6
## Fase del ciclo a la que se despierta al dormir de DÍA (noche cerrada, con las
## farolas ya del todo encendidas: empiezan en 0,75).
@export_range(0.75, 0.99, 0.01) var fase_noche := 0.85
## Segundos tras despertar en los que la cama no vuelve a ofrecer dormir.
@export var espera_tras_dormir := 1.2

var _durmiendo := false
var _bloqueo_hasta := 0
var _veces := 0


func _ready() -> void:
	add_to_group("cama_casa_leo")


func texto_prompt() -> String:
	return TEXTO


func durmiendo() -> bool:
	return _durmiendo


func veces_dormido() -> int:
	return _veces


func _jugador() -> Node3D:
	for n in get_tree().get_nodes_in_group("player"):
		if n.has_method("colocar_en"):
			return n as Node3D
	return null


## ¿Leo está junto a la cama? Distancia en planta al rectángulo del colchón.
func en_rango() -> bool:
	if not activa or _durmiendo or Time.get_ticks_msec() < _bloqueo_hasta:
		return false
	var j := _jugador()
	if j == null:
		return false
	var local := to_local(j.global_position)
	if absf(local.y) > 1.5:
		return false
	var dx := maxf(absf(local.x) - semiejes.x, 0.0)
	var dz := maxf(absf(local.z) - semiejes.y, 0.0)
	return Vector2(dx, dz).length() <= margen


func intentar_usar() -> bool:
	if not en_rango():
		return false
	_dormir()
	return true


func _ciclo() -> Node:
	return get_tree().get_first_node_in_group("ciclo_dia_noche")


## Fase a la que se despierta: de día → noche cerrada; de noche → mañana.
func fase_destino() -> float:
	var ciclo := _ciclo()
	if ciclo == null:
		return -1.0
	var de_dia: bool = ciclo.has_method("es_de_dia") and bool(ciclo.call("es_de_dia"))
	return fase_noche if de_dia else float(ciclo.call("fase_dia_pleno"))


func _dormir() -> void:
	_durmiendo = true
	_veces += 1
	var ciclo := _ciclo()
	var destino := fase_destino()
	var de_dia := destino >= 0.5
	var j := _jugador()
	var modo_previo := Node.PROCESS_MODE_INHERIT
	if j != null:
		modo_previo = j.process_mode
		j.process_mode = Node.PROCESS_MODE_DISABLED   # congelado: ni input ni física
	var capa := _capa_sueno("Hasta la noche" if de_dia else "Hasta la mañana")
	var negro := capa.get_node("Negro") as ColorRect
	var textos := capa.get_node("Centro") as Control
	var tw := capa.create_tween()
	tw.tween_property(negro, "modulate:a", 1.0, fundido_segundos).set_trans(Tween.TRANS_SINE)
	tw.tween_property(textos, "modulate:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		if ciclo != null and destino >= 0.0:
			ciclo.call("poner_fase", destino)
		print("[cama] Leo duerme: fase → %.3f (%s)" % [destino, "noche" if de_dia else "día"]))
	tw.tween_interval(negro_segundos)
	tw.tween_property(textos, "modulate:a", 0.0, 0.3)
	tw.tween_property(negro, "modulate:a", 0.0, fundido_segundos).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(j):
			j.process_mode = modo_previo
		capa.queue_free()
		_bloqueo_hasta = Time.get_ticks_msec() + int(espera_tras_dormir * 1000.0)
		_durmiendo = false)


## Capa del sueño: negro a pantalla completa POR ENCIMA de todo el HUD (y del
## post-proceso PS2, que está debajo), con el texto en el estilo del HUD.
func _capa_sueno(subtitulo: String) -> CanvasLayer:
	var capa := CanvasLayer.new()
	capa.name = "SuenoLeo"
	capa.layer = 110
	add_child(capa)
	var negro := ColorRect.new()
	negro.name = "Negro"
	negro.color = Color.BLACK
	negro.set_anchors_preset(Control.PRESET_FULL_RECT)
	negro.mouse_filter = Control.MOUSE_FILTER_STOP
	negro.modulate.a = 0.0
	capa.add_child(negro)
	var centro := VBoxContainer.new()
	centro.name = "Centro"
	centro.theme = TEMA
	centro.set_anchors_preset(Control.PRESET_CENTER)
	centro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centro.grow_vertical = Control.GROW_DIRECTION_BOTH
	centro.alignment = BoxContainer.ALIGNMENT_CENTER
	centro.modulate.a = 0.0
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(centro)
	var zz := Label.new()
	zz.text = "Z z z"
	zz.theme_type_variation = &"HudEtiqueta"
	zz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centro.add_child(zz)
	var titulo := Label.new()
	titulo.name = "Titulo"
	titulo.text = "Durmiendo…"
	titulo.theme_type_variation = &"HudObjetivo"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centro.add_child(titulo)
	var sub := Label.new()
	sub.text = subtitulo
	sub.theme_type_variation = &"HudSecundario"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centro.add_child(sub)
	return capa
