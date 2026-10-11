extends Node3D

## Spawner de enemigos de prueba para la partida real (módulo "enemigos prueba").
##
## Tecla G (acción "enemigos_prueba" del Input Map): activa/desactiva. Al activar
## genera 6 enemigos en un anillo alrededor de la POSICIÓN ACTUAL del jugador
## (grupo "player"), siempre en posiciones válidas: sobre el suelo, sin edificios
## ni obstáculos, sin solaparse entre sí ni con el personaje. Se puede usar en
## cualquier momento de la partida; desactivar retira SÓLO los enemigos generados
## por este sistema. Si alguno desaparece (muere y se libera), se repone hasta
## volver a tener seis. Nunca se recarga la escena y nunca se duplica: mantener
## la tecla no genera enemigos extra (es "just pressed" y además se cuenta antes
## de generar).
##
## No depende de ningún nivel concreto: funciona igual en la ciudad, en una arena
## de prueba o en una escena vacía. La escena del enemigo y todo el combate
## (gestor, tokens, formación) viven en este mismo módulo.
##
## Interfaz pública: alternar(), activar(), desactivar(), esta_activo(), contar().

const ENEMY_SCENE := preload("res://enemigos prueba/scenes/enemy.tscn")

@export_group("Activación")
## Acción que activa/desactiva el sistema (G por defecto, ver README.md).
@export var action_toggle: StringName = &"enemigos_prueba"
## Enemigos que el sistema mantiene a la vez.
@export var enemy_count: int = 6

@export_group("Anillo de aparición")
## Radios mínimo y máximo (m) del anillo alrededor del jugador.
@export var ring_radius_min: float = 4.5
@export var ring_radius_max: float = 8.0
## Separación mínima (m) entre apariciones (además de la comprobación de solape).
@export var min_separation: float = 2.2
## Intentos por enemigo con ángulos y radios alternativos antes de darse por
## vencido con esa posición (si un edificio ocupa el punto, se prueba otro).
@export var attempts_per_enemy: int = 28
## Sonda vertical: desde dónde y hasta dónde se busca el suelo.
@export var ground_probe_up: float = 6.0
@export var ground_probe_down: float = 30.0
## Inclinación máxima del terreno aceptada (coseno de la normal): 0.64 ≈ 50°.
@export var ground_max_slope_cos: float = 0.64
## Diferencia máxima de altura (m) entre el punto de aparición y el jugador.
## Rechaza techos de edificios, cornisas y demás zonas inaccesibles para el
## combate, aunque sean "suelo" horizontal.
@export var max_ground_height_delta: float = 1.5
## Holgura (m) sobre el punto de suelo donde se apoya al enemigo.
@export var ground_clearance: float = 0.03

var _activo: bool = false
var _contenedor: Node3D
## Cápsula reutilizada en cada comprobación de hueco (mismas medidas que la del
## enemigo: radio 0.5, alto 2.0).
var _capsula: CapsuleShape3D


func _ready() -> void:
	_capsula = CapsuleShape3D.new()
	_capsula.radius = 0.5
	_capsula.height = 2.0
	_contenedor = Node3D.new()
	_contenedor.name = "EnemigosActivos"
	add_child(_contenedor)
	_contenedor.child_exiting_tree.connect(_on_enemigo_salio)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(action_toggle):
		alternar()
		get_viewport().set_input_as_handled()


# --- Interfaz pública -------------------------------------------------------

## Activa o desactiva. Es seguro llamarlo aunque ya esté en ese estado.
func alternar() -> void:
	if _activo:
		desactivar()
	else:
		activar()


## Activa el sistema: genera los enemigos que falten hasta `enemy_count`.
## Llamarlo dos veces no duplica: primero cuenta los que ya existen.
func activar() -> void:
	if _activo:
		return
	_activo = true
	var existentes := _contar()
	var faltan := enemy_count - existentes
	if faltan <= 0:
		print("[enemigos prueba] ya hay ", existentes, " enemigos; no se genera nada.")
		return
	_generar(faltan)
	print("[enemigos prueba] ACTIVADO: ", _contar(), "/", enemy_count,
			" enemigos alrededor del jugador.")


## Desactiva el sistema y retira SÓLO los enemigos que generó él.
func desactivar() -> void:
	if not _activo and _contenedor.get_child_count() == 0:
		return
	_activo = false
	var n := 0
	for hijo in _contenedor.get_children():
		if is_instance_valid(hijo):
			n += 1
			hijo.queue_free()
	print("[enemigos prueba] DESACTIVADO: retirados ", n, " enemigos.")


func esta_activo() -> bool:
	return _activo


func contar() -> int:
	return _contar()


# --- Generación -------------------------------------------------------------

func _generar(cantidad: int) -> void:
	var jugador := get_tree().get_first_node_in_group("player") as Node3D
	if jugador == null:
		push_warning("[enemigos prueba] no hay jugador (grupo \"player\") en la escena; no se generan enemigos.")
		return
	var generados := 0
	var fallos := 0
	for i in cantidad:
		var resultado := _buscar_posicion(jugador, i)
		if not bool(resultado.get("ok", false)):
			fallos += 1
			continue
		var enemigo := ENEMY_SCENE.instantiate() as Node3D
		enemigo.position = resultado["pos"] as Vector3
		_contenedor.add_child(enemigo)
		generados += 1
	if fallos > 0:
		push_warning("[enemigos prueba] no encontré %d posiciones válidas (¿edificios, paredes o agua alrededor?); se generaron %d de %d." %
				[fallos, generados, cantidad])


