class_name GerenteEnemigosPrueba
extends Node3D

## Gerente de los enemigos de prueba de la PARTIDA PRINCIPAL
## (res://ziba/escenas/ziba_prototipo.tscn). No es una escena de prueba: vive en
## el mundo real y funciona con cualquier transformación del jugador.
##
## Tecla G (acción "enemigos_prueba"): genera CINCO enemigos alrededor del
## jugador en puntos validados (suelo firme + hueco libre): tres de CUERPO A
## CUERPO (la misma escena de H) y dos CON ARMAS (la misma escena de J). Si ya
## hay un grupo activo NO genera otros cinco encima: retira el grupo y lo dice
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
## Escenas de los enemigos CON ESQUELETO (cuerpo a cuerpo y tirador). Igual que la
## cápsula, se resuelven con preload para no depender de la caché de clases global.
const ESCENA_MELEE := preload("res://Enemigos Prueba/Scenes/enemigo_melee.tscn")
const ESCENA_TIRADOR := preload("res://Enemigos Prueba/Scenes/enemigo_tirador.tscn")
const ESCENA_TANQUE := preload("res://Enemigos Prueba/Scenes/enemigo_tanque.tscn")
const ESCENA_JEFE := preload("res://Enemigos Prueba/Scenes/enemigo_jefe.tscn")
const GRUPO := &"enemigos_prueba"
const ACCION := &"enemigos_prueba"
const ACCION_MELEE := &"enemigos_melee"
const ACCION_TIRADOR := &"enemigos_tirador"
const ACCION_TANQUE := &"enemigos_tanque"
const ACCION_JEFE := &"enemigos_jefe"
const GRUPO_GESTOR := &"combat_manager"
const GRUPO_JUGADOR := &"player"
## Altura total (m) de la cápsula del enemigo: la misma de enemigo_prueba.tscn.
const ALTURA_CAPSULA := 1.8

## Tipos de enemigo que puede generar este gerente, cada uno con su tecla:
## H = cuerpo a cuerpo, J = tirador, G = MEZCLA de los dos (3 + 2).
## CAPSULA sigue existiendo para la API de cápsulas (generar_grupo), pero la
## tecla G ya NO la usa.
## Fase 3: nuevos roles TANQUE (K) y JEFE (L)
enum Tipo { CAPSULA, MELEE, TIRADOR, MEZCLA, TANQUE, JEFE }
const ESCENAS := {
	Tipo.CAPSULA: ESCENA_ENEMIGO,
	Tipo.MELEE: ESCENA_MELEE,
	Tipo.TIRADOR: ESCENA_TIRADOR,
	Tipo.TANQUE: ESCENA_TANQUE,
	Tipo.JEFE: ESCENA_JEFE,
}
const NOMBRES := {
	Tipo.CAPSULA: "cápsula",
	Tipo.MELEE: "cuerpo a cuerpo",
	Tipo.TIRADOR: "tirador",
	Tipo.MEZCLA: "cuerpo a cuerpo + armas",
	Tipo.TANQUE: "tanque",
	Tipo.JEFE: "jefe",
}
const PREFIJOS := {
	Tipo.CAPSULA: "Enemigo",
	Tipo.MELEE: "Melee",
	Tipo.TIRADOR: "Tirador",
	Tipo.TANQUE: "Tanque",
	Tipo.JEFE: "Jefe",
}
const TECLAS := {
	Tipo.CAPSULA: "G",
	Tipo.MELEE: "H",
	Tipo.TIRADOR: "J",
	Tipo.MEZCLA: "G",
	Tipo.TANQUE: "K",
	Tipo.JEFE: "L",
}

@export_group("Aparición (tecla G)")
## Cuántos enemigos de CUERPO A CUERPO genera la tecla G (escena de H).
@export var cantidad_melee_g: int = 3
## Cuántos enemigos CON ARMAS genera la tecla G (escena de J).
@export var cantidad_tirador_g: int = 2
## Cuántas cápsulas genera la API de cápsulas (generar_grupo). La tecla G ya no
## usa este valor: se conserva para las pruebas del sistema de cápsulas.
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
## +25 % sobre el valor original (60 -> 75) a petición de diseño.
@export var vida_enemigo: float = 75.0
## Daño de cada golpe enemigo (por EstadisticasJugador.recibir_danio).
@export var dano_enemigo: float = 10.0

