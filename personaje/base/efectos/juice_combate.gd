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
var _whooshes: Array[AudioStreamWAV] = []
var _sfx_medio: Array[AudioStream] = []
var _sfx_pesado: Array[AudioStream] = []
var _sfx_sordo: Array[AudioStream] = []
var _ultimo := {}
var _voces: Array[AudioStreamPlayer] = []
var _voz_siguiente := 0
var _sonidos_disparados := 0

# ------------------------------------------------------ DESTELLO + ESTALLIDO
@export_group("Destello")
## Destello blanco-cálido sobre el enemigo golpeado (material_overlay aditivo con
## contorno fresnel; no toca sus materiales ni su modelo). Se suma al destello
## rojo que ya tenía el enemigo, que se conserva.
@export var destello_enemigo_activo := true
@export var destello_color := Color(1.0, 0.94, 0.82)
## Segundos REALES que tarda en apagarse (cubre el hitstop).
@export var destello_duracion := 0.13
## Estallido de luz en el PUNTO DE CONTACTO (estrella) y, en golpes pesados y
## remates, un anillo de onda expansiva.
@export var estallido_activo := true
@export var estallido_color := Color(1.0, 0.82, 0.5)
@export var estallido_tamano := PackedFloat32Array([0.55, 0.7, 0.95])
@export var estallido_tamano_remate := 1.3
## Metros por encima del centro de golpe del enemigo (≈ pecho, 1 m) donde nace el
## estallido: los tres golpes de la cadena son puñetazos altos (cara/hombro).
@export var estallido_altura := 0.42

const SHADER_DESTELLO := preload("res://personaje/base/efectos/shaders/juice_destello_golpe.gdshader")
const SHADER_ESTALLIDO := preload("res://personaje/base/efectos/shaders/juice_estallido.gdshader")
var _estallidos_creados := 0

# ------------------------------------------------- REACCIÓN FÍSICA PROCEDURAL
@export_group("Reaccion del enemigo")
## El nodo `Visual` del enemigo se inclina hacia atrás (eje perpendicular al
## golpe, con pivote en los pies) y retrocede un palmo, y vuelve con un rebote.
## Se suma a su animación de "recibir" y a su empuje real, que no se tocan.
## Va en tiempo de JUEGO: durante el hitstop la pose queda congelada en el pico.
@export var reaccion_activa := true
@export var reaccion_grados := PackedFloat32Array([7.0, 10.0, 15.0])
@export var reaccion_grados_remate := 22.0
@export var reaccion_retroceso := 0.07
@export var reaccion_subida := 0.06
@export var reaccion_vuelta := 0.3

# ---------------------------------------------------------- CÁMARA LENTA
@export_group("Camara lenta")
## Al tumbar al ÚLTIMO enemigo del encuentro: cámara lenta marcada ("final KO").
@export var camara_lenta_ultimo_activa := true
@export_range(0.05, 1.0, 0.05) var camara_lenta_ultimo_escala := 0.25
## Segundos REALES; el último 40 % vuelve a velocidad normal con suavidad.
@export var camara_lenta_ultimo_duracion := 0.9
@export var camara_lenta_ultimo_fov := -6.0
## En cualquier otro remate (quedan enemigos): un respiro corto y leve.
@export var camara_lenta_remate_activa := true
@export_range(0.05, 1.0, 0.05) var camara_lenta_remate_escala := 0.5
@export var camara_lenta_remate_duracion := 0.22

var _lenta_desde_us := 0
var _lenta_hasta_us := 0
var _lenta_escala := 1.0
var _lentas := 0

# ------------------------------------------------------- EFECTOS DE PANTALLA
@export_group("Pantalla")
## Blur radial + aberración cromática desde el punto del impacto en los golpes
## pesados (gancho) y remates. Por debajo del HUD.
@export var pantalla_golpe_activa := true
@export_range(0.0, 0.2, 0.005) var blur_gancho := 0.035
@export_range(0.0, 0.2, 0.005) var blur_remate := 0.06
@export_range(0.0, 0.03, 0.001) var aberracion_golpe := 0.006
## Pulso de aberración al RECIBIR daño (se suma a la viñeta roja del HUD).
@export var aberracion_dano_activa := true
@export_range(0.0, 0.03, 0.001) var aberracion_dano := 0.012
@export var pantalla_duracion := 0.22

