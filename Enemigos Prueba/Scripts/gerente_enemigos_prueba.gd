class_name GerenteEnemigosPrueba
extends Node3D

## Gerente de los enemigos de prueba de la PARTIDA PRINCIPAL
## (res://ziba/escenas/ziba_prototipo.tscn). No es una escena de prueba: vive en
## el mundo real y funciona con cualquier transformación del jugador.
##
## Tecla G (acción "enemigos_prueba"): genera exactamente seis cápsulas
## alrededor del jugador en puntos validados (suelo firme + hueco libre). Si ya
## hay un grupo activo NO genera otras seis encima: retira el grupo y lo dice
## por consola, de modo que G se puede reutilizar para regenerarlo limpio.
##
## Coordina sin duplicar nada de lo que ya existe:
##   · el anillo de cerco lo reparte el CombatFormation del módulo FreeFlow
##     (reutilizado tal cual); aquí sólo se recorta contra paredes,
##   · los turnos de ataque los lleva el AttackTokenManager del módulo
##     (max_attackers = 2 en combat_config.tres),
##   · el daño al jugador pasa por EstadisticasJugador.recibir_danio().
##
## El jugador se localiza por grupo y, si no está, por tipo (ControladorLeo),
## nunca por una ruta de nodo rígida: la escena se puede reordenar sin romperlo.

## Emitida al generar un grupo, con cuántos enemigos se crearon de verdad.
signal grupo_generado(cantidad: int)
## Emitida al retirar el grupo activo.
signal grupo_retirado()

const ESCENA_ENEMIGO := preload("res://Enemigos Prueba/Scenes/enemigo_prueba.tscn")
## El tipo del enemigo se resuelve con preload (no con el class_name global):
## así este script no depende de la caché de clases global del editor.
const ClaseEnemigo := preload("res://Enemigos Prueba/Scripts/enemigo_prueba.gd")
const GRUPO := &"enemigos_prueba"
const ACCION := &"enemigos_prueba"
const GRUPO_GESTOR := &"combat_manager"
const GRUPO_JUGADOR := &"player"
## Altura total (m) de la cápsula del enemigo: la misma de enemigo_prueba.tscn.
const ALTURA_CAPSULA := 1.8

@export_group("Aparición (tecla G)")
@export var cantidad: int = 6
## Radio (m) al que se reparten los enemigos alrededor del jugador.
@export var radio_aparicion: float = 7.0
## Separación mínima (m) entre dos puntos de aparición.
@export var separacion_minima: float = 1.6

@export_group("Cerco")
## Radio (m) del anillo de combate. Con CombatManager manda el
## formation_radius de su config (2.5); este es el respaldo sin gestor.
@export var radio_cerco: float = 2.5

@export_group("Enemigos")
## Vida de cada cápsula (configurable; se aplica al aparecer).
@export var vida_enemigo: float = 60.0
## Daño de cada golpe enemigo (por EstadisticasJugador.recibir_danio).
@export var dano_enemigo: float = 10.0

var _enemigos: Array[Node3D] = []
var _angulos: Dictionary = {}        # instance_id -> ángulo base (respaldo sin gestor)
var _destino_cache: Dictionary = {}  # instance_id -> {t, p} (recorte contra paredes)
var _siguiente_id: int = 0
var _jugador: Node3D = null
var _estadisticas: EstadisticasJugador = null
var _gestor: Node = null
var _sonda_hueco: SphereShape3D

func _ready() -> void:
	_sonda_hueco = SphereShape3D.new()
	_sonda_hueco.radius = 0.55
	# El jugador puede no existir aún cuando el mundo se instancia en la pantalla
	# de carga: se resuelve en diferido y, si hiciera falta, otra vez al generar.
	_resolver_referencias.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACCION):
		_alternar_grupo()
		get_viewport().set_input_as_handled()

# =============================================================== API (la usa el enemigo)
## Posición de cerco de un enemigo. La pide cada enemigo en su bucle de física.
func posicion_de(e: Node3D) -> Vector3:
	if _jugador == null or not is_instance_valid(_jugador):
		return e.global_position
	var base := Vector3.ZERO
	var tiene := false
	var gestor := gestor_combate()
	if gestor != null:
		var formacion: Variant = gestor.get("formation")
		if formacion != null and bool(formacion.has_slot(e)):
			base = formacion.get_slot(e)
			tiene = true
	if not tiene:
		var ang := float(_angulos.get(e.get_instance_id(), 0.0))
		base = _jugador.global_position + Vector3(cos(ang), 0.0, sin(ang)) * radio_cerco
	return _recortar_contra_paredes(e, base)

func enemigos_vivos() -> Array:
	return _enemigos

func jugador() -> Node3D:
	if _jugador == null or not is_instance_valid(_jugador):
		_resolver_referencias()
	return _jugador

func estadisticas() -> EstadisticasJugador:
	if _estadisticas == null or not is_instance_valid(_estadisticas):
		_resolver_referencias()
	return _estadisticas