@export_group("Enemigos con esqueleto (H / J / K / L) - Fase 3")
## Cuántos enemigos cuerpo a cuerpo genera la tecla H.
@export var cantidad_melee: int = 3
## Vida de cada cuerpo a cuerpo (se aplica al aparecer).
## +25 % sobre el valor original (60 -> 75).
@export var vida_melee: float = 75.0
## Daño de cada golpe del combo golpe1-2-3 (H).
@export var dano_melee: float = 8.0
## Cuántos tiradores genera la tecla J.
@export var cantidad_tirador: int = 2
## Vida de cada tirador (se aplica al aparecer).
## +25 % sobre el valor original (45 -> 56.25).
@export var vida_tirador: float = 56.25
## Daño de cada proyectil del tirador (J).
@export var dano_tirador: float = 6.0
## Fase 3: Tanques (K)
@export var cantidad_tanque: int = 1
@export var vida_tanque: float = 150.0
@export var dano_tanque: float = 20.0
## Fase 3: Jefes (L)
@export var cantidad_jefe: int = 1
@export var vida_jefe: float = 300.0
@export var dano_jefe: float = 25.0

var _enemigos: Array[Node3D] = []
## Enemigos agrupados por tipo (Tipo -> Array): permite que cada tecla genere o
## retire SÓLO su tipo sin estorbar a los demás.
var _grupos: Dictionary = {}
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
	for t in [Tipo.CAPSULA, Tipo.MELEE, Tipo.TIRADOR, Tipo.MEZCLA, Tipo.TANQUE, Tipo.JEFE]:
		_grupos[t] = []
	# El jugador puede no existir aún cuando el mundo se instancia en la pantalla
	# de carga: se resuelve en diferido y, si hiciera falta, otra vez al generar.
	_resolver_referencias.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACCION):
		_alternar_grupo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACCION_MELEE):
		_alternar_tipo(Tipo.MELEE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACCION_TIRADOR):
		_alternar_tipo(Tipo.TIRADOR)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACCION_TANQUE):
		_alternar_tipo(Tipo.TANQUE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACCION_JEFE):
		_alternar_tipo(Tipo.JEFE)
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
		base = _centro_jugador() + Vector3(cos(ang), 0.0, sin(ang)) * radio_cerco
	return _recortar_contra_paredes(e, base)

func enemigos_vivos() -> Array:
	return _enemigos

func jugador() -> Node3D:
	if _jugador == null or not is_instance_valid(_jugador):
		_resolver_referencias()
	# El "objetivo" de combate es el CUERPO ACTIVO: en la transformación VUELO
	# la raíz del jugador queda como ancla inmóvil y el cuerpo que realmente se
	# mueve es el nodo hijo "Vuelo". Sin esto, los enemigos perseguían/atacaban
	# la posición vieja del ancla (spawns, cerco, orientación y ataques).
	if _jugador != null and _jugador.has_method("cuerpo_activo"):
		var activo := _jugador.call("cuerpo_activo") as Node3D
		if activo != null:
			return activo
	return _jugador

## Centro REAL de combate del jugador (mismo criterio que jugador()).
func _centro_jugador() -> Vector3:
	if _jugador == null or not is_instance_valid(_jugador):
		_resolver_referencias()
	if _jugador == null:
		return Vector3.ZERO
	var objetivo := jugador()
	return objetivo.global_position if objetivo != null else _jugador.global_position

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
## API pública de la aparición de CÁPSULAS (pruebas y depuración de ese sistema):
## genera el grupo de cápsulas y, si ya hay uno activo, no duplica. La tecla G ya
## NO entra por aquí: G genera la mezcla de cuerpo a cuerpo + armas.
func generar_grupo() -> void:
	_generar(Tipo.CAPSULA)

## API pública: retira TODOS los grupos activos (igual que la segunda pulsación
## de G, ampliada a los tipos nuevos para no dejar nada suelto).
func retirar_grupo() -> void:
	_retirar_todos()

## API pública de los enemigos con esqueleto (pruebas y depuración): genera o
## retira el grupo de un tipo concreto sin pasar por el teclado.
func generar_tipo(tipo: int) -> void:
	_generar(tipo)

func retirar_tipo(tipo: int) -> void:
	_retirar(tipo)

