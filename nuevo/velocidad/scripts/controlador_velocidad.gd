extends CharacterBody3D

# Componentes del modulo Velocidad (preload, sin class_name global para evitar
# colisiones con el proyecto anfitrion).
const CamaraV := preload("res://velocidad/scripts/camara_velocidad.gd")
const TrazadorV := preload("res://velocidad/scripts/trazador.gd")
const EfectosV := preload("res://velocidad/scripts/efectos_velocidad.gd")
const CombateV := preload("res://velocidad/scripts/combate.gd")
const EfectoTransfV := preload("res://velocidad/scripts/efecto_transformacion.gd")

# Jugador principal del mundo: Leo (forma humana) <-> Velocista (transformación).
#
# Un ÚNICO CharacterBody3D sostiene las dos formas. Sólo cambia lo que se ve
# (modelo humano o modelo velocista) y las capacidades asociadas. La posición,
# el cuerpo físico, la colisión y la cámara son los mismos en ambas formas.
#
# La forma VELOCISTA reutiliza TAL CUAL los sistemas ya existentes de
# res://ziba/: EfectosVelocidad, CapaVelocidad (shader), SistemaCombate,
# TrazadorRuta, RayosVelocidad y la cámara CamaraZiba. La lógica de estados
# (dash, caída-dash, carga de poder, supervelocidad, combate, emote) es la del
# prototipo ziba/scripts/jugador.gd, portada aquí sin cambiar su comportamiento.
#
# La forma HUMANA usa el modelo y las animaciones propias de Leo
# (res://Leo/), con movimiento/correr/salto y las acciones del proyecto.

enum Forma { HUMANO, VELOCISTA }

# Estados del sistema de supervelocidad (idénticos a ziba/scripts/jugador.gd).
enum Estado { NORMAL, DASH, CAIDA_DASH, CARGA, PREPARADO, EJECUCION }

# ------------------------------------------------------------------ Leo: forma humana
const H_VEL_CAMINAR := 3.0
const H_VEL_CORRER := 5.5
const H_ACELERACION := 40.0
const H_DESACELERACION := 50.0
const H_GRAVEDAD := 24.0
const H_SALTO := 7.5
# A partir de esta velocidad horizontal el salto usa el clip "en carrera".
const H_VELOCIDAD_SALTO_CORRIENDO := 3.5
const H_UMBRAL_MOVIMIENTO := 0.15
const H_MEZCLA := 0.15
# Agacharse (misma mecánica que el Leo original de res://Leo/leo.gd):
# velocidad reducida, no se puede correr ni saltar, y la cámara baja un poco.
const H_VEL_AGACHADO := 2.5
const H_ALTURA_AGACHADO := 0.7
const H_MEZCLA_AGACHARSE := 0.25

# Clips de la librería de Leo (res://Leo/animations/leo_animations.tres).
const ANIM_H_IDLE := "idle"
const ANIM_H_WALK := "walk"
const ANIM_H_RUN := "fast_run"
const ANIM_H_SALTO := "jump_up"
const ANIM_H_SALTO_CORRIENDO := "running_jump"
# Clips de agachado: "crouch_walk" ya existe en leo_animations.tres (no se crea nada).
# "crouch_idle" todavía no existe; si falta, se congela la pose de crouch_walk (como en leo.gd).
const ANIM_H_CROUCH_WALK := "crouch_walk"
const ANIM_H_CROUCH_IDLE := "crouch_idle"

# ------------------------------------------- Velocista: supervelocidad (ziba/)
# Animaciones existentes (librerías del AnimationPlayer del modelo velocista).
const ANIM_INACTIVO := "inactivo"
const ANIM_ADELANTE := "caminar_hacia_adelante"
const ANIM_ATRAS := "caminar_hacia_atras"
const ANIM_CARGA := "cargar_poder_click-derecho"
const ANIM_DASH := "dash-con-shift"
const ANIM_SALTO := "jumping up(1)"
const ANIM_SUPERVELOCIDAD := "superduper_velocidad"
const ANIM_INACTIVO_VELOCIDAD := "inactivo_despues-despues-de-30s-velocidad"
const ANIM_COMBO_1 := "combo-1"
const ANIM_COMBO_2 := "combo-2"
const ANIM_COMBO_3 := "combo-3"
const ANIM_COMBO_4 := "combo-4"
const ANIM_MODO_ATAQUE := "inactivo_modo_ataque"
const ANIM_EMOTE := "calentamiento_ataque"

