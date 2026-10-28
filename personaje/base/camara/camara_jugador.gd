class_name CamaraZiba
extends Node3D

# Camara en tercera persona vinculada al jugador.
# - El mouse controla yaw (rotacion Y) y pitch (rotacion X).
# - Durante la carga: zoom progresivo, pitch de dibujo y vibracion ligera.
# - Durante la ejecucion: FOV ampliado + vibracion (efecto cinematografico).
# Nunca se separa del jugador: es un hijo del CharacterBody3D.

@export var sensibilidad: float = 0.0025
# Limite inferior (mirar hacia abajo / camara alta): mantiene la 3a persona.
@export var limite_pitch: float = 1.25
# Limite superior (mirar hacia arriba): evita que la camara entre en el
# personaje / primera persona. Se conserva el control vertical del mouse.
@export var limite_pitch_superior: float = 0.20
@export var largo_base: float = 2.6
@export var fov_base: float = 70.0
@export var pitch_objetivo_inicial: float = -0.25

const RADIO_COLISION: float = 0.16
const MARGEN_COLISION: float = 0.22
const MARGEN_PARED: float = 0.25
const DISTANCIA_MINIMA: float = 0.14

var permitir_look: bool = true
var objetivo_largo: float = 2.6
var objetivo_fov: float = 70.0
var vibracion: float = 0.0

var _pitch: float = -0.25
var _pitch_obj: float = -0.25
var _brazo: SpringArm3D
var _cam: Camera3D
var _jugador_rid: RID
var _tiene_rid: bool = false
var _distancia_actual: float = 2.6

# --- Pulido del combate (JuiceCombate) ----------------------------------------
# Sacudida por "trauma" (Squirrel Eiserloh, GDC 2016): el impacto SUMA trauma
# (0..1), la sacudida es trauma² (los golpes flojos casi no se notan y los
# fuertes sí) y se lee de un ruido coherente, no de randf (que da un temblor
# "eléctrico"). El trauma decae en tiempo REAL: el hitstop no lo congela.
# Todo es aditivo sobre lo que ya hacía la cámara (vibración, FOV de la carga).
const TRAUMA_DECAIMIENTO := 2.2        # trauma/s
const SACUDIDA_MAX_DESPLAZAMIENTO := 0.09  # m de h/v_offset a trauma 1
const SACUDIDA_MAX_GIRO := 0.035       # rad de alabeo (roll) a trauma 1
const SACUDIDA_FRECUENCIA := 28.0      # Hz aproximados del ruido
const FOV_PUNCH_RECUPERACION := 9.0    # 1/s: vuelta del golpe de FOV
var _trauma: float = 0.0
var _fov_extra: float = 0.0
var _fov_suave: float = 70.0
var _vib_h: float = 0.0
var _vib_v: float = 0.0
var _t_ruido: float = 0.0
var _ruido := FastNoiseLite.new()
var _t_real_us: int = 0

func _ready() -> void:
	_brazo = get_node_or_null("Brazo") as SpringArm3D
	_cam = get_node_or_null("Brazo/Camara") as Camera3D
	objetivo_largo = largo_base
	objetivo_fov = fov_base
	_pitch = pitch_objetivo_inicial
	_pitch_obj = pitch_objetivo_inicial
	_distancia_actual = largo_base
	rotation.x = _pitch
	if _brazo != null:
		_brazo.spring_length = largo_base
		if _brazo.shape == null:
			var esfera := SphereShape3D.new()
			esfera.radius = RADIO_COLISION
			_brazo.shape = esfera
		_brazo.margin = maxf(_brazo.margin, MARGEN_COLISION)
		_brazo.collision_mask = 1
		# El brazo no debe chocar con el propio cuerpo del jugador: si lo hace,
		# se acorta hasta el pivote y la camara cae en primera persona.
		var cuerpo := get_parent()
		if cuerpo is CollisionObject3D:
			_jugador_rid = (cuerpo as CollisionObject3D).get_rid()
			_tiene_rid = true
			_brazo.add_excluded_object(_jugador_rid)
	if _cam != null:
		_cam.fov = fov_base
		_cam.near = 0.04
	_fov_suave = fov_base
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.frequency = 1.0
	_ruido.seed = 7

func _unhandled_input(event: InputEvent) -> void:
	if not permitir_look:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# La sensibilidad y la inversión vertical las aporta el autoload de
		# JUGABILIDAD (menú de configuración). sensibilidad sigue siendo la base.
		var s: float = sensibilidad * AjustesJugabilidad.factor_sensibilidad()
		var signo_y: float = AjustesJugabilidad.signo_eje_vertical()
		rotate_y(-event.relative.x * s)
		_pitch_obj = clampf(_pitch_obj - event.relative.y * s * signo_y, -limite_pitch, limite_pitch_superior)

func definir_pitch(v: float) -> void:
	_pitch_obj = clampf(v, -limite_pitch, limite_pitch_superior)
	_pitch = _pitch_obj
	rotation.x = _pitch

