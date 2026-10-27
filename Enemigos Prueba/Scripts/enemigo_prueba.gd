class_name EnemigoPrueba
extends CharacterBody3D

## Enemigo cápsula de prueba (una escena reutilizable, un solo controlador).
##
## Vive en res://Enemigos Prueba/ y está pensado para la PARTIDA PRINCIPAL
## (res://ziba/escenas/ziba_prototipo.tscn): el gerente (GerenteEnemigosPrueba)
## crea seis copias con la tecla G y las coordina.
##
## Contratos que habla (los REALES del proyecto, no inventados):
##   · FreeFlow (transformación de ataque): is_alive(), take_hit(),
##     is_stunned(), execute() + registro en el CombatManager del módulo
##     (grupo "combat_manager"), tal como pide su README (apartado H).
##   · Fuerza: grupo "damageable" + take_damage(cantidad, desde, empuje).
##   · Acuática: apply_damage(cantidad, desde, tipo) + get_hit_center()/
##     get_hit_radius() (el mismo contrato del maniquí de entrenamiento).
##
## La vida es PROPIA e independiente por enemigo. El daño al jugador pasa
## SIEMPRE por EstadisticasJugador.recibir_danio() (el sistema real de vida y
## escudo): aquí no se duplica ninguna vida del jugador.

## Emitida al morir (la usa el gerente para recalcular el cerco y la lista).
signal murio(enemigo: EnemigoPrueba)

## Estados de la IA. El orden importa para el monitor de verificación:
## CERCO(0), ATURDIDO(1), PREPARAR(2), GOLPEAR(3), RECUPERAR(4), MUERTO(5).
enum Estado { CERCO, ATURDIDO, PREPARAR, GOLPEAR, RECUPERAR, MUERTO }

const GRUPO := &"enemigos_prueba"
const GRUPO_DANIO := &"damageable"
## Ancho (m) de la barra de vida sobre la cápsula (debe coincidir con el quad de
## $BarraVida/Barra en enemigo_prueba.tscn; el relleno lo pinta su shader).
const ANCHO_BARRA := 0.9

@export_group("Vida")
## Vida máxima configurable por instancia (el gerente la fija al aparecer).
@export var vida_max: float = 75.0

@export_group("Ataque")
## Daño base de un golpe (el del módulo de referencia es enemy_damage = 10).
@export var danio_base: float = 10.0
## Variación aleatoria del daño (±15 %): evita golpes idénticos en serie.
@export var varianza_dano: float = 0.15
## Alcance del golpe (m, entre centros). El anillo de cerco está a 2.5 m.
@export var alcance_golpe: float = 2.9
## Arco frontal mínimo (dot) para que el golpe conecte.
@export var arco_golpe: float = 0.25
## Tiempos del ataque: preparación, ventana de impacto y recuperación. Son los
## valores del grupo "Enemy" del combat_config del módulo (0.5 / 0.12 / 0.8).
@export var t_preparacion: float = 0.5
@export var t_ventana: float = 0.12
@export var t_recuperacion: float = 0.8
## Espera entre ataques propios (aleatoria): desincroniza a los seis.
@export var espera_min: float = 0.8
@export var espera_max: float = 1.8

@export_group("Animación")
## Clips de la librería nativa Mixamo. Si la escena no trae nodo `Animador`, se
## ignoran sin más: el enemigo sigue funcionando igual.
@export var clip_idle: StringName = &"idle_combate"
@export var clip_andar: StringName = &"caminar_combate"
@export var clip_ataque: StringName = &"golpe_1"
@export var clip_recibir: StringName = &"recibir_combate"
@export var clip_muerte: StringName = &"muerte_1"
## Ventana (s) en la que el clip de REACCIÓN manda sobre la locomoción, igual que
## en el enemigo base. Sin ella la locomoción pisaba la reacción al fotograma
## siguiente y el golpe recibido no se veía nunca.
@export_range(0.05, 1.0, 0.05) var duracion_recibir: float = 0.35

@export_group("Movimiento")
@export var velocidad: float = 3.2
@export var aceleracion: float = 16.0
@export var gravedad: float = 22.0
## Tolerancia (m) para dar por alcanzada la posición de cerco.
@export var radio_parada: float = 0.35

