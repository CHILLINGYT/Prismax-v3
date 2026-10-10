extends CharacterBody3D

const WALK_SPEED = 3.0
const RUN_SPEED = 5.5
const CROUCH_SPEED = 2.5
const JUMP_VELOCITY = 4.5

# --- Animaciones ------------------------------------------------------------------------------
# Todas viven en "res://personaje/transformaciones/humano/animations/leo_animations.tres", la librería del
# AnimationPlayer "Animador". Ninguna animación lleva desplazamiento propio (no hay root
# motion): el movimiento de Leo lo decide SIEMPRE el código de más abajo.
const ANIM_IDLE = "idle"
const ANIM_WALK = "walk"
const ANIM_CROUCH_WALK = "crouch_walk"
const ANIM_T_POSE = "t_pose" # Pose fija de 1 fotograma: sirve de referencia, no se usa en partida.
const ANIM_JUMP_UP = "jump_up" # Salto vertical desde el sitio
const ANIM_RUNNING_JUMP = "running_jump" # Salto en carrera
# Las tres siguientes ya están en la librería ("Fast Run.fbx", "Walking Backwards.fbx" y
# "Macarena Dance.fbx"). Si algún día faltara alguna, el sistema usa el respaldo que se indica
# en vez de romperse.
const ANIM_FAST_RUN = "fast_run" # correr con SHIFT+W (respaldo: walk acelerado)
const ANIM_WALK_BACKWARDS = "walk_backwards" # andar hacia atrás con S (respaldo: walk)
# Pasos laterales (ya están en la librería: "walking izquierda.fbx" y "walking derecha.fbx").
# Se usan cuando el input es PURAMENTE lateral (A sola o D sola); con diagonales manda el clip
# frontal/trasero y el fundido cruzado se encarga de la transición.
const ANIM_WALK_LEFT = "walking_izquierda" # A: paso lateral hacia la izquierda (respaldo: walk)
const ANIM_WALK_RIGHT = "walking_derecha" # D: paso lateral hacia la derecha (respaldo: walk)
const ANIM_BAILE = "macarena_dance" # baile con R (sin respaldo: si faltara, R no haría nada)
# Opcional: no existe todavía. Si se añadiera, sustituiría a la pose congelada de crouch_walk.
const ANIM_CROUCH_IDLE = "crouch_idle" # agachado quieto (respaldo: pose congelada de crouch_walk)

# Estados de animación, de mayor a menor prioridad (el orden de calcular_estado() es la prioridad).
enum Estado { BAILE, SALTO, AGACHADO_MOVIENDO, AGACHADO_QUIETO, ATRAS, LATERAL_IZQUIERDA, LATERAL_DERECHA, CORRER, CAMINAR, IDLE }

# A partir de esta velocidad horizontal el salto cuenta como "en carrera" y usa running_jump
# (caminar = 3.0, correr = 5.5). Bajalo a 0.2 si preferís que cualquier salto en movimiento sea running_jump.
const VELOCIDAD_SALTO_CORRIENDO = 3.5
# Segundos de fundido cruzado entre animaciones: es lo que hace fluida la transición.
const MEZCLA_ANIMACIONES = 0.15
# Entrar y salir de agachado es un movimiento más largo: se le da algo más de fundido.
const MEZCLA_AGACHARSE = 0.25
# Por debajo de esta velocidad horizontal Leo se considera quieto.
const UMBRAL_MOVIMIENTO = 0.15
# Cuánto baja el pivote de la cámara al agacharse.
const ALTURA_AGACHADO = 0.7

var sens: float = .5
var current_speed: float = WALK_SPEED
var is_crouching: bool = false
var salto_en_aire: bool = false # Verdadero desde que despega hasta que vuelve a tocar el suelo
var animacion_salto: String = ANIM_JUMP_UP # Clip elegido en el momento de despegar
var retrocediendo: bool = false # El input actual empuja hacia atrás (S): usa walk_backwards
var lateral: int = 0 # -1 = paso lateral izquierda (A), +1 = derecha (D), 0 = sin lateral puro
var bailando: bool = false # Baile de Macarena en curso: Leo queda clavado en el sitio
var espera_congelar: float = 0.0 # Segundos que faltan para congelar la pose de agachado quieto