func _process(delta: float) -> void:
	_pitch = lerpf(_pitch, _pitch_obj, 10.0 * delta)
	rotation.x = _pitch
	if _brazo != null:
		_brazo.spring_length = lerpf(_brazo.spring_length, objetivo_largo, 6.0 * delta)
	if _cam != null:
		# Tiempo REAL (sin la escala del hitstop/cámara lenta): la sacudida y el
		# golpe de FOV se ven y se recuperan aunque el mundo esté congelado.
		# Reloj del sistema, no `delta / time_scale`: en el fotograma en que el
		# hitstop cambia la escala, ese cociente da un salto de ×25.
		var ahora_us: int = Time.get_ticks_usec()
		var real: float = 0.0 if _t_real_us == 0 else minf(float(ahora_us - _t_real_us) / 1_000_000.0, 0.1)
		_t_real_us = ahora_us
		_fov_suave = lerpf(_fov_suave, objetivo_fov, 5.0 * delta)
		_fov_extra = lerpf(_fov_extra, 0.0, clampf(FOV_PUNCH_RECUPERACION * real, 0.0, 1.0))
		_cam.fov = _fov_suave + _fov_extra
		if vibracion > 0.001:
			var s := vibracion * 0.05
			_vib_h = randf_range(-s, s)
			_vib_v = randf_range(-s, s)
		else:
			_vib_h = lerpf(_vib_h, 0.0, 0.4)
			_vib_v = lerpf(_vib_v, 0.0, 0.4)
		var sh := 0.0
		var sv := 0.0
		var roll := 0.0
		if _trauma > 0.0:
			_trauma = maxf(0.0, _trauma - TRAUMA_DECAIMIENTO * real)
			_t_ruido += real * SACUDIDA_FRECUENCIA
			var k := _trauma * _trauma
			sh = SACUDIDA_MAX_DESPLAZAMIENTO * k * _ruido.get_noise_2d(_t_ruido, 0.0)
			sv = SACUDIDA_MAX_DESPLAZAMIENTO * k * _ruido.get_noise_2d(0.0, _t_ruido + 50.0)
			roll = SACUDIDA_MAX_GIRO * k * _ruido.get_noise_2d(_t_ruido + 100.0, 100.0)
		_cam.h_offset = _vib_h + sh
		_cam.v_offset = _vib_v + sv
		_cam.rotation.z = roll
	_limitar_contra_obstaculos(delta, false)

## Pulido del combate: suma TRAUMA (0..1, se acumula hasta 1) y un golpe de FOV
## en grados (negativo = acerca, "punch-in"). Lo llama JuiceCombate.
func impulso_golpe(trauma: float, fov_grados: float = 0.0) -> void:
	_trauma = clampf(_trauma + maxf(trauma, 0.0), 0.0, 1.0)
	_fov_extra += fov_grados

func trauma_actual() -> float:
	return _trauma

func fov_extra_actual() -> float:
	return _fov_extra

func _physics_process(delta: float) -> void:
	_limitar_contra_obstaculos(delta, false)

func forzar_ajuste_inmediato() -> void:
	_limitar_contra_obstaculos(0.0, true)

func distancia_actual() -> float:
	return _distancia_actual

func _limitar_contra_obstaculos(delta: float, instantaneo: bool) -> void:
	if _brazo == null or _cam == null or not is_inside_tree():
		return
	var mundo3d: World3D = get_world_3d()
	if mundo3d == null:
		return
	var espacio: PhysicsDirectSpaceState3D = mundo3d.direct_space_state
	if espacio == null:
		return
	var largo_max: float = maxf(DISTANCIA_MINIMA, _brazo.spring_length)
	var hit_brazo: float = _brazo.get_hit_length()
	var tope: float = largo_max
	if hit_brazo > 0.001 and hit_brazo < largo_max:
		tope = maxf(DISTANCIA_MINIMA, hit_brazo)
	var base: Transform3D = _brazo.global_transform
	var origen: Vector3 = base.origin
	var dir: Vector3 = base.basis.z.normalized()
	var der: Vector3 = base.basis.x.normalized()
	var excl: Array[RID] = []
	if _tiene_rid:
		excl.append(_jugador_rid)
	for offset_lat: float in [0.0, -0.09, 0.09]:
		var desde: Vector3 = origen + der * offset_lat
		var hasta: Vector3 = desde + dir * (largo_max + MARGEN_PARED)
		var q := PhysicsRayQueryParameters3D.create(desde, hasta, _brazo.collision_mask, excl)
		q.hit_from_inside = true
		q.hit_back_faces = true
		var res: Dictionary = espacio.intersect_ray(q)
		if not res.is_empty():
			var p_golpe: Vector3 = res["position"] as Vector3
			var d_segura: float = maxf(DISTANCIA_MINIMA, desde.distance_to(p_golpe) - MARGEN_PARED)
			if d_segura < tope:
				tope = d_segura
	if instantaneo or tope <= _distancia_actual:
		_distancia_actual = clampf(tope, DISTANCIA_MINIMA, largo_max)
	else:
		_distancia_actual = lerpf(_distancia_actual, minf(tope, largo_max), clampf(10.0 * delta, 0.0, 1.0))
	_cam.position = Vector3(0.0, 0.0, _distancia_actual)