## Identificador único de esta instancia de IA (lo asigna el gerente).
var id_ia: int = -1

# Referencia al gerente. Se deja como Variant a propósito (igual que hace
# controlador_leo.gd con su gestor): evita un ciclo de tipado entre las dos
# clases y permite comprobar los métodos con call() sin acoplarse.
var _gerente: Variant = null

var _estado: int = Estado.CERCO
var _vida: float = 0.0
var _t_ataque: float = 0.0
var _espera: float = 0.0
var _golpe_aplicado: bool = false
var _t_empuje: float = 0.0
var _inclinacion: float = 0.0
var _flash: float = 0.0
var _muerto: bool = false
var _velocidad_propia: float = 0.0
## Tiempo que le queda al clip de reacción por delante de la locomoción.
var _t_recibir: float = 0.0

@onready var _cuerpo: MeshInstance3D = $Cuerpo
@onready var _barra: Node3D = $BarraVida
@onready var _barra_mesh: MeshInstance3D = $BarraVida/Barra
@onready var _visual: Node3D = get_node_or_null("Visual") as Node3D
@onready var _anim: AnimationPlayer = get_node_or_null("Animador") as AnimationPlayer
var _mat_cuerpo: StandardMaterial3D
var _mat_barra: ShaderMaterial
var _mat_flash: Array[StandardMaterial3D] = []

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
	# Espera inicial repartida: los seis no arrancan el primer ataque a la vez.
	_espera = randf_range(0.2, 0.9)
	_duplicar_materiales()
	_preparar_flash_visual()
	_actualizar_barra()
	_registrar_en_combate()
	if _anim != null and _anim.has_animation(clip_idle):
		_anim.play(clip_idle)

# =============================================================== Bucle de IA
func _physics_process(delta: float) -> void:
	if _muerto:
		return
	_actualizar_flash(delta)
	_actualizar_barra_por_camara()
	_t_recibir = maxf(0.0, _t_recibir - delta)
	_animar_por_velocidad()
	_espera = maxf(0.0, _espera - delta)

	var jugador: Node3D = _obtener_jugador()
	if jugador == null:
		_fisica(delta, Vector3.ZERO, 0.0)
		return
	# Seguro barato: si un enemigo cae fuera del mundo, se retira solo.
	if global_position.y < jugador.global_position.y - 30.0:
		_morir()
		return

	_orientar(jugador, delta)
	var stats: EstadisticasJugador = _obtener_estadisticas()
	var jugador_vivo: bool = stats != null and not stats.muerto

	match _estado:
		Estado.ATURDIDO:
			_t_ataque -= delta
			_fisica(delta, Vector3.ZERO, 0.0)
			if _t_ataque <= 0.0:
				_estado = Estado.CERCO
				_espera = maxf(_espera, 0.25)
		Estado.PREPARAR:
			_fase_preparar(delta, jugador)
		Estado.GOLPEAR:
			_fase_golpear(delta, jugador, stats, jugador_vivo)
		Estado.RECUPERAR:
			_fase_recuperar(delta)
		_:
			_fase_cerco(delta, jugador, jugador_vivo)

## Posición de cerco: la pide al gerente (anillo del CombatFormation del módulo,
## recortado contra paredes). Persigue el punto, no al jugador en línea recta.
func _fase_cerco(delta: float, jugador: Node3D, jugador_vivo: bool) -> void:
	var destino: Vector3 = _punto_de_cerco()
	var hacia := destino - global_position
	hacia.y = 0.0
	var dist := hacia.length()
	var dir := Vector3.ZERO
	if dist > radio_parada:
		dir = hacia / dist
	dir = _con_separacion(dir)
	_fisica(delta, dir, _velocidad_propia)

	var distancia := _distancia_plana(jugador)
	if jugador_vivo and distancia <= alcance_golpe and _en_arco(jugador) and _espera <= 0.0:
		# Pide turno (máx. 2 a la vez, con cola justa). Sin gestor de combate
		# en la escena, el turno se concede siempre (y manda la espera propia).
		if _pedir_turno():
			_empezar_preparacion()
	elif _tiene_turno():
		# Ya no puede o no quiere atacar: suelta el turno para no bloquear la cola.
		_soltar_turno()

