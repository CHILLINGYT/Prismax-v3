extends Node3D
class_name CamaraTerceraPersona

## Cámara en tercera persona que orbita alrededor del personaje.
##
## Jerarquía que necesita (los nombres dan igual, el orden de los nodos no):
##
##     Personaje (CharacterBody3D)
##     └── Pivote          <- ESTE script. Gira en Y (orbitar) y en X (arriba/abajo).
##         └── SpringArm3D <- su spring_length es la distancia a la que se pone la cámara.
##             └── Camera3D <- en el origen (0, 0, 0): el SpringArm la empuja hacia atrás.
##
## Comportamiento:
## · Clic derecho mantenido + ratón -> la cámara orbita alrededor del personaje
##   (se le puede ver de frente, de espaldas y de perfil) sin moverlo ni girarlo.
## · Al soltar el clic derecho -> la cámara vuelve suavemente a su sitio, detrás del personaje.
##
## Este script solo escribe la ROTACIÓN del pivote. Nunca toca la posición ni el
## cuerpo del personaje, así que el movimiento, el salto y las colisiones siguen igual.

# ---------------------------------------------------------------- Ajustes (Inspector)
## Grados de giro por píxel de ratón (el mismo valor que usa leo.gd).
@export_range(0.05, 2.0, 0.05) var sensibilidad: float = 0.5
## Límite por arriba: la cámara sube y mira hacia abajo (grados negativos).
@export_range(-89.0, 0.0, 1.0) var pitch_min: float = -75.0
## Límite por abajo: la cámara baja y mira hacia arriba (grados positivos).
@export_range(0.0, 89.0, 1.0) var pitch_max: float = 30.0
## Suavizado mientras se orbita. Más alto = sigue al ratón más de cerca.
@export_range(1.0, 40.0, 0.5) var velocidad_giro: float = 20.0
## Suavizado al volver a la posición original. Más bajo = vuelta más pausada.
@export_range(0.5, 20.0, 0.5) var velocidad_retorno: float = 6.0
## Ángulo de reposo (0 = a la altura del pivote, mirando de frente al personaje).
@export_range(-45.0, 45.0, 1.0) var pitch_reposo: float = 0.0
## Botón que activa la órbita.
@export var boton_orbita: MouseButton = MOUSE_BUTTON_RIGHT
## Si está activo, el SpringArm3D acorta la distancia para no atravesar paredes o suelo.
@export var evitar_paredes: bool = true
## Opcional: nodo del personaje. Si se deja vacío se busca subiendo por la jerarquía.
@export var objetivo: Node3D

# ---------------------------------------------------------------- Estado
## True mientras se mantiene pulsado el botón de órbita.
var orbitando: bool = false

var _yaw_objetivo: float = 0.0
var _pitch_objetivo: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _brazo: SpringArm3D = null

func _ready() -> void:
	_brazo = _buscar_brazo()
	_pitch_objetivo = deg_to_rad(pitch_reposo)
	_pitch = _pitch_objetivo
	_yaw = 0.0
	rotation = Vector3(_pitch, _yaw, 0.0)

	if _brazo == null:
		push_warning("CamaraTerceraPersona: no encuentro ningún SpringArm3D hijo, así que la cámara no mantendrá una distancia fija.")
		return

	if evitar_paredes:
		var cuerpo: CollisionObject3D = _buscar_cuerpo()
		if cuerpo != null:
			# Sin esto el brazo chocaría con el propio personaje y la cámara se le pegaría encima.
			_brazo.add_excluded_object(cuerpo.get_rid())
	else:
		# Distancia siempre exacta (la cámara puede atravesar muros).
		_brazo.collision_mask = 0

func _unhandled_input(evento: InputEvent) -> void:
	# El botón se atiende en el mismo evento para que el cambio sea inmediato.
	if evento is InputEventMouseButton and evento.button_index == boton_orbita:
		_poner_orbita(evento.pressed)
		return

	if evento is InputEventMouseMotion and orbitando:
		_yaw_objetivo += deg_to_rad(-evento.relative.x * sensibilidad)
		_pitch_objetivo = clampf(
			_pitch_objetivo + deg_to_rad(-evento.relative.y * sensibilidad),
			deg_to_rad(pitch_min),
			deg_to_rad(pitch_max)
		)

func _process(delta: float) -> void:
	# Sondeo del botón: así la órbita también funciona si algún Control se come el evento.
	_poner_orbita(Input.is_mouse_button_pressed(boton_orbita))

	# Suavizado exponencial: el mismo tacto a 60 que a 144 FPS.
	var velocidad: float = velocidad_giro if orbitando else velocidad_retorno
	var t: float = 1.0 - exp(-velocidad * delta)
	_yaw = lerp_angle(_yaw, _yaw_objetivo, t)
	_pitch = lerpf(_pitch, _pitch_objetivo, t)
	rotation = Vector3(_pitch, _yaw, 0.0)

# Activa o desactiva la órbita. Al desactivarla, los objetivos vuelven a la pose de reposo
# (detrás del personaje): el suavizado de _process hace el viaje de vuelta.
func _poner_orbita(activa: bool) -> void:
	if activa == orbitando:
		return
	orbitando = activa
	if not orbitando:
		_yaw_objetivo = 0.0
		_pitch_objetivo = deg_to_rad(pitch_reposo)

func _buscar_brazo() -> SpringArm3D:
	for hijo in get_children():
		if hijo is SpringArm3D:
			return hijo
	return null

func _buscar_cuerpo() -> CollisionObject3D:
	if objetivo is CollisionObject3D:
		return objetivo
	var nodo: Node = get_parent()
	while nodo != null:
		if nodo is CollisionObject3D:
			return nodo
		nodo = nodo.get_parent()
	return null
