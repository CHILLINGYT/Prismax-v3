class_name JugadorZiba
extends CharacterBody3D

# Prototipo de supervelocidad (Ziva). Todo independiente de otros sistemas del proyecto.
# Estados:
#   NORMAL      -> movimiento con aceleracion, salto y combate.
#   DASH        -> desplazamiento rapido de ~10 m en la direccion WASD.
#   CAIDA_DASH  -> en el aire: desciende rapido y al tocar suelo ejecuta el dash.
#   CARGA       -> click derecho: postura de carga, dibuja la ruta con el mouse.
#   EJECUCION   -> recorre toda la trayectoria dibujada a supervelocidad.
# Las animaciones ya importadas del AnimationPlayer del modelo se conectan con
# esos estados (seccion "Animaciones"): no se crean ni se reemplazan clips.

enum Estado { NORMAL, DASH, CAIDA_DASH, CARGA, PREPARADO, EJECUCION }

# --- Animaciones existentes (librerias del AnimationPlayer del modelo) ---
# Cada libreria contiene un unico clip ('mixamo_com'), asi que se reproduce con
# el nombre completo "libreria/clip". Los nombres de las librerias no cambian.
const ANIM_INACTIVO := "inactivo"
const ANIM_ADELANTE := "caminar_hacia_adelante"
const ANIM_ATRAS := "caminar_hacia_atras"
const ANIM_CARGA := "cargar_poder_click-derecho"
const ANIM_DASH := "dash-con-shift"
const ANIM_SALTO := "jumping up(1)"
const ANIM_SUPERVELOCIDAD := "superduper_velocidad"
const ANIM_INACTIVO_VELOCIDAD := "inactivo_despues-despues-de-30s-velocidad" # reservada
# Animaciones de combate y emote. Los nombres de libreria ya existen en el
# AnimationPlayer del modelo (los anade ziba_prototipo.tscn): no se crean clips.
const ANIM_COMBO_1 := "combo-1"
const ANIM_COMBO_2 := "combo-2"
const ANIM_COMBO_3 := "combo-3"
const ANIM_COMBO_4 := "combo-4"
const ANIM_MODO_ATAQUE := "inactivo_modo_ataque" # reposo tras combatir (temporal)
const ANIM_EMOTE := "calentamiento_ataque"       # emote independiente del combate

# Tiempos de blending: cortos y responsivos; nunca retrasan la accion.
const BLEND_MARCHA := 0.25          # inactivo -> caminar
const BLEND_MARCHA_FIN := 0.30      # caminar -> inactivo (desaceleracion natural)
const BLEND_CAMBIO_MARCHA := 0.18   # caminar adelante <-> caminar atras
const BLEND_SALTO := 0.10           # -> saltar
const BLEND_POST_SALTO := 0.15      # aterrizaje -> caminar/inactivo
const BLEND_DASH := 0.06            # -> dash (respuesta inmediata del SHIFT)
const BLEND_POST_DASH := 0.12       # dash -> caminar/inactivo
const BLEND_CARGA := 0.10           # -> cargar poder (click derecho)
const BLEND_LIBERACION := 0.08      # carga -> supervelocidad (salida explosiva)
const BLEND_FIN_VELOCIDAD := 0.22   # supervelocidad -> inactivo
const BLOQUEO_FIN_VELOCIDAD := 0.12 # instante en inactivo al completar la ruta
const BLEND_ATAQUE := 0.08          # -> combo (respuesta inmediata del click)
const BLEND_POST_ATAQUE := 0.16     # combo -> inactivo_modo_ataque
const BLEND_EMOTE := 0.12           # -> emote (tecla 2)

# Tiempo que se mantiene "inactivo_modo_ataque" tras terminar la actividad de combate.
const TIEMPO_MODO_ATAQUE := 10.0

# Movilidad durante el ataque: se reduce la velocidad, pero no se bloquea.
const FACTOR_MOVILIDAD_ATAQUE := 0.35 # fraccion de la velocidad normal mientras ataca
# Pequeno avance fisico por golpe, en la direccion a la que mira el personaje.
const IMPULSO_AVANCE := 4.5

@export_group("Movimiento")
@export var velocidad_max: float = 7.0
@export var aceleracion: float = 45.0
@export var desaceleracion: float = 55.0
@export var gravedad: float = 24.0
@export var fuerza_salto: float = 7.5

