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

# ------------------------------------------------------- CÁMARA: SACUDIDA + FOV
@export_group("Camara")
## Sacudida por trauma (ruido coherente, trauma²) en cada impacto confirmado.
@export var sacudida_activa := true
## Trauma que suma cada eslabón (jab, cros, gancho) y el remate. 0..1.
@export var trauma_por_golpe := PackedFloat32Array([0.28, 0.36, 0.5])
@export var trauma_remate := 0.62
## Golpe de FOV ("punch-in", grados; negativo = la cámara se acerca un instante).
@export var fov_punch_activo := true
@export var fov_punch_por_golpe := PackedFloat32Array([-0.8, -1.2, -2.4])
@export var fov_punch_remate := -4.0

# ---------------------------------------------------------------- AUDIO EN CAPAS
@export_group("Audio")
## Capas de sonido encima del golpe que ya tenía el proyecto (que se conserva):
##  · WHOOSH al lanzar cada golpe (sintetizado por código: ruido filtrado con un
##    barrido de frecuencia; no es un asset externo);
##  · PUÑETAZO de Kenney (CC0) al conectar: "medium" en el jab, "heavy" en cros/gancho;
##  · GOLPE SORDO de cuerpo (Kenney impactSoft_heavy) en cros, gancho y remate;
##  · capa GRAVE en el remate (el puñetazo pesado una octava abajo).
## Cada capa elige variante al azar SIN repetir la anterior y varía el tono.
@export var audio_capas_activo := true
@export var bus_audio := &"Efectos"
@export_range(-40.0, 6.0, 0.5) var whoosh_db := -11.0
@export_range(-40.0, 6.0, 0.5) var punetazo_db := -3.0
@export_range(-40.0, 6.0, 0.5) var sordo_db := -7.0
@export_range(-40.0, 6.0, 0.5) var remate_grave_db := -2.0
## Variación aleatoria del tono (± fracción): evita el efecto "ametralladora".
@export_range(0.0, 0.3, 0.01) var variacion_tono := 0.08

const SFX_DIR := "res://assets/sfx_combat/kenney_impact/"
const VOCES := 8
static var _whooshes: Array[AudioStreamWAV] = []
var _sfx_medio: Array[AudioStream] = []
var _sfx_pesado: Array[AudioStream] = []
var _sfx_sordo: Array[AudioStream] = []
var _ultimo := {}
var _voces: Array[AudioStreamPlayer] = []
var _voz_siguiente := 0
var _sonidos_disparados := 0

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
	_preparar_audio()
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
func _on_golpe_lanzado(indice: int) -> void:
	if audio_capas_activo and not _whooshes.is_empty():
		# El gancho (más largo y cargado) suena algo más grave y fuerte.
		var tono := 1.0 - 0.06 * float(clampi(indice, 0, 2))
		_sonar(_elegir(_whooshes, "whoosh"), whoosh_db + 1.5 * float(clampi(indice, 0, 2)), tono)


func _on_golpe_conectado(objetivo: Node3D, _dir: Vector3, indice: int, remate: bool) -> void:
	if objetivo == null:
		return
	if hitstop_activo:
		var dur := hitstop_remate if remate else _valor_por_golpe(hitstop_por_golpe, indice, 0.05)
		_hitstop(dur)
	_camara_golpe(indice, remate)
	_audio_golpe(indice, remate)


# ------------------------------------------------------------------ audio
func _preparar_audio() -> void:
	for i in 5:
		_cargar_en(_sfx_medio, "impactPunch_medium_%03d.ogg" % i)
		_cargar_en(_sfx_pesado, "impactPunch_heavy_%03d.ogg" % i)
		_cargar_en(_sfx_sordo, "impactSoft_heavy_%03d.ogg" % i)
	if _whooshes.is_empty():
		for v in 4:
			_whooshes.append(_sintetizar_whoosh(v))
	for i in VOCES:
		var p := AudioStreamPlayer.new()
		p.name = "VozJuice%d" % i
		p.bus = bus_audio if AudioServer.get_bus_index(bus_audio) >= 0 else &"Master"
		add_child(p)
		_voces.append(p)