const SHADER_PANTALLA := preload("res://personaje/base/efectos/shaders/juice_pantalla_golpe.gdshader")
const CAPA_PANTALLA := 5
var _capa_pantalla: CanvasLayer = null
var _rect_pantalla: ColorRect = null
var _mat_pantalla: ShaderMaterial = null
var _blur := 0.0
var _aberr := 0.0
var _pantalla_max := 0.0
var _t_pantalla_us := 0

# ---------------------------------------------------------------- VIBRACIÓN
@export_group("Vibracion")
## Vibración de todos los mandos conectados (motor débil = "zumbido" agudo,
## fuerte = golpe grave). Sin mando conectado no hace nada.
@export var vibracion_activa := true
## [débil, fuerte, segundos] por eslabón; el remate y el daño recibido aparte.
@export var vibracion_por_golpe: Array[Vector3] = [Vector3(0.25, 0.10, 0.08), Vector3(0.30, 0.25, 0.10), Vector3(0.35, 0.55, 0.14)]
@export var vibracion_remate := Vector3(0.45, 0.9, 0.22)
@export var vibracion_dano := Vector3(0.6, 0.5, 0.18)
var _vibraciones := 0

# ------------------------------------------------- TIMING Y "SNAP" (tuning)
@export_group("Timing")
## Buffer de entrada más permisivo. El gancho no se puede encadenar hasta pasados
## 0,284 s (preparación) + 0,10 s (activo) = 0,384 s, pero el buffer del módulo
## guardaba la pulsación 0,2 s: pulsar al principio del gancho se PERDÍA y la
## cadena parecía "trabarse". Con 0,40 s cualquier pulsación hecha durante un
## golpe sale en cuanto ese golpe lo permite. Una pulsación = un golpe, igual.
@export var buffer_permisivo_activo := true
@export_range(0.1, 0.8, 0.01) var buffer_segundos := 0.40
## "Snap" del acercamiento al objetivo: la misma velocidad máxima del módulo
## (approach_speed 9 m/s), pero alcanzada antes. Con 30 m/s² tardaba 0,3 s en
## llegar a velocidad (la mitad de un acercamiento corto); con 75, 0,12 s: el
## personaje "salta" hacia el enemigo como en Arkham, sin teletransportarse.
@export var lunge_activo := true
@export var lunge_aceleracion := 75.0
const ACELERACION_ORIGINAL := 30.0
var _buffer_original := -1.0

# ------------------------------------------------------ INDICADOR DE AMENAZA
@export_group("Indicador de amenaza")
## Aviso sobre la cabeza de cada enemigo que tiene un ataque en curso (lo que ya
## registran en el ThreatSystem del CombatManager). Late cada vez más rápido y
## crece al aparecer. NO añade ningún contraataque: el proyecto no lo tiene en la
## forma Combate; es lectura del peligro (ver informe: propuesta de "counter").
@export var indicador_amenaza_activo := true
## Ámbar: distinto del cian de la bolita de "objetivo actual" que ya existe.
@export var indicador_color := Color(1.0, 0.72, 0.25)
@export var indicador_altura := 1.9      ## m sobre el centro de golpe (por encima de la bolita de objetivo, a 1,45)
@export var indicador_tamano := 0.5      ## m a 6 m de distancia (se compensa la perspectiva)

const SHADER_AMENAZA := preload("res://personaje/base/efectos/shaders/juice_indicador_amenaza.gdshader")
var _indicadores := {}   ## enemigo (instance_id) -> MeshInstance3D

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
	_preparar_pantalla()
	var stats := _jugador.get_node_or_null("Estadisticas")
	if stats != null and stats.has_signal("danio_recibido"):
		stats.connect("danio_recibido", _on_danio_recibido)
	if _jugador.has_signal("golpe_conectado"):
		_jugador.connect("golpe_conectado", _on_golpe_conectado)
	if _jugador.has_signal("golpe_lanzado"):
		_jugador.connect("golpe_lanzado", _on_golpe_lanzado)


