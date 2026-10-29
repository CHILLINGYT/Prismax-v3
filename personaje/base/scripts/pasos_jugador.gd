class_name PasosJugador
extends Node

## Pisadas del jugador SINCRONIZADAS CON LA ANIMACIÓN REAL, para las seis
## transformaciones (humano, combate, fuerza, velocista, acuático y vuelo).
##
## No usa temporizadores propios ni un reloj paralelo: cada fotograma el
## controlador le pasa el AnimationPlayer de la forma activa y este nodo lee la
## FASE del clip que de verdad se está reproduciendo (posición ÷ duración) y
## dispara el sonido en el instante en que el pie correspondiente pasa por su
## punto de contacto. Por eso el sonido queda clavado al pie aunque cambie la
## velocidad (speed_scale), aunque el clip dé la vuelta (bucle) o aunque un
## fotograma largo se salte el contacto de golpe.
##
## Los clips de pisada son RECORTES del banco original de cada transformación
## (res://Audio/personaje/pasos/<forma>/paso_NN.tres). Los bancos originales
## quedan intactos: sólo se leen para hornear los recortes
## (ver .backup_pasos/_captura_pasos.gd, que documenta el corte).

## Emitida en cada pisada. Sirve para medir/verificar el sincronismo.
## `u` es la FASE DE CONTACTO que se cruzó (la de la tabla para ese pie).
signal pisada(forma: String, clip: String, pie: String, u: float, variante: int)
## Emitida cada vez que suena el golpe de la forma Combate (una por impacto real).
signal golpe

# --- Tabla de contacto (MEDIDA, no estimada) ------------------------------------
# "izq"/"der": fracción del ciclo (0..1) en la que ESE pie alcanza su punto más
#   bajo sobre el suelo (apoyo completo). Medida muestreando a 240 Hz la altura
#   del tobillo de los huesos reales del esqueleto de cada modelo
#   (.backup_pasos/_fases_contacto.gd, mismo método del relevamiento).
# "carpeta": subcarpeta de res://Audio/personaje/pasos/ con los recortes.
# "guarda": segundos mínimos sin disparar tras un CAMBIO de clip de locomoción
#   (evita el paso duplicado del fundido entre clips).
# "sep":    segundos mínimos entre dos disparos seguidos de la misma forma
#   (mantiene el solape de los pasos largos bajo control).
# "vol":    volumen del reproductor en dB (el bus "Efectos" sigue mandando).
const TABLA := {
	"humano": {
		"walk":        {"izq": 0.5586, "der": 0.0312, "carpeta": "base",       "guarda": 0.10, "sep": 0.12, "vol": -4.0},
		"fast_run":    {"izq": 0.3984, "der": 0.8516, "carpeta": "base",       "guarda": 0.08, "sep": 0.10, "vol": -3.5},
		"crouch_walk": {"izq": 0.5484, "der": 0.0645, "carpeta": "base",       "guarda": 0.12, "sep": 0.14, "vol": -7.0},
	},
	"combate": {
		"walk":        {"izq": 0.3359, "der": 0.8203, "carpeta": "combate",    "guarda": 0.10, "sep": 0.12, "vol": -4.5},
	},
	"fuerza": {
		"Walk":          {"izq": 0.5349, "der": 0.0262, "carpeta": "fuerza", "guarda": 0.12, "sep": 0.30, "vol": -8.0},
		"Run":           {"izq": 0.0214, "der": 0.5357, "carpeta": "fuerza", "guarda": 0.10, "sep": 0.28, "vol": -7.0},
		"CrouchWalk":    {"izq": 0.0000, "der": 0.5000, "carpeta": "fuerza", "guarda": 0.15, "sep": 0.34, "vol": -9.0},
		"RockCarryWalk": {"izq": 0.5349, "der": 0.0262, "carpeta": "fuerza", "guarda": 0.12, "sep": 0.30, "vol": -8.5},
	},
	"velocista": {
		"caminar_hacia_adelante": {"izq": 0.3688, "der": 0.8750, "carpeta": "velocidad", "guarda": 0.10, "sep": 0.12, "vol": -5.0},
		"caminar_hacia_atras":    {"izq": 0.6579, "der": 0.1250, "carpeta": "velocidad", "guarda": 0.10, "sep": 0.12, "vol": -5.0},
	},
	"acuatico": {
		# Fases MEDIDAS con .backup_pasos/_fases_contacto.gd sobre el PROPIO modelo
		# acuático (tobillo mixamorig_LeftFoot/RightFoot, el MÍNIMO del apoyo), NO
		# copiadas de otra forma: walk y run tienen sus propios puntos de contacto.
		"walk": {"izq": 0.2762, "der": 0.7297, "carpeta": "acuatico", "guarda": 0.10, "sep": 0.12, "vol": -5.0},
		"run":  {"izq": 0.3512, "der": 0.8690, "carpeta": "acuatico", "guarda": 0.08, "sep": 0.10, "vol": -4.0},
	},
	"vuelo": {
		# Locomoción terrestre del águila: el clip retargeteado del personaje de
		# COMBATE (vuelo_walk, ver personaje/base/scripts/retarget_locomocion_vuelo.gd)
		# con los MISMOS recortes de pisada del combate. Fases MEDIDAS sobre el clip
		# retargeteado y alineado al suelo (pruebas/probe_fases_vuelo_walk.tscn,
		# mínimo real del tobillo/punta): 0.3203 / 0.8125 (el clip del combate mide
		# 0.3359 / 0.8203 — la diferencia es de una muestra de 240 Hz).
		# "sep" CORTO (0.06) a propósito: la forma vuela a 5 m/s caminando y 8,5 m/s
		# corriendo con el MISMO clip, así que la cadencia real llega a ~10 pasos/s;
		# con 0,12 s se recortarían pisadas y la cadencia dejaría de seguir a la
		# animación. El fondo de 6 reproductores aguanta el solape.
		"vuelo_walk": {"izq": 0.3203, "der": 0.8125, "carpeta": "combate", "guarda": 0.10, "sep": 0.06, "vol": -4.5},
	},
}