func _cargar_en(lista: Array[AudioStream], archivo: String) -> void:
	var ruta := SFX_DIR + archivo
	if ResourceLoader.exists(ruta):
		var s := load(ruta) as AudioStream
		if s != null:
			lista.append(s)


func _audio_golpe(indice: int, remate: bool) -> void:
	if not audio_capas_activo:
		return
	var pesado := indice >= 1 or remate
	var lista := _sfx_pesado if pesado else _sfx_medio
	var extra_db := 2.0 if indice >= 2 else 0.0
	_sonar(_elegir(lista, "punetazo"), punetazo_db + extra_db, 1.0 - (0.05 if indice >= 2 else 0.0))
	if pesado:
		_sonar(_elegir(_sfx_sordo, "sordo"), sordo_db, 0.92)
	if remate:
		_sonar(_elegir(_sfx_pesado, "grave"), remate_grave_db, 0.55)


## Elige una variante al azar sin repetir la última de esa capa.
func _elegir(lista: Array, capa: String) -> AudioStream:
	if lista.is_empty():
		return null
	var i := randi() % lista.size()
	if lista.size() > 1 and i == int(_ultimo.get(capa, -1)):
		i = (i + 1 + randi() % (lista.size() - 1)) % lista.size()
	_ultimo[capa] = i
	return lista[i] as AudioStream


func _sonar(stream: AudioStream, db: float, tono: float) -> void:
	if stream == null or _voces.is_empty():
		return
	var p := _voces[_voz_siguiente]
	_voz_siguiente = (_voz_siguiente + 1) % _voces.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = maxf(0.1, tono * (1.0 + randf_range(-variacion_tono, variacion_tono)))
	p.play()
	_sonidos_disparados += 1


## WHOOSH sintetizado: ruido blanco por un filtro pasa-banda (SVF de Chamberlin)
## cuyo centro barre 380 Hz → ~2 kHz → 500 Hz, con envolvente de ataque rápido.
## `variante` cambia la semilla, la duración y el pico del barrido.
static func _sintetizar_whoosh(variante: int) -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.20 + 0.025 * float(variante % 3)
	var n := int(dur * sr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + variante * 17
	var pico := 1700.0 + 180.0 * float(variante)
	var datos := PackedByteArray()
	datos.resize(n * 2)
	var low := 0.0
	var band := 0.0
	var q := 0.85
	for k in n:
		var u := float(k) / float(n)
		# Barrido: sube hasta el pico al 40 % y baja.
		var fc: float = lerpf(380.0, pico, u / 0.4) if u < 0.4 else lerpf(pico, 500.0, (u - 0.4) / 0.6)
		var f := 2.0 * sin(PI * fc / float(sr))
		var x := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - q * band
		band += f * high
		# Envolvente: ataque al 35 %, caída suave (curva de potencia).
		var env: float = pow(u / 0.35, 1.6) if u < 0.35 else pow(1.0 - (u - 0.35) / 0.65, 2.2)
		# Ganancia medida para no saturar (pico < 0 dBFS) con RMS ≈ −15 dBFS.
		var s := clampf(band * env * 1.05, -1.0, 1.0)
		datos.encode_s16(k * 2, int(s * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = datos
	return wav


## Lectura para pruebas: cuántas capas de sonido disparó esta capa.
func sonidos_disparados() -> int:
	return _sonidos_disparados


# ------------------------------------------------------------------ cámara
func _pivote_camara() -> Node:
	return _jugador.get_node_or_null("PivoteCamara") if _jugador != null else null


func _camara_golpe(indice: int, remate: bool) -> void:
	var piv := _pivote_camara()
	if piv == null or not piv.has_method("impulso_golpe"):
		return
	var trauma := 0.0
	var fov := 0.0
	if sacudida_activa:
		trauma = trauma_remate if remate else _valor_por_golpe(trauma_por_golpe, indice, 0.3)
	if fov_punch_activo:
		fov = fov_punch_remate if remate else _valor_por_golpe(fov_punch_por_golpe, indice, -1.0)
	if trauma > 0.0 or not is_zero_approx(fov):
		piv.call("impulso_golpe", trauma, fov)


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