func _exit_tree() -> void:
	for id in _indicadores.keys():
		var ind: MeshInstance3D = _indicadores[id]
		if is_instance_valid(ind):
			ind.queue_free()
	_indicadores.clear()
	# Nunca dejar el juego a cámara lenta si el jugador desaparece a mitad.
	if not is_equal_approx(_escala_puesta, 1.0) and is_equal_approx(Engine.time_scale, _escala_puesta):
		Engine.time_scale = 1.0
	_escala_puesta = 1.0


func _process(delta: float) -> void:
	_actualizar_tiempo()
	_actualizar_pantalla(delta)
	_aplicar_timing()
	_actualizar_indicadores()


## Se reaplica cada fotograma (barato): el combo puede ser el del gestor del
## encuentro o el propio del controlador, y ambos pueden aparecer más tarde.
func _aplicar_timing() -> void:
	if _jugador == null:
		return
	if "c_aceleracion_acercar" in _jugador:
		_jugador.set("c_aceleracion_acercar", lunge_aceleracion if lunge_activo else ACELERACION_ORIGINAL)
	if not _jugador.has_method("combo_actual"):
		return
	var combo: Variant = _jugador.call("combo_actual")
	if combo == null:
		return
	if _buffer_original < 0.0:
		_buffer_original = float(combo.buffer_time)
	combo.buffer_time = buffer_segundos if buffer_permisivo_activo else _buffer_original


# ------------------------------------------------------------------ eventos
func _on_golpe_lanzado(indice: int) -> void:
	if audio_capas_activo and not _whooshes.is_empty():
		# El gancho (más largo y cargado) suena algo más grave y fuerte.
		var tono := 1.0 - 0.06 * float(clampi(indice, 0, 2))
		_sonar(_elegir(_whooshes, "whoosh"), whoosh_db + 1.5 * float(clampi(indice, 0, 2)), tono)


func _on_golpe_conectado(objetivo: Node3D, dir: Vector3, indice: int, remate: bool) -> void:
	if objetivo == null:
		return
	if hitstop_activo:
		var dur := hitstop_remate if remate else _valor_por_golpe(hitstop_por_golpe, indice, 0.05)
		_hitstop(dur)
	_camara_golpe(indice, remate)
	_audio_golpe(indice, remate)
	if destello_enemigo_activo:
		_destello_enemigo(objetivo)
	if estallido_activo:
		_estallido(objetivo, dir, indice, remate)
	if reaccion_activa:
		_reaccion(objetivo, dir, indice, remate)
	if vibracion_activa:
		var v: Vector3 = vibracion_remate
		if not remate and not vibracion_por_golpe.is_empty():
			v = vibracion_por_golpe[clampi(indice, 0, vibracion_por_golpe.size() - 1)]
		_vibrar(v)
	if pantalla_golpe_activa and (indice >= 2 or remate):
		_pulso_pantalla(blur_remate if remate else blur_gancho, aberracion_golpe,
				_punto_contacto(objetivo, dir))
	if remate:
		if _quedan_enemigos(objetivo):
			if camara_lenta_remate_activa:
				_camara_lenta(camara_lenta_remate_escala, camara_lenta_remate_duracion)
		elif camara_lenta_ultimo_activa:
			_camara_lenta(camara_lenta_ultimo_escala, camara_lenta_ultimo_duracion)
			var piv := _pivote_camara()
			if piv != null and piv.has_method("impulso_golpe") and fov_punch_activo:
				piv.call("impulso_golpe", 0.0, camara_lenta_ultimo_fov)


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