# Tiempos de blending (idénticos al prototipo).
const BLEND_MARCHA := 0.25
const BLEND_MARCHA_FIN := 0.30
const BLEND_CAMBIO_MARCHA := 0.18
const BLEND_SALTO := 0.10
const BLEND_POST_SALTO := 0.15
const BLEND_DASH := 0.06
const BLEND_POST_DASH := 0.12
const BLEND_CARGA := 0.10
const BLEND_LIBERACION := 0.08
const BLEND_FIN_VELOCIDAD := 0.22
const BLOQUEO_FIN_VELOCIDAD := 0.12
const BLEND_ATAQUE := 0.08
const BLEND_POST_ATAQUE := 0.16
const BLEND_EMOTE := 0.12
# Fundido al entrar/salir de la transformación.
const BLEND_TRANSFORMACION := 0.15

const TIEMPO_MODO_ATAQUE := 10.0
const FACTOR_MOVILIDAD_ATAQUE := 0.35
const IMPULSO_AVANCE := 4.5
const VENTANA_CONTINUACION := 0.5

@export_group("Forma humana")
@export var h_vel_caminar: float = H_VEL_CAMINAR
@export var h_vel_correr: float = H_VEL_CORRER

@export_group("Movimiento velocista")
@export var velocidad_max: float = 7.0
@export var aceleracion: float = 45.0
@export var desaceleracion: float = 55.0
@export var gravedad: float = 24.0
@export var fuerza_salto: float = 7.5

@export_group("Dash")
@export var distancia_dash: float = 10.0
@export var duracion_dash: float = 0.09
@export var distancia_objetivo_dash: float = 9.0

@export_group("Poder supervelocidad")
@export var vel_trayecto_max: float = 60.0
@export var vel_trayecto_min: float = 34.0

var forma: int = Forma.HUMANO
var estado: int = Estado.NORMAL
# Verdadero mientras corre la transición visual al cambiar de forma con G.
var _transformando: bool = false

@onready var humano: Node3D = $Humano
@onready var anim_humano: AnimationPlayer = $Humano/Animador
@onready var vel_modelo: Node3D = $Visual/Pose/Volteo/Modelo
@onready var visual: Node3D = $Visual
@onready var pose: Node3D = $Visual/Pose
@onready var pivote: CamaraV = $PivoteCamara
@onready var trazador: TrazadorV = $Trazador
@onready var efectos: EfectosV = $Efectos
@onready var combate: CombateV = $Combate
@onready var efecto_transf: EfectoTransfV = $EfectoTransformacion

# --- Estado forma humana ---
var h_salto_aire: bool = false
var h_anim_salto: String = ANIM_H_SALTO
var h_agachado: bool = false
var h_pivote_y_base: float = 1.6
var h_espera_congelar: float = 0.0

# --- Estado velocista ---
var _dir_dash: Vector3 = Vector3.ZERO
var _pos_dash_inicio: Vector3 = Vector3.ZERO
var _objetivo_dash: Vector3 = Vector3.ZERO
var _t_dash: float = 0.0
var _t_carga: float = 0.0
var _t_preparado: float = 0.0
var _puntos: Array[Vector3] = []
var _idx: int = 0
var _vel_trayecto: float = 0.0
var _hubo_combo_atras: bool = false
var _en_ventana_atras: bool = false
var _t_ventana: float = 0.0
var _dir_orient_ventana: Vector3 = Vector3.ZERO
var _ultimo_dir_movimiento: Vector3 = Vector3.ZERO
var _anim: AnimationPlayer = null
var _anim_nombres: Dictionary = {}
var _anim_actual: String = ""
var _bloqueo_anim: float = 0.0
var _ataque_activo: bool = false
var _t_ataque: float = 0.0
var _emote_activo: bool = false
var _t_emote: float = 0.0
var _en_modo_ataque: bool = false
var _t_modo_ataque: float = 0.0
var _salto_forzado: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_configurar_animaciones()
	combate.golpe_realizado.connect(_on_golpe_realizado)
	# Altura base del pivote de cámara, para bajarla al agacharse y restaurarla después.
	h_pivote_y_base = pivote.position.y
	# Iguala la altura visual de la forma velocista a la de Leo humano.
	_ajustar_escala_velocista()
	# La partida arranca SIEMPRE en la forma humana (Leo).
	forma = Forma.HUMANO
	visual.visible = false
	humano.visible = true
	_reproducir_humano(ANIM_H_IDLE, 0.0)

