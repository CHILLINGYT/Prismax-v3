class_name EnemigoBase
extends CharacterBody3D

## Base COMÚN de los enemigos con esqueleto (melee y tirador). Recoge TODO lo que
## ambas clases comparten: vida propia, el contrato de daño real del proyecto,
## el registro en el CombatManager, los turnos y la amenaza del módulo FreeFlow,
## la barra de vida, el destello de daño y el control del AnimationPlayer.
##
## Contratos que habla (los REALES del proyecto, idénticos a los de la cápsula
## `enemigo_prueba.gd`, para que CUALQUIER ataque del jugador los alcance):
##   · FreeFlow: is_alive(), take_hit(), is_stunned(), execute() + registro en
##     el CombatManager (grupo "combat_manager").
##   · Fuerza: grupo "damageable" en el COLLIDER RAÍZ (el CharacterBody3D) +
##     take_damage(cantidad, desde, empuje) — lo exige FuerzaCombat.golpear_esfera.
##   · Acuática: apply_damage(cantidad, desde, tipo) + get_hit_center()/get_hit_radius().
##   · Velocista: encadena take_hit -> take_damage -> apply_damage.
##
## Las subclases sólo implementan `_pensar()` (la IA). Todo lo demás vive aquí.
##
## IMPORTANTE (collision_layer/mask): la RAÍZ debe seguir en la capa 16 con máscara
## 17, igual que la cápsula, para que el mundo la pare y para que el raycast/sonda
## del gerente la vea. El contrato de Fuerza exige que el nodo del grupo
## "damageable" con take_damage sea el collider raíz, no un hijo.

## Emitida al morir (la usa el gerente para recalcular el cerco y la lista).
signal murio(enemigo: Node)

## Estados de la IA compartidos. El orden importa para el monitor: CERCO(0),
## ATURDIDO(1), ATACAR(2), RECUPERAR(3), MUERTO(4).
enum Estado { CERCO, ATURDIDO, ATACAR, RECUPERAR, MUERTO }

const GRUPO := &"enemigos_prueba"
const GRUPO_DANIO := &"damageable"

@export_group("Vida")
## Vida máxima configurable por instancia (el gerente la fija al aparecer).
## Valor de reserva ya con el +25 % de diseño (60 -> 75): sólo se usa si se
## instancia la escena SIN gerente; en el juego manda el valor del gerente.
@export var vida_max: float = 75.0

@export_group("Ataque")
## Daño base de un golpe/proyectil (el del módulo es enemy_damage = 10).
@export var danio_base: float = 10.0
## Variación aleatoria del daño (±15 %): evita golpes idénticos en serie.
@export var varianza_dano: float = 0.15

@export_group("Movimiento")
@export var velocidad: float = 3.0
@export var aceleracion: float = 16.0
@export var gravedad: float = 22.0
## Tolerancia (m) para dar por alcanzada una posición objetivo.
@export var radio_parada: float = 0.35
## Distancia (m) a la que dos enemigos se separan para no apilarse.
@export var radio_separacion: float = 1.4
## Altura (m) del "pecho": origen de los rayos de visión y de esquiva.
@export var altura_pecho: float = 1.0
## Distancia (m) del sondeo de esquiva contra paredes.
@export var sonda_esquiva: float = 1.2
## Ángulo (grados) que se desvía para bordear un obstáculo.
@export var angulo_esquiva: float = 55.0

@export_group("Animación")
@export var clip_idle: StringName = &"idle_combate"
@export var clip_andar: StringName = &"caminar_combate"
@export var clip_muerte: StringName = &"muerte_1"
## Mezcla (s) al cambiar de clip.
@export var mezcla: float = 0.2
## Velocidad horizontal (m/s) a partir de la cual se considera que anda.
@export var umbral_andar: float = 0.4

## Identificador único de esta instancia de IA (lo asigna el gerente).
var id_ia: int = -1

# Referencia al gerente como Variant (igual que la cápsula): evita un ciclo de
# tipado y permite comprobar sus métodos con call() sin acoplarse a su clase.
var _gerente: Variant = null

var _estado: int = Estado.CERCO
var _vida: float = 0.0
var _t_fase: float = 0.0
var _espera: float = 0.0
var _t_empuje: float = 0.0
var _flash: float = 0.0
var _muerto: bool = false
var _velocidad_propia: float = 0.0
## Lado de esquiva (-1/1) y temporizador: se mantiene un instante para no vibrar.
var _lado_esquiva: float = 0.0
var _t_esquiva: float = 0.0
var _mat_flash: Array[StandardMaterial3D] = []
var _mat_barra: ShaderMaterial = null