# ------------------------------------------------------------------ destello
func _destello_enemigo(objetivo: Node3D) -> void:
	var visual := objetivo.get_node_or_null("Visual")
	var raiz: Node = visual if visual != null else objetivo
	var mat: ShaderMaterial = null
	if objetivo.has_meta(&"juice_destello"):
		mat = objetivo.get_meta(&"juice_destello") as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = SHADER_DESTELLO
		objetivo.set_meta(&"juice_destello", mat)
		var mallas: Array[Node] = raiz.find_children("*", "MeshInstance3D", true, false)
		if raiz is MeshInstance3D:
			mallas.append(raiz)
		for n in mallas:
			var mi := n as MeshInstance3D
			# La barra de vida (fuera de Visual) nunca entra; dentro de Visual se
			# respeta un overlay que ya existiera.
			if mi != null and mi.material_overlay == null and not String(mi.name).begins_with("Barra"):
				mi.material_overlay = mat
	mat.set_shader_parameter("color", destello_color)
	mat.set_shader_parameter("fuerza", 1.0)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fuerza", v), 1.0, 0.0, destello_duracion) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Punto de contacto: la superficie del enemigo que mira al atacante (el mismo
## criterio que VfxImpacto, para que luz y chispas salgan del mismo sitio).
func _punto_contacto(objetivo: Node3D, dir: Vector3) -> Vector3:
	var centro := objetivo.global_position + Vector3.UP * 1.0
	if objetivo.has_method("get_hit_center"):
		centro = objetivo.call("get_hit_center")
	var radio := 0.6
	if objetivo.has_method("get_hit_radius"):
		radio = maxf(float(objetivo.call("get_hit_radius")), 0.2)
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	return centro - d * radio * 0.75 + Vector3.UP * estallido_altura


func _estallido(objetivo: Node3D, dir: Vector3, indice: int, remate: bool) -> void:
	var escena := get_tree().current_scene if get_tree() != null else null
	if escena == null:
		return
	var punto := _punto_contacto(objetivo, dir)
	var tam := estallido_tamano_remate if remate else _valor_por_golpe(estallido_tamano, indice, 0.6)
	_quad_estallido(escena, punto, 0, tam, 0.11)
	if indice >= 2 or remate:
		_quad_estallido(escena, punto, 1, tam * 1.9, 0.24)


func _quad_estallido(padre: Node, punto: Vector3, forma: int, tam: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "JuiceEstallido"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_ESTALLIDO
	mat.set_shader_parameter("color", estallido_color)
	mat.set_shader_parameter("forma", forma)
	mat.set_shader_parameter("vida", 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)
	mi.global_position = punto
	mi.scale = Vector3.ONE * tam * (0.45 if forma == 0 else 0.6)
	_estallidos_creados += 1
	var tw := mi.create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * tam, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("vida", v), 1.0, 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


# ------------------------------------------------------------------ pantalla
func _preparar_pantalla() -> void:
	_capa_pantalla = CanvasLayer.new()
	_capa_pantalla.name = "JuicePantalla"
	_capa_pantalla.layer = CAPA_PANTALLA
	add_child(_capa_pantalla)
	_rect_pantalla = ColorRect.new()
	_rect_pantalla.name = "Efecto"
	_rect_pantalla.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect_pantalla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_pantalla = ShaderMaterial.new()
	_mat_pantalla.shader = SHADER_PANTALLA
	_rect_pantalla.material = _mat_pantalla
	_rect_pantalla.visible = false   # sin efecto, ni siquiera se dibuja (coste 0)
	_capa_pantalla.add_child(_rect_pantalla)


## Vibra todos los mandos conectados. `v` = (débil, fuerte, segundos).
func _vibrar(v: Vector3) -> void:
	_vibraciones += 1
	for dispositivo in Input.get_connected_joypads():
		Input.start_joy_vibration(dispositivo, clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), maxf(v.z, 0.0))


func vibraciones_pedidas() -> int:
	return _vibraciones


func _on_danio_recibido(_cantidad: float) -> void:
	if vibracion_activa:
		_vibrar(vibracion_dano)
	if aberracion_dano_activa:
		_pulso_pantalla(0.0, aberracion_dano, Vector3.INF)


## `punto` en el mundo (centro del efecto) o Vector3.INF = centro de pantalla.
func _pulso_pantalla(blur: float, aberr: float, punto: Vector3) -> void:
	if _mat_pantalla == null:
		return
	_blur = maxf(_blur, blur)
	_aberr = maxf(_aberr, aberr)
	var centro := Vector2(0.5, 0.5)
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if punto != Vector3.INF and cam != null and not cam.is_position_behind(punto):
		var tam := get_viewport().get_visible_rect().size
		var p := cam.unproject_position(punto)
		centro = Vector2(clampf(p.x / tam.x, 0.1, 0.9), clampf(p.y / tam.y, 0.1, 0.9))
	_mat_pantalla.set_shader_parameter("centro", centro)


