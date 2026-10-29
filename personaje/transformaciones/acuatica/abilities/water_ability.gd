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

## IMPACTO CONFIRMADO (sonido): el chapoteo de agua del propio proyecto. El impacto
## a un ENEMIGO suena SÓLO cuando el daño se aplica de verdad a un objetivo válido
## (apply_damage), UNA vez por objetivo y ejecución: ni al aparecer la habilidad, ni
## en cada tick de un área sobre el mismo enemigo. El choque contra el ESCENARIO
## (pared, suelo, props) y el FINAL de la trayectoria sin tocar nada también suenan,
## con sus propios volúmenes y tonos (AUD_CHOQUE_DB / AUD_FIN_DB): así una habilidad
## que no golpea a nadie se oye terminar, pero NUNCA se disfraza de un impacto contra
## un enemigo que no recibió daño. La oleada (water_surge) trae su propio reproductor
## (más voces y más alcance) y desactiva este con `sonido_impacto_propio`.
const AUD_IMPACTO_AGUA := preload("res://audio/personaje/transformacion/Animaciones acuaticas/golpe agua 2.wav")
## Voces en rueda: dos impactos seguidos (o dos a la vez) no se cortan entre sí, y
## nunca se crean nodos por impacto.
const VOCES_IMPACTO_AGUA := 4
## Volumen de cada impacto: por debajo del golpe del puño, para no saturar.
const AUD_IMPACTO_DB := -5.0
## Choque contra el ESCENARIO (pared, suelo, cualquier objeto del mundo): el mismo
## chapoteo, algo más suave (el agua golpea algo duro, no un cuerpo). Suena UNA vez
## por ejecución: la habilidad se gasta al chocar, así que no se repite.
const AUD_CHOQUE_DB := -7.0
## FINAL de la trayectoria sin haber tocado nada (se le acabó el tiempo volando por
## el aire): el MISMO archivo, más bajo y algo más grave, como cierre. Es el aviso de
## que la habilidad terminó sin golpear a nadie.
const AUD_FIN_DB := -11.0
const AUD_FIN_PITCH := 0.82
## Nombres de los GRUPOS DE VOCES compartidos que viven colgados del host (el mismo
## padre que las habilidades). Un proyectil se libera en el fotograma del impacto: si
## las voces fueran hijas suyas, el chapoteo se cortaría antes de sonar. Al ser un
## grupo reutilizado por todas las habilidades, tampoco se acumulan nodos.
const POOL_IMPACTO := "SonidosImpactoAgua"
const POOL_IMPACTO_OLA := "SonidosOlaAgua"

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
## true en las habilidades que traen su propio reproductor de impacto (la oleada).
## Se fija en _build_visual() de la subclase, ANTES de _preparar_sonido_impacto().
var sonido_impacto_propio := false
var _voces_impacto: Array[AudioStreamPlayer3D] = []
var _voz_impacto := 0
## Objetivos ya sonados (por id de instancia): un mismo enemigo no repite sonido.
var _sonados_impacto := {}
## El choque contra el escenario ya sonó en esta ejecución (sólo una vez).
var _sonado_escena := false
## El final por tiempo ya sonó en esta ejecución (sólo una vez).
var _sonado_fin := false


## Prepara la habilidad. Se llama justo despues de instanciarla.
func setup(p_caster: Node3D, p_origin: Vector3, p_direction: Vector3) -> void:
	caster = p_caster
	direction = p_direction.normalized() if p_direction.length_squared() > 0.0001 else Vector3.FORWARD
	global_position = p_origin


func _ready() -> void:
	_build_visual()
	_preparar_sonido_impacto()


## Prepara el reproductor del IMPACTO (voces 3D en rueda) sin crear nodos por golpe.
## Las subclases con reproductor propio (la oleada) lo desactivan con la marca.
func _preparar_sonido_impacto() -> void:
	if sonido_impacto_propio:
		return
	var pool := _pool_sonidos(POOL_IMPACTO)
	if pool.get_child_count() == 0:
		for i in VOCES_IMPACTO_AGUA:
			var voz := AudioStreamPlayer3D.new()
			voz.name = "SonidoImpacto%d" % (i + 1)
			voz.stream = AUD_IMPACTO_AGUA
			voz.volume_db = AUD_IMPACTO_DB
			voz.max_distance = 40.0
			pool.add_child(voz)
	_voces_impacto.clear()
	for hijo in pool.get_children():
		if hijo is AudioStreamPlayer3D:
			_voces_impacto.append(hijo as AudioStreamPlayer3D)