@export_group("Dash")
# Distancia nominal del Dash: fija la VELOCIDAD (distancia_dash / duracion_dash).
@export var distancia_dash: float = 10.0
@export var duracion_dash: float = 0.09
# Punto interno de finalizacion (donde el Dash considera alcanzado el objetivo).
# Es ligeramente menor que distancia_dash para compensar el pequeno excedente
# del desplazamiento por frames: objetivo ~9 m -> recorrido real ~10 m.
@export var distancia_objetivo_dash: float = 9.0

@export_group("Poder supervelocidad")
@export var vel_trayecto_max: float = 60.0
@export var vel_trayecto_min: float = 34.0

var estado: int = Estado.NORMAL

@onready var visual: Node3D = $Visual
@onready var pose: Node3D = $Visual/Pose
@onready var pivote: CamaraZiba = $PivoteCamara
@onready var trazador: TrazadorRuta = $Trazador
@onready var efectos: EfectosVelocidad = $Efectos
@onready var combate: SistemaCombate = $Combate

var _dir_dash: Vector3 = Vector3.ZERO
var _pos_dash_inicio: Vector3 = Vector3.ZERO
var _objetivo_dash: Vector3 = Vector3.ZERO
var _t_dash: float = 0.0
var _t_carga: float = 0.0
var _t_preparado: float = 0.0
var _puntos: Array[Vector3] = []
var _idx: int = 0
var _vel_trayecto: float = 0.0
# Logica de continuacion hacia atras (S+A / S+D): ventana de 0.5 s.
const VENTANA_CONTINUACION := 0.5
var _hubo_combo_atras: bool = false
var _en_ventana_atras: bool = false
var _t_ventana: float = 0.0
var _dir_orient_ventana: Vector3 = Vector3.ZERO
var _ultimo_dir_movimiento: Vector3 = Vector3.ZERO
var _anim: AnimationPlayer = null
var _anim_nombres: Dictionary = {}
var _anim_actual: String = ""
var _bloqueo_anim: float = 0.0
# Capa de combate/emote: no toca la logica de movimiento ni la de combate, solo
# decide que animacion manda mientras dura un golpe, el reposo de combate o el emote.
var _ataque_activo: bool = false
var _t_ataque: float = 0.0
var _emote_activo: bool = false
var _t_emote: float = 0.0
var _en_modo_ataque: bool = false
var _t_modo_ataque: float = 0.0
# El salto tiene prioridad sobre el ataque: al cancelar con ESPACIO se marca
# este flag para reproducir "jumping up(1)" de inmediato incluso en el frame en
# que aun se esta sobre el suelo. No altera la fisica del salto.
var _salto_forzado: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_configurar_animaciones()
	# El sistema de combate sigue siendo el que decide golpe y numero de combo;
	# aqui solo se reproduce la animacion correspondiente a ese resultado.
	combate.golpe_realizado.connect(_on_golpe_realizado)
	_reproducir_anim(ANIM_INACTIVO, 0.0)

func estado_actual() -> int:
	return estado

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
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

# ---------------- Movimiento normal ----------------
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

func _procesar_normal(delta: float) -> void:
	var dir := _direccion_entrada()
	_actualizar_logica_atras(delta, dir)

	# Durante el ataque la movilidad se reduce (no se bloquea): el personaje
	# puede seguir avanzando, pero mas lento. Fuera del ataque, velocidad normal.
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
		# El salto tiene prioridad: si hay un ataque en curso, se cancela al
		# instante y arranca el salto. La fisica del salto no cambia.
		if _ataque_activo:
			_cancelar_ataque_por_salto()
		velocity.y = fuerza_salto

	move_and_slide()

	# Orientacion del modelo. Con S (retroceso) el cuerpo mira al lado contrario
	# del desplazamiento para que caminar_hacia_atras se lea como backpedal
	# natural. En la ventana de continuacion (tras soltar A/D manteniendo S) se
	# mantiene la orientacion contraria al movimiento combinado anterior.
	if _en_ventana_atras:
		_orientar(delta, _dir_orient_ventana)
	else:
		var retrocede := Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante")
		_orientar(delta, -dir if retrocede else dir)

	# El ataque solo puede iniciarse apoyado en el suelo: en el aire no comienza
	# ningun combo ni avanza el contador. El salto y el control aereo no cambian.
	if is_on_floor() and Input.is_action_just_pressed("atacar"):
		combate.intentar_golpe()
	if Input.is_action_just_pressed("emote"):
		_intentar_emote()
	if Input.is_action_just_pressed("dash"):
		_intentar_dash()
	if Input.is_action_just_pressed("cargar_poder"):
		_iniciar_carga()