func _actualizar_pantalla(_delta: float) -> void:
	if _mat_pantalla == null:
		return
	# Se apaga en tiempo REAL (se ve igual durante el hitstop). Se mide con el
	# reloj del sistema: `delta / time_scale` falla justo en el fotograma en que
	# cambia la escala (el delta ya venía con la escala anterior).
	var ahora := Time.get_ticks_usec()
	var real := 0.0 if _t_pantalla_us == 0 else minf(float(ahora - _t_pantalla_us) / 1_000_000.0, 0.1)
	_t_pantalla_us = ahora
	var caida := real / maxf(pantalla_duracion, 0.01)
	_blur = maxf(0.0, _blur - blur_remate * caida)
	_aberr = maxf(0.0, _aberr - aberracion_dano * caida)
	var activo := _blur > 0.0005 or _aberr > 0.0002
	_rect_pantalla.visible = activo
	if activo:
		_pantalla_max = maxf(_pantalla_max, _blur + _aberr)
		_mat_pantalla.set_shader_parameter("blur", _blur)
		_mat_pantalla.set_shader_parameter("aberracion", _aberr)


## Lectura para pruebas: pico de efecto de pantalla visto desde la última lectura.
func pantalla_pico_y_reset() -> float:
	var v := _pantalla_max
	_pantalla_max = 0.0
	return v


func pantalla_visible() -> bool:
	return _rect_pantalla != null and _rect_pantalla.visible


# ------------------------------------------------------- indicador de amenaza
func _amenazas() -> Array:
	var gestor := get_tree().get_first_node_in_group("combat_manager") if get_tree() != null else null
	if gestor == null:
		return []
	var t: Variant = gestor.get("threats")
	if t == null or not t.has_method("get_active"):
		return []
	return t.call("get_active")


func _actualizar_indicadores() -> void:
	var vivos := {}
	if indicador_amenaza_activo and _jugador is Node3D:
		var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
		var ahora := float(Time.get_ticks_msec()) / 1000.0
		for t in _amenazas():
			var e: Variant = t.get("enemy")
			if not is_instance_valid(e) or not (e is Node3D):
				continue
			var en := e as Node3D
			if en.has_method("is_alive") and not bool(en.call("is_alive")):
				continue
			var id := en.get_instance_id()
			vivos[id] = true
			var ind: MeshInstance3D = _indicadores.get(id, null)
			if ind == null or not is_instance_valid(ind):
				ind = _crear_indicador()
				if ind == null:
					continue
				_indicadores[id] = ind
				ind.set_meta(&"nace", ahora)
			var centro := en.global_position + Vector3.UP * 1.0
			if en.has_method("get_hit_center"):
				centro = en.call("get_hit_center")
			ind.global_position = centro + Vector3.UP * indicador_altura
			# Tamaño casi constante en pantalla (legible lejos, discreto cerca).
			var dist := 6.0
			if cam != null:
				dist = maxf(cam.global_position.distance_to(ind.global_position), 1.0)
			var nace := ahora - float(ind.get_meta(&"nace", ahora))
			var aparicion := clampf(nace / 0.12, 0.0, 1.0)
			var escala := indicador_tamano * clampf(dist / 6.0, 0.6, 2.2) * lerpf(1.6, 1.0, aparicion)
			ind.scale = Vector3.ONE * escala
			# Latido que se acelera mientras dura la amenaza.
			var total := maxf(float(t.get("total", 1.0)), 0.01)
			var resta := clampf(float(t.get("time_left", 0.0)) / total, 0.0, 1.0)
			var mat := ind.material_override as ShaderMaterial
			mat.set_shader_parameter("latido", 0.5 + 0.5 * sin(ahora * lerpf(28.0, 10.0, resta)))
			mat.set_shader_parameter("intensidad", lerpf(1.6, 1.0, aparicion))
	for id in _indicadores.keys():
		if not vivos.has(id):
			var viejo: MeshInstance3D = _indicadores[id]
			if is_instance_valid(viejo):
				viejo.queue_free()
			_indicadores.erase(id)


