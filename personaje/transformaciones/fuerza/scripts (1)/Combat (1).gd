class_name FuerzaCombat
extends RefCounted

## =============================================================================
##  Combat.gd — daño compartido por todas las habilidades
## =============================================================================
##  Sistema MÍNIMO y por "pato" (duck typing): cualquier nodo que
##    · esté en el grupo "damageable"   y
##    · tenga un método  take_damage(cantidad: float, desde: Vector3, empuje: Vector3)
##  recibe daño. No hay que registrar nada ni heredar de ninguna clase base.
##
##  Si más adelante metes tus propios enemigos, sólo tienes que añadirlos al
##  grupo "damageable" y darles un take_damage(): las tres habilidades ya les
##  hacen daño sin tocar ni una línea de Player.gd.
## =============================================================================

const GRUPO: String = "damageable"


## Golpea TODO lo que haya dentro de una esfera (el pisotón, la roca al chocar).
##   espacio   -> PhysicsDirectSpaceState3D del mundo
##   caida     -> fracción del daño que queda en el borde (0.45 = 45 %)
##   hacia_arriba -> cuánto se empuja hacia arriba además de hacia fuera
## Devuelve la lista de nodos alcanzados (para depurar y para efectos).
static func golpear_esfera(espacio: PhysicsDirectSpaceState3D, centro: Vector3,
		radio: float, dano: float, empuje: float, excluir: Array = [],
		caida: float = 0.45, hacia_arriba: float = 0.35,
		maximo: int = 48) -> Array:
	var alcanzados: Array = []
	if espacio == null or dano <= 0.0 or radio <= 0.0:
		return alcanzados

	var sonda: SphereShape3D = SphereShape3D.new()
	sonda.radius = maxf(radio, 0.05)

	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = sonda
	params.transform = Transform3D(Basis(), centro)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = excluir
	params.margin = 0.0

	var resultados: Array[Dictionary] = espacio.intersect_shape(params, maximo)
	for r: Dictionary in resultados:
		var cuerpo: Object = r.get("collider")
		if cuerpo == null or not (cuerpo is Node3D):
			continue
		var nodo: Node3D = cuerpo
		# Un enemigo compuesto por varias formas aparece repetido: dañarlo una vez.
		if alcanzados.has(nodo):
			continue
		if not nodo.is_in_group(GRUPO) or not nodo.has_method("take_damage"):
			continue

		var distancia: float = _distancia_al_centro(nodo, centro)
		var u: float = clampf(distancia / maxf(radio, 0.01), 0.0, 1.0)
		var cantidad: float = dano * lerpf(1.0, caida, u)

		var dir: Vector3 = nodo.global_position - centro
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = Vector3.UP
		else:
			dir = dir.normalized()
		var impulso: Vector3 = (dir + Vector3.UP * hacia_arriba).normalized() * empuje * lerpf(1.0, caida, u)

		nodo.call("take_damage", cantidad, centro, impulso)
		alcanzados.append(nodo)

	return alcanzados


## Distancia del impacto al bicho, para calcular cuánto daño le llega.
##
## Se mide sobre el origen del nodo, que en casi todos los enemigos está en los
## PIES: un golpe en el pecho saldría "lejano" y quedaría ridículamente flojo.
## Por eso la diferencia de altura cuenta menos que la horizontal.
static func _distancia_al_centro(nodo: Node3D, centro: Vector3) -> float:
	var dif: Vector3 = nodo.global_position - centro
	dif.y *= 0.4
	return dif.length()


## Punto de impacto en el suelo justo debajo de un nodo (para el pisotón).
static func suelo_bajo(nodo: Node3D) -> Vector3:
	return Vector3(nodo.global_position.x, nodo.global_position.y, nodo.global_position.z)


## Saca la cámara del jugador (grupo "player_camera") para sacudirla sin
## acoplar nada: la cámara se apunta sola a ese grupo en su _ready().
## También le da un golpe de campo de visión: se nota el impacto sin marear.
static func sacudir_camara(arbol: SceneTree, intensidad: float) -> void:
	if arbol == null or intensidad <= 0.0:
		return
	var cam: Node = arbol.get_first_node_in_group("player_camera")
	if cam == null:
		return
	if cam.has_method("shake"):
		cam.call("shake", intensidad)
	if cam.has_method("punch_fov"):
		cam.call("punch_fov")
