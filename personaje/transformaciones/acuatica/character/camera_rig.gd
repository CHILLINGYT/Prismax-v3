class_name PlayerCameraRig
extends Node3D
## =============================================================================
##  CAMARA EN TERCERA PERSONA (desacoplada del personaje)
## =============================================================================
##  Estructura:  CameraPivot (Node3D, este script)
##                 └── SpringArm3D   (aleja la camara y la acerca si hay
##                    │                paredes o suelo en medio)
##                    └── Camera3D
##
##  REPARTO DE RESPONSABILIDADES (esto es lo que evita que se mezclen):
##
##    RATON -> SOLO esta camara: yaw en este nodo, pitch en el SpringArm3D.
##    WASD  -> SOLO el jugador (Player.gd mueve el CharacterBody3D).
##
##  El pivote tiene top_level = true: NO hereda la rotacion del jugador, asi que
##  girar el personaje con A/D o W/S no gira la camara. Solo copia su POSICION,
##  y lo hace en _physics_process (el jugador ya se movio en ese mismo tick),
##  por lo que no hay retardo ni jitter.
##
##  La camara aporta la orientacion para calcular el movimiento relativo a la
##  camara (get_movement_direction), pero nunca mueve al personaje.
## =============================================================================

## Ruta al SpringArm3D. Si se deja vacia se busca entre los hijos.
@export var spring_arm_path: NodePath

@export_group("Seguimiento")
## Nodo al que sigue la camara. Si se deja vacio se usa el padre (el jugador).
@export var follow_target: Node3D
## Altura del pivote respecto al origen del personaje (metros).
@export var target_height := 1.45
## Suavizado horizontal (1/s). 0 = pegada al personaje, que da sensacion de
## "pegatina" (el personaje parece una imagen fija en el centro). Un valor bajo
## (12-20) hace que la camara siga con un pequeno retardo: es lo que da
## sensacion de peso y de que el personaje se mueve fisicamente.
@export var follow_smoothing := 18.0
## Suavizado vertical (1/s). Mas bajo que el horizontal: asi los saltos no
## arrastran la camara y el personaje sube en pantalla.
@export var vertical_smoothing := 6.0

@export_group("Ratón")
## Grados de giro por pixel de raton.
@export var sensitivity := 0.22
## Invierte el eje vertical.
@export var invert_y := false
## Limites del angulo vertical (grados). Positivo = camara por encima.
@export var pitch_min := -50.0
@export var pitch_max := 65.0
@export var start_yaw := 0.0
@export var start_pitch := 14.0
@export var capture_mouse_on_start := true

@export_group("Agua")
## Distancia del brazo FUERA y DENTRO del agua. Sumergido la camara se acerca:
## dentro del agua no se ve lejos y una camara alejada solo ve agua azul.
@export var air_spring_length := 3.6
@export var water_spring_length := 2.2
## Limites de pitch DENTRO del agua (grados). Se abre el abanico: desde el fondo
## hay que poder mirar hacia arriba, a la superficie.
@export var water_pitch_min := -75.0
@export var water_pitch_max := 80.0
## Rapidez (1/s) con la que la camara se adapta al entrar o salir del agua.
@export var water_blend_speed := 3.0

@export_group("Apuntado (modo F)")
## Cuánto se desplaza la cámara hacia el HOMBRO DERECHO (metros) al apuntar. El
## desplazamiento va sobre el eje X de la cámara, o sea PERPENDICULAR a la mirada:
## así la mira sigue centrada en pantalla y solo cambia el encuadre.
@export var aim_shoulder_offset := 0.8
## Cuánto sube la cámara al apuntar (metros).
@export var aim_height_offset := 0.12
## Distancia del brazo al apuntar. Se acerca algo para que se vea el agua que el
## personaje sostiene en la mano.
@export var aim_spring_length := 2.4
## Rapidez (1/s) de la transición a la cámara de apuntado. NO es instantánea a
## propósito: entrar y salir del modo F tiene que ser suave, sin tirón.
@export var aim_blend_speed := 3.0