@onready var cam: CamaraTerceraPersona = $pivote # Pivote de la cámara (gestiona él solo su rotación)
@onready var original_cam_y: float = cam.position.y # Guarda la altura inicial del pivote de la cámara
@onready var animador: AnimationPlayer = $Animador

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# El baile dura una sola pasada: cuando su clip acaba, esta señal devuelve a Leo a su estado
	# normal aunque llegue a perderse el momento exacto en que el reproductor se detiene.
	animador.animation_finished.connect(_al_terminar_animacion)
	# Animación inicial para comprobar que el modelo de Mixamo funciona.
	cambiar_animacion(ANIM_IDLE)

# Se dispara al acabar cualquier clip que no esté en bucle. Solo interesa el del baile.
func _al_terminar_animacion(nombre: StringName) -> void:
	if nombre == ANIM_BAILE:
		bailando = false

func _physics_process(delta: float) -> void:
	# Al tocar suelo se acaba el salto (se comprueba antes de mover para no cancelarlo
	# en el mismo fotograma en que despega): la animación vuelve a caminar/correr.
	if salto_en_aire and is_on_floor():
		salto_en_aire = false
	# El baile es de una sola pasada: cuando su clip acaba, Leo vuelve solo a su estado normal
	# (idle o el movimiento que estuviera pidiendo el jugador). Se comprueba ANTES de elegir
	# animación, para que el clip terminado no se reinicie.
	# Red de seguridad: si por lo que sea la señal no llegara, aquí también se cierra el baile
	# en cuanto su clip deja de sonar. (No sirve comprobar current_animation: al terminar un clip
	# que no está en bucle, Godot puede dejar de devolver su nombre y entonces reproducir() volvería
	# a arrancar el baile desde el principio, en bucle infinito.)
	if bailando and not animador.is_playing():
		bailando = false
	manejar_estados(delta) # Verifica si estás corriendo o agachado
	if bailando:
		estado_baile(delta)
	else:
		movimiento(delta)
	move_and_slide()
	actualizar_animaciones(delta) # Elige la animación según el estado (ver calcular_estado())

func _input(event: InputEvent) -> void:
	# El ratón gira a Leo SOLO cuando no se está orbitando la cámara. Mientras se
	# mantiene el clic derecho, el ratón mueve únicamente la vista (lo lleva
	# CamaraTerceraPersona) y el personaje se queda quieto y mirando igual.
	if event is InputEventMouseMotion and not cam.orbitando:
		rotate_y(deg_to_rad(-event.relative.x * sens))
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		alternar_baile()

# --- Correr, agacharse y altura de la cámara ---------------------------------------------------
func manejar_estados(delta: float) -> void:
	if Input.is_key_pressed(KEY_CTRL) and not bailando:
		is_crouching = true
		current_speed = CROUCH_SPEED
		# Baja la cámara suavemente (ajusta ALTURA_AGACHADO según el tamaño de tu personaje)
		cam.position.y = lerp(cam.position.y, original_cam_y - ALTURA_AGACHADO, 8 * delta)
	else:
		is_crouching = false
		# Devuelve la cámara a su altura original suavemente
		cam.position.y = lerp(cam.position.y, original_cam_y, 8 * delta)

		# Solo puedes correr si no estás agachado
		if Input.is_key_pressed(KEY_SHIFT):
			current_speed = RUN_SPEED
		else:
			current_speed = WALK_SPEED