# ---------------- Combate y emote (solo capa de animacion) ----------------
# El indice de combo lo calcula el sistema de combate existente; aqui se traduce
# 1:1 a la animacion combo-N. No se altera el contador ni la logica de golpes.
func _on_golpe_realizado(indice: int) -> void:
	_en_modo_ataque = true
	_t_modo_ataque = TIEMPO_MODO_ATAQUE
	# Un golpe cancela un emote en curso: el ataque manda.
	_emote_activo = false
	_t_emote = 0.0
	_ataque_activo = true
	var clave := _clave_combo(indice)
	_t_ataque = _duracion_anim(clave)
	# forced: cada click debe reiniciar el clip aunque repita el mismo combo.
	_reproducir_anim(clave, BLEND_ATAQUE, true)
	# Rayos electricos que acompanan el golpe: solo efecto visual. La cantidad e
	# intensidad crecen con el indice del combo (1..4). No tocan la animacion.
	efectos.golpe_ataque(indice)
	# Pequeno avance fisico del golpe, en la direccion a la que mira el
	# personaje. Se integra como velocidad (respeta colisiones via move_and_slide)
	# y decae solo; nunca mueve la posicion de forma directa ni el modelo visual.
	var adelante := -visual.global_transform.basis.z
	adelante.y = 0.0
	if adelante.length() > 0.001:
		adelante = adelante.normalized()
		var horiz := Vector3(velocity.x, 0.0, velocity.z) + adelante * IMPULSO_AVANCE
		# Nunca superar la velocidad normal: el avance es un empujon corto, no un sprint.
		if horiz.length() > velocidad_max:
			horiz = horiz.normalized() * velocidad_max
		velocity.x = horiz.x
		velocity.z = horiz.z

# Cancela el ataque activo para dar paso al salto (ESPACIO). Solo capa de
# animacion y efectos: no toca hitboxes, daño, velocidad ni la fisica del salto.
func _cancelar_ataque_por_salto() -> void:
	_ataque_activo = false
	_t_ataque = 0.0
	_salto_forzado = true
	# Corta la generacion de rayos del golpe (los ya emitidos se desvanecen solos).
	efectos.cancelar_ataque()
	# La secuencia de combo se cancela: no continua al siguiente golpe.
	combate.cancelar_combo()
	# El salto arranca de inmediato reutilizando el blending existente.
	_reproducir_anim(ANIM_SALTO, BLEND_SALTO, true)

func _intentar_emote() -> void:
	# No interrumpe un ataque en curso (prioridad consistente con el ataque).
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

# Logica S + A / S + D y ventana de 0.5 s:
# - S sola, S+A o S+D  -> caminar_hacia_atras inmediato.
# - Al soltar A o D manteniendo S: durante VENTANA_CONTINUACION se considera
#   continuacion del movimiento anterior (caminar_hacia_adelante orientado hacia
#   el lado contrario del movimiento combinado).
# - Pasados los 0.5 s, o al re-pulsar A/D -> caminar_hacia_atras.
# El temporizador solo arranca cuando se suelta A/D tras haber estado combinada
# con S; nunca cuando S se pulso sola desde el principio.
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
	# Alinear el cuerpo con la direccion horizontal del Dash ANTES de moverse:
	# nunca se ejecuta el Dash conservando una orientacion lateral previa.
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
	print("[Ziba] dash recorrido: ", snappedf((global_position - _pos_dash_inicio).length(), 0.01), " m")
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
	# Alinear al personaje con la direccion horizontal de la camara antes de
	# adoptar la postura de carga. Solo yaw: se ignora el pitch vertical, asi
	# que el personaje nunca mira al suelo aunque la camara este inclinada.
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
	# Breve instante de carga final antes de salir disparado.
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

# ---------------- Ejecucion de la trayectoria ----------------
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

	# 1) Vertical: gravedad / suelo. No altera la trayectoria horizontal.
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()

	# 2) Desplazamiento horizontal con barrido (move_and_collide) usando el
	#    volumen real del jugador: detecta muros a alta velocidad y coloca el
	#    cuerpo justo en el punto de contacto, fuera de la geometria. La
	#    superficie solida tiene prioridad: si bloquea la trayectoria se detiene
	#    (sin esquivar, sin rodear, sin pathfinding, sin tocar la trayectoria).
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
	# Al completar (o quedar bloqueado) el recorrido se pasa a inactivo: se
	# mantiene un instante para que se vea el aterrizaje y luego manda la entrada.
	_bloqueo_anim = BLOQUEO_FIN_VELOCIDAD
	_reproducir_anim(ANIM_INACTIVO, BLEND_FIN_VELOCIDAD)

