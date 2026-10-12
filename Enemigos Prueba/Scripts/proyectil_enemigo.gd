class_name ProyectilEnemigo
extends Node3D

## Proyectil pequeño, rápido y configurable de los enemigos tiradores.
##
## Es un Node3D (no un cuerpo físico): avanza con un RAYCAST por fotograma desde
## su posición a la siguiente, así que NO puede atravesar paredes ni al jugador
## por ir rápido (un Area3D se colaría a estas velocidades). Al impactar:
##   · si el cuerpo golpeado (o un ancestro suyo) tiene un EstadisticasJugador,
##     le aplica `recibir_danio()` — el sistema REAL de vida/escudo del jugador;
##   · en cualquier caso se destruye.
##
## Capa por defecto = 1 (mundo + jugador). Los enemigos viven en la capa 16, así
## que los proyectiles NO se dañan entre ellos.

@export var velocidad: float = 26.0
@export var dano: float = 8.0
## Segundos de vida máxima antes de autodestruirse.
@export var duracion: float = 3.0
## Máscara de colisión del barrido (1 = mundo + jugador).
@export var mascara: int = 1
## Radio (m) de colisión del barrido (y de la bola visible con escala 1).
@export var radio: float = 0.14
## Multiplicador del tamaño VISUAL sobre el radio (1 = bola del tamaño del radio).
@export var escala_visual: float = 1.0

var _dir: Vector3 = Vector3.FORWARD
var _duenio: Node3D = null
var _activo: bool = false
var _t: float = 0.0
var _bola: SphereShape3D
var _consulta := PhysicsShapeQueryParameters3D.new()

@onready var _malla: MeshInstance3D = get_node_or_null("Malla") as MeshInstance3D

func _ready() -> void:
	# La bola de colisión y el tamaño visible salen del radio configurado. El
	# tirador fija `radio` tras instanciar y ANTES de add_child, así que aquí ya
	# llega el valor definitivo.
	_bola = SphereShape3D.new()
	_bola.radius = radio
	_consulta.shape = _bola
	_consulta.collide_with_bodies = true
	_consulta.collide_with_areas = false
	_actualizar_malla()

## Ajusta la bola visible al radio de colisión configurado.
func _actualizar_malla() -> void:
	if _malla == null:
		return
	var esf := _malla.mesh as SphereMesh
	if esf == null:
		return
	esf = esf.duplicate() as SphereMesh
	esf.radius = radio * escala_visual
	esf.height = radio * 2.0 * escala_visual
	_malla.mesh = esf

## Arranca el proyectil. Se llama SIEMPRE después de añadirlo al árbol.
func lanzar(origen: Vector3, direccion: Vector3, duenio: Node3D = null, vel: float = -1.0, dmg: float = -1.0) -> void:
	if not is_inside_tree():
		return
	global_position = origen
	_dir = direccion.normalized() if direccion.length_squared() > 0.0001 else Vector3.FORWARD
	_duenio = duenio
	if vel > 0.0:
		velocidad = vel
	if dmg > 0.0:
		dano = dmg
	_t = 0.0
	_activo = true
	if _dir.cross(Vector3.UP).length_squared() > 0.0001:
		look_at(origen + _dir, Vector3.UP)

func _physics_process(delta: float) -> void:
	if not _activo or not is_inside_tree():
		return
	_t += delta
	if _t >= duracion:
		queue_free()
		return
	var paso := _dir * velocidad * delta
	var desde := global_position
	# BARRIDO de esfera (no un rayo): a esta velocidad un rayo se colaría por las
	# esquinas y una esfera quieta se saltaría la pared entre dos fotogramas.
	# cast_motion devuelve la fracción SEGURA del movimiento.
	_consulta.shape = _bola
	_consulta.transform = Transform3D(Basis(), desde)
	_consulta.motion = paso
	_consulta.collision_mask = mascara
	_consulta.exclude = _exclusiones()
	var espacio := get_world_3d().direct_space_state
	var fracciones := espacio.cast_motion(_consulta)
	if fracciones.is_empty() or fracciones[0] >= 1.0:
		global_position = desde + paso
		return
	var choque := desde + paso * fracciones[0]
	global_position = choque
	# ¿Con quién chocó realmente? Se pregunta en el punto de impacto.
	_consulta.transform = Transform3D(Basis(), choque)
	_consulta.motion = Vector3.ZERO
	var res := espacio.intersect_shape(_consulta, 1)
	_impactar(res[0].get("collider") if not res.is_empty() else null)

## Quién NO debe ser golpeado: quien lo lanzó y cualquier enemigo (grupo
## "damageable"). Así no hay fuego amigo entre enemigos ni auto-daño.
func _exclusiones() -> Array[RID]:
	var excluir: Array[RID] = []
	if _duenio is CollisionObject3D:
		excluir.append((_duenio as CollisionObject3D).get_rid())
	for e in get_tree().get_nodes_in_group(&"damageable"):
		if e is CollisionObject3D:
			excluir.append((e as CollisionObject3D).get_rid())
	return excluir

func _impactar(collider: Variant) -> void:
	var stats := _buscar_estadisticas(collider)
	if stats != null and not stats.muerto:
		stats.recibir_danio(dano)
	queue_free()

## Sube por los ancestros buscando el nodo EstadisticasJugador del cuerpo golpeado.
func _buscar_estadisticas(nodo: Variant) -> EstadisticasJugador:
	var n := nodo as Node
	if n == null:
		return null
	if n is EstadisticasJugador:
		return n as EstadisticasJugador
	var p: Node = n
	while p != null:
		var e := p.get_node_or_null("Estadisticas") as EstadisticasJugador
		if e != null:
			return e
		p = p.get_parent()
	return null