@onready var _visual: Node3D = get_node_or_null("Visual") as Node3D
@onready var _anim: AnimationPlayer = get_node_or_null("Animador") as AnimationPlayer
@onready var _barra: Node3D = get_node_or_null("BarraVida") as Node3D
@onready var _barra_mesh: MeshInstance3D = get_node_or_null("BarraVida/Barra") as MeshInstance3D

# =============================================================== Ciclo de vida
## Lo llama el gerente ANTES de añadirlo al árbol.
func configurar(gerente: Variant, id_unico: int) -> void:
	_gerente = gerente
	id_ia = id_unico

func _ready() -> void:
	add_to_group(GRUPO)
	add_to_group(GRUPO_DANIO)
	_vida = maxf(vida_max, 1.0)
	_velocidad_propia = velocidad * randf_range(0.92, 1.08)
	_espera = randf_range(0.2, 0.9)
	_preparar_flash()
	_duplicar_barra()
	_actualizar_barra()
	_registrar_en_combate()
	if _anim != null and _anim.has_animation(clip_idle):
		_anim.play(clip_idle)

# =============================================================== Bucle
func _physics_process(delta: float) -> void:
	if _muerto:
		return
	_actualizar_flash(delta)
	_actualizar_barra_por_camara()
	_espera = maxf(0.0, _espera - delta)

	var jugador: Node3D = _obtener_jugador()
	if jugador == null:
		_fisica(delta, Vector3.ZERO, 0.0)
		_actualizar_animacion()
		return
	# Seguro barato: si un enemigo cae fuera del mundo, se retira solo.
	if global_position.y < jugador.global_position.y - 30.0:
		_morir()
		return

	_orientar(jugador, delta)
	var stats: EstadisticasJugador = _obtener_estadisticas()
	var jugador_vivo: bool = stats != null and not stats.muerto

	if _estado == Estado.ATURDIDO:
		_t_fase -= delta
		_fisica(delta, Vector3.ZERO, 0.0)
		if _t_fase <= 0.0:
			_estado = Estado.CERCO
			_espera = maxf(_espera, 0.25)
	else:
		_pensar(delta, jugador, stats, jugador_vivo)

	_actualizar_animacion()

## Punto de extensión: la IA concreta de cada enemigo. El estado ATURDIDO ya lo
## resuelve esta base antes de llegar aquí.
func _pensar(_delta: float, _jugador: Node3D, _stats: EstadisticasJugador, _jugador_vivo: bool) -> void:
	pass