## Devuelve el nodo COMPARTIDO [param nombre] colgado del host (el mismo padre que la
## habilidad), creándolo la primera vez. Compartirlo es lo que permite que el sonido
## del impacto siga sonando aunque la habilidad se libere en ese mismo fotograma.
func _pool_sonidos(nombre: String) -> Node3D:
	var host := get_parent()
	if host == null:
		host = self
	var pool := host.get_node_or_null(nombre) as Node3D
	if pool == null:
		pool = Node3D.new()
		pool.name = nombre
		host.add_child(pool)
	return pool


## Toma una voz para sonar AHORA: preferentemente una que esté libre (así hasta
## cuatro impactos a la vez no se cortan entre sí) y, si todas suenan, la rueda.
func _tomar_voz(voces: Array[AudioStreamPlayer3D], indice: int) -> AudioStreamPlayer3D:
	for v in voces:
		if not v.playing:
			return v
	return voces[indice % voces.size()]


## Suena una voz del grupo compartido EN [param point], con su volumen y su tono.
## El volumen y el tono se fijan SIEMPRE, en cada uso: las voces son compartidas y
## una que acaba de sonar como final (más grave) no puede quedarse con ese tono para
## el siguiente impacto. Nunca se queda bloqueada: si todas están sonando, usa la de
## la rueda, que se reinicia (con cuatro voces, dos sonidos seguidos no se cortan).
func _sonar_voz(voces: Array[AudioStreamPlayer3D], point: Vector3, db: float, pitch: float) -> void:
	if voces.is_empty():
		return
	var voz := _tomar_voz(voces, _voz_impacto)
	if voz.playing:
		_voz_impacto = (_voz_impacto + 1) % voces.size()
	voz.global_position = point
	voz.volume_db = db
	voz.pitch_scale = pitch
	voz.play()


## IMPACTO CONFIRMADO de la habilidad: suena en el punto del objetivo alcanzado y
## UNA sola vez por objetivo. Lo llama `hurt()` sólo con el daño ya aplicado, así que
## un fallo (nadie) nunca suena y un área que golpea cada tick no repite el mismo
## sonido sobre el mismo enemigo.
func _sonar_impacto_agua(target: Node3D) -> void:
	if sonido_impacto_propio or _voces_impacto.is_empty() or target == null:
		return
	var id := target.get_instance_id()
	if _sonados_impacto.has(id):
		return
	_sonados_impacto[id] = true
	_sonar_voz(_voces_impacto, _center_of(target), AUD_IMPACTO_DB, 1.0)


## CHOQUE CONTRA EL ESCENARIO (pared, suelo, un objeto del mundo): también suena. Es
## el mismo chapoteo con el volumen de choque y UNA sola vez por ejecución. Las
## habilidades que traen su propio reproductor (la oleada) lo disparan ellas.
func _sonar_impacto_escena(point: Vector3) -> void:
	if sonido_impacto_propio or _voces_impacto.is_empty() or _sonado_escena:
		return
	_sonado_escena = true
	_sonar_voz(_voces_impacto, point, AUD_CHOQUE_DB, 1.0)


## FINAL de la trayectoria sin haber tocado nada: la habilidad se apagó volando por
## el aire. Suena UNA vez, más bajo y más grave, como CIERRE; nunca como un impacto
## contra un enemigo que jamás recibió daño.
func _sonar_fin(point: Vector3) -> void:
	if sonido_impacto_propio or _voces_impacto.is_empty() or _sonado_fin:
		return
	_sonado_fin = true
	_sonar_voz(_voces_impacto, point, AUD_FIN_DB, AUD_FIN_PITCH)


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
	# Daño aplicado a un objetivo válido = IMPACTO CONFIRMADO: aquí (y sólo aquí)
	# suena el chapoteo de la habilidad.
	_sonar_impacto_agua(target)


## Atrapa a un objetivo si sabe estarlo (prision de agua).
func trap(target: Node3D, duration: float) -> bool:
	if target == null or not target.has_method("trap"):
		return false
	target.call("trap", duration)
	return true


## Que pasa al chocar. Por defecto: daño al objetivo y desaparece. Si el choque es
## contra el ESCENARIO (pared, suelo, un objeto) la habilidad también suena: el
## chapoteo del choque, con su propio volumen.
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
	else:
		_sonar_impacto_escena(point)
	_on_impact(point, target)
	queue_free()


## Se acabó el tiempo de vida. Si no había tocado nada (ni enemigo ni escenario), la
## habilidad se despide con el sonido de finalización.
func _expire() -> void:
	if _spent:
		return
	_spent = true
	if _sonados_impacto.is_empty() and not _sonado_escena:
		_sonar_fin(global_position)
	_on_expire()
	queue_free()


# --- Puntos de extension para las subclases -----------------------------------
func _build_visual() -> void:
	pass


func _on_impact(_point: Vector3, _target: Node3D) -> void:
	pass


func _on_expire() -> void:
	pass