## Carpeta de los recortes de pisada.
const RUTA_PASOS := "res://Audio/personaje/pasos"
## Cantidad de reproductores del fondo común. Si todos están ocupados, el paso
## nuevo se DESCARTA (nunca se corta un paso a medias).
const REPRODUCTORES := 6
## Sonido de golpe de la forma Combate (banco ORIGINAL, cortado en origen por
## offset medido en vez de recortado: es un golpe único, no un banco de pasos).
const RUTA_GOLPE_COMBATE := "res://Audio/personaje/transformacion/combate/golpe.mp3"
## Silencio de cabecera MEDIDO del golpe (s): se salta para que el impacto
## audible caiga en el fotograma del golpe, no 75 ms después. El archivo no se toca.
const AUD_INICIO_GOLPE_COMBATE := 0.070
const VOL_GOLPE_COMBATE := -2.0
## El reproductor del golpe de Combate sólo se crea donde se usa: las formas que
## ya tienen su propio sonido de golpe (el vuelo, con Golpe3/Golpe4) lo apagan
## para no duplicar reproductores ni sonidos.
@export var crear_golpe: bool = true
## Guarda tras aterrizar (s): el aterrizaje no se duplica con el paso siguiente.
const GUARDA_ATERRIZAJE := 0.10

var _reps: Array[AudioStreamPlayer] = []
var _golpe: AudioStreamPlayer = null
## carpeta -> Array[AudioStream] (se carga una sola vez, la primera vez que suena).
var _variantes: Dictionary = {}
## "carpeta|pie" -> próxima variante a usar (rotación por pie).
var _turno: Dictionary = {}
var _forma: String = ""
var _clip: String = ""
var _u_ant: float = -1.0
var _t_guarda: float = 0.0
var _t_sep: float = 0.0
var _en_suelo: bool = true
var _suena: bool = true

func _ready() -> void:
	for i in REPRODUCTORES:
		var p := AudioStreamPlayer.new()
		p.name = "Paso%d" % (i + 1)
		p.bus = &"Efectos"
		add_child(p)
		_reps.append(p)
	if crear_golpe:
		_golpe = AudioStreamPlayer.new()
		_golpe.name = "GolpeCombate"
		_golpe.bus = &"Efectos"
		_golpe.volume_db = VOL_GOLPE_COMBATE
		var st: AudioStream = load(RUTA_GOLPE_COMBATE)
		if st != null:
			_golpe.stream = st
		add_child(_golpe)