# Fuerza usada por herramientas/diagnóstico (igual que el prototipo).
func forma_actual() -> int:
	return forma

func esta_transformado() -> bool:
	return forma == Forma.VELOCISTA

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# G (interruptor): humano -> velocista y velocista -> humano.
	# is_action_just_pressed evita que mantener G repita la transformación.
	if Input.is_action_just_pressed("transformacion_velocidad"):
		_alternar_forma_con_efecto()

	# Durante la transición visual no hay control horizontal ni nuevas acciones:
	# sólo actúa la gravedad (para no quedar flotando) y se mueve el cuerpo.
	if _transformando:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravedad * delta
		elif velocity.y < 0.0:
			velocity.y = -0.1
		move_and_slide()
		return

	if forma == Forma.HUMANO:
		_procesar_humano(delta)
	else:
		match estado:
			Estado.NORMAL:
				_procesar_normal(delta)
			Estado.DASH:
				_procesar_dash(delta)
			Estado.CAIDA_DASH:
				_procesar_caida_dash()
			Estado.CARGA:
				_procesar_carga(delta)
			Estado.PREPARADO:
				_procesar_preparado(delta)
			Estado.EJECUCION:
				_procesar_ejecucion(delta)
		_actualizar_animaciones(delta)
		_actualizar_pose(delta)

# =============================================================== TRANSFORMACIÓN
func _alternar_forma() -> void:
	if forma == Forma.HUMANO:
		_entrar_velocista()
	else:
		_entrar_humano()

# Transición visual al cambiar de forma con G: reproduce el efecto, cambia de
# forma en su pico y espera a que termine antes de devolver el control. La
# lógica interna del cambio de forma NO cambia (_alternar_forma).
func _alternar_forma_con_efecto() -> void:
	if _transformando:
		return
	_transformando = true
	efecto_transf.reproducir()
	await efecto_transf.pico_alcanzado
	_alternar_forma()
	await efecto_transf.terminado
	_transformando = false

func _entrar_velocista() -> void:
	forma = Forma.VELOCISTA
	h_salto_aire = false
	h_agachado = false
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	visual.visible = true
	_anim_actual = ""
	_salto_forzado = false
	_ataque_activo = false
	_emote_activo = false
	_bloqueo_anim = 0.0
	_reproducir_anim(ANIM_INACTIVO, BLEND_TRANSFORMACION, true)

func _entrar_humano() -> void:
	forma = Forma.HUMANO
	_detener_velocista()
	visual.visible = false
	humano.visible = true
	h_salto_aire = false
	_reproducir_humano(ANIM_H_IDLE, BLEND_TRANSFORMACION)

# Apaga y limpia todo lo que la forma velocista pudiera tener activo, para que
# al volver a humano no quede ningún efecto a medias.
func _detener_velocista() -> void:
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	efectos.terminar_dash()
	efectos.terminar_carga()
	efectos.terminar_ejecucion()
	efectos.cancelar_ataque()
	trazador.limpiar()
	combate.cancelar_combo()
	pivote.vibracion = 0.0
	pivote.permitir_look = true
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.definir_pitch(-0.25)
	pivote.position.y = h_pivote_y_base

# ============================================================== FORMA HUMANA (Leo)
func _direccion_entrada() -> Vector3:
	var base := pivote.global_transform.basis
	var adelante := -base.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	var derecha := base.x
	derecha.y = 0.0
	derecha = derecha.normalized()
	var v := Vector2.ZERO
	if Input.is_action_pressed("mover_adelante"):
		v.y -= 1.0
	if Input.is_action_pressed("mover_atras"):
		v.y += 1.0
	if Input.is_action_pressed("mover_izquierda"):
		v.x -= 1.0
	if Input.is_action_pressed("mover_derecha"):
		v.x += 1.0
	if v == Vector2.ZERO:
		return Vector3.ZERO
	v = v.normalized()
	return (adelante * (-v.y) + derecha * v.x).normalized()

