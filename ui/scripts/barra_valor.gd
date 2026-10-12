class_name BarraValor
extends Control

## Barra horizontal interactiva (blanca) para elegir un valor entero.
##
## - Se puede ARRASTRAR el indicador o HACER CLIC en cualquier punto de la barra.
## - Emite `valor_cambiado` cuando cambia.
## - Se auto-construye (no necesita nodos hijos en la escena): pista oscura,
##   relleno blanco e indicador blanco.
##
## Pensada para reutilizarse (hoy: DISTANCIA DE VISIÓN 0..10).

signal valor_cambiado(valor: int)

const ALTO_PISTA := 6.0
const TAM_TIRADOR := 14.0

@export var minimo: int = 0
@export var maximo: int = 10

## Valor actual (0..maximo). Cámbialo con poner_valor().
var valor: int = 0

var _pista: ColorRect
var _relleno: ColorRect
var _tirador: ColorRect
var _arrastrando: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pista = _crear_rect(Color(0.28, 0.30, 0.34, 0.9))
	_relleno = _crear_rect(Color(1, 1, 1, 1))
	_tirador = _crear_rect(Color(1, 1, 1, 1))
	resized.connect(_actualizar)
	_actualizar()

func _crear_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

## Fija el valor (sin emitir si no cambia).
func poner_valor(v: int) -> void:
	v = clampi(v, minimo, maximo)
	if v == valor:
		return
	valor = v
	_actualizar()
	valor_cambiado.emit(valor)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_arrastrando = true
			_fijar_por_x(event.position.x)
		else:
			_arrastrando = false
	elif event is InputEventMouseMotion and _arrastrando:
		_fijar_por_x(event.position.x)

func _fijar_por_x(x: float) -> void:
	var w := maxf(1.0, size.x)
	var t := clampf(x / w, 0.0, 1.0)
	poner_valor(int(round(lerpf(float(minimo), float(maximo), t))))

func _actualizar() -> void:
	if _pista == null:
		return
	var w := size.x
	var cy := size.y * 0.5
	_pista.position = Vector2(0, cy - ALTO_PISTA * 0.5)
	_pista.size = Vector2(w, ALTO_PISTA)
	var t := 0.0 if maximo == minimo else float(valor - minimo) / float(maximo - minimo)
	var x := t * w
	_relleno.position = Vector2(0, cy - ALTO_PISTA * 0.5)
	_relleno.size = Vector2(x, ALTO_PISTA)
	_tirador.position = Vector2(
			clampf(x - TAM_TIRADOR * 0.5, 0.0, maxf(0.0, w - TAM_TIRADOR)),
			cy - TAM_TIRADOR * 0.5)
	_tirador.size = Vector2(TAM_TIRADOR, TAM_TIRADOR)