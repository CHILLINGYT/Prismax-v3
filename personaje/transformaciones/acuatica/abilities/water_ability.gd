class_name WaterAbility
extends Node3D
## =============================================================================
##  HABILIDAD DE AGUA (base)
## =============================================================================
##  Clase base de todo lo que se lanza y viaja por el mundo: el proyectil, la
##  esfera de area, la prision y la oleada. Aqui esta lo comun:
##
##    * SE MUEVE de verdad (velocidad * delta), no es una animacion.
##    * CHOCA de verdad: un rayo contra el escenario para no atravesar paredes y
##      una esfera de impacto contra los objetivos.
##    * HACE DAÑO de verdad: llama a apply_damage() del objetivo.
##    * SE BORRA SOLA al chocar o al acabarse su tiempo.
##
##  QUE ES UN OBJETIVO
##    Cualquier nodo del grupo "damageable" que tenga estos metodos:
##      apply_damage(amount: float, from_position: Vector3, kind: StringName) -> void
##      get_hit_center() -> Vector3     (opcional, por defecto su posicion)
##      get_hit_radius() -> float       (opcional, por defecto 0.5)
##      trap(duration: float) -> void   (solo si puede quedar atrapado)
##    Asi una habilidad puede golpear a un maniqui, a un enemigo o al jugador sin
##    saber que es: solo necesita el grupo y esos metodos.
##
##  Las subclases solo reescriben:
##    _build_visual()   como se ve
##    _advance(delta)   como se mueve (por defecto: recto)
##    _on_impact(...)   que pasa al chocar
##
##  NOTA: las subclases hacen "extends WaterAbility" por class_name. Si acabas de
##  mover o crear esta carpeta y el editor todavia no la ha escaneado, el nombre
##  no estara registrado y daran error: se arregla solo al reescanear.
## =============================================================================

## Grupo del que se recogen los objetivos golpeables.
const TARGET_GROUP := &"damageable"

## Nodo del caster, para no golpearse a si mismo.
var caster: Node3D = null
## Direccion normalizada de lanzamiento.
var direction := Vector3.FORWARD
## Daño que aplica cada impacto.
var damage := 0.0
## Radio (m) de la esfera de impacto.
var hit_radius := 0.6
## Velocidad (m/s).
var speed := 12.0
## Tiempo de vida maximo (s) antes de desaparecer sola.
var lifetime := 3.0
## Empuje (m/s) que se le da al objetivo golpeado.
var knockback := 3.0
## Capa de fisica del escenario contra la que choca (1 = mundo por defecto).
var world_mask := 1
## Tipo de daño que se le pasa al objetivo (para que elija su reaccion).
var damage_kind: StringName = &"light"
## true si la habilidad nace DEBAJO del agua. Cambia el aspecto (remolinos y
## burbujas en vez de salpicaduras de superficie) y le mete la RESISTENCIA del
## agua: sumergida, la habilidad se va frenando durante el vuelo en vez de volar
## como si estuviera en el aire.
var underwater := false
## Resistencia del agua (1/s) cuando se lanza sumergida.
var underwater_drag := 1.2
## Velocidad (m/s) minima a la que puede llegar por la resistencia del agua.
const UNDERWATER_MIN_SPEED := 2.0

var _elapsed := 0.0
var _spent := false
var _visual: Node3D = null


## Prepara la habilidad. Se llama justo despues de instanciarla.
func setup(p_caster: Node3D, p_origin: Vector3, p_direction: Vector3) -> void:
	caster = p_caster
	direction = p_direction.normalized() if p_direction.length_squared() > 0.0001 else Vector3.FORWARD
	global_position = p_origin


func _ready() -> void:
	_build_visual()


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		_expire()
		return
	if underwater:
		speed = maxf(speed - speed * underwater_drag * delta, UNDERWATER_MIN_SPEED)
	_advance(delta)
	if _spent:
		return
	_check_hits()


