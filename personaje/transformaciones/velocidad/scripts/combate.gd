class_name SistemaCombate
extends Node

# Combo de cuatro golpes con click izquierdo. El combo cicla 1-2-3-4-1-2...
# Se reinicia a 1 si pasa mucho tiempo sin atacar.

# Se emite cada vez que el sistema decide que se ejecuta un golpe, con el
# indice de combo ya calculado (1..4). El jugador usa este resultado existente
# para elegir la animacion; la logica del combo no cambia.
signal golpe_realizado(indice: int)

@export var tiempo_reset: float = 1.3

# --- Afterimage de supervelocidad (unico efecto visual de los combos) ---
# Cada golpe deja una o varias siluetas residuales del modelo (misma malla y
# misma postura del esqueleto en ese instante). Son solo visuales: sin fisica,
# sin colisiones, sin combate. Se desvanecen rapido y se liberan solas.
const SILUETAS_POR_GOLPE := 3       # varias siluetas breves en vez de una larga
const INTERVALO_SILUETAS := 0.03    # separacion entre siluetas (fraccion de segundo)
const DURACION_SILUETA := 0.24      # vida de cada silueta
const ALFA_SILUETA := 0.75          # opacidad inicial de la silueta
const COLOR_SILUETA := Color(0.30, 0.78, 1.0)  # cian electrico (velocidad)
const OFFSET_SILUETA_BASE := 0.28   # desplazamiento de la 1a silueta detras del golpe
const OFFSET_SILUETA_PASO := 0.22   # distancia extra entre siluetas (estela)

var _indice: int = 0
var _timer: float = 0.0
var _jugador: Node3D
var _visual: Node3D
var _modelo: Node3D
var _mat_silueta: StandardMaterial3D

func _ready() -> void:
	_jugador = get_parent() as Node3D
	_mat_silueta = _crear_mat_silueta()
	if _jugador != null:
		_visual = _jugador.get_node_or_null("Visual") as Node3D
		_modelo = _jugador.get_node_or_null("Visual/Pose/Volteo/Modelo") as Node3D

func intentar_golpe() -> void:
	if _timer <= 0.0:
		_indice = 0
	_indice = (_indice % 4) + 1
	_timer = tiempo_reset
	_ejecutar(_indice)

func golpe_actual() -> int:
	return _indice

# Cancela la secuencia de combo en curso (p. ej. al cancelar un ataque con un
# salto): el siguiente golpe vuelve a empezar por combo-1. No altera la logica
# de progresion del combo, solo reinicia su posicion.
func cancelar_combo() -> void:
	_indice = 0
	_timer = 0.0

func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_indice = 0

func _ejecutar(i: int) -> void:
	print("[Ziba] golpe de combo: ", i)
	golpe_realizado.emit(i)
	_emitir_afterimage()

# ---------------- Afterimage de supervelocidad ----------------
func _crear_mat_silueta() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Mezcla normal (no aditiva): la silueta se lee como residuo translucido
	# tambien sobre escenas claras, no solo sobre fondos oscuros.
	m.albedo_color = Color(COLOR_SILUETA.r, COLOR_SILUETA.g, COLOR_SILUETA.b, ALFA_SILUETA)
	m.emission_enabled = true
	m.emission = COLOR_SILUETA
	m.emission_energy_multiplier = 1.0
	return m

func _emitir_afterimage() -> void:
	if _modelo == null or not is_instance_valid(_modelo):
		return
	# Las siluetas aparecen escalonadas por unos pocos frames para que cada una
	# capte una postura ligeramente distinta del golpe.
	var t := create_tween()
	for k in range(SILUETAS_POR_GOLPE):
		t.tween_callback(_crear_silueta.bind(k))
		t.tween_interval(INTERVALO_SILUETAS)

func _crear_silueta(k: int) -> void:
	if _modelo == null or not is_instance_valid(_modelo):
		return
	var escena := get_tree().current_scene
	if escena == null and _jugador != null:
		escena = _jugador.get_parent()
	if escena == null:
		return

	var fantasma := _modelo.duplicate() as Node3D
	if fantasma == null:
		return
	escena.add_child(fantasma)

	# Las siluetas se colocan un poco por detras del movimiento real del golpe.
	# Se calcula en cada emision para adaptarse al desplazamiento (frontal o lateral).
	var atras := _direccion_atras()
	var base := _modelo.global_transform
	var offset := atras * (OFFSET_SILUETA_BASE + OFFSET_SILUETA_PASO * float(k)) + Vector3.UP * (0.03 * float(k))
	fantasma.global_transform = Transform3D(base.basis, base.origin + offset)

	var mallas: Array[MeshInstance3D] = []
	_preparar_fantasma(fantasma, mallas)
	if mallas.is_empty():
		fantasma.queue_free()
		return

	var t := create_tween()
	t.set_parallel(true)
	t.tween_method(_set_transparencia.bind(mallas), 0.0, 1.0, DURACION_SILUETA)
	t.chain().tween_callback(fantasma.queue_free)

func _direccion_atras() -> Vector3:
	# Hacia donde quedan las siluetas: detras del movimiento real. Con el jugador
	# desplazandose, detras del desplazamiento; quieto, detras de su orientacion.
	var cuerpo := _jugador as CharacterBody3D
	if cuerpo != null:
		var v := Vector3(cuerpo.velocity.x, 0.0, cuerpo.velocity.z)
		if v.length() > 0.5:
			return -v.normalized()
	if _visual != null:
		var atras := _visual.global_transform.basis.z
		atras.y = 0.0
		if atras.length() > 0.001:
			return atras.normalized()
	return Vector3.BACK

func _preparar_fantasma(n: Node, mallas: Array[MeshInstance3D]) -> void:
	# Silueta puramente visual: material de velocidad, sin sombras, sin animacion
	# propia (mantiene congelada la postura capturada) y sin ningun tipo de fisica.
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_override = _mat_silueta
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mallas.append(mi)
	if n is AnimationPlayer:
		(n as AnimationPlayer).stop()
	if n is CollisionObject3D:
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	for c in n.get_children():
		_preparar_fantasma(c, mallas)

func _set_transparencia(v: float, mallas: Array[MeshInstance3D]) -> void:
	for mi in mallas:
		if is_instance_valid(mi):
			mi.transparency = v