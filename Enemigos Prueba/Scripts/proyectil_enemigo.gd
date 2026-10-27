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

## Modelo REAL de la munición (Tarea 2): cartucho 6.5x55 COMPLETO (culote + casco +
## punta), no una bala suelta. Sustituye a la bola visible; la lógica de vuelo, el
## barrido y el daño son exactamente los mismos.
const ESCENA_MUNICION := "res://modelos 3d armas/bullet_6.5x55mm_swedish.glb"
## Largo real del modelo (m) medido con `_tests/probe_armas.gd` sobre la escena
## importada: sirve para escalarlo de forma UNIFORME hasta el tamaño visible del
## proyectil. (El cartucho real mide 8 cm; a 26 m/s y a 10-20 m de distancia eso son
## un par de píxeles, así que el tamaño visible se mantiene en el que ya tenía la
## bola: radio*2*escala_visual. Es una escala UNIFORME, no un estirado de ejes.)
const LARGO_MODELO := 0.4482
## Brillo propio del proyectil: se añade emisión a COPIAS de los materiales del
## cartucho (los recursos importados NO se tocan) para que se siga leyendo en vuelo,
## como se leía la bola emisiva. 0.0 = cartucho tal cual, sin brillo.
const BRILLO_RASTRO := 0.9
const COLOR_RASTRO := Color(1.0, 0.72, 0.35)

var _dir: Vector3 = Vector3.FORWARD
var _duenio: Node3D = null
var _activo: bool = false
var _t: float = 0.0
var _bola: SphereShape3D
var _consulta := PhysicsShapeQueryParameters3D.new()

@onready var _malla: MeshInstance3D = get_node_or_null("Malla") as MeshInstance3D
## Cartucho real (hijo directo de la escena). Si está, manda él como malla visible;
## el nombre antiguo "Malla/Municion" también se acepta por compatibilidad.
@onready var _municion: Node3D = _buscar_municion()
## ¿Ya se le puso el brillo al cartucho? (se hace una sola vez, con copias).
var _brillo_puesto: bool = false

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

## Ajusta la malla VISIBLE al radio de colisión configurado. Con el cartucho real
## (Tarea 2) la escala es UNIFORME y conserva el tamaño visible que tenía la bola;
## si no hay cartucho, sigue funcionando el camino de la bola de siempre.
func _actualizar_malla() -> void:
	if _municion != null:
		_municion.scale = Vector3.ONE * (radio * 2.0 * escala_visual / LARGO_MODELO)
		_poner_brillo_rastro()
		return
	if _malla == null:
		return
	var esf := _malla.mesh as SphereMesh
	if esf == null:
		return
	esf = esf.duplicate() as SphereMesh
	esf.radius = radio * escala_visual
	esf.height = radio * 2.0 * escala_visual
	_malla.mesh = esf

## Nodo del cartucho real, esté como hijo directo (escena nueva) o bajo "Malla"
## (disposición antigua): así el script funciona con las dos.
func _buscar_municion() -> Node3D:
	var directo := get_node_or_null("Municion") as Node3D
	if directo != null:
		return directo
	return get_node_or_null("Malla/Municion") as Node3D


## Brillo del proyectil: copias de los materiales del cartucho con emisión cálida.
## Se trabaja sobre COPIAS (los materiales importados del GLB quedan intactos, igual
## que hace el destello de daño de los enemigos): el cartucho se ve como es, pero
## con luz propia suficiente para seguirlo en vuelo.
func _poner_brillo_rastro() -> void:
	if _brillo_puesto or BRILLO_RASTRO <= 0.0:
		return
	_brillo_puesto = true
	for n in _municion.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if base == null or not (base is BaseMaterial3D):
				continue
			var copia := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			if copia is StandardMaterial3D:
				var sm := copia as StandardMaterial3D
				sm.emission_enabled = true
				sm.emission = COLOR_RASTRO
				sm.emission_energy_multiplier = BRILLO_RASTRO
			mi.set_surface_override_material(s, copia)

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
	# ¿Con quién chocó realmente? OJO: el barrido deja la esfera parada JUSTO en
	# contacto (sin solape), así que preguntar con intersect_shape en el punto de
	# parada SEGURA no encuentra a nadie y el impacto se perdía (el proyectil se
	# destruía sin dañar al jugador). Se pregunta en la fracción INSEGURA —donde
	# ya hay solape— y, si aun así no devuelve nada, se respalda con un RAYO por
	# el mismo segmento. Así el cuerpo golpeado (jugador, pared, suelo...) se
	# identifica siempre y el daño va al objetivo real, nunca a través de muros.
	_consulta.transform = Transform3D(Basis(), desde + paso * fracciones[1])
	_consulta.motion = Vector3.ZERO
	var res := espacio.intersect_shape(_consulta, 1)
	var golpeado: Variant = res[0].get("collider") if not res.is_empty() else null
	if golpeado == null:
		var rayo := PhysicsRayQueryParameters3D.create(desde, desde + paso, mascara, _exclusiones())
		var impacto := espacio.intersect_ray(rayo)
		if not impacto.is_empty():
			golpeado = impacto.get("collider")
	_impactar(golpeado)

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
	# Se marca inactivo ANTES de nada: aunque el free sea diferido, ningún
	# fotograma posterior puede volver a entrar aquí y duplicar el daño.
	_activo = false
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