## Movimiento recto. Si se topa con algo, impacta ahi mismo.
func _advance(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta
	var obstacle := _raycast(from, to)
	if obstacle != null:
		var target := _damageable_of(obstacle)
		if target == null or _stops_on_target():
			_impact(to, target)
			return
		# Era un objetivo y esta habilidad NO se para con ellos (la oleada): sigue
		# avanzando. El daño ya lo lleva _check_hits(), que ademas se acuerda de a
		# quien ha golpeado, asi que no se puede contar dos veces.
	global_position = to


## true si la habilidad se para al topar con un OBJETIVO. El proyectil si (revienta
## contra el); la oleada no: sigue arrollando y va golpeando a todos.
func _stops_on_target() -> bool:
	return true


## Reaccion del agua segun DONDE se haya lanzado. La comparten todas las
## habilidades: en la superficie es una salpicadura con su onda, y BAJO EL AGUA es
## un remolino con burbujas y nada de salpicadura (no hay superficie que romper).
func water_burst(at: Vector3, radius: float, strength := 1.0) -> void:
	var host := get_parent() as Node3D
	if underwater:
		WaterEffects.bubbles(host, at,
			int(clampf(34.0 * strength, 10.0, 90.0)), radius * 0.45, strength)
		WaterEffects.current(host, at, direction, radius * 1.1, strength)
	else:
		WaterEffects.burst(host, at, radius, strength)


## Onda circular. Debajo del agua no hay superficie que ondear: se cambia por una
## corriente, que es lo que se ve cuando algo se mueve dentro del agua.
func water_ring(at: Vector3, diameter: float, duration: float, strength := 1.0) -> void:
	var host := get_parent() as Node3D
	if underwater:
		WaterEffects.current(host, at, Vector3.UP, diameter * 0.35, strength)
	else:
		WaterEffects.ring(host, at, diameter, duration, strength)


## Espuma: solo tiene sentido en la SUPERFICIE. Debajo del agua se cambia por una
## nube de burbujas que sube, que es lo que se ve cuando el agua se revuelve.
func water_foam(at: Vector3, radius: float, duration: float) -> void:
	var host := get_parent() as Node3D
	if underwater:
		WaterEffects.bubbles(host, at, int(clampf(radius * 26.0, 8.0, 60.0)), radius * 0.5, 0.8)
	else:
		WaterEffects.foam(host, at, radius, duration)


## Un rayo contra el escenario entre la posicion anterior y la nueva: sin esto la
## habilidad atravesaria paredes y suelos a poco rapida que fuese.
## Devuelve el cuerpo con el que ha chocado, o null.
func _raycast(from: Vector3, to: Vector3) -> Object:
	if not is_inside_tree():
		return null
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var exclude: Array[RID] = []
	if caster is CollisionObject3D:
		exclude.append((caster as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, world_mask, exclude)
	var hit := space.intersect_ray(query)
	return hit.get("collider")


## Si lo que ha cortado el rayo es un objetivo (o cuelga de uno), lo devuelve.
## Es lo que hace que un proyectil que da a un maniqui le haga daño A EL y no se
## limite a desaparecer contra su cuerpo.
func _damageable_of(collider: Object) -> Node3D:
	var node := collider as Node
	while node != null:
		if node.is_in_group(TARGET_GROUP) and node.has_method("apply_damage"):
			return node as Node3D
		node = node.get_parent()
	return null


## Busca objetivos dentro del radio de impacto y les hace daño.
func _check_hits() -> void:
	var targets := find_targets(global_position, hit_radius)
	if targets.is_empty():
		return
	_impact(global_position, targets[0])


## Objetivos del grupo "damageable" cuyo cuerpo toca la esfera de impacto.
## Se filtra por distancia en vez de por colision fisica para que valga cualquier
## nodo, aunque no tenga cuerpo de fisica.
func find_targets(center: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not is_inside_tree():
		return found
	for node in get_tree().get_nodes_in_group(TARGET_GROUP):
		var target := node as Node3D
		if target == null or target == caster or not target.is_inside_tree():
			continue
		if _is_dead(target):
			continue
		var target_radius := 0.5
		if target.has_method("get_hit_radius"):
			target_radius = float(target.call("get_hit_radius"))
		if center.distance_to(_center_of(target)) <= radius + target_radius:
			found.append(target)
	return found


func _center_of(target: Node3D) -> Vector3:
	if target.has_method("get_hit_center"):
		return Vector3(target.call("get_hit_center"))
	return target.global_position


func _is_dead(target: Node3D) -> bool:
	if target.has_method("is_defeated"):
		return bool(target.call("is_defeated"))
	return false


## Daño + empuje a un objetivo. Si no tiene apply_damage() no se hace nada: la
## habilidad no sabe ni le importa que tipo de cosa es.
func hurt(target: Node3D, from_position: Vector3, amount: float = -1.0, kind: StringName = &"") -> void:
	if target == null or not target.has_method("apply_damage"):
		return
	var a := amount if amount >= 0.0 else damage
	var k := kind if kind != &"" else damage_kind
	target.call("apply_damage", a, from_position, k)


## Atrapa a un objetivo si sabe estarlo (prision de agua).
func trap(target: Node3D, duration: float) -> bool:
	if target == null or not target.has_method("trap"):
		return false
	target.call("trap", duration)
	return true


## Que pasa al chocar. Por defecto: daño al objetivo y desaparece.
func _impact(point: Vector3, target: Node3D) -> void:
	if _spent:
		return
	_spent = true
	# El aspecto se apaga antes de borrarse: asi la habilidad no se queda un
	# fotograma congelada con el ultimo dibujo en el aire.
	if _visual != null:
		_visual.visible = false
	if target != null:
		hurt(target, point)
	_on_impact(point, target)
	queue_free()


## Se acabó el tiempo de vida.
func _expire() -> void:
	if _spent:
		return
	_spent = true
	_on_expire()
	queue_free()


# --- Puntos de extension para las subclases -----------------------------------
func _build_visual() -> void:
	pass


func _on_impact(_point: Vector3, _target: Node3D) -> void:
	pass


func _on_expire() -> void:
	pass
