extends CharacterBody3D
class_name VueloFeatherProjectile

## Pluma-proyectil del HARPY. El daño lo cobra LA PROPIA PLUMA al
## colisionar (antes solo moría en silencio: layer 0 la hacía invisible
## para los detectores del maniquí). Si el golpeado está en el grupo
## "maniqui" recibe recibir_golpe(); si es una caja (RigidBody), recibe
## el empujón físico de la pluma.

@export_range(1.0, 100.0, 1.0) var speed: float = 32.0
@export_range(0.2, 10.0, 0.1) var lifetime: float = 3.0
## Daño que infiere la pluma al impactar un maniquí de práctica.
@export_range(1, 100, 1) var danio: int = 12
## Empujón que recibe el golpeado (maniquí) o la caja al ser rozada.
@export_range(0.0, 15.0, 0.5) var empujon: float = 3.5
## Máscara de colisión del proyectil: qué capas detecta. Por defecto capa 1
## (mundo y maniquíes de práctica) + la capa de enemigos del proyecto (valor 16,
## el mismo que usa enemigo_base), para darle a los dos tipos de objetivo.
@export var mascara_colision: int = 17

var _direction: Vector3 = Vector3.FORWARD
var _remaining_lifetime: float = 0.0
var _shooter: CharacterBody3D
var _launched: bool = false


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	# Evita que los rayos de apuntado detecten otras plumas.
	collision_layer = 0

	# Detecta cuerpos en la máscara configurada (por defecto la capa 1).
	collision_mask = mascara_colision

	_remaining_lifetime = lifetime


func launch(
	shooter: CharacterBody3D,
	spawn_position: Vector3,
	direction: Vector3
) -> void:
	_shooter = shooter
	_direction = direction.normalized()
	_remaining_lifetime = lifetime
	global_position = spawn_position

	if _shooter != null:
		add_collision_exception_with(_shooter)

	var up_axis: Vector3 = Vector3.UP
	if absf(_direction.dot(up_axis)) > 0.98:
		up_axis = Vector3.FORWARD

	look_at(global_position + _direction, up_axis)
	_launched = true


func _physics_process(delta: float) -> void:
	if not _launched:
		return

	_remaining_lifetime -= delta
	if _remaining_lifetime <= 0.0:
		queue_free()
		return

	var collision := move_and_collide(_direction * speed * delta)
	if collision != null:
		_impactar(collision.get_collider())
		queue_free()


## Consecuencia del impacto: daño a maniquíes Y enemigos reales del proyecto
## (cada uno por su contrato, vía el puente compartido), empujón físico a cajas
## y otros RigidBody. El piso no hace nada (solo muere la pluma).
func _impactar(golpeado: Object) -> void:
	if golpeado == null:
		return
	var nodo := golpeado as Node
	if nodo != null and (nodo.is_in_group("maniqui") or nodo.is_in_group("damageable")):
		if VueloDano.aplicar(golpeado, danio, _direction, empujon):
			return
	if golpeado is RigidBody3D:
		(golpeado as RigidBody3D).apply_central_impulse(
			_direction * empujon * 0.6
		)