## Preparación visible: se inclina atrás, se enciende y avanza un poco.
func _fase_preparar(delta: float, jugador: Node3D) -> void:
	_t_ataque -= delta
	_fisica(delta, _dir_plano_hacia(jugador), _velocidad_propia * 0.35)
	if _t_ataque <= 0.0:
		_limpiar_amenaza()
		_estado = Estado.GOLPEAR
		_t_ataque = t_ventana
		_golpe_aplicado = false
		_inclinacion = -0.3
		_flash = 1.0

## Ventana de impacto: UNA sola aplicación de daño por golpe (bandera propia).
func _fase_golpear(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	_t_ataque -= delta
	_fisica(delta, _dir_plano_hacia(jugador), _velocidad_propia * 0.9)
	if not _golpe_aplicado and jugador_vivo and stats != null:
		var distancia := _distancia_plana(jugador)
		if distancia <= alcance_golpe + 0.25 and _en_arco(jugador):
			_golpe_aplicado = true
			var dano := danio_base * randf_range(1.0 - varianza_dano, 1.0 + varianza_dano)
			stats.recibir_danio(dano)
	if _t_ataque <= 0.0:
		_estado = Estado.RECUPERAR
		_t_ataque = t_recuperacion
		_inclinacion = 0.0

func _fase_recuperar(delta: float) -> void:
	_t_ataque -= delta
	_fisica(delta, Vector3.ZERO, 0.0)
	if _t_ataque <= 0.0:
		_soltar_turno()
		_espera = randf_range(espera_min, espera_max)
		_estado = Estado.CERCO

func _empezar_preparacion() -> void:
	_estado = Estado.PREPARAR
	_animar_una_vez(clip_ataque)
	_t_ataque = t_preparacion * randf_range(0.9, 1.2)
	_inclinacion = 0.1
	_flash = 0.5
	# Amenaza registrada para el contraataque contextual del FreeFlow (opcional).
	_registrar_amenaza(_t_ataque)

# =============================================================== Física / pose
func _fisica(delta: float, dir: Vector3, vel: float) -> void:
	_cuerpo.rotation.x = lerp_angle(_cuerpo.rotation.x, _inclinacion, 9.0 * delta)
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
		if dist > 0.001 and dist < 1.4:
			separacion += (dif / dist) * ((1.4 - dist) / 1.4)
	if separacion.length_squared() <= 0.0001:
		return dir
	if dir.length_squared() <= 0.0001:
		return separacion.normalized() * 0.35
	return (dir + separacion * 1.5).normalized()

func _orientar(jugador: Node3D, delta: float) -> void:
	var hacia := jugador.global_position - global_position
	hacia.y = 0.0
	if hacia.length_squared() > 0.001:
		# El visor (cara) está en -Z, como el forward del cuerpo.
		rotation.y = lerp_angle(rotation.y, atan2(-hacia.x, -hacia.z), 8.0 * delta)

func _actualizar_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 3.5)
	if _mat_cuerpo != null:
		_mat_cuerpo.emission_energy_multiplier = _flash * 1.4
	for m in _mat_flash:
		if is_instance_valid(m):
			m.emission_energy_multiplier = _flash * 1.8

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
	_animar_una_vez(clip_recibir)
	_t_recibir = duracion_recibir
	# EFECTO de impacto en el punto de contacto: aquí el daño ya está confirmado
	# (un golpe al aire no pasa de aquí) y es UNA llamada por impacto, así que no
	# se puede duplicar por fotogramas ni por varias colisiones del mismo golpe.
	VfxImpacto.reproducir(self, dir, cantidad)
	if empuje > 0.0 and dir.length_squared() > 0.0001:
		velocity.x += dir.x * empuje
		velocity.z += dir.z * empuje
		_t_empuje = 0.18
	# Un golpe interrumpe preparación/golpe: se limpia amenaza y turno para que
	# la cola de ataques no quede bloqueada por un enemigo interrumpido.
	if _estado == Estado.PREPARAR or _estado == Estado.GOLPEAR:
		_limpiar_amenaza()
		_soltar_turno()
		_estado = Estado.CERCO
		_inclinacion = 0.0
	if aturde > 0.0:
		_limpiar_amenaza()
		_soltar_turno()
		_estado = Estado.ATURDIDO
		_t_ataque = maxf(_t_ataque, aturde)
		_inclinacion = 0.0
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
	var gestor := _gestor_combate()
	if gestor != null and gestor.has_method("unregister_enemy"):
		gestor.call("unregister_enemy", self)
	remove_from_group(GRUPO_DANIO)
	remove_from_group(GRUPO)
	velocity = Vector3.ZERO
	_animar_una_vez(clip_muerte)
	# Un muerto no bloquea ni es seleccionable; desaparece en medio segundo.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if _barra != null:
		_barra.visible = false
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.45)
	var destino := global_position - Vector3.UP * 0.4
	t.tween_property(self, "global_position", destino, 0.45)
	t.chain().tween_callback(queue_free)
	murio.emit(self)