## Gestor de combate de la escena (el del módulo FreeFlow). Se busca UNA vez por
## grupo y se guarda: nada de búsquedas globales por fotograma.
func gestor_combate() -> Node:
	if _gestor == null or not is_instance_valid(_gestor):
		_gestor = get_tree().get_first_node_in_group(GRUPO_GESTOR) as Node
		_enlazar_gestor()
	return _gestor

# =============================================================== Aparición (G)
## API pública de la aparición (para pruebas y depuración): genera el grupo
## igual que la tecla G. Si ya hay uno activo NO duplica: lo avisa y no hace nada.
func generar_grupo() -> void:
	_generar_grupo()

## API pública: retira el grupo activo (igual que la segunda pulsación de G).
func retirar_grupo() -> void:
	if _enemigos.is_empty():
		_limpiar_muertos()
	_retirar_grupo()

func _alternar_grupo() -> void:
	_limpiar_muertos()
	if not _enemigos.is_empty():
		print("[Enemigos] Grupo ya activo (%d enemigos): se retira. Pulsa G otra vez para generar uno nuevo." % _enemigos.size())
		_retirar_grupo()
		return
	_generar_grupo()

func _generar_grupo() -> void:
	_limpiar_muertos()
	if not _enemigos.is_empty():
		# Nunca se generan seis encima de un grupo activo.
		print("[Enemigos] Ya hay un grupo activo (%d): no se genera otro." % _enemigos.size())
		return
	_resolver_referencias()
	if _jugador == null:
		push_warning("[Enemigos] No se encontró el jugador en la escena: no se generan enemigos.")
		return

	var centro := _jugador.global_position
	var base := _angulo_frente()
	var excluir: Array[RID] = []
	if _jugador is CollisionObject3D:
		excluir.append((_jugador as CollisionObject3D).get_rid())
	var colocados: Array[Vector3] = []
	var creados := 0
	for i in cantidad:
		var ang := base + TAU * float(i) / float(cantidad)
		var punto: Variant = _buscar_punto(ang, centro, excluir, colocados)
		if punto == null:
			continue
		if _crear_enemigo(punto, ang, excluir, colocados) != null:
			creados += 1
	print("[Enemigos] Generados %d/%d alrededor del jugador (radio %.1f m)." % [creados, cantidad, radio_aparicion])
	grupo_generado.emit(creados)

func _retirar_grupo() -> void:
	var lote := _enemigos.duplicate()
	for e in lote:
		if is_instance_valid(e) and e is ClaseEnemigo:
			(e as ClaseEnemigo).retirar()
	_enemigos.clear()
	_angulos.clear()
	_destino_cache.clear()
	print("[Enemigos] Grupo retirado.")
	grupo_retirado.emit()

# =============================================================== Puntos válidos
## Busca un punto de aparición: suelo firme, lejos del jugador y de los ya
## colocados, y sin objetos sólidos a la altura del pecho. Devuelve null si no
## encuentra ninguno tras varios intentos (entonces ese enemigo no se crea).
func _buscar_punto(ang0: float, centro: Vector3, excluir: Array[RID], colocados: Array[Vector3]) -> Variant:
	if not is_inside_tree():
		return null
	var espacio := get_world_3d().direct_space_state
	for intento in 8:
		var ang := ang0
		var radio := radio_aparicion
		if intento > 0:
			ang += randf_range(-0.16, 0.16)
			radio *= randf_range(0.75, 1.2)
		var candidato := centro + Vector3(cos(ang), 0.0, sin(ang)) * radio
		# 1) Suelo firme debajo del candidato.
		var rayo := PhysicsRayQueryParameters3D.create(
				candidato + Vector3.UP * 24.0, candidato - Vector3.UP * 32.0, 1, excluir)
		var golpe := espacio.intersect_ray(rayo)
		if golpe.is_empty():
			continue
		var suelo: Vector3 = golpe.get("position", Vector3.ZERO)
		var pos := suelo + Vector3.UP * (ALTURA_CAPSULA * 0.5 + 0.06)
		# 2) Ni dentro del jugador ni encima de otro enemigo ya colocado.
		if Vector2(pos.x - centro.x, pos.z - centro.z).length() < 3.0:
			continue
		var despejado := true
		for c in colocados:
			if Vector2(pos.x - c.x, pos.z - c.z).length() < separacion_minima:
				despejado = false
				break
		if not despejado:
			continue
		# 3) Sin paredes ni objetos sólidos a la altura del pecho.
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _sonda_hueco
		q.transform = Transform3D(Basis(), pos + Vector3.UP * 0.9)
		q.collision_mask = 1
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = excluir
		if not espacio.intersect_shape(q, 1).is_empty():
			continue
		return pos
	return null

func _crear_enemigo(pos: Vector3, ang: float, excluir: Array[RID], colocados: Array[Vector3]) -> ClaseEnemigo:
	var e := ESCENA_ENEMIGO.instantiate() as ClaseEnemigo
	if e == null:
		return null
	_siguiente_id += 1
	e.name = "Enemigo%d" % _siguiente_id
	e.vida_max = vida_enemigo
	e.danio_base = dano_enemigo
	e.configurar(self, _siguiente_id)
	add_child(e)
	e.global_position = pos
	# La conexión muere con el nodo al liberarse: no queda ninguna referencia.
	e.murio.connect(_al_morir_enemigo)
	_enemigos.append(e)
	_angulos[e.get_instance_id()] = ang
	if e is CollisionObject3D:
		excluir.append((e as CollisionObject3D).get_rid())
	colocados.append(pos)
	return e