var _spring_arm: SpringArm3D
var _pitch := 0.0
## 0 = camara en el aire, 1 = camara dentro del agua. Lo pone el jugador.
var _underwater := 0.0
var _water_target := 0.0
## El jugador está apuntando (modo F) y cuánto lleva mezclada ya la cámara de
## hombro (0 = encuadre normal, 1 = del todo en el hombro).
var _aiming := false
var _aim_blend := 0.0


func _ready() -> void:
	# NO heredar la transformacion del jugador: la camara es independiente.
	top_level = true
	if follow_target == null:
		follow_target = get_parent() as Node3D
	_spring_arm = get_node_or_null(spring_arm_path) as SpringArm3D
	if _spring_arm == null:
		_spring_arm = _find_child_of_type(self, "SpringArm3D") as SpringArm3D
	if _spring_arm == null:
		push_warning("PlayerCameraRig: no se encontro un SpringArm3D hijo de %s" % name)
	else:
		# El export manda: si la escena y el export no coinciden, gana el export.
		_spring_arm.spring_length = air_spring_length
	rotation.y = deg_to_rad(start_yaw)
	_pitch = start_pitch
	_apply_pitch()
	_snap_to_target()
	if capture_mouse_on_start:
		set_mouse_captured(true)


func _physics_process(delta: float) -> void:
	# El jugador ya movio su transform en este mismo tick de fisica, asi que
	# seguirle aqui no introduce retardo de un frame (el suavizado es a proposito).
	_update_water_blend(delta)
	_update_aim_blend(delta)
	_update_spring_length()
	if follow_target == null:
		return
	var target_position := follow_target.global_position + Vector3.UP * target_height
	# MODO F: la camara se va al HOMBRO DERECHO. El desplazamiento va sobre el eje
	# X de la camara (perpendicular a la mirada), asi que la mira sigue centrada en
	# pantalla y solo cambia el encuadre. Lo mezcla _aim_blend, asi que entrar y
	# salir de apuntar es progresivo.
	if _aim_blend > 0.0:
		var right := global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.001:
			target_position += right.normalized() * (aim_shoulder_offset * _aim_blend)
		target_position += Vector3.UP * (aim_height_offset * _aim_blend)
	if follow_smoothing <= 0.0 and vertical_smoothing <= 0.0:
		global_position = target_position
		return
	var current := global_position
	global_position = Vector3(
		_approach(current.x, target_position.x, follow_smoothing, delta),
		_approach(current.y, target_position.y, vertical_smoothing, delta),
		_approach(current.z, target_position.z, follow_smoothing, delta)
	)


## Adaptacion de la camara al agua. Es progresiva a proposito: entrar al agua no
## debe dar un tiron de camara, debe sentirse como que la camara se moja.
func _update_water_blend(delta: float) -> void:
	var target := clampf(_water_target, 0.0, 1.0)
	if is_equal_approx(_underwater, target):
		return
	_underwater = move_toward(_underwater, target, water_blend_speed * delta)


## Transicion (progresiva) a la camara de APUNTADO del modo F. Se mezcla con la
## misma idea que el agua: entrar o salir de apuntar no da un tiron de camara. El
## desplazamiento en si lo aplica _physics_process.
func _update_aim_blend(delta: float) -> void:
	var target := 1.0 if _aiming else 0.0
	if is_equal_approx(_aim_blend, target):
		return
	_aim_blend = move_toward(_aim_blend, target, aim_blend_speed * delta)


## Distancia del brazo: mezcla el agua y el apuntado (apuntando se acerca un poco,
## para que se vea bien el agua que el personaje sostiene en la mano).
func _update_spring_length() -> void:
	if _spring_arm == null:
		return
	var base := lerpf(air_spring_length, water_spring_length, _underwater)
	_spring_arm.spring_length = lerpf(base, aim_spring_length, _aim_blend)