func _crear_indicador() -> MeshInstance3D:
	var escena := get_tree().current_scene if get_tree() != null else null
	if escena == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "JuiceIndicadorAmenaza"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_AMENAZA
	mat.set_shader_parameter("color", indicador_color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	escena.add_child(mi)
	return mi


func indicadores_visibles() -> int:
	return _indicadores.size()


# ------------------------------------------------------------------ reacción
func _reaccion(objetivo: Node3D, dir: Vector3, indice: int, remate: bool) -> void:
	var visual := objetivo.get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	# Pose de reposo guardada UNA vez: cada reacción parte de ella, así varios
	# golpes seguidos nunca acumulan deriva.
	if not visual.has_meta(&"juice_reposo"):
		visual.set_meta(&"juice_reposo", visual.transform)
	var reposo: Transform3D = visual.get_meta(&"juice_reposo")
	var padre := visual.get_parent() as Node3D
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001 or padre == null:
		return
	var d_local := (padre.global_transform.basis.inverse() * d.normalized())
	d_local.y = 0.0
	if d_local.length_squared() < 0.0001:
		return
	d_local = d_local.normalized()
	var eje := Vector3.UP.cross(d_local).normalized()
	var grados := reaccion_grados_remate if remate else _valor_por_golpe(reaccion_grados, indice, 8.0)
	var ang := deg_to_rad(grados)
	var desplaz := d_local * reaccion_retroceso * (1.6 if remate else 1.0)
	var subida := reaccion_subida if indice >= 2 or remate else 0.0
	if visual.has_meta(&"juice_tween"):
		var previo := visual.get_meta(&"juice_tween") as Tween
		if previo != null and previo.is_valid():
			previo.kill()
	var aplicar := func(k: float) -> void:
		if not is_instance_valid(visual):
			return
		var t := reposo
		t.basis = Basis(eje, ang * k) * reposo.basis
		t.origin = reposo.origin + desplaz * k + Vector3.UP * subida * k
		visual.transform = t
	var tw := visual.create_tween()
	tw.tween_method(aplicar, 0.0, 1.0, 0.055).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(aplicar, 1.0, 0.0, reaccion_vuelta).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	visual.set_meta(&"juice_tween", tw)


func estallidos_creados() -> int:
	return _estallidos_creados


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
	if ahora < _lenta_hasta_us:
		var total := float(maxi(_lenta_hasta_us - _lenta_desde_us, 1))
		var u := float(ahora - _lenta_desde_us) / total
		# Meseta y salida suave en el último 40 % (smoothstep), sin "tirón".
		var k := 1.0 if u < 0.6 else 1.0 - smoothstep(0.6, 1.0, u)
		escala = minf(escala, lerpf(1.0, _lenta_escala, k))
	return escala


func _camara_lenta(escala: float, segundos: float) -> void:
	var ahora := Time.get_ticks_usec()
	# Una cámara lenta en curso más fuerte no se acorta.
	if ahora < _lenta_hasta_us and _lenta_escala <= escala:
		return
	_lenta_desde_us = ahora
	_lenta_hasta_us = ahora + int(segundos * 1_000_000.0)
	_lenta_escala = escala
	_lentas += 1
	_actualizar_tiempo()


## ¿Queda algún enemigo vivo en el encuentro además del que acaba de caer?
func _quedan_enemigos(caido: Node) -> bool:
	var gestor := get_tree().get_first_node_in_group("combat_manager") if get_tree() != null else null
	var lista: Array = []
	if gestor != null and gestor.has_method("get_active_enemies"):
		lista = gestor.call("get_active_enemies")
	else:
		lista = get_tree().get_nodes_in_group(&"enemigos_prueba")
	for e in lista:
		if e == caido or not is_instance_valid(e):
			continue
		if e.has_method("is_alive") and not bool(e.call("is_alive")):
			continue
		return true
	return false


func camaras_lentas() -> int:
	return _lentas


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