# ------------------------------------------------------------------ API pública
## Llamar UNA vez por fotograma desde el controlador, con la forma activa, su
## AnimationPlayer, delta y si el jugador puede pisar (en el suelo y en una
## acción de locomoción). Es lo único que hace sonar los pasos.
func actualizar(forma: String, ap: AnimationPlayer, permitido: bool, delta: float) -> void:
	_t_guarda = maxf(_t_guarda - delta, 0.0)
	_t_sep = maxf(_t_sep - delta, 0.0)
	if forma != _forma:
		# Cambio de transformación: lo que estuviera sonando ya no corresponde.
		if not _forma.is_empty():
			detener()
		_forma = forma
		_clip = ""
		_u_ant = -1.0
		_en_suelo = permitido
		return
	if not permitido:
		# En el aire (o acción que no es locomoción): se rearma el seguimiento.
		if _en_suelo:
			_en_suelo = false
		_clip = ""
		_u_ant = -1.0
		return
	var cfg_forma: Variant = TABLA.get(forma)
	if ap == null or cfg_forma == null:
		_clip = ""
		_u_ant = -1.0
		return
	var nombre := _clave_clip(ap)
	var cfg: Variant = (cfg_forma as Dictionary).get(nombre)
	if cfg == null:
		# Clip que NO es de locomoción (salto, golpe, dash, carga, caída...):
		# no genera pisadas y se rearma el seguimiento.
		_clip = ""
		_u_ant = -1.0
		_en_suelo = true
		return
	var largo := ap.current_animation_length
	if largo <= 0.0001:
		return
	var u := clampf(ap.current_animation_position / largo, 0.0, 1.0)
	if _clip != nombre:
		# Transición de clip. Si venía de otra LOCOMOCIÓN, una guarda breve evita
		# que el paso del fundido se cuele dos veces; si venía de un salto/ataque,
		# la guarda de aterrizaje evita duplicar el golpe contra el suelo.
		var antes_loco: bool = (_clip != "") and (cfg_forma as Dictionary).has(_clip)
		_clip = nombre
		_u_ant = u
		if antes_loco:
			_t_guarda = maxf(_t_guarda, float((cfg as Dictionary)["guarda"]))
		elif not _en_suelo:
			_t_guarda = maxf(_t_guarda, GUARDA_ATERRIZAJE)
		_en_suelo = true
		return
	_en_suelo = true
	var cfgd: Dictionary = cfg
	for pie in ["izq", "der"]:
		var fase := float(cfgd[pie])
		if not _cruza(_u_ant, u, fase):
			continue
		if _t_guarda > 0.0 or _t_sep > 0.0:
			continue
		_sonar(String(cfgd["carpeta"]), pie, float(cfgd["vol"]), fase)
		_t_sep = float(cfgd["sep"])
	_u_ant = u

## Corta los pasos en curso (cambio de forma, pausa, muerte...).
func detener() -> void:
	for p in _reps:
		if p.playing:
			p.stop()
	_clip = ""
	_u_ant = -1.0
	_t_guarda = 0.0
	_t_sep = 0.0

## Sonido de golpe de la forma Combate: UNA vez por golpe, en el instante real
## del impacto (lo llama el controlador cuando el golpe conecta).
func golpe_combate() -> void:
	if _golpe == null or _golpe.stream == null:
		return
	_golpe.stop()
	_golpe.play(AUD_INICIO_GOLPE_COMBATE)
	golpe.emit()

## Silencia/reanuda todo el sistema (ajustes, pausa).
func silenciar(si: bool) -> void:
	_suena = not si
	if si:
		detener()

# ------------------------------------------------------------------ interno
## Devuelve la clave de config del clip en curso. Los clips del velocista se
## llaman "libreria/clip"; su clave es la librería (caminar_hacia_adelante...).
func _clave_clip(ap: AnimationPlayer) -> String:
	var n := String(ap.current_animation)
	var i := n.find("/")
	return n.substr(0, i) if i >= 0 else n

## ¿La fase pasó de u_ant a u cruzando el contacto p? Cubre el salto de fotograma
## (aunque se coma el contacto entero) y la vuelta del bucle.
func _cruza(u_ant: float, u: float, p: float) -> bool:
	if u_ant < 0.0:
		return false
	if u < u_ant:
		return p > u_ant or p <= u
	return u_ant < p and p <= u

func _sonar(carpeta: String, pie: String, vol: float, fase: float) -> void:
	if not _suena:
		return
	var lista := _variantes_de(carpeta)
	if lista.is_empty():
		return
	var p := _libre()
	if p == null:
		return
	var clave := carpeta + "|" + pie
	var i := int(_turno.get(clave, 0))
	var v := i % lista.size()
	_turno[clave] = (i + 1) % lista.size()
	p.stream = lista[v]
	p.volume_db = vol
	p.play()
	pisada.emit(_forma, _clip, pie, fase, v)

## Reproductor libre del fondo común. Si TODOS están sonando devuelve null: es
## preferible perder una pisada que cortar otra a medias.
func _libre() -> AudioStreamPlayer:
	for p in _reps:
		if not p.playing:
			return p
	return null

func _variantes_de(carpeta: String) -> Array:
	if _variantes.has(carpeta):
		return _variantes[carpeta]
	var lista: Array = []
	var ruta_carpeta := "%s/%s" % [RUTA_PASOS, carpeta]
	if not DirAccess.dir_exists_absolute(ruta_carpeta):
		push_warning("[Pasos] Sin carpeta de recortes: %s/%s" % [RUTA_PASOS, carpeta])
		_variantes[carpeta] = lista
		return lista
	# `ResourceLoader.list_directory`: en el juego EXPORTADO los .tres se remapean
	# (.remap) y DirAccess no los vería; en el editor la lista es la misma.
	var nombres := ResourceLoader.list_directory(ruta_carpeta)
	nombres.sort()
	for n in nombres:
		var s := String(n)
		if s.begins_with("paso_") and s.ends_with(".tres"):
			var st: AudioStream = load("%s/%s/%s" % [RUTA_PASOS, carpeta, s])
			if st != null:
				lista.append(st)
	if lista.is_empty():
		push_warning("[Pasos] Carpeta sin recortes válidos: %s/%s" % [RUTA_PASOS, carpeta])
	_variantes[carpeta] = lista
	return lista