## El jugador avisa de si esta apuntando (modo F).
func set_aiming(active: bool) -> void:
	_aiming = active


## Cuanto lleva la camara movida hacia el hombro (0 = normal, 1 = del todo).
func get_aim_blend() -> float:
	return _aim_blend


## El jugador avisa de cuanto esta la camara dentro del agua (0 = aire, 1 = dentro).
func set_underwater(amount: float) -> void:
	_water_target = clampf(amount, 0.0, 1.0)


## Cuanto lleva la camara metida en el agua (0..1). Ya suavizado.
func get_underwater() -> float:
	return _underwater


## Limites de pitch de ahora mismo, mezclando aire y agua: dentro del agua el
## abanico es mas amplio porque hay que poder mirar a la superficie.
func _pitch_limits() -> Vector2:
	return Vector2(
		lerpf(pitch_min, water_pitch_min, _underwater),
		lerpf(pitch_max, water_pitch_max, _underwater))


## Interpolacion exponencial independiente del framerate.
func _approach(from: float, to: float, rate: float, delta: float) -> float:
	if rate <= 0.0:
		return to
	return lerpf(from, to, 1.0 - exp(-rate * delta))


## Coloca la camara en su sitio sin suavizado (para el primer frame).
func _snap_to_target() -> void:
	if follow_target != null:
		global_position = follow_target.global_position + Vector3.UP * target_height


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Mover el raton a la derecha gira la camara; el personaje se orienta aparte.
		look_relative((event as InputEventMouseMotion).relative)
	elif event.is_action_pressed("ui_cancel"):
		# Escape libera el raton para poder salir de la ventana.
		set_mouse_captured(false)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		set_mouse_captured(true)


## Gira la vista con un desplazamiento de raton (pixeles). Esta separado del
## manejador de eventos a proposito: asi el sentido de los DOS ejes se puede
## comprobar con una prueba, que es como se encontro que el vertical iba al reves.
func look_relative(relative: Vector2) -> void:
	# Raton a la DERECHA -> la vista gira a la derecha.
	rotation.y -= deg_to_rad(relative.x * sensitivity)
	# Raton ARRIBA (relative.y negativo) -> la vista mira HACIA ARRIBA.
	# [!] OJO con el signo: "pitch positivo" es la camara POR ENCIMA del jugador,
	# o sea mirando hacia ABAJO. Subir la mirada es BAJAR el pitch. Restando este
	# termino el eje vertical quedaba invertido (raton arriba -> camara abajo).
	var vertical := relative.y * sensitivity
	if invert_y:
		vertical = -vertical
	var limits := _pitch_limits()
	_pitch = clampf(_pitch + vertical, limits.x, limits.y)
	_apply_pitch()


## Direccion de movimiento en el mundo (plano XZ) a partir del input.
## [param input_vector] viene de Input.get_vector(...) con .y = adelante.
func get_movement_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() < 0.000001:
		return Vector3.ZERO
	var cam_basis := global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	return (right * input_vector.x + forward * input_vector.y).normalized()


## Direccion a la que mira la camara (util para apuntar, rayos, etc.).
func get_look_direction() -> Vector3:
	var camera := get_camera()
	if camera == null:
		return -global_transform.basis.z
	return -camera.global_transform.basis.z


func get_camera() -> Camera3D:
	if _spring_arm != null:
		var camera := _find_child_of_type(_spring_arm, "Camera3D") as Camera3D
		if camera != null:
			return camera
	return _find_child_of_type(self, "Camera3D") as Camera3D


## Captura o libera el raton.
func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _apply_pitch() -> void:
	if _spring_arm == null:
		return
	# El SpringArm3D coloca la camara en su +Z local: con pitch positivo la
	# camara sube por encima del jugador.
	_spring_arm.rotation.x = deg_to_rad(-_pitch)


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.is_class(type_name):
			return child
	return null