## Retirada limpia pedida por el gerente (tecla G otra vez): sin tween, directa.
func retirar() -> void:
	if _muerto:
		return
	_muerto = true
	_estado = Estado.MUERTO
	_limpiar_amenaza()
	_soltar_turno()
	var gestor := _gestor_combate()
	if gestor != null and gestor.has_method("unregister_enemy"):
		gestor.call("unregister_enemy", self)
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

func _en_arco(jugador: Node3D) -> bool:
	var hacia := _dir_plano_hacia(jugador)
	if hacia.length_squared() <= 0.0001:
		return false
	return (-global_transform.basis.z).normalized().dot(hacia) >= arco_golpe

func _punto_de_cerco() -> Vector3:
	if _gerente != null:
		var punto: Vector3 = _gerente.call("posicion_de", self)
		return punto
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
func _registrar_amenaza(t: float) -> void:
	var gestor := _gestor_combate()
	if gestor == null:
		return
	var threats: Variant = gestor.get("threats")
	if threats != null:
		threats.register(self, "melee", t, true)

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

func _actualizar_barra() -> void:
	var fraccion := 0.0
	if vida_max > 0.0:
		fraccion = clampf(_vida / vida_max, 0.0, 1.0)
	# La barra es UNA sola pieza: su shader pinta el fondo, el relleno y el color
	# (de rojo a verde). Antes eran dos quads y el relleno quedaba tapado por el
	# fondo según hacia dónde mirase el enemigo.
	if _mat_barra != null:
		_mat_barra.set_shader_parameter("fraccion", fraccion)

## Oculta la barra si el enemigo queda pegado a la cámara: a esa distancia la
## barra taparía media pantalla y no aporta nada (el enemigo está justo delante).
## Dos umbrales para que no parpadee al caminar cerca del borde.
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

# ---------------------------------------------------------------- animación
func _animar(clip: StringName) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if _anim.current_animation == String(clip) and _anim.is_playing():
		return
	_anim.play(clip)

func _animar_una_vez(clip: StringName) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_anim.play(clip)

## Locomoción: anda o se queda quieto según su velocidad real.
func _animar_por_velocidad() -> void:
	if _estado == Estado.PREPARAR or _estado == Estado.GOLPEAR or _estado == Estado.MUERTO:
		return
	# Mientras dura la reacción al golpe, la locomoción NO pisa ese clip.
	if _t_recibir > 0.0:
		return
	var sp := Vector2(velocity.x, velocity.z).length()
	_animar(clip_andar if sp > 0.4 else clip_idle)

## Copia POR INSTANCIA los materiales del modelo para poder destellar al recibir
## daño (la cápsula de depósito queda oculta cuando el modelo se visualiza).
func _preparar_flash_visual() -> void:
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

func _duplicar_materiales() -> void:
	# Materiales POR INSTANCIA (duplicados una sola vez): el destello de daño y
	# el color de la barra de un enemigo no tocan a los demás.
	if _cuerpo.material_override is StandardMaterial3D:
		_mat_cuerpo = (_cuerpo.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		_cuerpo.material_override = _mat_cuerpo
	if _barra_mesh.material_override is ShaderMaterial:
		_mat_barra = (_barra_mesh.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		_barra_mesh.material_override = _mat_barra
