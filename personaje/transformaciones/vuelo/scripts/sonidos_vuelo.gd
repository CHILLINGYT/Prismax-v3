class_name VueloSonidos
extends Node
## SONIDOS del personaje de VUELO (carpeta "Sonido personaje vuelo").
##
## Cada evento tiene su PROPIO reproductor: un golpe no corta el aleteo, el
## despegue no corta la retomada de aire, etc. El aleteo usa DOS voces alternas
## (el clip dura 0.59 s y el aleteo de ascenso ocurre cada ~0.68 s: con una sola
## voz el arranque de cada aleteo pisaría la cola del anterior).
##
## Sincronización con la ANIMACIÓN real (nada de temporizadores inventados):
##  * Aleteo (sin número): lo dispara FlightArmsOverlay en CADA ciclo real del
##    clip de aleteo; con el aleteo congelado (planeo/descenso), no suena.
##  * Despegue (2.2): PlayerFlightController al activar el vuelo DESDE EL SUELO.
##  * Aire retomar (2.1): acá — transición real reposo (>= espera_reposo) → movimiento.
##  * Golpes (3 y 4): VueloGroundCombat al CONFIRMAR el impacto sobre un enemigo
##    (si el golpe no conecta, no suena nada).

## Volumen del aleteo (se repite mucho: por debajo del resto).
@export var volumen_aleteo_db: float = -4.0
@export var volumen_despegue_db: float = 0.0
@export var volumen_aire_db: float = -2.0
@export var volumen_golpes_db: float = 0.0
## Reposo horizontal (m/s) para considerar al ave quieta en el aire.
@export_range(0.05, 2.0, 0.05) var umbral_quieto: float = 0.5
## Velocidad horizontal (m/s) que marca la retomada real del movimiento.
@export_range(0.2, 8.0, 0.1) var umbral_movimiento: float = 1.5
## Segundos de reposo continuo antes de armar el aviso de retomada (~1 s).
@export_range(0.2, 3.0, 0.1) var espera_reposo: float = 1.0

@onready var _aleteo_a: AudioStreamPlayer = get_node_or_null("Aleteo_A") as AudioStreamPlayer
@onready var _aleteo_b: AudioStreamPlayer = get_node_or_null("Aleteo_B") as AudioStreamPlayer
@onready var _despegue: AudioStreamPlayer = get_node_or_null("Despegue") as AudioStreamPlayer
@onready var _aire: AudioStreamPlayer = get_node_or_null("AireRetomar") as AudioStreamPlayer
@onready var _golpe_3: AudioStreamPlayer = get_node_or_null("Golpe3") as AudioStreamPlayer
@onready var _golpe_4: AudioStreamPlayer = get_node_or_null("Golpe4") as AudioStreamPlayer

var _elegido: int = 0
var _fc: Node = null
var _cuerpo: CharacterBody3D = null
var _t_quieto: float = 0.0
var _armado: bool = false


func _ready() -> void:
	# El vuelo real: el cuerpo es el padre (Player) y el controlador es hermano.
	_fc = get_parent().get_node_or_null("FlightController")
	_cuerpo = get_parent() as CharacterBody3D


## Transición REAL pausa → movimiento en el aire: el sonido 2.1 sale una vez,
## cuando el ave venía de estar quieta (>= espera_reposo) y retoma el movimiento.
func _physics_process(delta: float) -> void:
	if _fc == null or _cuerpo == null:
		return
	var volando: bool = bool(_fc.get("is_flying"))
	if not volando:
		_t_quieto = 0.0
		_armado = false
		return
	var vel_h := Vector2(_cuerpo.velocity.x, _cuerpo.velocity.z).length()
	if vel_h <= umbral_quieto:
		_t_quieto += delta
		if _t_quieto >= espera_reposo:
			_armado = true
		return
	_t_quieto = 0.0
	if _armado and vel_h >= umbral_movimiento:
		_armado = false
		aire_retomar()


## Un aleteo REAL de la animación (lo llama FlightArmsOverlay en cada ciclo).
## Usa la primera voz libre; si las dos están sonando, alterna (nunca se pisa).
func aleteo() -> void:
	var player: AudioStreamPlayer = null
	if _aleteo_a != null and not _aleteo_a.playing:
		player = _aleteo_a
	elif _aleteo_b != null and not _aleteo_b.playing:
		player = _aleteo_b
	else:
		player = _aleteo_a if _elegido == 0 else _aleteo_b
		_elegido = 1 - _elegido
	_tocar(player, volumen_aleteo_db)


## Despegue desde el suelo: una sola vez por activación del vuelo.
func despegue() -> void:
	_tocar(_despegue, volumen_despegue_db)


## Retomada del movimiento tras el reposo en el aire.
func aire_retomar() -> void:
	_tocar(_aire, volumen_aire_db)


## Golpe confirmado de la cadena: Golpe 1 y 3 = sonido 3; Golpe 2 y 4 = sonido 4.
func golpe(indice: int) -> void:
	_tocar(_golpe_3 if indice % 2 == 0 else _golpe_4, volumen_golpes_db)


## Corta todo (salir del vuelo, muerte, transformación).
func detener_todo() -> void:
	for p in [_aleteo_a, _aleteo_b, _despegue, _aire, _golpe_3, _golpe_4]:
		if p != null:
			(p as AudioStreamPlayer).stop()


func _tocar(p: AudioStreamPlayer, vol_db: float) -> void:
	if p == null or p.stream == null:
		return
	p.volume_db = vol_db
	p.play()