# --- Movimiento --------------------------------------------------------------------------------
func movimiento(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Salto con ESPACIO (se evita que salte si está agachado)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY
		iniciar_salto() # Elige y arranca el clip: jump_up o running_jump

	# Movimiento WASD
	var input_dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1

	input_dir = input_dir.normalized()

	# S empuja hacia atrás respecto a donde mira Leo (su "adelante" es -Z): eso elige walk_backwards.
	# Si se pulsan W y S a la vez el vector queda a cero y Leo se queda quieto, sin estados raros.
	retrocediendo = input_dir.y > 0.05

	# Movimiento PURAMENTE lateral (A sola o D sola): usa su propio clip de paso lateral.
	# Si hay componente adelante/atrás (diagonales W+A, W+D, S+A, S+D...) manda el clip frontal o
	# trasero y el lateral se resuelve con el fundido cruzado del sistema, sin inventar clips
	# diagonales. Si se pulsan A y D a la vez, input_dir.x queda a 0 y no hay estado lateral
	# contradictorio (Leo simplemente se queda quieto en ese eje).
	if is_zero_approx(input_dir.y) and not is_zero_approx(input_dir.x):
		lateral = -1 if input_dir.x < 0.0 else 1
	else:
		lateral = 0

	# Convertir el movimiento 2D a movimiento 3D respetando hacia dónde mira el personaje
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		# Sin input NO hay desplazamiento residual: la posición la manda solo el input. Ninguna
		# animación lleva desplazamiento dentro (no hay root motion), así que nada puede empujar
		# a Leo después de soltar la tecla.
		velocity.x = 0.0
		velocity.z = 0.0

# El baile deja a Leo clavado en el sitio mientras dure su clip: se anulan las velocidades
# horizontales, así W/A/S/D no lo desplazan, y solo actúa la gravedad por si el suelo desaparece.
# Para salir del baile antes de tiempo se vuelve a pulsar R (ver alternar_baile()).
func estado_baile(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = 0.0
	velocity.z = 0.0

# R enciende o apaga el baile. Al ser una alternancia, pulsar R varias veces no acumula
# reproducciones ni estados superpuestos. Solo arranca en el suelo y sin estar agachado.
func alternar_baile() -> void:
	if not animador.has_animation(ANIM_BAILE):
		return
	if not bailando and (not is_on_floor() or is_crouching):
		return
	bailando = not bailando
	if bailando:
		velocity.x = 0.0
		velocity.z = 0.0

# Arranca un salto. Se elige el clip en el instante de despegar (running_jump si venía
# corriendo, jump_up si salta desde el sitio o andando) y se reproduce desde el principio.
# Durante el vuelo no se vuelve a tocar: así el clip no se reinicia si se queda corto.
func iniciar_salto() -> void:
	salto_en_aire = true
	var rapidez: float = Vector2(velocity.x, velocity.z).length()
	animacion_salto = ANIM_RUNNING_JUMP if rapidez > VELOCIDAD_SALTO_CORRIENDO else ANIM_JUMP_UP
	if animador.has_animation(animacion_salto):
		animador.speed_scale = ritmo_salto()
		animador.play(animacion_salto, MEZCLA_ANIMACIONES)

# Duración real del salto (subida + bajada) según la física que usa movimiento().
func tiempo_de_vuelo() -> float:
	var gravedad: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return 2.0 * JUMP_VELOCITY / gravedad

# Ritmo al que hay que reproducir el clip de salto para que su propio descenso coincida con
# el descenso real (los dos clips duran ~0.85-0.90 s y el salto real dura ~0.92 s). Se limita
# para que el salto no se vuelva nervioso ni se arrastre.
func ritmo_salto() -> float:
	var clip: Animation = animador.get_animation(animacion_salto)
	if clip == null or clip.length <= 0.0:
		return 1.0
	return clampf(clip.length / tiempo_de_vuelo(), 0.75, 1.6)

# En el aire manda el clip del salto, que cubre la subida y también la bajada (no hay clip de
# caída). No se reinicia si se quedó corto: una caída larga no repite el despegue.
func animar_salto() -> void:
	if animador.current_animation != animacion_salto:
		animador.speed_scale = 1.0
		animador.play(animacion_salto, MEZCLA_ANIMACIONES)
	animador.speed_scale = ritmo_salto()

# --- Selección de animación --------------------------------------------------------------------
# Reproduce una animación solo si no está sonando ya, para no reiniciarla en cada fotograma.
# "mezcla" son los segundos de fundido cruzado con la animación anterior (0 = corte seco).
func cambiar_animacion(nombre: String, mezcla: float = MEZCLA_ANIMACIONES) -> void:
	if not animador.has_animation(nombre):
		return
	if animador.current_animation != nombre or not animador.is_playing():
		animador.play(nombre, mezcla)

# Devuelve el primer clip de la lista que exista de verdad en la librería. Así el sistema ya
# tiene preparado cada estado aunque su animación todavía no se haya añadido.
func elegir_clip(opciones: Array) -> String:
	for opcion in opciones:
		if animador.has_animation(opcion):
			return opcion
	return ANIM_IDLE

# Estado que manda ahora mismo. El orden de los "if" ES la prioridad de los estados:
# baile > salto > agachado > lateral > andar atrás > correr > caminar > quieto.
func calcular_estado(se_mueve: bool) -> int:
	if bailando and animador.has_animation(ANIM_BAILE):
		return Estado.BAILE
	if salto_en_aire:
		return Estado.SALTO
	if is_crouching:
		return Estado.AGACHADO_MOVIENDO if se_mueve else Estado.AGACHADO_QUIETO
	if not se_mueve:
		return Estado.IDLE
	if lateral < 0:
		return Estado.LATERAL_IZQUIERDA
	if lateral > 0:
		return Estado.LATERAL_DERECHA
	if retrocediendo:
		return Estado.ATRAS
	if current_speed >= RUN_SPEED - 0.01:
		return Estado.CORRER
	return Estado.CAMINAR

# Reproduce un clip ajustando el ritmo del ciclo a la velocidad real (ritmo = velocidad
# horizontal / velocidad de referencia) para que los pies no patinen. Con ritmo 0.0 la animación
# se queda congelada donde está (así se sostiene la pose de agachado quieto).
func reproducir(nombre: String, ritmo: float = 1.0, mezcla: float = MEZCLA_ANIMACIONES) -> void:
	if not animador.has_animation(nombre):
		return
	# 0.0 = congelado; cualquier otro valor se limita para que el ciclo no se vuelva nervioso.
	var escala: float = 0.0 if ritmo <= 0.0 else clampf(ritmo, 0.4, 1.8)
	if animador.current_animation != nombre or not animador.is_playing():
		animador.speed_scale = 1.0
		animador.play(nombre, mezcla)
	animador.speed_scale = escala

# Agachado y quieto. Si algún día se añade un clip propio (crouch_idle) se reproduce tal cual.
# Mientras no lo haya se usa el ciclo de crouch_walk: primero se deja que el fundido de entrada
# meta la pose (con el ciclo andando) y, en cuanto el fundido termina, se congela el ciclo donde
# esté. Congelarlo YA no sirve: Godot divide el tiempo de fundido por speed_scale, así que con
# speed_scale 0 el fundido nunca llega a aplicarse y el personaje se quedaría como estaba.
func animar_agachado_quieto(delta: float) -> void:
	if animador.has_animation(ANIM_CROUCH_IDLE):
		reproducir(ANIM_CROUCH_IDLE, 1.0, MEZCLA_AGACHARSE)
		return
	if animador.current_animation != ANIM_CROUCH_WALK or not animador.is_playing():
		reproducir(ANIM_CROUCH_WALK, 1.0, MEZCLA_AGACHARSE)
		espera_congelar = MEZCLA_AGACHARSE
		return
	if espera_congelar > 0.0:
		espera_congelar -= delta
		return
	reproducir(ANIM_CROUCH_WALK, 0.0)

# Elige la animación según el estado actual de Leo. Una sola función decide, en este orden.
func actualizar_animaciones(delta: float) -> void:
	var velocidad_horizontal: float = Vector2(velocity.x, velocity.z).length()
	var clip: String = ANIM_IDLE
	var ritmo: float = 1.0
	var mezcla: float = MEZCLA_ANIMACIONES

	match calcular_estado(velocidad_horizontal > UMBRAL_MOVIMIENTO):
		Estado.SALTO:
			animar_salto()
			return
		Estado.AGACHADO_QUIETO:
			animar_agachado_quieto(delta)
			return
		Estado.BAILE:
			clip = ANIM_BAILE # el baile se reproduce a ritmo normal: Leo no se desplaza
		Estado.AGACHADO_MOVIENDO:
			clip = ANIM_CROUCH_WALK
			ritmo = velocidad_horizontal / CROUCH_SPEED
			mezcla = MEZCLA_AGACHARSE
		Estado.ATRAS:
			clip = elegir_clip([ANIM_WALK_BACKWARDS, ANIM_WALK])
			ritmo = velocidad_horizontal / WALK_SPEED
		Estado.LATERAL_IZQUIERDA:
			clip = elegir_clip([ANIM_WALK_LEFT, ANIM_WALK])
			ritmo = velocidad_horizontal / WALK_SPEED
		Estado.LATERAL_DERECHA:
			clip = elegir_clip([ANIM_WALK_RIGHT, ANIM_WALK])
			ritmo = velocidad_horizontal / WALK_SPEED
		Estado.CORRER:
			clip = elegir_clip([ANIM_FAST_RUN, ANIM_WALK])
			# Con el clip propio de correr el ritmo se mide contra RUN_SPEED; si no existe y
			# se acelera el de caminar, contra WALK_SPEED (como se hacía antes).
			ritmo = velocidad_horizontal / (RUN_SPEED if clip == ANIM_FAST_RUN else WALK_SPEED)
		Estado.CAMINAR:
			clip = ANIM_WALK
			ritmo = velocidad_horizontal / WALK_SPEED
	reproducir(clip, ritmo, mezcla)