# =============================================================== ETAPA 1 (eventos)
## API pública para el sistema de eventos: crea UN enemigo de un tipo concreto en
## una POSICIÓN GLOBAL dada, sin depender de que esté cerca del jugador. Devuelve
## el nodo creado o null si el tipo, la escena o la posición no son válidos (en
## ese caso NO se crea nada).
##
## Reutiliza EXACTAMENTE la misma escena, inicialización, registro de combate y
## contrato de daño que G/H/J: sólo cambia de dónde sale la posición. El enemigo
## NO entra en los cajones por tipo de las teclas, así que retirar_grupo(),
## retirar_tipo() y los conteos de G/H/J no cambian en nada.
func crear_enemigo_en(posicion: Vector3, tipo: int) -> Node3D:
	if not ESCENAS.has(tipo):
		push_warning("[Enemigos] crear_enemigo_en: tipo inválido (%s)." % str(tipo))
		return null
	var escena: PackedScene = ESCENAS[tipo]
	if escena == null:
		push_warning("[Enemigos] crear_enemigo_en: no hay escena para el tipo %s." % str(tipo))
		return null
	if not is_inside_tree():
		push_warning("[Enemigos] crear_enemigo_en: el gerente no está en el árbol.")
		return null
	_resolver_referencias()
	if _jugador == null:
		push_warning("[Enemigos] crear_enemigo_en: no hay jugador en la escena.")
		return null
	var apoyo: Variant = _validar_posicion_en(posicion)
	if apoyo == null:
		push_warning("[Enemigos] crear_enemigo_en: posición inválida %s (sin suelo firme o con obstáculo)." % str(posicion))
		return null
	return _instanciar_enemigo_en(escena, tipo, apoyo)

## Comprueba sin efectos secundarios si una posición global es válida para un
## enemigo (suelo firme + hueco libre) y devuelve el punto de apoyo, o null. La
## usa el DirectorEventos para validar tubos y puntos de aparición.
func posicion_valida_en(posicion: Vector3) -> Variant:
	_resolver_referencias()
	return _validar_posicion_en(posicion)

func _alternar_grupo() -> void:
	_alternar_tipo(Tipo.MEZCLA)

func _alternar_tipo(tipo: int) -> void:
	_limpiar_muertos()
	var lista: Array = _grupos.get(tipo, [])
	if not lista.is_empty():
		if tipo == Tipo.CAPSULA or tipo == Tipo.MEZCLA:
			print("[Enemigos] Grupo ya activo (%d enemigos): se retira. Pulsa G otra vez para generar uno nuevo." % lista.size())
		else:
			print("[Enemigos] Grupo de %s ya activo (%d): se retira. Pulsa %s otra vez para generar uno nuevo." % [NOMBRES[tipo], lista.size(), TECLAS[tipo]])
		_retirar(tipo)
		return
	_generar(tipo)

func _generar(tipo: int) -> void:
	_limpiar_muertos()
	var lista: Array = _grupos.get(tipo, [])
	if not lista.is_empty():
		# Nunca se genera encima de un grupo activo del mismo cajón.
		if tipo == Tipo.CAPSULA or tipo == Tipo.MEZCLA:
			print("[Enemigos] Ya hay un grupo activo (%d): no se genera otro." % lista.size())
		else:
			print("[Enemigos] Ya hay un grupo de %s activo (%d): no se genera otro." % [NOMBRES[tipo], lista.size()])
		return
	_resolver_referencias()
	if _jugador == null:
		push_warning("[Enemigos] No se encontró el jugador en la escena: no se generan enemigos.")
		return

	var cuantos := _cantidad_de(tipo)
	if cuantos <= 0:
		return
	# Plan de aparición: una entrada por enemigo. La tecla G (MEZCLA) reparte
	# cuerpo a cuerpo y armas reutilizando las MISMAS escenas de H y J; el resto
	# de tipos usa su propia escena. El cupo total reparte el anillo por igual.
	var plan: Array = []
	if tipo == Tipo.MEZCLA:
		for i in cantidad_melee_g:
			plan.append({"escena": ESCENA_MELEE, "tipo": Tipo.MELEE})
		for i in cantidad_tirador_g:
			plan.append({"escena": ESCENA_TIRADOR, "tipo": Tipo.TIRADOR})
	else:
		for i in cuantos:
			plan.append({"escena": ESCENAS[tipo], "tipo": tipo})
	cuantos = plan.size()
	if cuantos <= 0:
		return
	var centro := _centro_jugador()
	var base := _angulo_frente()
	var excluir: Array[RID] = []
	if _jugador is CollisionObject3D:
		excluir.append((_jugador as CollisionObject3D).get_rid())
	# El cuerpo activo (p. ej. el águila volando) también se excluye: el sondeo
	# de puntos de aparición no debe chocar con él.
	var activo := jugador()
	if activo != null and activo != _jugador and activo is CollisionObject3D:
		excluir.append((activo as CollisionObject3D).get_rid())
	var colocados: Array[Vector3] = []
	var creados := 0
	for i in cuantos:
		var ang := base + TAU * float(i) / float(cuantos)
		var punto: Variant = _buscar_punto(ang, centro, excluir, colocados)
		if punto == null:
			continue
		var paso: Dictionary = plan[i]
		if _crear_enemigo(paso["escena"], int(paso["tipo"]), tipo, punto, ang, excluir, colocados) != null:
			creados += 1
	if tipo == Tipo.CAPSULA:
		print("[Enemigos] Generados %d/%d alrededor del jugador (radio %.1f m)." % [creados, cuantos, radio_aparicion])
	elif tipo == Tipo.MEZCLA:
		print("[Enemigos] Generados %d/%d alrededor del jugador (radio %.1f m): %d cuerpo a cuerpo + %d armas." % [creados, cuantos, radio_aparicion, cantidad_melee_g, cantidad_tirador_g])
	else:
		print("[Enemigos] Generados %d/%d de %s alrededor del jugador (radio %.1f m)." % [creados, cuantos, NOMBRES[tipo], radio_aparicion])
	grupo_generado.emit(creados)