## Busca una posición válida del anillo para el enemigo `indice`. Empieza en su
## ángulo base (repartidos a 360°/enemy_count) y prueba desvíos de ángulo y radio
## alternativos. Devuelve {ok: bool, pos: Vector3}.
func _buscar_posicion(jugador: Node3D, indice: int) -> Dictionary:
	var base := TAU * float(indice) / float(maxi(1, enemy_count))
	for intento in attempts_per_enemy:
		var desvio := 0.0
		var radio := randf_range(ring_radius_min, ring_radius_max)
		if intento > 0:
			# Desvío creciente en zigzag y radios repartidos por el anillo.
			desvio = (0.30 + 0.10 * floorf(float(intento) / 2.0)) * (1.0 if intento % 2 == 1 else -1.0)
			radio = lerpf(ring_radius_min, ring_radius_max, fmod(float(intento) * 0.37, 1.0))
		var angulo := base + desvio
		var destino := jugador.global_position + Vector3(cos(angulo), 0.0, sin(angulo)) * radio
		var resultado := _posicion_valida(destino, jugador)
		if bool(resultado.get("ok", false)):
			return resultado
	return {"ok": false}


## Comprueba un candidato: suelo con inclinación razonable debajo (capa física
## del terreno) y hueco de cápsula libre (sin edificios, muros, props, el propio
## jugador ni otros enemigos ya generados).
func _posicion_valida(destino: Vector3, jugador: Node3D) -> Dictionary:
	var espacio := get_world_3d().direct_space_state

	# 1) Sonda de suelo: rayo hacia abajo desde arriba del destino.
	var desde := destino + Vector3.UP * ground_probe_up
	var hasta := destino - Vector3.UP * ground_probe_down
	var sonda := PhysicsRayQueryParameters3D.create(desde, hasta)
	sonda.collide_with_bodies = true
	sonda.collide_with_areas = false
	# El jugador se excluye de la sonda para no "encontrar" su cabeza cuando el
	# destino cae sobre él; el test de hueco de abajo sí lo detecta y lo rechaza.
	if jugador is CollisionObject3D:
		sonda.exclude = [(jugador as CollisionObject3D).get_rid()]
	var impacto := espacio.intersect_ray(sonda)
	if impacto.is_empty():
		return {"ok": false}
	var punto := impacto["position"] as Vector3
	var normal := impacto["normal"] as Vector3
	if normal.dot(Vector3.UP) < ground_max_slope_cos:
		return {"ok": false}  # pared, techo o pendiente demasiado empinada

	# Fuera del nivel del jugador = techo de edificio, cornisa o zona a la que no
	# se puede llegar caminando: no vale como punto de aparición para el combate.
	if absf(punto.y - jugador.global_position.y) > max_ground_height_delta:
		return {"ok": false}

	# 2) Hueco libre: la cápsula del enemigo (r=0.5, alto 2.0, centro a 1 m del
	# suelo) no puede solaparse con nada sólido. Esto cubre edificios, muros,
	# props, el jugador y los enemigos ya presentes.
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = _capsula
	# El centro va a 1 m del punto MÁS 5 cm de holgura: así la propia superficie
	# de apoyo no cuenta como solape (ni con el margen de contacto del motor).
	consulta.transform = Transform3D(Basis(), punto + Vector3.UP * 1.05)
	consulta.collide_with_bodies = true
	consulta.collide_with_areas = false
	consulta.margin = 0.0
	# El cuerpo que sirvió de suelo se excluye por RID: evita falsos positivos
	# con la superficie en la que el enemigo se apoya.
	consulta.exclude = [impacto["rid"]]
	var choques := espacio.intersect_shape(consulta, 1)
	if not choques.is_empty():
		return {"ok": false}

	# 3) Separación mínima entre apariciones (refuerza el test de solape).
	for otro in _contenedor.get_children():
		if otro is Node3D and (otro as Node3D).global_position.distance_to(punto) < min_separation:
			return {"ok": false}

	# El origen del enemigo está a ras de suelo: su cápsula ocupa de 0 a 2 m.
	return {"ok": true, "pos": Vector3(destino.x, punto.y + ground_clearance, destino.z)}


# --- Reposición -------------------------------------------------------------

## Un enemigo salió del árbol (normalmente murió y se liberó tras el "linger"):
## repone para volver a tener seis. Si el sistema está desactivado, no hace nada.
func _on_enemigo_salio(_nodo: Node) -> void:
	if not _activo:
		return
	_reponer.call_deferred()


func _reponer() -> void:
	if not _activo:
		return
	var faltan := enemy_count - _contar()
	if faltan <= 0:
		return
	_generar(faltan)


func _contar() -> int:
	var n := 0
	for hijo in _contenedor.get_children():
		if is_instance_valid(hijo):
			n += 1
	return n