# ---------------- Animaciones ----------------
func _configurar_animaciones() -> void:
	_anim = get_node_or_null("Visual/Pose/Volteo/Modelo/AnimationPlayer") as AnimationPlayer
	if _anim == null:
		push_warning("[Ziba] Sin AnimationPlayer en el modelo: el jugador se movera sin animaciones.")
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
	# Los clips llegan importados sin bucle: se ajusta el bucle que necesita cada
	# estado (el clip en si no se modifica ni se reemplaza). La carga usa
	# ping-pong: inicio -> final -> inicio sin salto visual al mantener pulsado.
	match clave:
		# El reposo de combate se mantiene hasta 10 s: debe repetirse en bucle.
		ANIM_INACTIVO, ANIM_ADELANTE, ANIM_ATRAS, ANIM_SUPERVELOCIDAD, ANIM_MODO_ATAQUE:
			anim.loop_mode = Animation.LOOP_LINEAR
		ANIM_CARGA:
			anim.loop_mode = Animation.LOOP_PINGPONG
		# Ataques y emote son acciones de una sola vez.
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
	# Transiciones cortas: la accion responde al instante; el blending solo suaviza.
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
	# Temporizadores de la capa de combate/emote (no afectan movimiento).
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
				# El clip del combo se esta reproduciendo: se deja terminar.
				pass
			elif _emote_activo:
				# El emote se esta reproduciendo: se deja terminar.
				pass
			elif not is_on_floor():
				# El salto manda en el aire; al tocar suelo se reevalua la marcha.
				_reproducir_anim(ANIM_SALTO, _blend_para(ANIM_SALTO))
			elif _salto_forzado:
				# Ataque cancelado por salto: en el mismo frame aun en el suelo,
				# se reproduce el salto para que la transicion sea inmediata y
				# limpia (sin un frame de reposo intermedio).
				_salto_forzado = false
				_reproducir_anim(ANIM_SALTO, BLEND_SALTO)
			elif _bloqueo_anim > 0.0:
				# Recien terminada la supervelocidad: aterriza en inactivo.
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
			elif _en_ventana_atras:
				# Continuacion tras soltar A/D manteniendo S: marcha adelante
				# con el cuerpo orientado en sentido contrario al movimiento
				# combinado anterior (ver _procesar_normal).
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante"):
				_reproducir_anim(ANIM_ATRAS, _blend_para(ANIM_ATRAS))
			elif _direccion_entrada().length() > 0.05:
				# W avanza; A/D reutilizan la marcha hacia adelante y el giro de
				# _orientar hace que el cuerpo acompanie la direccion lateral.
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif _en_modo_ataque:
				# Quieto tras combatir: reposo de combate temporal (10 s).
				_reproducir_anim(ANIM_MODO_ATAQUE, BLEND_POST_ATAQUE)
			else:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
		Estado.DASH, Estado.CAIDA_DASH:
			_reproducir_anim(ANIM_DASH, _blend_para(ANIM_DASH))
		Estado.CARGA:
			_reproducir_anim(ANIM_CARGA, _blend_para(ANIM_CARGA))
		Estado.PREPARADO, Estado.EJECUCION:
			# La supervelocidad se mantiene durante todo el recorrido.
			_reproducir_anim(ANIM_SUPERVELOCIDAD, _blend_para(ANIM_SUPERVELOCIDAD))

# ---------------- Posicionamiento y pose procedural ----------------
func _actualizar_pose(delta: float) -> void:
	var vel_h := Vector3(velocity.x, 0.0, velocity.z).length()
	var inclinacion := 0.0
	var altura := 0.0
	match estado:
		Estado.CARGA:
			# La postura de carga la aporta la propia animacion "cargar poder"
			# (agachado): ya baja la cadera manteniendo los pies plantados en el
			# suelo. No se aplica ningun descenso vertical aqui. El antiguo
			# altura = -0.22 bajaba todo el modelo y hundia al personaje bajo el
			# suelo. Se conserva unicamente la inclinacion de la postura.
			inclinacion = -0.55
			altura = 0.0
		Estado.DASH, Estado.EJECUCION:
			inclinacion = -0.6
			altura = -0.05
		_:
			inclinacion = -clampf(vel_h / velocidad_max, 0.0, 1.0) * 0.18
	pose.rotation.x = lerp_angle(pose.rotation.x, inclinacion, 10.0 * delta)
	pose.position.y = lerpf(pose.position.y, altura, 10.0 * delta)

# ---------------- Orientacion del modelo ----------------
func _orientar(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, objetivo, 12.0 * delta)

func _orientar_instant(dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	visual.rotation.y = atan2(-dir.x, -dir.z)