# =============================================================== Física / pose
func _fisica(delta: float, dir: Vector3, vel: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if _t_empuje > 0.0:
		# Empuje recibido: el control se cede un instante para que se VEA.
		_t_empuje -= delta
		horiz = horiz.move_toward(Vector3.ZERO, aceleracion * 0.25 * delta)
	else:
		var objetivo := dir.normalized() * vel if dir.length_squared() > 0.001 else Vector3.ZERO
		horiz = horiz.move_toward(objetivo, aceleracion * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()

## Adverso de `_fisica`: aplica dir+vel, pero sin soltar el empuje recibido.
func _avanzar(delta: float, dir: Vector3, vel: float) -> void:
	_fisica(delta, dir, vel)

func _orientar(jugador: Node3D, delta: float) -> void:
	var hacia := jugador.global_position - global_position
	hacia.y = 0.0
	if hacia.length_squared() > 0.001:
		# El forward del cuerpo es -Z (igual que la cápsula).
		rotation.y = lerp_angle(rotation.y, atan2(-hacia.x, -hacia.z), 8.0 * delta)

## Separa a los enemigos entre sí para que no se apilen en el mismo punto.
func _con_separacion(dir: Vector3) -> Vector3:
	var otros: Array = _enemigos_del_gerente()
	if otros.is_empty():
		return dir
	var separacion := Vector3.ZERO
	for nodo in otros:
		var otro := nodo as Node3D
		if otro == null or otro == self:
			continue
		var dif := global_position - otro.global_position
		dif.y = 0.0
		var dist := dif.length()
		if dist > 0.001 and dist < radio_separacion:
			separacion += (dif / dist) * ((radio_separacion - dist) / radio_separacion)
	if separacion.length_squared() <= 0.0001:
		return dir
	if dir.length_squared() <= 0.0001:
		return separacion.normalized() * 0.35
	return (dir + separacion * 1.5).normalized()

# =============================================================== Esquiva de obstáculos
## RIDs que los sondeos deben ignorar: el propio enemigo, el jugador y los demás
## enemigos (si no, un enemigo se "esquivaría" a sí mismo o al jugador).
func _rids_excluidos() -> Array[RID]:
	var out: Array[RID] = []
	if self is CollisionObject3D:
		out.append((self as CollisionObject3D).get_rid())
	var jugador := _obtener_jugador()
	if jugador is CollisionObject3D:
		out.append((jugador as CollisionObject3D).get_rid())
	for nodo in _enemigos_del_gerente():
		var otro := nodo as CollisionObject3D
		if otro != null:
			out.append(otro.get_rid())
	return out

## ¿El segmento desde->hasta está libre de geometría sólida (capa 1 del mundo)?
func _rayo_libre(desde: Vector3, hasta: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var rayo := PhysicsRayQueryParameters3D.create(desde, hasta, 1, _rids_excluidos())
	return get_world_3d().direct_space_state.intersect_ray(rayo).is_empty()

## Esquiva básica: si el camino de frente está tapado por una pared, se desvía a
## un lado (el más despejado) durante ~0,6 s para NO quedarse atascado. Mantener
## el lado evita que el enemigo vibre entre izquierda y derecha.
func _dir_con_esquiva(delta: float, dir: Vector3) -> Vector3:
	if dir.length_squared() <= 0.0001:
		return dir
	_t_esquiva = maxf(0.0, _t_esquiva - delta)
	var desde := global_position + Vector3.UP * altura_pecho
	if _rayo_libre(desde, desde + dir.normalized() * sonda_esquiva):
		return dir
	if _lado_esquiva == 0.0 or _t_esquiva <= 0.0:
		var desvio := deg_to_rad(angulo_esquiva)
		var izq := dir.rotated(Vector3.UP, desvio)
		var der := dir.rotated(Vector3.UP, -desvio)
		var libre_izq := _rayo_libre(desde, desde + izq.normalized() * sonda_esquiva)
		var libre_der := _rayo_libre(desde, desde + der.normalized() * sonda_esquiva)
		if libre_izq and not libre_der:
			_lado_esquiva = 1.0
		elif libre_der and not libre_izq:
			_lado_esquiva = -1.0
		else:
			_lado_esquiva = 1.0 if randf() < 0.5 else -1.0
		_t_esquiva = 0.6
	return dir.rotated(Vector3.UP, deg_to_rad(angulo_esquiva) * _lado_esquiva)

# =============================================================== Animación
func _animar(clip: StringName) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if _anim.current_animation == String(clip) and _anim.is_playing():
		return
	_anim.play(clip, mezcla)

## Reproduce un clip una sola vez (golpes, disparo): no reanuda si ya está sonando.
func _animar_una_vez(clip: StringName) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_anim.play(clip, mezcla)

func _duracion_clip(clip: StringName) -> float:
	if _anim == null or not _anim.has_animation(clip):
		return 0.5
	return _anim.get_animation(clip).length

## Locomoción por defecto: anda o se está quieto según su velocidad. Las
## subclases la sobreescriben si necesitan otra cosa.
func _actualizar_animacion() -> void:
	if _estado == Estado.ATACAR:
		return
	var sp := Vector2(velocity.x, velocity.z).length()
	_animar(clip_andar if sp > umbral_andar else clip_idle)

# =============================================================== Contratos de daño
func is_alive() -> bool:
	return not _muerto

func is_stunned() -> bool:
	return _estado == Estado.ATURDIDO

## Contrato FreeFlow: daño + empuje + aturdimiento del golpe del jugador.
func take_hit(amount: float, dir: Vector3, knockback: float, stun: float) -> bool:
	if _muerto or amount <= 0.0:
		return false
	_aplicar_dano(amount, dir, knockback, stun)
	return true

## Contrato Fuerza (grupo "damageable"): take_damage(cantidad, desde, empuje).
func take_damage(cantidad: float, desde: Vector3, empuje: Vector3) -> void:
	_aplicar_dano(cantidad, _dir_desde(desde), empuje.length(), 0.0)

## Contrato acuática: apply_damage(cantidad, desde, tipo).
func apply_damage(cantidad: float, desde: Vector3, _tipo: StringName = &"melee") -> void:
	_aplicar_dano(cantidad, _dir_desde(desde), 0.0, 0.0)

## Remate del módulo: muerte inmediata.
func execute() -> void:
	if _muerto:
		return
	_aplicar_dano(_vida + 1.0, Vector3.FORWARD, 0.0, 0.0)

func get_hit_center() -> Vector3:
	return global_position + Vector3.UP * 1.0

func get_hit_radius() -> float:
	return 0.6

func vida_actual() -> float:
	return _vida

func estado_actual() -> int:
	return _estado

func _dir_desde(desde: Vector3) -> Vector3:
	var dir := global_position - desde
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		return dir.normalized()
	return Vector3.FORWARD

func _aplicar_dano(cantidad: float, dir: Vector3, empuje: float, aturde: float) -> void:
	if _muerto or cantidad <= 0.0:
		return
	_vida = maxf(0.0, _vida - cantidad)
	_flash = 1.0
	if empuje > 0.0 and dir.length_squared() > 0.0001:
		velocity.x += dir.x * empuje
		velocity.z += dir.z * empuje
		_t_empuje = 0.18
	# Un golpe interrumpe el ataque: se limpia amenaza y turno para no bloquear
	# la cola de ataques con un enemigo interrumpido.
	if _estado == Estado.ATACAR:
		_limpiar_amenaza()
		_soltar_turno()
		_estado = Estado.CERCO
		_espera = maxf(_espera, 0.2)
	if aturde > 0.0:
		_limpiar_amenaza()
		_soltar_turno()
		_estado = Estado.ATURDIDO
		_t_fase = maxf(_t_fase, aturde)
	_actualizar_barra()
	if _vida <= 0.0:
		_morir()

# =============================================================== Muerte
func _morir() -> void:
	if _muerto:
		return
	_muerto = true
	_estado = Estado.MUERTO
	_limpiar_amenaza()
	_soltar_turno()
	_desregistrar()
	remove_from_group(GRUPO_DANIO)
	remove_from_group(GRUPO)
	velocity = Vector3.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if _barra != null:
		_barra.visible = false
	if _anim != null and _anim.has_animation(clip_muerte):
		_anim.play(clip_muerte, 0.1)
	var t := create_tween()
	t.set_parallel(true)
	var destino := global_position - Vector3.UP * 0.25
	t.tween_property(self, "global_position", destino, 1.4)
	t.tween_property(self, "scale", Vector3(0.08, 0.08, 0.08), 1.4)
	t.chain().tween_callback(queue_free)
	murio.emit(self)

## Retirada limpia pedida por el gerente (otra pulsación de la tecla): sin tween.
func retirar() -> void:
	if _muerto:
		return
	_muerto = true
	_estado = Estado.MUERTO
	_limpiar_amenaza()
	_soltar_turno()
	_desregistrar()
	remove_from_group(GRUPO_DANIO)
	remove_from_group(GRUPO)
	queue_free()

# =============================================================== Utilidades
func _distancia_plana(objetivo: Node3D) -> float:
	var dif := objetivo.global_position - global_position
	dif.y = 0.0
	return dif.length()

func _dir_plano_hacia(objetivo: Node3D) -> Vector3:
	var dif := objetivo.global_position - global_position
	dif.y = 0.0
	return dif.normalized() if dif.length_squared() > 0.0001 else Vector3.ZERO

func _en_arco(jugador: Node3D, minimo: float) -> bool:
	var hacia := _dir_plano_hacia(jugador)
	if hacia.length_squared() <= 0.0001:
		return false
	return (-global_transform.basis.z).normalized().dot(hacia) >= minimo

## ¿Hay línea de visión clara hasta el jugador (sin paredes de por medio)?
func _con_linea_de_vision(jugador: Node3D, altura: float) -> bool:
	if not is_inside_tree():
		return false
	var desde := global_position + Vector3.UP * altura
	var hasta := jugador.global_position + Vector3.UP * altura
	var excluir: Array[RID] = []
	if self is CollisionObject3D:
		excluir.append((self as CollisionObject3D).get_rid())
	if jugador is CollisionObject3D:
		excluir.append((jugador as CollisionObject3D).get_rid())
	for nodo in _enemigos_del_gerente():
		var otro := nodo as CollisionObject3D
		if otro != null:
			excluir.append(otro.get_rid())
	var rayo := PhysicsRayQueryParameters3D.create(desde, hasta, 1, excluir)
	return get_world_3d().direct_space_state.intersect_ray(rayo).is_empty()

func _punto_de_cerco() -> Vector3:
	if _gerente != null:
		return _gerente.call("posicion_de", self)
	return global_position

func _enemigos_del_gerente() -> Array:
	if _gerente == null:
		return []
	return _gerente.call("enemigos_vivos")

func _obtener_jugador() -> Node3D:
	if _gerente == null:
		return null
	return _gerente.call("jugador") as Node3D

func _obtener_estadisticas() -> EstadisticasJugador:
	if _gerente == null:
		return null
	return _gerente.call("estadisticas") as EstadisticasJugador

func _gestor_combate() -> Node:
	if _gerente != null:
		var g: Variant = _gerente.call("gestor_combate")
		if g is Node and is_instance_valid(g):
			return g as Node
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"combat_manager") as Node

# --- Turnos (AttackTokenManager del módulo FreeFlow, reutilizado tal cual) ---
func _pedir_turno() -> bool:
	var gestor := _gestor_combate()
	if gestor == null:
		return true
	var tokens: Variant = gestor.get("tokens")
	if tokens == null:
		return true
	return bool(tokens.request(self))

func _soltar_turno() -> void:
	var gestor := _gestor_combate()
	if gestor == null:
		return
	var tokens: Variant = gestor.get("tokens")
	if tokens != null:
		tokens.release(self)

func _tiene_turno() -> bool:
	var gestor := _gestor_combate()
	if gestor == null:
		return false
	var tokens: Variant = gestor.get("tokens")
	if tokens == null:
		return false
	return bool(tokens.has_token(self))

# --- Amenaza (ThreatSystem del módulo, para el contraataque contextual) ---
func _registrar_amenaza(t: float, tipo: String = "melee") -> void:
	var gestor := _gestor_combate()
	if gestor == null:
		return
	var threats: Variant = gestor.get("threats")
	if threats != null:
		threats.register(self, tipo, t, true)

func _limpiar_amenaza() -> void:
	var gestor := _gestor_combate()
	if gestor == null:
		return
	var threats: Variant = gestor.get("threats")
	if threats != null:
		threats.clear_for(self)

# --- Registro / barra / materiales ---
func _registrar_en_combate() -> void:
	var gestor := _gestor_combate()
	if gestor != null and gestor.has_method("register_enemy"):
		gestor.call("register_enemy", self)

func _desregistrar() -> void:
	var gestor := _gestor_combate()
	if gestor != null and gestor.has_method("unregister_enemy"):
		gestor.call("unregister_enemy", self)

func _actualizar_barra() -> void:
	var fraccion := 0.0
	if vida_max > 0.0:
		fraccion = clampf(_vida / vida_max, 0.0, 1.0)
	if _mat_barra != null:
		_mat_barra.set_shader_parameter("fraccion", fraccion)

## Oculta la barra si el enemigo queda pegado a la cámara (dos umbrales para que
## no parpadee), igual que la cápsula.
func _actualizar_barra_por_camara() -> void:
	if _barra == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist := cam.global_position.distance_to(_barra.global_position)
	if _barra.visible and dist < 2.2:
		_barra.visible = false
	elif not _barra.visible and dist > 2.6:
		_barra.visible = true

func _actualizar_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 3.5)
	for m in _mat_flash:
		if is_instance_valid(m):
			m.emission_energy_multiplier = _flash * 1.8

func _duplicar_barra() -> void:
	if _barra_mesh != null and _barra_mesh.material_override is ShaderMaterial:
		_mat_barra = (_barra_mesh.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		_barra_mesh.material_override = _mat_barra

## Materiales POR INSTANCIA: el destello de daño de un enemigo no toca a los
## demás ni al modelo del jugador (que comparte los materiales importados).
func _preparar_flash() -> void:
	if _visual == null:
		return
	for n in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if base == null or not (base is BaseMaterial3D):
				continue
			var dup := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			if dup is StandardMaterial3D:
				var sm := dup as StandardMaterial3D
				sm.emission_enabled = true
				sm.emission = Color(1.0, 0.25, 0.22)
				sm.emission_energy_multiplier = 0.0
				_mat_flash.append(sm)
			mi.set_surface_override_material(s, dup)