func _procesar_humano(delta: float) -> void:
	if h_salto_aire and is_on_floor():
		h_salto_aire = false

	# Agacharse con CTRL (misma mecánica que el Leo original): no mientras salta.
	h_agachado = Input.is_key_pressed(KEY_CTRL) and not h_salto_aire

	var dir := _direccion_entrada()
	var corriendo := Input.is_key_pressed(KEY_SHIFT) and not h_agachado
	var vel_objetivo := h_vel_caminar
	if h_agachado:
		vel_objetivo = H_VEL_AGACHADO
	elif corriendo:
		vel_objetivo = h_vel_correr

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, H_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, H_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= H_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# No se puede saltar agachado.
	if is_on_floor() and Input.is_action_just_pressed("saltar") and not h_agachado:
		velocity.y = H_SALTO
		_iniciar_salto_humano()

	move_and_slide()
	_orientar_humano(delta, dir)
	_actualizar_altura_camara(delta)
	_actualizar_anim_humano(delta)

func _orientar_humano(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	humano.rotation.y = lerp_angle(humano.rotation.y, objetivo, 12.0 * delta)

func _iniciar_salto_humano() -> void:
	h_salto_aire = true
	var rapidez := Vector2(velocity.x, velocity.z).length()
	h_anim_salto = ANIM_H_SALTO_CORRIENDO if rapidez > H_VELOCIDAD_SALTO_CORRIENDO else ANIM_H_SALTO
	_reproducir_humano(h_anim_salto)

func _actualizar_anim_humano(delta: float) -> void:
	if anim_humano == null:
		return
	if h_salto_aire:
		anim_humano.speed_scale = 1.0
		_reproducir_humano(h_anim_salto)
		return
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if h_agachado:
		if rapidez < H_UMBRAL_MOVIMIENTO:
			_animar_agachado_quieto(delta)
		else:
			_reproducir_humano(ANIM_H_CROUCH_WALK, H_MEZCLA_AGACHARSE)
			anim_humano.speed_scale = clampf(rapidez / H_VEL_AGACHADO, 0.4, 1.8)
		return
	anim_humano.speed_scale = 1.0
	if rapidez < H_UMBRAL_MOVIMIENTO:
		_reproducir_humano(ANIM_H_IDLE)
	elif Input.is_key_pressed(KEY_SHIFT):
		_reproducir_humano(_clip_humano([ANIM_H_RUN, ANIM_H_WALK]))
	else:
		_reproducir_humano(ANIM_H_WALK)

# Reproduce un clip humano sólo si no está ya sonando (no lo reinicia cada frame).
func _reproducir_humano(nombre: String, mezcla: float = H_MEZCLA) -> void:
	if anim_humano == null or not anim_humano.has_animation(nombre):
		return
	if anim_humano.current_animation != nombre or not anim_humano.is_playing():
		anim_humano.speed_scale = 1.0
		anim_humano.play(nombre, mezcla)

# Devuelve el primer clip de la lista que exista en la librería de Leo.
func _clip_humano(opciones: Array) -> String:
	for opcion in opciones:
		if anim_humano.has_animation(opcion):
			return opcion
	return ANIM_H_IDLE

# Baja el pivote de la cámara al agacharse y lo devuelve a su altura al levantarse.
func _actualizar_altura_camara(delta: float) -> void:
	var objetivo := h_pivote_y_base - (H_ALTURA_AGACHADO if h_agachado else 0.0)
	pivote.position.y = lerpf(pivote.position.y, objetivo, 8.0 * delta)

# Agachado y quieto: si existe "crouch_idle" se reproduce; si no, se usa el ciclo de
# crouch_walk y, tras el fundido de entrada, se congela la pose (igual que res://Leo/leo.gd).
func _animar_agachado_quieto(delta: float) -> void:
	if anim_humano.has_animation(ANIM_H_CROUCH_IDLE):
		anim_humano.speed_scale = 1.0
		_reproducir_humano(ANIM_H_CROUCH_IDLE, H_MEZCLA_AGACHARSE)
		return
	if anim_humano.current_animation != ANIM_H_CROUCH_WALK or not anim_humano.is_playing():
		_reproducir_humano(ANIM_H_CROUCH_WALK, H_MEZCLA_AGACHARSE)
		anim_humano.speed_scale = 1.0
		h_espera_congelar = H_MEZCLA_AGACHARSE
		return
	if h_espera_congelar > 0.0:
		h_espera_congelar -= delta
		return
	anim_humano.speed_scale = 0.0

# La forma velocista debe verse EXACTAMENTE del mismo tamaño que Leo humano. La causa
# real de la diferencia NO es un nodo padre ni la importación: son escalas base distintas.
# El FBX de Leo viene en unidades diminutas (leo.tscn lo compensa con escala 200 -> ~1.95 m),
# mientras que el FBX del velocista ya viene en metros (~0.98 m). Se normaliza la escala del
# modelo velocista a la altura real de Leo, en lugar de tocar el CharacterBody3D o la colisión.
func _ajustar_escala_velocista() -> void:
	var h_leo := _altura_visual(humano)
	var h_vel := _altura_visual(vel_modelo)
	if h_leo > 0.001 and h_vel > 0.001:
		var s := h_leo / h_vel
		vel_modelo.scale = Vector3(s, s, s)

# Altura de la caja envolvente de todas las mallas de un subárbol, medida en el espacio
# local del nodo indicado (incluye su propia escala actual).
func _altura_visual(raiz: Node3D) -> float:
	var inv := raiz.global_transform.affine_inverse()
	var caja := AABB()
	var cont := 0
	for nodo in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null:
			continue
		var c: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		caja = c if cont == 0 else caja.merge(c)
		cont += 1
	return caja.size.y

# ============================================================ VELOCISTA (ziba/)
# A partir de aquí el comportamiento es el del prototipo de supervelocidad
# (ziba/scripts/jugador.gd). Los nodos Efectos/Trazador/Combate/CapaVelocidad y
# la cámara CamaraZiba se reutilizan sin cambios.
func _procesar_normal(delta: float) -> void:
	var dir := _direccion_entrada()
	_actualizar_logica_atras(delta, dir)

	var vel_objetivo := velocidad_max
	if _ataque_activo:
		vel_objetivo *= FACTOR_MOVILIDAD_ATAQUE

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, aceleracion * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, desaceleracion * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and Input.is_action_just_pressed("saltar"):
		if _ataque_activo:
			_cancelar_ataque_por_salto()
		velocity.y = fuerza_salto

	move_and_slide()

	if _en_ventana_atras:
		_orientar(delta, _dir_orient_ventana)
	else:
		var retrocede := Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante")
		_orientar(delta, -dir if retrocede else dir)

	if is_on_floor() and Input.is_action_just_pressed("atacar"):
		combate.intentar_golpe()
	if Input.is_action_just_pressed("emote"):
		_intentar_emote()
	if Input.is_action_just_pressed("dash"):
		_intentar_dash()
	if Input.is_action_just_pressed("cargar_poder"):
		_iniciar_carga()

func _on_golpe_realizado(indice: int) -> void:
	_en_modo_ataque = true
	_t_modo_ataque = TIEMPO_MODO_ATAQUE
	_emote_activo = false
	_t_emote = 0.0
	_ataque_activo = true
	var clave := _clave_combo(indice)
	_t_ataque = _duracion_anim(clave)
	_reproducir_anim(clave, BLEND_ATAQUE, true)
	efectos.golpe_ataque(indice)
	var adelante := -visual.global_transform.basis.z
	adelante.y = 0.0
	if adelante.length() > 0.001:
		adelante = adelante.normalized()
		var horiz := Vector3(velocity.x, 0.0, velocity.z) + adelante * IMPULSO_AVANCE
		if horiz.length() > velocidad_max:
			horiz = horiz.normalized() * velocidad_max
		velocity.x = horiz.x
		velocity.z = horiz.z

func _cancelar_ataque_por_salto() -> void:
	_ataque_activo = false
	_t_ataque = 0.0
	_salto_forzado = true
	efectos.cancelar_ataque()
	combate.cancelar_combo()
	_reproducir_anim(ANIM_SALTO, BLEND_SALTO, true)

func _intentar_emote() -> void:
	if _ataque_activo:
		return
	_emote_activo = true
	_t_emote = _duracion_anim(ANIM_EMOTE)
	_reproducir_anim(ANIM_EMOTE, BLEND_EMOTE, true)

func _clave_combo(indice: int) -> String:
	match indice:
		1:
			return ANIM_COMBO_1
		2:
			return ANIM_COMBO_2
		3:
			return ANIM_COMBO_3
		4:
			return ANIM_COMBO_4
	return ANIM_COMBO_1

func _duracion_anim(clave: String) -> float:
	var nombre := String(_anim_nombres.get(clave, ""))
	if _anim == null or nombre.is_empty():
		return 0.3
	var anim := _anim.get_animation(nombre)
	return anim.length if anim != null else 0.3

func _actualizar_logica_atras(delta: float, dir: Vector3) -> void:
	var s := Input.is_action_pressed("mover_atras")
	var w := Input.is_action_pressed("mover_adelante")
	var a := Input.is_action_pressed("mover_izquierda")
	var d := Input.is_action_pressed("mover_derecha")

	if not s or w:
		_hubo_combo_atras = false
		_en_ventana_atras = false
		_t_ventana = 0.0
		if dir.length() > 0.05:
			_ultimo_dir_movimiento = dir
		return

	if a or d:
		_hubo_combo_atras = true
		_en_ventana_atras = false
		_t_ventana = 0.0
		_ultimo_dir_movimiento = dir
		return

	if _en_ventana_atras:
		_t_ventana += delta
		if _t_ventana >= VENTANA_CONTINUACION:
			_en_ventana_atras = false
		return

	if _hubo_combo_atras:
		_en_ventana_atras = true
		_t_ventana = 0.0
		_dir_orient_ventana = -_ultimo_dir_movimiento
		_hubo_combo_atras = false

# ---------------- Dash ----------------
func _intentar_dash() -> void:
	var dir := _direccion_entrada()
	if dir.length() < 0.05:
		dir = -pivote.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
	if is_on_floor():
		_iniciar_dash(dir)
	else:
		estado = Estado.CAIDA_DASH
		_dir_dash = dir
		velocity = Vector3(0.0, -35.0, 0.0)
		efectos.iniciar_caida_dash()

func _iniciar_dash(dir: Vector3) -> void:
	estado = Estado.DASH
	_dir_dash = dir
	_orientar_instant(dir)
	_objetivo_dash = global_position + dir * distancia_objetivo_dash
	_objetivo_dash.y = global_position.y
	_pos_dash_inicio = global_position
	_t_dash = 0.0
	_bloqueo_anim = 0.0
	efectos.iniciar_dash(dir)

func _procesar_dash(delta: float) -> void:
	_t_dash += delta
	var to := _objetivo_dash - global_position
	to.y = 0.0
	if to.length() < 0.4 or _t_dash > 0.5:
		_terminar_dash()
		return
	var dir := to.normalized()
	var col := move_and_collide(dir * (distancia_dash / duracion_dash) * delta)
	if col != null:
		_terminar_dash()
		return
	efectos.actualizar_ejecucion(global_position, dir)

func _terminar_dash() -> void:
	estado = Estado.NORMAL
	velocity = _dir_dash * velocidad_max
	print("[Leo] dash recorrido: ", snappedf((global_position - _pos_dash_inicio).length(), 0.01), " m")
	efectos.terminar_dash()

func _procesar_caida_dash() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -35.0
	move_and_slide()
	if is_on_floor():
		_iniciar_dash(_dir_dash)

# ---------------- Carga / trazado ----------------
func _iniciar_carga() -> void:
	estado = Estado.CARGA
	_t_carga = 0.0
	_bloqueo_anim = 0.0
	var cam_fwd := -pivote.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length() > 0.001:
		_orientar_instant(cam_fwd.normalized())
	pivote.permitir_look = false
	pivote.definir_pitch(-0.32)
	pivote.objetivo_largo = pivote.largo_base * 0.6
	pivote.objetivo_fov = pivote.fov_base + 6.0
	var cam := pivote.get_node_or_null("Brazo/Camara") as Camera3D
	trazador.iniciar(global_position, cam, 0.0)
	efectos.iniciar_carga()

func _procesar_carga(delta: float) -> void:
	_t_carga += delta
	velocity = velocity.move_toward(Vector3.ZERO, desaceleracion * delta)
	if not is_on_floor():
		velocity.y -= gravedad * delta
	move_and_slide()

	var t := clampf(_t_carga / 1.8, 0.0, 1.0)
	efectos.actualizar_carga(t)
	pivote.vibracion = lerpf(0.15, 1.0, t)
	pivote.objetivo_largo = pivote.largo_base * lerpf(0.6, 0.42, t)

	if Input.is_action_just_released("cargar_poder"):
		_soltar_carga()

func _soltar_carga() -> void:
	pivote.permitir_look = true
	pivote.vibracion = 0.0
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.definir_pitch(-0.25)
	var muestras := trazador.finalizar()
	efectos.terminar_carga()
	if muestras.size() >= 2:
		_puntos = muestras
		_idx = 0
		_vel_trayecto = vel_trayecto_min
		_t_preparado = 0.0
		estado = Estado.PREPARADO
		pivote.objetivo_largo = pivote.largo_base * 0.7
		pivote.objetivo_fov = pivote.fov_base + 12.0
		pivote.vibracion = 0.5
	else:
		trazador.limpiar()
		estado = Estado.NORMAL

func _procesar_preparado(delta: float) -> void:
	_t_preparado += delta
	velocity = velocity.move_toward(Vector3.ZERO, desaceleracion * delta)
	if not is_on_floor():
		velocity.y -= gravedad * delta
	move_and_slide()
	if _t_preparado >= 0.12:
		_iniciar_recorrido()

func _iniciar_recorrido() -> void:
	estado = Estado.EJECUCION
	trazador.set_ejecucion(true)
	efectos.iniciar_ejecucion()
	pivote.objetivo_largo = pivote.largo_base * 0.9
	pivote.objetivo_fov = pivote.fov_base + 20.0
	pivote.vibracion = 0.6

# ---------------- Ejecución de la trayectoria ----------------
func _procesar_ejecucion(delta: float) -> void:
	if _idx >= _puntos.size():
		_terminar_ejecucion()
		return
	var objetivo := _puntos[_idx]
	var to := objetivo - global_position
	to.y = 0.0
	if to.length() < 0.8:
		_idx += 1
		if _idx >= _puntos.size():
			_terminar_ejecucion()
			return
		objetivo = _puntos[_idx]
		to = objetivo - global_position
		to.y = 0.0
	if to.length() < 0.001:
		_idx += 1
		return
	var dir := to.normalized()
	_vel_trayecto = move_toward(_vel_trayecto, vel_trayecto_max, 220.0 * delta)

	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()

	var col := move_and_collide(dir * _vel_trayecto * delta)
	_orientar_instant(dir)
	velocity.x = dir.x * _vel_trayecto
	velocity.z = dir.z * _vel_trayecto
	if col != null:
		_terminar_ejecucion()
		return

	efectos.actualizar_ejecucion(global_position, dir)
	trazador.agregar_estela(global_position)

func _terminar_ejecucion() -> void:
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.vibracion = 0.0
	efectos.terminar_ejecucion()
	trazador.finalizar_ejecucion()
	_bloqueo_anim = BLOQUEO_FIN_VELOCIDAD
	_reproducir_anim(ANIM_INACTIVO, BLEND_FIN_VELOCIDAD)

# ---------------- Animaciones (velocista) ----------------
func _configurar_animaciones() -> void:
	_anim = get_node_or_null("Visual/Pose/Volteo/Modelo/AnimadorVelocista") as AnimationPlayer
	if _anim == null:
		push_warning("[Leo] Sin AnimationPlayer en el modelo velocista: la forma velocista se movera sin animaciones.")
		return
	for lib_nombre in _anim.get_animation_library_list():
		var clave := String(lib_nombre)
		if clave.is_empty():
			continue
		var lib: AnimationLibrary = _anim.get_animation_library(lib_nombre)
		if lib == null or lib.get_animation_list().is_empty():
			continue
		var clip := lib.get_animation_list()[0]
		_anim_nombres[clave] = "%s/%s" % [clave, clip]
		_preparar_bucle(clave, lib.get_animation(clip))

func _preparar_bucle(clave: String, anim: Animation) -> void:
	match clave:
		ANIM_INACTIVO, ANIM_ADELANTE, ANIM_ATRAS, ANIM_SUPERVELOCIDAD, ANIM_MODO_ATAQUE:
			anim.loop_mode = Animation.LOOP_LINEAR
		ANIM_CARGA:
			anim.loop_mode = Animation.LOOP_PINGPONG
		ANIM_COMBO_1, ANIM_COMBO_2, ANIM_COMBO_3, ANIM_COMBO_4, ANIM_EMOTE:
			anim.loop_mode = Animation.LOOP_NONE

func _reproducir_anim(clave: String, blend: float, forzar: bool = false) -> void:
	if _anim == null:
		return
	if clave == _anim_actual and not forzar:
		return
	var nombre := String(_anim_nombres.get(clave, ""))
	if nombre.is_empty():
		return
	_anim_actual = clave
	_anim.play(nombre, blend)

func _blend_para(clave: String) -> float:
	match clave:
		ANIM_SALTO:
			return BLEND_SALTO
		ANIM_DASH:
			return BLEND_DASH
		ANIM_CARGA:
			return BLEND_CARGA
		ANIM_SUPERVELOCIDAD:
			return BLEND_LIBERACION
	match _anim_actual:
		ANIM_DASH:
			return BLEND_POST_DASH
		ANIM_SALTO:
			return BLEND_POST_SALTO
		ANIM_SUPERVELOCIDAD:
			return BLEND_FIN_VELOCIDAD
		ANIM_ADELANTE, ANIM_ATRAS:
			return BLEND_MARCHA_FIN if clave == ANIM_INACTIVO else BLEND_CAMBIO_MARCHA
	return BLEND_MARCHA

func _actualizar_animaciones(delta: float) -> void:
	if _anim == null:
		return
	_bloqueo_anim = maxf(0.0, _bloqueo_anim - delta)
	if _ataque_activo:
		_t_ataque -= delta
		if _t_ataque <= 0.0:
			_ataque_activo = false
	if _emote_activo:
		_t_emote -= delta
		if _t_emote <= 0.0:
			_emote_activo = false
	if _en_modo_ataque:
		_t_modo_ataque -= delta
		if _t_modo_ataque <= 0.0:
			_en_modo_ataque = false
	match estado:
		Estado.NORMAL:
			if _ataque_activo:
				pass
			elif _emote_activo:
				pass
			elif not is_on_floor():
				_reproducir_anim(ANIM_SALTO, _blend_para(ANIM_SALTO))
			elif _salto_forzado:
				_salto_forzado = false
				_reproducir_anim(ANIM_SALTO, BLEND_SALTO)
			elif _bloqueo_anim > 0.0:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
			elif _en_ventana_atras:
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante"):
				_reproducir_anim(ANIM_ATRAS, _blend_para(ANIM_ATRAS))
			elif _direccion_entrada().length() > 0.05:
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif _en_modo_ataque:
				_reproducir_anim(ANIM_MODO_ATAQUE, BLEND_POST_ATAQUE)
			else:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
		Estado.DASH, Estado.CAIDA_DASH:
			_reproducir_anim(ANIM_DASH, _blend_para(ANIM_DASH))
		Estado.CARGA:
			_reproducir_anim(ANIM_CARGA, _blend_para(ANIM_CARGA))
		Estado.PREPARADO, Estado.EJECUCION:
			_reproducir_anim(ANIM_SUPERVELOCIDAD, _blend_para(ANIM_SUPERVELOCIDAD))

# ---------------- Pose procedural (velocista) ----------------
func _actualizar_pose(delta: float) -> void:
	var vel_h := Vector3(velocity.x, 0.0, velocity.z).length()
	var inclinacion := 0.0
	var altura := 0.0
	match estado:
		Estado.CARGA:
			inclinacion = -0.55
			altura = 0.0
		Estado.DASH, Estado.EJECUCION:
			inclinacion = -0.6
			altura = -0.05
		_:
			inclinacion = -clampf(vel_h / velocidad_max, 0.0, 1.0) * 0.18
	pose.rotation.x = lerp_angle(pose.rotation.x, inclinacion, 10.0 * delta)
	pose.position.y = lerpf(pose.position.y, altura, 10.0 * delta)

# ---------------- Orientación del modelo (velocista) ----------------
func _orientar(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, objetivo, 12.0 * delta)

func _orientar_instant(dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	visual.rotation.y = atan2(-dir.x, -dir.z)