func _retirar(tipo: int) -> void:
	var lista: Array = _grupos.get(tipo, [])
	for e in lista.duplicate():
		# Duck typing: retira cualquier enemigo con retirar(), sin exigir su clase.
		if is_instance_valid(e) and (e as Node).has_method("retirar"):
			(e as Node).call("retirar")
	_grupos[tipo] = []
	_limpiar_muertos()
	if tipo == Tipo.CAPSULA or tipo == Tipo.MEZCLA:
		print("[Enemigos] Grupo retirado.")
	else:
		print("[Enemigos] Grupo de %s retirado." % NOMBRES[tipo])
	grupo_retirado.emit()

func _retirar_todos() -> void:
	var habia := not _enemigos.is_empty()
	for e in _enemigos.duplicate():
		if is_instance_valid(e) and (e as Node).has_method("retirar"):
			(e as Node).call("retirar")
	for t in _grupos.keys():
		_grupos[t] = []
	_limpiar_muertos()
	if habia:
		print("[Enemigos] Grupo retirado.")
		grupo_retirado.emit()

func _cantidad_de(tipo: int) -> int:
	match tipo:
		Tipo.MELEE:
			return cantidad_melee
		Tipo.TIRADOR:
			return cantidad_tirador
		Tipo.TANQUE:
			return cantidad_tanque
		Tipo.JEFE:
			return cantidad_jefe
		Tipo.MEZCLA:
			return cantidad_melee_g + cantidad_tirador_g
		_:
			return cantidad

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

## Crea un enemigo. `tipo` decide vida, daño y prefijo de nombre; `grupo` es el
## cajón del gerente al que pertenece (la tecla que lo generó) y es lo que se
## retira de una vez: la tecla G mete sus cinco enemigos de DOS tipos distintos
## en el mismo cajón (MEZCLA) para que una sola pulsación retire todos.
func _crear_enemigo(escena: PackedScene, tipo: int, grupo: int, pos: Vector3, ang: float, excluir: Array[RID], colocados: Array[Vector3]) -> Node3D:
	var e := escena.instantiate() as Node3D
	if e == null:
		return null
	_siguiente_id += 1
	e.name = "%s%d" % [PREFIJOS[tipo], _siguiente_id]
	# Ajustes por tipo con duck typing: la cápsula y los enemigos con esqueleto
	# comparten los NOMBRES de propiedad (vida_max/danio_base), pero no la clase.
	if "vida_max" in e:
		e.set("vida_max", _vida_de(tipo))
	if "danio_base" in e:
		e.set("danio_base", _dano_de(tipo))
	if e.has_method("configurar"):
		e.call("configurar", self, _siguiente_id)
	add_child(e)
	e.global_position = pos
	# La conexión muere con el nodo al liberarse: no queda ninguna referencia.
	e.murio.connect(_al_morir_enemigo)
	_enemigos.append(e)
	var lista: Array = _grupos.get(grupo, [])
	lista.append(e)
	_grupos[grupo] = lista
	_angulos[e.get_instance_id()] = ang
	if e is CollisionObject3D:
		excluir.append((e as CollisionObject3D).get_rid())
	colocados.append(pos)
	return e