# =============================================================== Cerco
## Recorta el destino contra paredes: si un muro corta la recta jugador->anillo,
## el enemigo se queda del lado de acá (y no intenta meterse en el muro).
func _recortar_contra_paredes(e: Node3D, base: Vector3) -> Vector3:
	if _jugador == null or not is_instance_valid(_jugador) or not is_inside_tree():
		return base
	var id := e.get_instance_id()
	var ahora := Time.get_ticks_msec() / 1000.0
	var entrada: Dictionary = _destino_cache.get(id, {})
	if entrada.is_empty() or ahora - float(entrada.get("t", -1.0)) > 0.25:
		var desde := _jugador.global_position + Vector3.UP * 1.1
		var hacia := base + Vector3.UP * 1.1
		var excluir: Array[RID] = []
		if _jugador is CollisionObject3D:
			excluir.append((_jugador as CollisionObject3D).get_rid())
		for otro in _enemigos:
			if otro != e and otro is CollisionObject3D:
				excluir.append((otro as CollisionObject3D).get_rid())
		var rayo := PhysicsRayQueryParameters3D.create(desde, hacia, 1, excluir)
		var golpe := get_world_3d().direct_space_state.intersect_ray(rayo)
		var punto := base
		if not golpe.is_empty():
			var dir := base - _jugador.global_position
			dir.y = 0.0
			var largo := dir.length()
			if largo > 0.001:
				var choque: Vector3 = golpe.get("position", base)
				var hasta := Vector2(choque.x - _jugador.global_position.x,
						choque.z - _jugador.global_position.z).length()
				if hasta < largo - 0.05:
					punto = _jugador.global_position + (dir / largo) * maxf(1.2, hasta - 0.6)
		entrada = {"t": ahora, "p": punto}
		_destino_cache[id] = entrada
	return entrada.get("p", base)

## Al morir un enemigo se recalcula el reparto: con CombatManager lo hace su
## formation en el siguiente fotograma; el respaldo queda aquí equiespaciado.
func _al_morir_enemigo(e: ClaseEnemigo) -> void:
	_enemigos.erase(e)
	_angulos.erase(e.get_instance_id())
	_destino_cache.erase(e.get_instance_id())
	_reasignar_angulos()
	print("[Enemigos] Enemigo %d eliminado. Quedan %d." % [e.id_ia, _enemigos.size()])

func _reasignar_angulos() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var vivos: Array[Node3D] = []
	for e in _enemigos:
		if is_instance_valid(e) and e.is_alive():
			vivos.append(e)
	if vivos.is_empty():
		return
	vivos.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _angulo_actual_de(a) < _angulo_actual_de(b))
	var n := vivos.size()
	# Gira el anillo lo mínimo (media de desfases) para que nadie cruce al jugador.
	var desplazamiento := 0.0
	for i in n:
		desplazamiento += wrapf(_angulo_actual_de(vivos[i]) - TAU * (float(i) / float(n)), -PI, PI)
	desplazamiento /= float(n)
	for i in n:
		_angulos[vivos[i].get_instance_id()] = TAU * (float(i) / float(n)) + desplazamiento

func _angulo_actual_de(e: Node3D) -> float:
	var dif := e.global_position - _jugador.global_position
	return atan2(dif.z, dif.x)

func _angulo_frente() -> float:
	var frente := -_jugador.global_transform.basis.z
	frente.y = 0.0
	if frente.length_squared() < 0.0001:
		return 0.0
	return atan2(frente.z, frente.x)

func _limpiar_muertos() -> void:
	var vivos: Array[Node3D] = []
	for e in _enemigos:
		if is_instance_valid(e) and e.is_alive():
			vivos.append(e)
	_enemigos = vivos

# =============================================================== Referencias
func _resolver_referencias() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		_jugador = _buscar_jugador()
	if _jugador != null and (_estadisticas == null or not is_instance_valid(_estadisticas)):
		_estadisticas = _jugador.get_node_or_null("Estadisticas") as EstadisticasJugador
	gestor_combate()

func _buscar_jugador() -> Node3D:
	var por_grupo := get_tree().get_first_node_in_group(GRUPO_JUGADOR)
	if por_grupo is ControladorLeo:
		return por_grupo as Node3D
	# Sin grupo: se busca por TIPO en todo el árbol (nunca por una ruta rígida),
	# así funciona tanto en la partida como en cualquier escena de prueba.
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if n is ControladorLeo:
			return n as Node3D
	return null

## El gestor del encuentro necesita saber quién es el jugador para centrar el
## anillo de formación: se le pasa en cuanto se le encuentra.
func _enlazar_gestor() -> void:
	if _gestor == null:
		return
	if _jugador != null and _gestor.has_method("set_player"):
		_gestor.call("set_player", _jugador)