## ============================================================= ETAPA 1 (auxiliares)
## Posición de apoyo válida para un enemigo bajo `posicion`, o null. Mismos
## criterios que la aparición de G: suelo firme (rayo hacia abajo, máscara 1) y
## hueco libre a la altura del pecho (misma sonda esférica). No modifica estado.
func _validar_posicion_en(posicion: Vector3) -> Variant:
	if not is_inside_tree():
		return null
	if _sonda_hueco == null:
		_sonda_hueco = SphereShape3D.new()
		_sonda_hueco.radius = 0.55
	var espacio := get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if _jugador is CollisionObject3D:
		excluir.append((_jugador as CollisionObject3D).get_rid())
	var rayo := PhysicsRayQueryParameters3D.create(
			posicion + Vector3.UP * 24.0, posicion - Vector3.UP * 32.0, 1, excluir)
	var golpe := espacio.intersect_ray(rayo)
	if golpe.is_empty():
		return null
	var suelo: Vector3 = golpe.get("position", Vector3.ZERO)
	var apoyo := suelo + Vector3.UP * (ALTURA_CAPSULA * 0.5 + 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sonda_hueco
	q.transform = Transform3D(Basis(), apoyo + Vector3.UP * 0.9)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = excluir
	if not espacio.intersect_shape(q, 1).is_empty():
		return null
	return apoyo

## Crea y añade el enemigo ya validado. NO lo mete en los cajones por tipo ni en
## _enemigos: es un enemigo "de evento", fuera del ciclo de las teclas.
func _instanciar_enemigo_en(escena: PackedScene, tipo: int, pos: Vector3) -> Node3D:
	var e := escena.instantiate() as Node3D
	if e == null:
		push_warning("[Enemigos] No se pudo instanciar la escena del tipo %s." % str(tipo))
		return null
	_siguiente_id += 1
	e.name = "%s%d" % [PREFIJOS[tipo], _siguiente_id]
	if "vida_max" in e:
		e.set("vida_max", _vida_de(tipo))
	if "danio_base" in e:
		e.set("danio_base", _dano_de(tipo))
	if e.has_method("configurar"):
		e.call("configurar", self, _siguiente_id)
	add_child(e)
	e.global_position = pos
	return e

func _vida_de(tipo: int) -> float:
	match tipo:
		Tipo.MELEE:
			return vida_melee
		Tipo.TIRADOR:
			return vida_tirador
		Tipo.TANQUE:
			return vida_tanque
		Tipo.JEFE:
			return vida_jefe
		_:
			return vida_enemigo

func _dano_de(tipo: int) -> float:
	match tipo:
		Tipo.MELEE:
			return dano_melee
		Tipo.TIRADOR:
			return dano_tirador
		Tipo.TANQUE:
			return dano_tanque
		Tipo.JEFE:
			return dano_jefe
		_:
			return dano_enemigo

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
		var desde := _centro_jugador() + Vector3.UP * 1.1
		var hacia := base + Vector3.UP * 1.1
		var excluir: Array[RID] = []
		if _jugador is CollisionObject3D:
			excluir.append((_jugador as CollisionObject3D).get_rid())
		var activo := jugador()
		if activo != null and activo != _jugador and activo is CollisionObject3D:
			excluir.append((activo as CollisionObject3D).get_rid())
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
func _al_morir_enemigo(e: Node3D) -> void:
	_enemigos.erase(e)
	for t in _grupos.keys():
		(_grupos[t] as Array).erase(e)
	_angulos.erase(e.get_instance_id())
	_destino_cache.erase(e.get_instance_id())
	_reasignar_angulos()
	var id: Variant = e.get("id_ia")
	if id == null:
		id = -1
	print("[Enemigos] Enemigo %d eliminado. Quedan %d." % [int(id), _enemigos.size()])

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
	var dif := e.global_position - _centro_jugador()
	return atan2(dif.z, dif.x)

func _angulo_frente() -> float:
	var objetivo := jugador()
	if objetivo == null:
		return 0.0
	var frente := -objetivo.global_transform.basis.z
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
	# Sincroniza las listas por tipo y limpia ángulos/caché de los que ya no están.
	for t in _grupos.keys():
		var lista: Array = _grupos[t]
		var viva: Array = []
		for e in lista:
			if is_instance_valid(e) and e.is_alive():
				viva.append(e)
		_grupos[t] = viva
	var ids: Dictionary = {}
	for e in _enemigos:
		ids[e.get_instance_id()] = true
	for k in _angulos.keys():
		if not ids.has(k):
			_angulos.erase(k)
	for k in _destino_cache.keys():
		if not ids.has(k):
			_destino_cache.erase(k)

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
